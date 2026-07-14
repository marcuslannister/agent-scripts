#!/usr/bin/env node

import { spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { TopologyError } from "./errors.mjs";
import { acquireLock, releaseLock } from "./lock.mjs";
import { failureDocument, HELP, writeHuman } from "./report.mjs";
import { DESTINATIONS, readManifest, readRegistry } from "./schema.mjs";
import { inspectDestination } from "./state.mjs";

const moduleDirectory = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(moduleDirectory, "../..");
const manifestPath = path.join(repoRoot, "skill-topology.json");
const registryPath = path.join(moduleDirectory, "registry.json");
const activeChildren = new Set();
let activeLock = null;

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

async function checkTopology() {
  const manifest = readManifest(manifestPath);
  const registry = readRegistry(registryPath);
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
      for (const destination of source.defaultDestinations) {
        if (!adapter.supportedDestinations.includes(destination)) {
          decisions.push({
            code: "unsupported-destination",
            sourceId: source.id,
            destination,
            message: `${source.id} does not support its default destination ${destination}`,
          });
        }
      }
      for (const [skill, destinations] of Object.entries(source.overrides)) {
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
      }

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
        const desired = entry.destinations.includes(destination);
        const claimedByOtherSource = (destinationClaims.get(`${entry.skill}\u0000${destination}`) ?? [])
          .some((sourceId) => sourceId !== entry.sourceId);
        if (!desired && claimedByOtherSource) {
          continue;
        }

        const destinationState = inspectDestination({
          repoRoot,
          home: os.homedir(),
          sourceId: entry.sourceId,
          skill: entry.skill,
          destination,
        });
        if (destinationState.kind === "foreign") {
          decisions.push({
            code: "surface-ownership-collision",
            sourceId: entry.sourceId,
            skill: entry.skill,
            destination,
            message: `${entry.skill} exists on ${destination} but is not the managed ${entry.sourceId} copy`,
          });
          continue;
        }
        if (destinationState.kind === "verification-failed") {
          throw new TopologyError(destinationState.message, 1);
        }

        const present = destinationState.kind !== "absent";
        if (desired && !present) {
          entry.missingDestinations.push(destination);
          drift.push({ sourceId: entry.sourceId, skill: entry.skill, destination, reason: "missing" });
        } else if (desired && destinationState.driftReason) {
          drift.push({ sourceId: entry.sourceId, skill: entry.skill, destination, reason: destinationState.driftReason });
        } else if (!desired && present) {
          entry.unexpectedDestinations.push(destination);
          drift.push({ sourceId: entry.sourceId, skill: entry.skill, destination, reason: "unexpected" });
        }
      }
    }

    if (decisions.length > 0) {
      decisions.sort((left, right) => `${left.sourceId}\u0000${left.skill}\u0000${left.destination}`.localeCompare(`${right.sourceId}\u0000${right.skill}\u0000${right.destination}`));
      for (const source of sources) {
        if (decisions.some((decision) => decision.sourceId === source.id)) {
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
          drift,
          decisions,
          errors: [],
          warnings: [],
        },
        exitCode: 3,
      };
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
