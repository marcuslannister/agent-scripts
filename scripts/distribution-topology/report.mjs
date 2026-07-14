export const HELP = `Usage: update-skill-topology.sh --check [--json]

Preview the manifest-owned skill distribution topology without changing it.

Options:
  --check  Discover inventory and report topology drift.
  --json   Write one JSON result document.
  -h, --help
            Show this help.

Exit codes:
  0   check clean
  1   drift or verification failure
  2   invalid usage or manifest
  3   user decision required
  130 interrupted
`;

export function writeHuman(document) {
  process.stdout.write("Skill topology check\n");
  process.stdout.write(`${"SOURCE".padEnd(13)}${"INVENTORY".padEnd(11)}${"DEFAULT".padEnd(9)}RESULT\n`);
  for (const source of document.sources) {
    process.stdout.write(`${source.id.padEnd(13)}${String(source.inventoryCount).padEnd(11)}${source.defaultDestinations.join(",").padEnd(9)}${source.result}\n`);
  }
  if (document.drift.length > 0) {
    process.stdout.write("\nDrift:\n");
  }
  for (const item of document.drift) {
    process.stdout.write(`- ${item.sourceId}/${item.skill} -> ${item.destination}: ${item.reason}\n`);
  }
  const resultCount = document.decisions.length > 0
    ? `${document.decisions.length} decision${document.decisions.length === 1 ? "" : "s"}`
    : `${document.drift.length} changes`;
  process.stdout.write(`\nResult: ${document.status} (${resultCount})\n`);

  if (document.decisions.length > 0) {
    process.stderr.write("Decision required:\n");
    for (const decision of document.decisions) {
      process.stderr.write(`- ${decision.message}\n`);
    }
  }
  for (const warning of document.warnings) {
    process.stderr.write(`warning: ${warning.message}\n`);
  }
}

export function failureDocument(error) {
  return {
    schemaVersion: 1,
    mode: "check",
    status: error.exitCode === 2 ? "invalid" : error.exitCode === 130 ? "interrupted" : "failed",
    sources: [],
    plan: [],
    drift: [],
    decisions: [],
    errors: [error.message],
    warnings: [],
  };
}
