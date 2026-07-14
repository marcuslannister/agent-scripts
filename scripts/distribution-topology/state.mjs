import { createHash } from "node:crypto";
import fs from "node:fs";
import path from "node:path";

export const COPY_OWNER = "repo-skills";

function contentFiles(root) {
  const files = [];

  function walk(directory, parts) {
    for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
      if (entry.name.startsWith(".")) {
        continue;
      }
      const nextParts = [...parts, entry.name];
      const absolutePath = path.join(directory, entry.name);
      if (entry.isDirectory()) {
        walk(absolutePath, nextParts);
      } else if (entry.isFile()) {
        files.push({ absolutePath, relativePath: `./${nextParts.join("/")}` });
      }
    }
  }

  walk(root, []);
  return files.sort((left, right) => Buffer.compare(Buffer.from(left.relativePath), Buffer.from(right.relativePath)));
}

export function computeCopyHash(root) {
  const combinedHash = createHash("sha256");
  for (const file of contentFiles(root)) {
    const fileHash = createHash("sha256").update(fs.readFileSync(file.absolutePath)).digest("hex");
    combinedHash.update(file.relativePath);
    combinedHash.update("\0");
    combinedHash.update(fileHash);
    combinedHash.update("\0");
  }
  return combinedHash.digest("hex");
}

function sourceSkillPath(repoRoot, sourceId, skill) {
  const sourceDirectory = sourceId === "repo-claude" ? "skills" : "codex-skills";
  return path.join(repoRoot, sourceDirectory, skill);
}

function destinationPath(repoRoot, home, destination, skill) {
  if (destination === "claude") {
    return path.join(repoRoot, "skills", skill);
  }
  return path.join(home, ".agents", "skills", skill);
}

function canonicalPath(candidate) {
  try {
    return fs.realpathSync(candidate);
  } catch {
    return path.resolve(candidate);
  }
}

export function inspectDestination({ repoRoot, home, sourceId, skill, destination }) {
  if (sourceId === "repo-claude" && destination === "claude") {
    return { kind: "canonical" };
  }

  const installedPath = destinationPath(repoRoot, home, destination, skill);
  if (!fs.existsSync(installedPath)) {
    return { kind: "absent" };
  }

  const expectedSourcePath = sourceSkillPath(repoRoot, sourceId, skill);
  let markerLines;
  try {
    markerLines = fs.readFileSync(path.join(installedPath, ".agent-scripts-copy"), "utf8").split(/\r?\n/u);
    if (markerLines[1] !== COPY_OWNER) {
      return { kind: "foreign", reason: markerLines[1] ? "other-owner" : "unowned" };
    }
    const recordedSource = canonicalPath(path.resolve(repoRoot, markerLines[0] ?? ""));
    const expectedSource = canonicalPath(expectedSourcePath);
    if (recordedSource !== expectedSource) {
      return { kind: "managed", driftReason: "source-mismatch" };
    }
  } catch {
    return { kind: "foreign", reason: "unowned" };
  }

  const storedHash = markerLines[2];
  if (!storedHash) {
    return { kind: "managed", driftReason: "unstamped" };
  }

  try {
    const sourceHash = computeCopyHash(expectedSourcePath);
    const installedHash = computeCopyHash(installedPath);
    return storedHash === sourceHash && storedHash === installedHash
      ? { kind: "managed" }
      : { kind: "managed", driftReason: "content-mismatch" };
  } catch (error) {
    return { kind: "verification-failed", message: `cannot verify ${sourceId}/${skill} on ${destination}: ${error.message}` };
  }
}

export function listRetiredOwnedCopies(home) {
  const surface = path.join(home, ".agents", "skills");
  if (!fs.existsSync(surface)) {
    return [];
  }

  const copies = [];
  for (const entry of fs.readdirSync(surface, { withFileTypes: true })) {
    if (!entry.isDirectory() || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/u.test(entry.name)) {
      continue;
    }
    try {
      const marker = fs.readFileSync(path.join(surface, entry.name, ".agent-scripts-copy"), "utf8").split(/\r?\n/u);
      if (marker[1] === COPY_OWNER) {
        copies.push({ skill: entry.name, destination: "codex" });
      }
    } catch {
      // Unowned entries are outside retired-publisher cleanup.
    }
  }
  return copies.sort((left, right) => left.skill.localeCompare(right.skill));
}
