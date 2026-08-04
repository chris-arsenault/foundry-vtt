//! Discord interactions endpoint for the Foundry VTT wake bot.
//!
//! Routes (manual lambda_http routing per platform norms — no Axum):
//!   GET  /health  liveness for the platform convention
//!   POST /        Discord interaction webhook (/foundry start|stop|status)
//!
//! Every POST is authenticated by Discord's ed25519 signature over
//! `timestamp || body`; the public key lives in SSM and is read at cold start.

use std::env;
use std::time::Duration;

use ed25519_dalek::{Signature, Verifier, VerifyingKey};
use lambda_http::{run, service_fn, Body, Error, Request, Response};
use serde_json::{json, Value};
use tokio::sync::OnceCell;
use tracing_subscriber::EnvFilter;

struct Config {
    ec2: aws_sdk_ec2::Client,
    http: reqwest::Client,
    key: VerifyingKey,
    instance_id: String,
    hostname: String,
    guild_id: String,
}

static CONFIG: OnceCell<Config> = OnceCell::const_new();

async fn ssm_value(ssm: &aws_sdk_ssm::Client, env_name: &str) -> Result<String, Error> {
    let param = env::var(env_name)?;
    let response = ssm.get_parameter().name(&param).send().await?;
    Ok(response
        .parameter()
        .and_then(|p| p.value())
        .ok_or_else(|| format!("{param} has no value"))?
        .trim()
        .to_string())
}

async fn config() -> Result<&'static Config, Error> {
    CONFIG
        .get_or_try_init(|| async {
            let aws = aws_config::load_defaults(aws_config::BehaviorVersion::latest()).await;
            let ssm = aws_sdk_ssm::Client::new(&aws);
            let hex_key = ssm_value(&ssm, "PUBLIC_KEY_PARAM").await?;
            let key = parse_public_key(&hex_key)
                .ok_or("public key parameter is not a 32-byte hex ed25519 key")?;
            Ok::<_, Error>(Config {
                ec2: aws_sdk_ec2::Client::new(&aws),
                http: reqwest::Client::builder()
                    .timeout(Duration::from_millis(2500))
                    .build()?,
                key,
                instance_id: env::var("INSTANCE_ID")?,
                hostname: env::var("FOUNDRY_HOSTNAME")?,
                // Exact-compare only; the PENDING placeholder never matches a
                // real guild id, so commands fail closed until it is set.
                guild_id: ssm_value(&ssm, "GUILD_ID_PARAM").await?,
            })
        })
        .await
}

fn authorized_guild(interaction: &Value, guild_id: &str) -> bool {
    interaction["guild_id"].as_str() == Some(guild_id)
}

fn parse_public_key(hex_key: &str) -> Option<VerifyingKey> {
    let bytes: [u8; 32] = hex::decode(hex_key).ok()?.try_into().ok()?;
    VerifyingKey::from_bytes(&bytes).ok()
}

fn verify_signature(key: &VerifyingKey, timestamp: &str, body: &[u8], sig_hex: &str) -> bool {
    let Ok(sig_bytes) = hex::decode(sig_hex) else {
        return false;
    };
    let Ok(sig) = Signature::from_slice(&sig_bytes) else {
        return false;
    };
    let mut message = timestamp.as_bytes().to_vec();
    message.extend_from_slice(body);
    key.verify(&message, &sig).is_ok()
}

fn subcommand(interaction: &Value) -> &str {
    interaction["data"]["options"][0]["name"]
        .as_str()
        .unwrap_or("status")
}

fn json_response(status: u16, body: &Value) -> Result<Response<Body>, Error> {
    Ok(Response::builder()
        .status(status)
        .header("content-type", "application/json")
        .body(Body::from(body.to_string()))?)
}

fn reply(content: String) -> Result<Response<Body>, Error> {
    json_response(200, &json!({ "type": 4, "data": { "content": content } }))
}

async fn instance_state(cfg: &Config) -> Result<String, Error> {
    let out = cfg
        .ec2
        .describe_instances()
        .instance_ids(&cfg.instance_id)
        .send()
        .await?;
    Ok(out
        .reservations()
        .first()
        .and_then(|r| r.instances().first())
        .and_then(|i| i.state())
        .and_then(|s| s.name())
        .map(|n| n.as_str().to_string())
        .unwrap_or_else(|| "unknown".to_string()))
}

async fn foundry_status(cfg: &Config) -> Option<Value> {
    let url = format!("https://{}/api/status", cfg.hostname);
    let response = cfg.http.get(url).send().await.ok()?;
    if !response.status().is_success() {
        return None;
    }
    response.json().await.ok()
}

async fn cmd_start(cfg: &Config) -> Result<Response<Body>, Error> {
    match instance_state(cfg).await?.as_str() {
        "running" => reply(format!(
            "Server is already running: https://{}",
            cfg.hostname
        )),
        "stopped" => {
            cfg.ec2
                .start_instances()
                .instance_ids(&cfg.instance_id)
                .send()
                .await?;
            reply(format!(
                "Starting the server. https://{} should be live in ~2 minutes. \
                 It stops itself after 60 minutes with no players connected.",
                cfg.hostname
            ))
        }
        other => reply(format!("Server is {other} — try again in a minute.")),
    }
}

async fn cmd_stop(cfg: &Config) -> Result<Response<Body>, Error> {
    let state = instance_state(cfg).await?;
    if state != "running" {
        return reply(format!("Server is {state}; nothing to stop."));
    }
    cfg.ec2
        .stop_instances()
        .instance_ids(&cfg.instance_id)
        .send()
        .await?;
    reply("Stopping the server.".to_string())
}

