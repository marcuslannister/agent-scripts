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
import { inspectDestination, listRetiredOwnedCopies } from "./state.mjs";

const moduleDirectory = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(moduleDirectory, "../..");
const manifestPath = path.join(repoRoot, "skill-topology.json");
const registryPath = path.join(moduleDirectory, "registry.json");
const activeChildren = new Set();
let activeLock = null;

function parseArguments(args) {
  if (args.length === 1 && (args[0] === "--help" || args[0] === "-h")) {
    return { help: true, json: false, mode: "reconcile" };
  }

  const json = args.includes("--json");
  const check = args.includes("--check");
  const known = args.every((argument) => argument === "--check" || argument === "--json");
  if (!known || args.filter((argument) => argument === "--check").length > 1 || args.filter((argument) => argument === "--json").length > 1) {
    throw new TopologyError("invalid arguments; use --check only to preview the skill topology", 2);
  }

  return { help: false, json, mode: check ? "check" : "reconcile" };
}

function runAdapterProcess(adapter, args) {
  const command = path.resolve(moduleDirectory, adapter.command);
  return new Promise((resolve) => {
    const child = spawn(command, args, {
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
    let finished = false;
    const finish = (result) => {
      if (finished) {
        return;
      }
      finished = true;
      activeChildren.delete(child);
      resolve(result);
    };
    child.on("error", (error) => {
      finish({ code: 1, stdout, stderr: error.message });
    });
    child.on("close", (code) => {
      finish({ code: code ?? 1, stdout, stderr });
    });
  });
}

function adapterFailureMessages(prefix, stderr) {
  const details = stderr.split(/\r?\n/u).map((line) => line.trim()).filter(Boolean);
  return details.length > 0
    ? details.map((detail) => `${prefix}: ${detail}`)
    : [prefix];
}

async function discoverInventory(adapter, discoveryRoot, mode) {
  const result = await runAdapterProcess(adapter, [adapter.sourceId, repoRoot, discoveryRoot, "discover", "", os.homedir(), mode]);
  if (interrupted) {
    throw new TopologyError("interrupted", 130);
  }
  if (result.code !== 0) {
    throw new TopologyError(`source ${adapter.sourceId} discovery failed${result.stderr.trim() ? `: ${result.stderr.trim()}` : ""}`, 1);
  }
  return result.stdout.split(/\r?\n/u).filter(Boolean).sort();
}

function orderedDestinations(destinations) {
  return DESTINATIONS.filter((destination) => destinations.includes(destination));
}

function runRuntimeAdapter(adapter, action, discoveryRoot, planPath, mode = "reconcile") {
  return runAdapterProcess(adapter, [adapter.sourceId, repoRoot, discoveryRoot, action, planPath, os.homedir(), mode]);
}

function writeNativePluginAllowlist(discoveryRoot, manifest, registryBySource) {
  const entries = [];
  for (const source of manifest.sources) {
    const plugin = registryBySource.get(source.id)?.plugin;
    if (!plugin) {
      continue;
    }
    for (const [destination, marketplace] of Object.entries(plugin.marketplaces)) {
      entries.push(`${destination}\t${plugin.name}@${marketplace}`);
    }
  }
  entries.sort();
  fs.writeFileSync(path.join(discoveryRoot, "native-plugins.tsv"), `${entries.join("\n")}${entries.length > 0 ? "\n" : ""}`);
}

function expectedStatesForAdapter(adapter, plan, destinationClaims) {
  const expectedStates = [];
  for (const entry of plan.filter((candidate) => candidate.sourceId === adapter.sourceId)) {
    for (const destination of adapter.supportedDestinations) {
      if (entry.sourceId === "repo-claude" && destination === "claude") {
        continue;
      }
      const claimedByOtherSource = (destinationClaims.get(`${entry.skill}\u0000${destination}`) ?? [])
        .some((sourceId) => sourceId !== entry.sourceId);
      if (!entry.destinations.includes(destination) && claimedByOtherSource) {
        continue;
      }
      expectedStates.push({
        state: entry.destinations.includes(destination) ? "present" : "absent",
        skill: entry.skill,
        destination,
      });
    }
  }
  return expectedStates;
}

async function inspectAdapterState({ adapter, plan, destinationClaims, discoveryRoot, mode }) {
  const drift = [];
  const decisions = [];
  const errors = [];
  const skipped = [];
  const expectedStates = expectedStatesForAdapter(adapter, plan, destinationClaims);
  const planPath = path.join(discoveryRoot, `${adapter.sourceId}.inspect.tsv`);
  fs.writeFileSync(planPath, expectedStates
    .map((item) => `${item.state}\t${item.skill}\t${item.destination}\n`)
    .join(""));

  const result = await runRuntimeAdapter(adapter, "inspect", discoveryRoot, planPath, mode);
  if (interrupted) {
    throw new TopologyError("interrupted", 130);
  }
  if (result.code !== 0) {
    errors.push(...adapterFailureMessages(`source ${adapter.sourceId} inspection failed`, result.stderr));
  }

  const expectedByKey = new Map(expectedStates.map((item) => [`${item.skill}\u0000${item.destination}`, item]));
  const seen = new Set();
  for (const line of result.stdout.split(/\r?\n/u).filter(Boolean)) {
    const [state, skill, destination, detail, ...extra] = line.split("\t");
    const key = `${skill}\u0000${destination}`;
    const validName = /^[a-z0-9]+(?:-[a-z0-9]+)*$/u.test(skill ?? "");
    const validDestination = DESTINATIONS.includes(destination);
    if (extra.length > 0 || !validName || !validDestination || !detail) {
      errors.push(`source ${adapter.sourceId} returned invalid inspection output`);
      continue;
    }
    if (state === "decision") {
      if (!/^[a-z0-9]+(?:-[a-z0-9]+)*@[a-z0-9]+(?:-[a-z0-9]+)*$/u.test(detail)
          || seen.has(`decision\u0000${destination}\u0000${detail}`)) {
        errors.push(`source ${adapter.sourceId} returned invalid decision inspection output`);
        continue;
      }
      seen.add(`decision\u0000${destination}\u0000${detail}`);
      decisions.push({
        code: "unknown-installed-plugin",
        sourceId: adapter.sourceId,
        skill,
        destination,
        pluginId: detail,
        message: `installed third-party plugin ${detail} on ${destination} is not listed in skill-topology.json`,
      });
      continue;
    }
    if (state === "orphan") {
      if (expectedByKey.has(key) || seen.has(`orphan\u0000${key}`)) {
        errors.push(`source ${adapter.sourceId} returned invalid orphan inspection output`);
        continue;
      }
      seen.add(`orphan\u0000${key}`);
      drift.push({ sourceId: adapter.sourceId, skill, destination, reason: "unexpected" });
      continue;
    }
    if (!["present", "absent", "drift", "foreign", "error"].includes(state) || !expectedByKey.has(key) || seen.has(key)) {
      errors.push(`source ${adapter.sourceId} returned invalid inspection output`);
      continue;
    }
    seen.add(key);
    const expected = expectedByKey.get(key);
    if (state === "error") {
      errors.push(`cannot verify ${adapter.sourceId}/${skill} on ${destination}: ${detail}`);
    } else if (state === "foreign") {
      if (expected.state === "present") {
        decisions.push({
          code: "surface-ownership-collision",
          sourceId: adapter.sourceId,
          skill,
          destination,
          message: `${skill} exists on ${destination} but is not the managed ${adapter.sourceId} copy`,
        });
      } else {
        skipped.push({ sourceId: adapter.sourceId, skill, destination, reason: detail });
      }
    } else if (expected.state === "present" && state === "absent") {
      const entry = plan.find((candidate) => candidate.sourceId === adapter.sourceId && candidate.skill === skill);
      if (entry && !entry.missingDestinations.includes(destination)) {
        entry.missingDestinations.push(destination);
      }
      drift.push({ sourceId: adapter.sourceId, skill, destination, reason: "missing" });
    } else if (expected.state === "present" && state === "drift") {
      drift.push({ sourceId: adapter.sourceId, skill, destination, reason: detail });
    } else if (expected.state === "absent" && ["present", "drift"].includes(state)) {
      const entry = plan.find((candidate) => candidate.sourceId === adapter.sourceId && candidate.skill === skill);
      if (entry && !entry.unexpectedDestinations.includes(destination)) {
        entry.unexpectedDestinations.push(destination);
      }
      drift.push({ sourceId: adapter.sourceId, skill, destination, reason: "unexpected" });
    }
  }

  for (const [key, expected] of expectedByKey) {
    if (!seen.has(key)) {
      errors.push(`source ${adapter.sourceId} returned incomplete inspection for ${expected.skill} -> ${expected.destination}`);
    }
  }
  return { drift, decisions, errors, skipped };
}

async function inspectPlan({ plan, registryBySource, destinationClaims, discoveryRoot, mode }) {
  const drift = [];
  const decisions = [];
  const errors = [];
  const skipped = [];

  for (const entry of plan) {
    entry.missingDestinations = [];
    entry.unexpectedDestinations = [];
    const adapter = registryBySource.get(entry.sourceId);
    if (adapter.stateInspection === "adapter") {
      continue;
    }
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
        if (desired) {
          decisions.push({
            code: "surface-ownership-collision",
            sourceId: entry.sourceId,
            skill: entry.skill,
            destination,
            message: `${entry.skill} exists on ${destination} but is not the managed ${entry.sourceId} copy`,
          });
        } else {
          skipped.push({
            sourceId: entry.sourceId,
            skill: entry.skill,
            destination,
            reason: destinationState.reason,
          });
        }
        continue;
      }
      if (destinationState.kind === "verification-failed") {
        errors.push(destinationState.message);
        continue;
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

  const desiredCodexSkills = new Set(plan
    .filter((entry) => entry.destinations.includes("codex"))
    .map((entry) => entry.skill));
  for (const copy of listRetiredOwnedCopies(os.homedir())) {
    if (desiredCodexSkills.has(copy.skill) || drift.some((item) => item.skill === copy.skill && item.destination === "codex")) {
      continue;
    }
    const sourceId = plan.find((entry) => entry.skill === copy.skill)?.sourceId ?? "repo-claude";
    drift.push({ sourceId, skill: copy.skill, destination: "codex", reason: "unexpected" });
  }

  for (const adapter of [...registryBySource.values()].filter((candidate) => candidate.stateInspection === "adapter")) {
    const inspected = await inspectAdapterState({ adapter, plan, destinationClaims, discoveryRoot, mode });
    drift.push(...inspected.drift);
    decisions.push(...inspected.decisions);
    errors.push(...inspected.errors);
    skipped.push(...inspected.skipped);
  }

  drift.sort((left, right) => `${left.sourceId}\u0000${left.skill}\u0000${left.destination}`.localeCompare(`${right.sourceId}\u0000${right.skill}\u0000${right.destination}`));
  skipped.sort((left, right) => `${left.sourceId}\u0000${left.skill}\u0000${left.destination}`.localeCompare(`${right.sourceId}\u0000${right.skill}\u0000${right.destination}`));
  return { drift, decisions, errors, skipped };
}

async function reconcileTopology({ document, plan, registryBySource, destinationClaims, discoveryRoot }) {
  const actionsBySource = new Map([...registryBySource.keys()].map((sourceId) => [sourceId, []]));
  const verificationBySource = new Map([...registryBySource.values()]
    .map((adapter) => [adapter.sourceId, expectedStatesForAdapter(adapter, plan, destinationClaims)]));
  for (const item of document.drift) {
    const entry = plan.find((candidate) => candidate.sourceId === item.sourceId && candidate.skill === item.skill);
    const operation = entry?.destinations.includes(item.destination) ? "install" : "remove";
    actionsBySource.get(item.sourceId).push({ operation, skill: item.skill, destination: item.destination });
  }
  for (const item of document.drift) {
    if (plan.some((entry) => entry.sourceId === item.sourceId && entry.skill === item.skill)) {
      continue;
    }
    verificationBySource.get(item.sourceId).push({ state: "absent", skill: item.skill, destination: item.destination });
  }
  for (const [sourceId, expectedStates] of verificationBySource) {
    const adapter = registryBySource.get(sourceId);
    if (!adapter.plugin) {
      continue;
    }
    for (const item of expectedStates.filter((candidate) => candidate.state === "present")) {
      const hasDriftAction = actionsBySource.get(sourceId)
        .some((action) => action.skill === item.skill && action.destination === item.destination);
      if (!hasDriftAction) {
        actionsBySource.get(sourceId).push({ operation: "refresh", skill: item.skill, destination: item.destination });
      }
    }
  }

  const changes = [];
  const errors = [];
  for (const [sourceId, actions] of [...actionsBySource].sort(([left], [right]) => left.localeCompare(right))) {
    const planPath = path.join(discoveryRoot, `${sourceId}.reconcile.tsv`);
    const planText = actions
      .sort((left, right) => `${left.skill}\u0000${left.destination}`.localeCompare(`${right.skill}\u0000${right.destination}`))
      .map((item) => `${item.operation}\t${item.skill}\t${item.destination}\n`)
      .join("");
    fs.writeFileSync(planPath, planText);
    const result = await runRuntimeAdapter(registryBySource.get(sourceId), "reconcile", discoveryRoot, planPath);
    if (interrupted) {
      throw new TopologyError("interrupted", 130);
    }
    for (const line of result.stdout.split(/\r?\n/u).filter(Boolean)) {
      const [action, skill, destination, ...extra] = line.split("\t");
      if (extra.length > 0 || !["installed", "removed", "updated"].includes(action) || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/u.test(skill ?? "") || !DESTINATIONS.includes(destination)) {
        errors.push(`source ${sourceId} returned invalid reconcile output`);
        continue;
      }
      changes.push({ action, sourceId, skill, destination });
    }
    if (result.code !== 0) {
      errors.push(...adapterFailureMessages(`source ${sourceId} reconciliation failed`, result.stderr));
    }
  }

  for (const [sourceId, expectedStates] of [...verificationBySource].sort(([left], [right]) => left.localeCompare(right))) {
    const planPath = path.join(discoveryRoot, `${sourceId}.verify.tsv`);
    const planText = expectedStates
      .sort((left, right) => `${left.skill}\u0000${left.destination}`.localeCompare(`${right.skill}\u0000${right.destination}`))
      .map((item) => `${item.state}\t${item.skill}\t${item.destination}\n`)
      .join("");
    fs.writeFileSync(planPath, planText);
    const result = await runRuntimeAdapter(registryBySource.get(sourceId), "verify", discoveryRoot, planPath);
    if (interrupted) {
      throw new TopologyError("interrupted", 130);
    }
    if (result.stdout.trim()) {
      errors.push(`source ${sourceId} returned invalid verification output`);
    }
    if (result.code !== 0) {
      errors.push(...adapterFailureMessages(`source ${sourceId} verification failed`, result.stderr));
    }
  }

  const verification = await inspectPlan({ plan, registryBySource, destinationClaims, discoveryRoot, mode: "reconcile" });
  errors.push(...verification.errors);
  for (const item of verification.drift) {
    errors.push(`final verification failed: ${item.sourceId}/${item.skill} -> ${item.destination}: ${item.reason}`);
  }

  for (const source of document.sources) {
    source.result = verification.decisions.some((item) => item.sourceId === source.id)
      ? "decision-required"
      : (errors.some((message) => message.includes(`source ${source.id}`))
          || verification.drift.some((item) => item.sourceId === source.id))
        ? "failed"
        : changes.some((item) => item.sourceId === source.id)
          ? "changed"
          : "clean";
  }

  document.mode = "reconcile";
  document.status = verification.decisions.length > 0
    ? "decision-required"
    : errors.length === 0
      ? "reconciled"
      : "failed";
  document.drift = verification.drift;
  document.decisions = verification.decisions;
  document.errors = errors;
  document.changes = changes;
  document.skipped = verification.skipped;
  const exitCode = verification.decisions.length > 0 ? 3 : errors.length === 0 ? 0 : 1;
  return { document, exitCode };
}

async function evaluateTopology(mode) {
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
    writeNativePluginAllowlist(discoveryRoot, manifest, registryBySource);
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

      const inventory = await discoverInventory(adapter, discoveryRoot, mode);
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
        supportedDestinations: orderedDestinations(adapter.supportedDestinations),
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

    const inspected = await inspectPlan({ plan, registryBySource, destinationClaims, discoveryRoot, mode });
    const drift = inspected.drift;
    decisions.push(...inspected.decisions);

    if (decisions.length > 0) {
      decisions.sort((left, right) => `${left.code}\u0000${left.sourceId ?? left.sourceIds?.join(",") ?? ""}\u0000${left.skill ?? ""}\u0000${left.destination ?? ""}`.localeCompare(`${right.code}\u0000${right.sourceId ?? right.sourceIds?.join(",") ?? ""}\u0000${right.skill ?? ""}\u0000${right.destination ?? ""}`));
      for (const source of sources) {
        if (decisions.some((decision) => decision.sourceId === source.id || decision.sourceIds?.includes(source.id))) {
          source.result = "decision-required";
        }
      }
      return {
        document: {
          schemaVersion: 1,
          mode,
          status: "decision-required",
          sources,
          plan,
          drift,
          decisions,
          errors: inspected.errors,
          warnings: [],
          changes: [],
          skipped: inspected.skipped,
        },
        exitCode: 3,
      };
    }

    if (inspected.errors.length > 0) {
      for (const source of sources) {
        if (inspected.errors.some((error) => error.includes(`${source.id}/`))) {
          source.result = "failed";
        }
      }
      return {
        document: {
          schemaVersion: 1,
          mode,
          status: "failed",
          sources,
          plan,
          drift,
          decisions: [],
          errors: inspected.errors,
          warnings: [],
          changes: [],
          skipped: inspected.skipped,
        },
        exitCode: 1,
      };
    }

    for (const source of sources) {
      if (drift.some((item) => item.sourceId === source.id)) {
        source.result = "drift";
      }
    }

    const document = {
      schemaVersion: 1,
      mode,
      status: drift.length === 0 ? "clean" : "drift",
      sources,
      plan,
      drift,
      decisions,
      errors: [],
      warnings: [],
      changes: [],
      skipped: inspected.skipped,
    };
    if (mode === "reconcile") {
      return await reconcileTopology({ document, plan, registryBySource, destinationClaims, discoveryRoot });
    }
    return {
      document,
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
    const result = await evaluateTopology(options.mode);
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
    const mode = process.argv.slice(2).includes("--check") ? "check" : "reconcile";
    process.stdout.write(`${JSON.stringify(failureDocument(error, mode), null, 2)}\n`);
  } else {
    process.stderr.write(`error: ${error.message}\n`);
  }
  process.exitCode = error.exitCode;
}
