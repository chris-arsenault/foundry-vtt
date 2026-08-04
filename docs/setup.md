# First-time setup

Everything here happens once. Day-to-day operation is
[operations.md](operations.md).

## 1. Stage the Foundry release

Foundry downloads are license-gated, so the zip is staged by hand. Download
the **NodeJS** build (not the Linux desktop build) from foundryvtt.com:

```bash
aws s3 cp FoundryVTT-Node-*.zip s3://foundry-vtt-releases-559098897826/foundryvtt.zip
```

## 2. Deploy

`scripts/deploy.sh` locally, or push to main. Note the
`discord_interactions_url` output — needed in step 4.

## 3. Create the Discord application

At https://discord.com/developers/applications → *New Application*. Discord
has no API for creating applications; this is a portal click-through.

- From **General Information**, copy the *Application ID* and *Public Key*.
- On the **Bot** tab: create the bot user, copy its *token*, and turn
  **Public Bot off**.
- Intents and permissions: **none**. This is a pure interactions-endpoint
  app — it never connects to the gateway, so all three privileged intents
  stay off and the permissions integer is 0.

Store the configuration in SSM — the public key and guild ID must be set
**before** step 4. The guild ID is your server's snowflake (enable Developer
Mode, right-click the server icon → Copy Server ID; any member can do this).
The Lambda rejects commands from any other server: a valid Discord signature
proves the request came from Discord for this app, not that it came from
*your* server, so the guild allowlist is the actual authorization
([ADR-0004](adr/0004-guild-allowlist-authorization.md)). Commands fail closed
while the guild ID is `PENDING`.

```bash
aws ssm put-parameter --name /ahara/foundry-vtt/discord-public-key \
  --type String --value <public key hex> --overwrite
aws ssm put-parameter --name /ahara/foundry-vtt/discord-guild-id \
  --type String --value <server id> --overwrite
aws ssm put-parameter --name /ahara/foundry-vtt/discord-client-secret \
  --type SecureString --value <client secret> --overwrite
aws ssm put-parameter --name /ahara/foundry-vtt/discord-bot-token \
  --type SecureString --value <bot token> --overwrite
```

## 4. Set the Interactions Endpoint URL

On the app's **General Information** page, paste the
`discord_interactions_url` output (`https://api.foundry-vtt.ahara.io/`) and
save. Discord immediately sends a signed verification PING; if it says the
URL "could not be verified," the public-key parameter is missing or wrong.

## 5. Register the slash command

Guild-scoped, so `/foundry` exists only in your server (run via
`with-cred --` in the managed environment, or set `DISCORD_BOT_TOKEN`
yourself):

```bash
curl -X POST \
  -H "Authorization: Bot $DISCORD_BOT_TOKEN" \
  -H "Content-Type: application/json" \
  "https://discord.com/api/v10/applications/<APP_ID>/guilds/<GUILD_ID>/commands" \
  -d '{
    "name": "foundry",
    "description": "Manage the Foundry VTT server",
    "options": [
      {"type": 1, "name": "start",  "description": "Wake the server"},
      {"type": 1, "name": "stop",   "description": "Stop the server"},
      {"type": 1, "name": "status", "description": "Server and world status"}
    ]
  }'
```

Verify it landed (an empty `[]` means the token or app ID was wrong):

```bash
curl -s -H "Authorization: Bot $DISCORD_BOT_TOKEN" \
  "https://discord.com/api/v10/applications/<APP_ID>/guilds/<GUILD_ID>/commands"
```

## 6. Add the app to your server

Registration alone does not make the command appear anywhere. Open this in a
browser, pick the server, authorize (requires the Manage Server permission in
that guild — hand the URL to an admin if you lack it):

```
https://discord.com/oauth2/authorize?client_id=<APP_ID>&scope=applications.commands
```

Only the `applications.commands` scope is needed; the bot user never joins
the server. Refresh the Discord client (Ctrl+R) and `/foundry` should
autocomplete. By default every server member can use it, including `stop`;
restrict it per-role/channel under *Server Settings → Integrations →
Foundry*.

## 7. First boot

`/foundry start` in Discord, wait ~2 minutes, open https://foundry.ahara.io,
enter the license key, and create the world. Configure S3 assets under Setup
→ filepicker (bucket `foundry-vtt-assets-559098897826`). Choose an
administrator password, set it in the setup UI, and store the same value in
SSM (Foundry keeps only a hash, so the parameter is the retrievable copy):

```bash
aws ssm put-parameter --name /ahara/foundry-vtt/admin-password \
  --type SecureString --value <admin password> --overwrite
```
