import { createHash } from "node:crypto";
import fs from "node:fs";
import path from "node:path";

const COPY_OWNER = "repo-skills";

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
      return { kind: "foreign" };
    }
    const recordedSource = fs.realpathSync(path.resolve(repoRoot, markerLines[0] ?? ""));
    const expectedSource = fs.realpathSync(expectedSourcePath);
    if (recordedSource !== expectedSource) {
      return { kind: "foreign" };
    }
  } catch {
    return { kind: "foreign" };
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