async fn cmd_status(cfg: &Config) -> Result<Response<Body>, Error> {
    let state = instance_state(cfg).await?;
    if state != "running" {
        return reply(format!(
            "Server is {state}. Use `/foundry start` to wake it."
        ));
    }
    let Some(status) = foundry_status(cfg).await else {
        return reply("Instance is running; Foundry is still starting up.".to_string());
    };
    let world = match status["world"].as_str() {
        Some(world) => format!(
            "world **{}** ({})",
            world,
            status["system"].as_str().unwrap_or("?")
        ),
        None => "no world active".to_string(),
    };
    reply(format!(
        "Server is up at https://{} — {}, {} player(s) connected.",
        cfg.hostname,
        world,
        status["users"].as_u64().unwrap_or(0)
    ))
}

async fn run_command(cfg: &Config, sub: &str) -> Result<Response<Body>, Error> {
    match sub {
        "start" => cmd_start(cfg).await,
        "stop" => cmd_stop(cfg).await,
        _ => cmd_status(cfg).await,
    }
}

async fn dispatch(cfg: &Config, sub: &str) -> Result<Response<Body>, Error> {
    match run_command(cfg, sub).await {
        Ok(response) => Ok(response),
        Err(err) => {
            tracing::error!(error = %err, command = sub, "command failed");
            reply("Something went wrong talking to AWS — check the Lambda logs.".to_string())
        }
    }
}

async fn handle_command(cfg: &Config, interaction: &Value) -> Result<Response<Body>, Error> {
    if !authorized_guild(interaction, &cfg.guild_id) {
        tracing::warn!(
            guild_id = interaction["guild_id"].as_str().unwrap_or("<none>"),
            "command from unauthorized guild"
        );
        return reply("This command only works in its home server.".to_string());
    }
    dispatch(cfg, subcommand(interaction)).await
}

fn header<'a>(req: &'a Request, name: &str) -> Option<&'a str> {
    req.headers().get(name).and_then(|v| v.to_str().ok())
}

async fn interaction(req: Request) -> Result<Response<Body>, Error> {
    let cfg = match config().await {
        Ok(cfg) => cfg,
        Err(err) => {
            tracing::error!(error = %err, "configuration unavailable");
            return json_response(500, &json!({ "error": "configuration unavailable" }));
        }
    };
    let (Some(sig), Some(ts)) = (
        header(&req, "x-signature-ed25519"),
        header(&req, "x-signature-timestamp"),
    ) else {
        return json_response(401, &json!({ "error": "missing signature" }));
    };
    if !verify_signature(&cfg.key, ts, req.body(), sig) {
        return json_response(401, &json!({ "error": "bad signature" }));
    }

    let interaction: Value = serde_json::from_slice(req.body())?;
    match interaction["type"].as_u64() {
        Some(1) => json_response(200, &json!({ "type": 1 })),
        Some(2) => handle_command(cfg, &interaction).await,
        _ => json_response(400, &json!({ "error": "unsupported interaction type" })),
    }
}

async fn handler(req: Request) -> Result<Response<Body>, Error> {
    match (req.method().as_str(), req.uri().path()) {
        ("GET", "/health") => json_response(200, &json!({ "status": "ok" })),
        ("POST", "/") => interaction(req).await,
        _ => json_response(404, &json!({ "error": "not found" })),
    }
}

#[tokio::main]
async fn main() -> Result<(), Error> {
    rustls::crypto::ring::default_provider()
        .install_default()
        .expect("Failed to install rustls crypto provider");

    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env())
        .json()
        .init();

    run(service_fn(handler)).await
}

#[cfg(test)]
mod tests {
    use super::*;
    use ed25519_dalek::{Signer, SigningKey};

    #[test]
    fn accepts_valid_signature_and_rejects_tampering() {
        let sk = SigningKey::from_bytes(&[7u8; 32]);
        let vk = sk.verifying_key();
        let ts = "1700000000";
        let body: &[u8] = br#"{"type":1}"#;
        let mut message = ts.as_bytes().to_vec();
        message.extend_from_slice(body);
        let sig = hex::encode(sk.sign(&message).to_bytes());

        assert!(verify_signature(&vk, ts, body, &sig));
        assert!(!verify_signature(&vk, "1700000001", body, &sig));
        assert!(!verify_signature(&vk, ts, body, "not-hex"));
    }

    #[test]
    fn parses_public_key_hex_only() {
        let vk = SigningKey::from_bytes(&[9u8; 32]).verifying_key();
        assert!(parse_public_key(&hex::encode(vk.to_bytes())).is_some());
        assert!(parse_public_key("PENDING").is_none());
    }

    #[test]
    fn extracts_subcommand_with_status_default() {
        let i = json!({ "type": 2, "data": { "options": [{ "name": "start" }] } });
        assert_eq!(subcommand(&i), "start");
        assert_eq!(subcommand(&json!({ "type": 2 })), "status");
    }

    #[test]
    fn rejects_foreign_missing_and_pending_guilds() {
        let home = json!({ "type": 2, "guild_id": "123456789012345678" });
        assert!(authorized_guild(&home, "123456789012345678"));
        assert!(!authorized_guild(&json!({ "type": 2, "guild_id": "999" }), "123456789012345678"));
        assert!(!authorized_guild(&json!({ "type": 2 }), "123456789012345678"));
        assert!(!authorized_guild(&home, "PENDING"));
    }
}
