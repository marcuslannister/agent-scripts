#!/usr/bin/env node

import { spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const HELP = `Usage: update-skill-topology.sh --check [--json]

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

const DESTINATIONS = ["claude", "codex"];
const CLASSIFICATIONS = ["repo-owned", "npx-only", "source-only", "plugin-both", "plugin-claude-only"];
const moduleDirectory = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(moduleDirectory, "../..");
const manifestPath = path.join(repoRoot, "skill-topology.json");
const registryPath = path.join(moduleDirectory, "registry.json");
const activeChildren = new Set();
let activeLock = null;

class TopologyError extends Error {
  constructor(message, exitCode) {
    super(message);
    this.exitCode = exitCode;
  }
}

function parseArguments(args) {
  if (args.length === 1 && (args[0] === "--help" || args[0] === "-h")) {
    return { help: true, json: false };
  }

  const json = args.includes("--json");
  const check = args.includes("--check");
  const known = args.every((argument) => argument === "--check" || argument === "--json");
  if (!known || !check || args.filter((argument) => argument === "--check").length !== 1 || args.filter((argument) => argument === "--json").length > 1) {
    throw new TopologyError("use --check to preview the skill topology", 2);
  }

  return { help: false, json };
}

function readJson(filePath, label) {
  try {
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch (error) {
    throw new TopologyError(`${label} is not valid JSON: ${error.message}`, 2);
  }
}

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function validateFields(value, allowed, required, label) {
  if (!isObject(value)) {
    throw new TopologyError(`${label} must be an object`, 2);
  }
  const unknown = Object.keys(value).filter((key) => !allowed.includes(key));
  if (unknown.length > 0) {
    throw new TopologyError(`${label} contains unknown field: ${unknown[0]}`, 2);
  }
  const missing = required.filter((key) => !Object.hasOwn(value, key));
  if (missing.length > 0) {
    throw new TopologyError(`${label} is missing required field: ${missing[0]}`, 2);
  }
}

function validateDestinations(value, label) {
  if (!Array.isArray(value) || value.length === 0) {
    throw new TopologyError(`${label} must be a non-empty destination array`, 2);
  }
  for (const destination of value) {
    if (!DESTINATIONS.includes(destination)) {
      throw new TopologyError(`${label} contains unknown destination: ${String(destination)}`, 2);
    }
  }
  if (new Set(value).size !== value.length) {
    throw new TopologyError(`${label} contains a duplicate destination`, 2);
  }
}

function readManifest() {
  const manifest = readJson(manifestPath, "skill topology manifest");
  validateFields(manifest, ["version", "sources"], ["version", "sources"], "skill topology manifest");
  if (manifest.version !== 1) {
    throw new TopologyError("skill topology manifest version must be 1", 2);
  }
  if (!Array.isArray(manifest.sources) || manifest.sources.length === 0) {
    throw new TopologyError("skill topology manifest sources must be a non-empty array", 2);
  }

  const sourceIds = new Set();
  for (const [index, source] of manifest.sources.entries()) {
    const label = `skill topology manifest source ${index}`;
    validateFields(source, ["id", "classification", "defaultDestinations", "overrides"], ["id", "classification", "defaultDestinations", "overrides"], label);
    if (typeof source.id !== "string" || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/u.test(source.id)) {
      throw new TopologyError(`${label} has an invalid id`, 2);
    }
    if (sourceIds.has(source.id)) {
      throw new TopologyError(`skill topology manifest contains duplicate source id: ${source.id}`, 2);
    }
    sourceIds.add(source.id);
    if (!CLASSIFICATIONS.includes(source.classification)) {
      throw new TopologyError(`${label} contains unknown classification: ${String(source.classification)}`, 2);
    }
    validateDestinations(source.defaultDestinations, `${label} defaultDestinations`);
    if (!isObject(source.overrides)) {
      throw new TopologyError(`${label} overrides must be an object`, 2);
    }
    for (const [skill, destinations] of Object.entries(source.overrides)) {
      if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/u.test(skill)) {
        throw new TopologyError(`${label} has an invalid override skill name: ${skill}`, 2);
      }
      validateDestinations(destinations, `${label} override ${skill}`);
    }
  }
  return manifest;
}

function readRegistry() {
  const registry = readJson(registryPath, "topology adapter registry");
  if (!Array.isArray(registry) || registry.length === 0) {
    throw new TopologyError("topology adapter registry must be a non-empty array", 2);
  }
  const sourceIds = new Set();
  for (const [index, adapter] of registry.entries()) {
    const label = `topology adapter registry entry ${index}`;
    validateFields(adapter, ["sourceId", "classification", "supportedDestinations", "command"], ["sourceId", "classification", "supportedDestinations", "command"], label);
    if (typeof adapter.sourceId !== "string" || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/u.test(adapter.sourceId)) {
      throw new TopologyError(`${label} has an invalid sourceId`, 2);
    }
    if (sourceIds.has(adapter.sourceId)) {
      throw new TopologyError(`topology adapter registry contains duplicate sourceId: ${adapter.sourceId}`, 2);
    }
    sourceIds.add(adapter.sourceId);
    if (!CLASSIFICATIONS.includes(adapter.classification)) {
      throw new TopologyError(`${label} contains unknown classification: ${String(adapter.classification)}`, 2);
    }
    validateDestinations(adapter.supportedDestinations, `${label} supportedDestinations`);
    if (typeof adapter.command !== "string" || adapter.command.length === 0 || path.isAbsolute(adapter.command) || adapter.command.split(/[\\/]/u).includes("..")) {
      throw new TopologyError(`${label} has an invalid command`, 2);
    }
  }
  return registry;
}

function lockDirectoryPath() {
  const userId = typeof process.getuid === "function" ? process.getuid() : "user";
  return path.join(os.tmpdir(), `agent-scripts-skill-topology-${userId}.lock`);
}

function readLockPid(lockPath) {
  try {
    const value = fs.readFileSync(path.join(lockPath, "pid"), "utf8").trim();
    return /^[1-9][0-9]*$/u.test(value) ? Number(value) : null;
  } catch {
    return null;
  }
}

function processIsAlive(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    return error.code === "EPERM";
  }
}

function cleanupStaleDiscoveryDirectories() {
  for (const entry of fs.readdirSync(os.tmpdir(), { withFileTypes: true })) {
    if (entry.name.startsWith("agent-scripts-topology-discovery-")) {
      fs.rmSync(path.join(os.tmpdir(), entry.name), { recursive: true, force: true });
    }
  }
}

function acquireLock() {
  const lockPath = lockDirectoryPath();
  let recoveredPid = null;
  let recoveredLock = false;

  for (let attempt = 0; attempt < 5; attempt += 1) {
    try {
      fs.mkdirSync(lockPath);
      try {
        fs.writeFileSync(path.join(lockPath, "pid"), `${process.pid}\n`, { flag: "wx" });
      } catch (error) {
        fs.rmSync(lockPath, { recursive: true, force: true });
        throw error;
      }
      if (recoveredLock) {
        cleanupStaleDiscoveryDirectories();
      }
      const warnings = recoveredLock ? [{
        code: "stale-lock-recovered",
        message: recoveredPid === null
          ? "recovered stale topology lock with no recorded PID"
          : `recovered stale topology lock held by PID ${recoveredPid}`,
      }] : [];
      return { path: lockPath, warnings };
    } catch (error) {
      if (error.code !== "EEXIST") {
        throw new TopologyError(`could not acquire topology lock: ${error.message}`, 1);
      }

      const ownerPid = readLockPid(lockPath);
      if (ownerPid !== null && processIsAlive(ownerPid)) {
        throw new TopologyError(`skill topology is already running (PID ${ownerPid})`, 1);
      }
      if (ownerPid === null) {
        try {
          const ageMilliseconds = Date.now() - fs.statSync(lockPath).mtimeMs;
          if (ageMilliseconds < 5000) {
            throw new TopologyError("skill topology is already running (PID pending)", 1);
          }
        } catch (statError) {
          if (statError instanceof TopologyError) {
            throw statError;
          }
          if (statError.code === "ENOENT") {
            continue;
          }
          throw new TopologyError(`could not inspect topology lock: ${statError.message}`, 1);
        }
      }

      const stalePath = `${lockPath}.stale-${process.pid}-${Date.now()}`;
      try {
        fs.renameSync(lockPath, stalePath);
      } catch (renameError) {
        if (renameError.code === "ENOENT") {
          continue;
        }
        throw new TopologyError(`could not recover stale topology lock: ${renameError.message}`, 1);
      }
      fs.rmSync(stalePath, { recursive: true, force: true });
      recoveredPid = ownerPid;
      recoveredLock = true;
    }
  }

  throw new TopologyError("could not acquire topology lock after concurrent recovery", 1);
}

function releaseLock(lock) {
  if (!lock) {
    return;
  }
  if (readLockPid(lock.path) === process.pid) {
    fs.rmSync(lock.path, { recursive: true, force: true });
  }
}

function discoverInventory(adapter, discoveryRoot) {
  const command = path.resolve(moduleDirectory, adapter.command);
  return new Promise((resolve, reject) => {
    const child = spawn(command, [adapter.sourceId, repoRoot, discoveryRoot], {
      cwd: repoRoot,
      env: process.env,
      stdio: ["ignore", "pipe", "pipe"],
    });
    activeChildren.add(child);
    let stdout = "";
    let stderr = "";
    child.stdout.setEncoding("utf8");
    child.stderr.setEncoding("utf8");
    child.stdout.on("data", (chunk) => { stdout += chunk; });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.on("error", (error) => {
      activeChildren.delete(child);
      reject(new TopologyError(`source ${adapter.sourceId} discovery failed: ${error.message}`, 1));
    });
    child.on("close", (code) => {
      activeChildren.delete(child);
      if (code !== 0) {
        reject(new TopologyError(`source ${adapter.sourceId} discovery failed${stderr.trim() ? `: ${stderr.trim()}` : ""}`, 1));
        return;
      }
      const inventory = stdout.split(/\r?\n/u).filter(Boolean).sort();
      resolve(inventory);
    });
  });
}

function orderedDestinations(destinations) {
  return DESTINATIONS.filter((destination) => destinations.includes(destination));
}

function destinationPath(destination, skill) {
  if (destination === "claude") {
    return path.join(repoRoot, "skills", skill);
  }
  return path.join(os.homedir(), ".agents", "skills", skill);
}

async function checkTopology() {
  const manifest = readManifest();
  const registry = readRegistry();
  const manifestBySource = new Map(manifest.sources.map((source) => [source.id, source]));
  const registryBySource = new Map(registry.map((adapter) => [adapter.sourceId, adapter]));

  for (const source of manifest.sources) {
    const adapter = registryBySource.get(source.id);
    if (!adapter) {
      throw new TopologyError(`manifest source has no registered adapter: ${source.id}`, 2);
    }
    if (adapter.classification !== source.classification) {
      throw new TopologyError(`source classification mismatch for ${source.id}: manifest=${source.classification}, registry=${adapter.classification}`, 2);
    }
  }

  const discoveryRoot = fs.mkdtempSync(path.join(os.tmpdir(), "agent-scripts-topology-discovery-"));

  try {
    const sources = [];
    const plan = [];
    const decisions = registry
      .filter((adapter) => !manifestBySource.has(adapter.sourceId))
      .map((adapter) => ({
        code: "adapter-without-policy",
        sourceId: adapter.sourceId,
        message: `registered adapter has no manifest policy: ${adapter.sourceId}`,
      }));

    for (const source of [...manifest.sources].sort((left, right) => left.id.localeCompare(right.id))) {
      const adapter = registryBySource.get(source.id);
      const inventory = await discoverInventory(adapter, discoveryRoot);
      if (new Set(inventory).size !== inventory.length || inventory.some((skill) => !/^[a-z0-9]+(?:-[a-z0-9]+)*$/u.test(skill))) {
        throw new TopologyError(`source ${source.id} returned an invalid inventory`, 1);
      }

      for (const skill of Object.keys(source.overrides).sort()) {
        if (!inventory.includes(skill)) {
          decisions.push({
            code: "stale-override",
            sourceId: source.id,
            skill,
            message: `override names a skill absent from ${source.id}: ${skill}`,
          });
        }
      }

      for (const skill of inventory) {
        const destinations = orderedDestinations(source.overrides?.[skill] ?? source.defaultDestinations ?? []);
        for (const destination of destinations) {
          if (!adapter.supportedDestinations.includes(destination)) {
            decisions.push({
              code: "unsupported-destination",
              sourceId: source.id,
              skill,
              destination,
              message: `${source.id} cannot distribute ${skill} to ${destination}`,
            });
          }
        }
        plan.push({ sourceId: source.id, skill, destinations, missingDestinations: [], unexpectedDestinations: [] });
      }
      sources.push({
        id: source.id,
        classification: source.classification,
        inventoryCount: inventory.length,
        defaultDestinations: orderedDestinations(source.defaultDestinations ?? []),
        result: "clean",
      });
    }

    const destinationClaims = new Map();
    for (const entry of plan) {
      for (const destination of entry.destinations) {
        const claimKey = `${entry.skill}\u0000${destination}`;
        const claims = destinationClaims.get(claimKey) ?? [];
        claims.push(entry.sourceId);
        destinationClaims.set(claimKey, claims);
      }
    }
    for (const [claimKey, sourceIds] of destinationClaims) {
      if (sourceIds.length < 2) {
        continue;
      }
      const [skill, destination] = claimKey.split("\u0000");
      decisions.push({
        code: "surface-collision",
        sourceIds: [...sourceIds].sort(),
        skill,
        destination,
        message: `${skill} is claimed by multiple sources on ${destination}: ${[...sourceIds].sort().join(", ")}`,
      });
    }

    decisions.sort((left, right) => `${left.code}\u0000${left.sourceId ?? left.sourceIds?.join(",") ?? ""}\u0000${left.skill ?? ""}\u0000${left.destination ?? ""}`.localeCompare(`${right.code}\u0000${right.sourceId ?? right.sourceIds?.join(",") ?? ""}\u0000${right.skill ?? ""}\u0000${right.destination ?? ""}`));
    if (decisions.length > 0) {
      for (const source of sources) {
        if (decisions.some((decision) => decision.sourceId === source.id || decision.sourceIds?.includes(source.id))) {
          source.result = "decision-required";
        }
      }
      return {
        document: {
          schemaVersion: 1,
          mode: "check",
          status: "decision-required",
          sources,
          plan,
          drift: [],
          decisions,
          errors: [],
          warnings: [],
        },
        exitCode: 3,
      };
    }

    const drift = [];
    for (const entry of plan) {
      const adapter = registryBySource.get(entry.sourceId);
      for (const destination of adapter.supportedDestinations) {
        const present = fs.existsSync(destinationPath(destination, entry.skill));
        const desired = entry.destinations.includes(destination);
        if (desired && !present) {
          entry.missingDestinations.push(destination);
          drift.push({ sourceId: entry.sourceId, skill: entry.skill, destination, reason: "missing" });
        } else if (!desired && present) {
          entry.unexpectedDestinations.push(destination);
          drift.push({ sourceId: entry.sourceId, skill: entry.skill, destination, reason: "unexpected" });
        }
      }
    }

    for (const source of sources) {
      if (drift.some((item) => item.sourceId === source.id)) {
        source.result = "drift";
      }
    }

    return {
      document: {
        schemaVersion: 1,
        mode: "check",
        status: drift.length === 0 ? "clean" : "drift",
        sources,
        plan,
        drift,
        decisions,
        errors: [],
        warnings: [],
      },
      exitCode: drift.length === 0 ? 0 : 1,
    };
  } finally {
    fs.rmSync(discoveryRoot, { recursive: true, force: true });
  }
}

function writeHuman(document) {
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

function failureDocument(error) {
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

const requestedJson = process.argv.slice(2).includes("--json");
let options;
let interrupted = false;

function handleInterrupt() {
  if (interrupted) {
    return;
  }
  interrupted = true;
  for (const child of activeChildren) {
    child.kill("SIGTERM");
  }
}

process.once("SIGINT", handleInterrupt);
process.once("SIGTERM", handleInterrupt);

async function run() {
  options = parseArguments(process.argv.slice(2));
  if (options.help) {
    process.stdout.write(HELP);
    return { exitCode: 0, document: null };
  }

  const lock = acquireLock();
  activeLock = lock;
  try {
    const result = await checkTopology();
    if (interrupted) {
      throw new TopologyError("interrupted", 130);
    }
    result.document.warnings.unshift(...lock.warnings);
    return result;
  } finally {
    releaseLock(lock);
    if (activeLock === lock) {
      activeLock = null;
    }
  }
}

try {
  const result = await run();
  if (result.document !== null) {
    if (options.json) {
      process.stdout.write(`${JSON.stringify(result.document, null, 2)}\n`);
    } else {
      writeHuman(result.document);
    }
  }
  process.exitCode = result.exitCode;
} catch (caught) {
  const error = interrupted
    ? new TopologyError("interrupted", 130)
    : caught instanceof TopologyError
      ? caught
      : new TopologyError(caught.message, 1);
  if (requestedJson) {
    process.stdout.write(`${JSON.stringify(failureDocument(error), null, 2)}\n`);
  } else {
    process.stderr.write(`error: ${error.message}\n`);
  }
  process.exitCode = error.exitCode;
}
