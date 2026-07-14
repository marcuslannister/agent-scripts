export const HELP = `Usage: update-skill-topology.sh [--check] [--json]

Reconcile the manifest-owned skill distribution topology. Use --check to preview.

Options:
  --check  Discover inventory and report topology drift.
  --json   Write one JSON result document.
  -h, --help
            Show this help.

Exit codes:
  0   reconciled or check clean
  1   drift or verification failure
  2   invalid usage or manifest
  3   user decision required
  130 interrupted
`;

export function writeHuman(document) {
  process.stdout.write(`Skill topology ${document.mode}\n`);
  process.stdout.write(`${"SOURCE".padEnd(20)}${"INVENTORY".padEnd(11)}${"DEFAULT".padEnd(14)}${"SUPPORTED".padEnd(14)}RESULT\n`);
  for (const source of document.sources) {
    process.stdout.write(`${source.id.padEnd(20)}${String(source.inventoryCount).padEnd(11)}${source.defaultDestinations.join(",").padEnd(14)}${source.supportedDestinations.join(",").padEnd(14)}${source.result}\n`);
  }
  if (document.drift.length > 0) {
    process.stdout.write("\nDrift:\n");
  }
  for (const item of document.drift) {
    process.stdout.write(`- ${item.sourceId}/${item.skill} -> ${item.destination}: ${item.reason}\n`);
  }
  if (document.changes.length > 0) {
    process.stdout.write("\nChanges:\n");
  }
  for (const item of document.changes) {
    process.stdout.write(`- ${item.action} ${item.sourceId}/${item.skill} -> ${item.destination}\n`);
  }
  process.stdout.write(`\nCodex-root hygiene: ${document.hygiene.status}\n`);
  for (const item of document.hygiene.entries) {
    process.stdout.write(`- legacy entry ${item.name}: ${item.kind}\n`);
  }
  for (const item of document.hygiene.changes) {
    process.stdout.write(`- migrated ${item.name} -> ${item.backupPath}\n`);
  }
  if (document.skipped.length > 0) {
    process.stdout.write("\nSkipped:\n");
  }
  for (const item of document.skipped) {
    process.stdout.write(`- ${item.sourceId}/${item.skill} -> ${item.destination}: ${item.reason}\n`);
  }
  const resultCount = document.decisions.length > 0
    ? `${document.decisions.length} decision${document.decisions.length === 1 ? "" : "s"}`
    : `${document.mode === "check"
      ? document.drift.length + document.hygiene.entries.length
      : document.changes.length + document.hygiene.changes.length} changes`;
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
  for (const error of document.errors) {
    process.stderr.write(`error: ${error}\n`);
  }
}

export function failureDocument(error, mode = "check") {
  return {
    schemaVersion: 1,
    mode,
    status: error.exitCode === 2 ? "invalid" : error.exitCode === 130 ? "interrupted" : "failed",
    sources: [],
    plan: [],
    drift: [],
    decisions: [],
    errors: [error.message],
    warnings: [],
    changes: [],
    skipped: [],
    hygiene: {
      status: "failed",
      legacyRoot: "",
      entries: [],
      changes: [],
      errors: [error.message],
    },
  };
}
