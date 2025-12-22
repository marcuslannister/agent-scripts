import { spawnSync } from 'node:child_process';
import { cpSync, existsSync, renameSync, rmSync } from 'node:fs';
import { basename, join, resolve } from 'node:path';
import process from 'node:process';

export type MoveResult = {
  missing: string[];
  errors: string[];
};

let cachedTrashCliCommand: string | null | undefined;

// Attempts to move the provided paths into trash instead of deleting in place.
export function movePathsToTrash(paths: string[], baseDir: string, options: { allowMissing: boolean }): MoveResult {
  const missing: string[] = [];
  const existing: { raw: string; absolute: string }[] = [];

  for (const rawPath of paths) {
    const absolute = resolvePath(baseDir, rawPath);
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

  const trashCliCommand = findTrashCliCommand();
  if (trashCliCommand) {
    try {
      const proc = spawnSync(
        trashCliCommand,
        existing.map((item) => item.absolute),
        {
          stdio: 'ignore',
        }
      );
      if (proc.status === 0) {
        return { missing, errors: [] };
      }
    } catch {
      // fall back to ~/.Trash
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
  return (
    typeof error === 'object' &&
    error !== null &&
    'code' in error &&
    (error as { code?: unknown }).code === 'EXDEV'
  );
}

function formatTrashError(error: unknown): string {
  if (error instanceof Error) {
    return error.message;
  }
  return String(error);
}

function findTrashCliCommand(): string | null {
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
    const proc = spawnSync(candidate, ['--help'], { stdio: 'ignore' });
    if (proc.status === 0 || proc.status === 1) {
      cachedTrashCliCommand = candidate;
      return candidate;
    }
  }

  cachedTrashCliCommand = null;
  return null;
}
