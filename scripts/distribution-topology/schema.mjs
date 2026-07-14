import fs from "node:fs";
import path from "node:path";

import { TopologyError } from "./errors.mjs";

export const DESTINATIONS = ["claude", "codex"];
const CLASSIFICATIONS = ["repo-owned", "npx-only", "source-only", "plugin-both", "plugin-claude-only"];

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

function validatePluginMetadata(value, label, supportedDestinations) {
  validateFields(value, ["name", "repo", "marketplaces"], ["name", "repo", "marketplaces"], label);
  if (typeof value.name !== "string" || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/u.test(value.name)) {
    throw new TopologyError(`${label} has an invalid name`, 2);
  }
  if (typeof value.repo !== "string" || !/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/u.test(value.repo)) {
    throw new TopologyError(`${label} has an invalid repo`, 2);
  }
  if (!isObject(value.marketplaces) || Object.keys(value.marketplaces).length === 0) {
    throw new TopologyError(`${label} marketplaces must be a non-empty object`, 2);
  }
  const unknownDestinations = Object.keys(value.marketplaces)
    .filter((destination) => !DESTINATIONS.includes(destination));
  if (unknownDestinations.length > 0) {
    throw new TopologyError(`${label} marketplaces contains unknown destination: ${unknownDestinations[0]}`, 2);
  }
  for (const destination of supportedDestinations) {
    const marketplace = value.marketplaces[destination];
    if (typeof marketplace !== "string" || !/^[a-z0-9]+(?:-[a-z0-9-]*[a-z0-9])?$/u.test(marketplace)) {
      throw new TopologyError(`${label} is missing a valid ${destination} marketplace`, 2);
    }
  }
}

export function readManifest(manifestPath) {
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

export function readRegistry(registryPath) {
  const registry = readJson(registryPath, "topology adapter registry");
  if (!Array.isArray(registry) || registry.length === 0) {
    throw new TopologyError("topology adapter registry must be a non-empty array", 2);
  }
  const sourceIds = new Set();
  for (const [index, adapter] of registry.entries()) {
    const label = `topology adapter registry entry ${index}`;
    validateFields(adapter, ["sourceId", "classification", "supportedDestinations", "command", "stateInspection", "plugin"], ["sourceId", "classification", "supportedDestinations", "command"], label);
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
    if (adapter.stateInspection !== undefined && !["topology", "adapter"].includes(adapter.stateInspection)) {
      throw new TopologyError(`${label} has an invalid stateInspection`, 2);
    }
    const pluginClassification = ["plugin-both", "plugin-claude-only"].includes(adapter.classification);
    if (!pluginClassification && adapter.plugin !== undefined) {
      throw new TopologyError(`${label} has plugin metadata for a non-plugin source`, 2);
    }
    if (adapter.plugin !== undefined) {
      const requiredPluginDestinations = adapter.classification === "plugin-both"
        ? adapter.supportedDestinations
        : Object.keys(adapter.plugin.marketplaces);
      validatePluginMetadata(adapter.plugin, `${label} plugin`, requiredPluginDestinations);
    }
    adapter.stateInspection ??= "topology";
  }
  return registry;
}
