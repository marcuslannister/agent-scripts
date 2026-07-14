import { randomUUID } from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const PENDING_GRACE_MILLISECONDS = 5000;
const userId = typeof process.getuid === "function" ? process.getuid() : "user";
const CLAIM_PREFIX = `agent-scripts-skill-topology-${userId}.claim-`;
const RECOVERY_PREFIX = `agent-scripts-skill-topology-${userId}.recovered-`;

function processIsAlive(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    return error.code === "EPERM";
  }
}

function readText(filePath) {
  try {
    return fs.readFileSync(filePath, "utf8").trim();
  } catch {
    return "";
  }
}

function removeClaim(claimPath) {
  fs.rmSync(claimPath, { recursive: true, force: true });
}

function recoverStaleClaim(claimPath) {
  const recoveryPath = path.join(os.tmpdir(), `${RECOVERY_PREFIX}${path.basename(claimPath)}-${randomUUID()}`);
  try {
    fs.renameSync(claimPath, recoveryPath);
  } catch (error) {
    if (error.code !== "ENOENT") {
      throw error;
    }
  }
}

function collectRecoveries() {
  const recovered = [];
  for (const entry of fs.readdirSync(os.tmpdir(), { withFileTypes: true })) {
    if (!entry.isDirectory() || !entry.name.startsWith(RECOVERY_PREFIX)) {
      continue;
    }
    const recoveryPath = path.join(os.tmpdir(), entry.name);
    const pidText = readText(path.join(recoveryPath, "pid"));
    recovered.push(/^[1-9][0-9]*$/u.test(pidText) ? Number(pidText) : null);
    removeClaim(recoveryPath);
  }
  return recovered;
}

function cleanupStaleDiscoveryDirectories() {
  for (const entry of fs.readdirSync(os.tmpdir(), { withFileTypes: true })) {
    if (entry.name.startsWith("agent-scripts-topology-discovery-")) {
      fs.rmSync(path.join(os.tmpdir(), entry.name), { recursive: true, force: true });
    }
  }
}

function scanClaims() {
  const live = [];

  for (const entry of fs.readdirSync(os.tmpdir(), { withFileTypes: true })) {
    if (!entry.isDirectory() || !entry.name.startsWith(CLAIM_PREFIX)) {
      continue;
    }

    const claimPath = path.join(os.tmpdir(), entry.name);
    let stats;
    try {
      stats = fs.statSync(claimPath, { bigint: true });
    } catch (error) {
      if (error.code === "ENOENT") {
        continue;
      }
      throw error;
    }

    const pidText = readText(path.join(claimPath, "pid"));
    const pid = /^[1-9][0-9]*$/u.test(pidText) ? Number(pidText) : null;
    const ageMilliseconds = Date.now() - Number(stats.mtimeMs);
    if ((pid !== null && !processIsAlive(pid)) || (pid === null && ageMilliseconds >= PENDING_GRACE_MILLISECONDS)) {
      recoverStaleClaim(claimPath);
      continue;
    }

    live.push({
      path: claimPath,
      name: entry.name,
      pid,
      state: readText(path.join(claimPath, "state")),
      created: stats.ctimeNs,
      inode: stats.ino,
    });
  }

  return { live };
}

function compareClaims(left, right) {
  if (left.created !== right.created) {
    return left.created < right.created ? -1 : 1;
  }
  if (left.inode !== right.inode) {
    return left.inode < right.inode ? -1 : 1;
  }
  return left.name.localeCompare(right.name);
}

function runningError(claim) {
  return new Error(claim.pid === null
    ? "skill topology is already running (PID pending)"
    : `skill topology is already running (PID ${claim.pid})`);
}

export function acquireLock() {
  const claimPath = path.join(os.tmpdir(), `${CLAIM_PREFIX}${process.pid}-${randomUUID()}`);
  fs.mkdirSync(claimPath);
  fs.writeFileSync(path.join(claimPath, "pid"), `${process.pid}\n`, { flag: "wx" });
  fs.writeFileSync(path.join(claimPath, "state"), "candidate\n", { flag: "wx" });

  try {
    const firstScan = scanClaims();
    const activeClaim = firstScan.live.find((claim) => claim.path !== claimPath && claim.state === "active");
    if (activeClaim) {
      throw runningError(activeClaim);
    }

    const winner = [...firstScan.live].sort(compareClaims)[0];
    if (!winner || winner.path !== claimPath) {
      throw runningError(winner);
    }

    fs.writeFileSync(path.join(claimPath, "state"), "active\n");
    const secondScan = scanClaims();
    const otherActiveClaim = secondScan.live.find((claim) => claim.path !== claimPath && claim.state === "active");
    if (otherActiveClaim) {
      throw runningError(otherActiveClaim);
    }

    const recovered = collectRecoveries();
    if (recovered.length > 0) {
      cleanupStaleDiscoveryDirectories();
    }
    const warnings = recovered.map((pid) => ({
      code: "stale-lock-recovered",
      message: pid === null
        ? "recovered stale topology lock with no recorded PID"
        : `recovered stale topology lock held by PID ${pid}`,
    }));
    return { path: claimPath, warnings };
  } catch (error) {
    removeClaim(claimPath);
    throw error;
  }
}

export function releaseLock(lock) {
  if (lock && readText(path.join(lock.path, "pid")) === String(process.pid)) {
    removeClaim(lock.path);
  }
}
