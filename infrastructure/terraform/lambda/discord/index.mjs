// Discord interactions endpoint: /foundry start|stop|status.
// Runs outside the VPC; reaches Foundry's public /api/status through the ALB.
import { createPublicKey, verify } from 'node:crypto';
import {
  EC2Client,
  DescribeInstancesCommand,
  StartInstancesCommand,
  StopInstancesCommand,
} from '@aws-sdk/client-ec2';
import { SSMClient, GetParameterCommand } from '@aws-sdk/client-ssm';

const ec2 = new EC2Client({});
const ssm = new SSMClient({});

const INSTANCE_ID = process.env.INSTANCE_ID;
const FOUNDRY_HOSTNAME = process.env.FOUNDRY_HOSTNAME;
const PUBLIC_KEY_PARAM = process.env.PUBLIC_KEY_PARAM;

// Ed25519 SPKI DER prefix; Discord publishes the raw 32-byte key as hex.
const ED25519_SPKI_PREFIX = Buffer.from('302a300506032b6570032100', 'hex');

let cachedKey;
async function discordPublicKey() {
  if (cachedKey) return cachedKey;
  const res = await ssm.send(new GetParameterCommand({ Name: PUBLIC_KEY_PARAM }));
  const hex = res.Parameter.Value.trim();
  if (!/^[0-9a-fA-F]{64}$/.test(hex)) {
    throw new Error(`SSM parameter ${PUBLIC_KEY_PARAM} is not a 32-byte hex key (still PENDING?)`);
  }
  cachedKey = createPublicKey({
    key: Buffer.concat([ED25519_SPKI_PREFIX, Buffer.from(hex, 'hex')]),
    format: 'der',
    type: 'spki',
  });
  return cachedKey;
}

const json = (statusCode, body) => ({
  statusCode,
  headers: { 'content-type': 'application/json' },
  body: JSON.stringify(body),
});
const reply = (content) => json(200, { type: 4, data: { content } });

async function instanceState() {
  const res = await ec2.send(new DescribeInstancesCommand({ InstanceIds: [INSTANCE_ID] }));
  return res.Reservations?.[0]?.Instances?.[0]?.State?.Name ?? 'unknown';
}

async function foundryStatus() {
  try {
    const res = await fetch(`https://${FOUNDRY_HOSTNAME}/api/status`, {
      signal: AbortSignal.timeout(2500),
    });
    if (!res.ok) return null;
    return await res.json();
  } catch {
    return null;
  }
}

async function handleCommand(sub) {
  const state = await instanceState();

  if (sub === 'start') {
    if (state === 'running') {
      return reply(`Server is already running: https://${FOUNDRY_HOSTNAME}`);
    }
    if (state !== 'stopped') {
      return reply(`Server is ${state} — try again in a minute.`);
    }
    await ec2.send(new StartInstancesCommand({ InstanceIds: [INSTANCE_ID] }));
    return reply(
      `Starting the server. https://${FOUNDRY_HOSTNAME} should be live in ~2 minutes. ` +
        `It stops itself after 60 minutes with no players connected.`
    );
  }

  if (sub === 'stop') {
    if (state !== 'running') {
      return reply(`Server is ${state}; nothing to stop.`);
    }
    await ec2.send(new StopInstancesCommand({ InstanceIds: [INSTANCE_ID] }));
    return reply('Stopping the server.');
  }

  // status
  if (state !== 'running') {
    return reply(`Server is ${state}. Use \`/foundry start\` to wake it.`);
  }
  const status = await foundryStatus();
  if (!status) {
    return reply('Instance is running; Foundry is still starting up.');
  }
  const world = status.world ? `world **${status.world}** (${status.system})` : 'no world active';
  return reply(
    `Server is up at https://${FOUNDRY_HOSTNAME} — ${world}, ${status.users ?? 0} player(s) connected.`
  );
}

export const handler = async (event) => {
  const sig = event.headers?.['x-signature-ed25519'];
  const ts = event.headers?.['x-signature-timestamp'];
  if (!sig || !ts) return json(401, { error: 'missing signature' });

  const rawBody = event.isBase64Encoded
    ? Buffer.from(event.body ?? '', 'base64')
    : Buffer.from(event.body ?? '', 'utf8');

  let key;
  try {
    key = await discordPublicKey();
  } catch (err) {
    console.error(err);
    return json(500, { error: 'public key unavailable' });
  }

  const valid = verify(null, Buffer.concat([Buffer.from(ts), rawBody]), key, Buffer.from(sig, 'hex'));
  if (!valid) return json(401, { error: 'bad signature' });

  const interaction = JSON.parse(rawBody.toString('utf8'));

  // PING from Discord's endpoint verification.
  if (interaction.type === 1) return json(200, { type: 1 });

  if (interaction.type !== 2) return json(400, { error: 'unsupported interaction type' });

  const sub = interaction.data?.options?.[0]?.name ?? 'status';
  try {
    return await handleCommand(sub);
  } catch (err) {
    console.error(err);
    return reply('Something went wrong talking to AWS — check the Lambda logs.');
  }
};
