#!/usr/bin/env bun
/**
 * Shared trash helpers used by the git/rm shims.
 * Keeps deletes recoverable by moving targets into macOS Trash (or trash-cli).
 */

import { cpSync, existsSync, renameSync, rmSync } from 'node:fs';
import { basename, join, normalize, resolve } from 'node:path';
import process from 'node:process';

export type MoveResult = {
  missing: string[];
  errors: string[];
};

let cachedTrashCliCommand: string | null | undefined;

export async function movePathsToTrash(
  paths: string[],
  baseDir: string,
  options: { allowMissing: boolean; refusePaths?: string[] }
): Promise<MoveResult> {
  const missing: string[] = [];
  const existing: { raw: string; absolute: string }[] = [];

  const workspaceCanonical = normalize(resolve(baseDir));
  const refuseCanonicals = new Set<string>([
    normalize('/'),
    workspaceCanonical,
    ...(options.refusePaths ?? []).map((p) => normalize(resolve(baseDir, p))),
  ]);

  for (const rawPath of paths) {
    const absolute = resolvePath(baseDir, rawPath);
    const canonical = normalize(absolute);

    if (refuseCanonicals.has(canonical)) {
      return {
        missing: [],
        errors: [`Refusing to trash protected path: ${rawPath}`],
      };
    }

    if (!existsSync(absolute)) {
      if (!options.allowMissing) {
        missing.push(rawPath);
      }
      continue;
    }

    existing.push({ raw: rawPath, absolute });
  }

  if (existing.length === 0) {
    return { missing, errors: [] };
  }

  const trashCliCommand = await findTrashCliCommand();
  if (trashCliCommand) {
    try {
      const cliArgs = [trashCliCommand, ...existing.map((item) => item.absolute)];
      const proc = Bun.spawn(cliArgs, {
        stdout: 'ignore',
        stderr: 'pipe',
      });
      const [exitCode, stderrText] = await Promise.all([proc.exited, readProcessStream(proc.stderr)]);
      if (exitCode === 0) {
        return { missing, errors: [] };
      }
      if (stderrText.trim().length > 0) {
        return { missing, errors: [stderrText.trim()] };
      }
    } catch (error) {
      return { missing, errors: [formatTrashError(error)] };
    }
  }

  const trashDir = getTrashDirectory();
  if (!trashDir) {
    return {
      missing,
      errors: ['Unable to locate macOS Trash directory (HOME/.Trash).'],
    };
  }

  const errors: string[] = [];
  for (const item of existing) {
    try {
      const target = buildTrashTarget(trashDir, item.absolute);
      try {
        renameSync(item.absolute, target);
      } catch (error) {
        if (isCrossDeviceError(error)) {
          cpSync(item.absolute, target, { recursive: true });
          rmSync(item.absolute, { recursive: true, force: true });
        } else {
          throw error;
        }
      }
    } catch (error) {
      errors.push(`Failed to move ${item.raw} to Trash: ${formatTrashError(error)}`);
    }
  }

  return { missing, errors };
}

export function formatTrashError(error: unknown): string {
  if (error instanceof Error) {
    return error.message;
  }
  return String(error);
}

function resolvePath(baseDir: string, input: string): string {
  if (input.startsWith('/')) {
    return input;
  }
  return resolve(baseDir, input);
}

function getTrashDirectory(): string | null {
  const home = process.env.HOME;
  if (!home) {
    return null;
  }
  const trash = join(home, '.Trash');
  if (!existsSync(trash)) {
    return null;
  }
  return trash;
}

function buildTrashTarget(trashDir: string, absolutePath: string): string {
  const baseName = basename(absolutePath);
  const timestamp = Date.now();
  let attempt = 0;
  let candidate = join(trashDir, baseName);
  while (existsSync(candidate)) {
    candidate = join(trashDir, `${baseName}-${timestamp}${attempt > 0 ? `-${attempt}` : ''}`);
    attempt += 1;
  }
  return candidate;
}

function isCrossDeviceError(error: unknown): boolean {
  return error instanceof Error && 'code' in error && (error as NodeJS.ErrnoException).code === 'EXDEV';
}

async function findTrashCliCommand(): Promise<string | null> {
  if (cachedTrashCliCommand !== undefined) {
    return cachedTrashCliCommand;
  }

  const candidateNames = ['trash-put', 'trash'];
  const searchDirs = new Set<string>();

  if (process.env.PATH) {
    for (const segment of process.env.PATH.split(':')) {
      if (segment && segment.length > 0) {
        searchDirs.add(segment);
      }
    }
  }

  const homebrewPrefix = process.env.HOMEBREW_PREFIX ?? '/opt/homebrew';
  searchDirs.add(join(homebrewPrefix, 'opt', 'trash', 'bin'));
  searchDirs.add('/usr/local/opt/trash/bin');

  const candidatePaths = new Set<string>();
  for (const name of candidateNames) {
    candidatePaths.add(name);
    for (const dir of searchDirs) {
      candidatePaths.add(join(dir, name));
    }
  }

  for (const candidate of candidatePaths) {
    try {
      const proc = Bun.spawn([candidate, '--help'], {
        stdout: 'ignore',
        stderr: 'ignore',
      });
      const exitCode = await proc.exited;
      if (exitCode === 0 || exitCode === 1) {
        cachedTrashCliCommand = candidate;
        return candidate;
      }
    } catch {
      // ignore probes
    }
  }

  cachedTrashCliCommand = null;
  return null;
}

async function readProcessStream(stream: unknown): Promise<string> {
  if (!stream) {
    return '';
  }
  try {
    const candidate = stream as { text?: () => Promise<string> };
    if (candidate.text) {
      return (await candidate.text()) ?? '';
    }
  } catch {
    // ignore
  }
  try {
    if (stream instanceof ReadableStream) {
      return await new Response(stream).text();
    }
    if (typeof stream === 'object' && stream !== null) {
      return await new Response(stream as BodyInit).text();
    }
  } catch {
    // ignore
  }
  return '';
}
