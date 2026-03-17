/**
 * Test runner for the 1claw OpenClaw plugin.
 * Run without OpenClaw: npx tsx scripts/test-plugin-runner.ts <command> [args...]
 *
 * Requires env: ONECLAW_VAULT_ID and either ONECLAW_TOKEN or (ONECLAW_AGENT_ID + ONECLAW_API_KEY)
 */

import oneclawPlugin from "../config/openclaw-1claw-plugin";

const ctx = {
  log: (msg: string) => console.log(msg),
  error: (msg: string) => console.error(msg),
  exit: (code: number) => process.exit(code),
};

const subcmd = process.argv[2] ?? "help";
const rest = process.argv.slice(3);

const command = oneclawPlugin.commands[subcmd as keyof typeof oneclawPlugin.commands];
if (!command) {
  console.error(`Unknown command: ${subcmd}`);
  console.error(`Available: ${Object.keys(oneclawPlugin.commands).join(", ")}`);
  process.exit(1);
}

command
  .handler(rest, ctx)
  .catch((err: Error) => {
    console.error(`Error: ${err.message}`);
    process.exit(1);
  });
