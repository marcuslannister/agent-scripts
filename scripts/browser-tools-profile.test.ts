import { lstatSync, mkdtempSync, mkdirSync, readFileSync, readlinkSync, symlinkSync, writeFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import os from 'node:os';
import path from 'node:path';
import { describe, test } from 'node:test';
import { pathToFileURL } from 'node:url';
import { copyChromeProfile, isMainModule } from './browser-tools.ts';

describe('copyChromeProfile', () => {
  test('preserves relative symlink targets', () => {
    const root = mkdtempSync(path.join(os.tmpdir(), 'browser-tools-profile-'));
    const source = path.join(root, 'source');
    const sourceLink = path.join(root, 'source-link');
    const destination = path.join(root, 'destination');
    mkdirSync(source);
    writeFileSync(path.join(source, 'target'), 'profile state');
    symlinkSync('target', path.join(source, 'relative-link'));
    symlinkSync('source', sourceLink);

    copyChromeProfile(sourceLink, destination);

    assert.equal(readlinkSync(path.join(destination, 'relative-link')), 'target');
  });

  test('rejects overlapping source and destination paths', () => {
    const root = mkdtempSync(path.join(os.tmpdir(), 'browser-tools-profile-overlap-'));
    const source = path.join(root, 'source');
    mkdirSync(source);
    writeFileSync(path.join(source, 'profile-state'), 'keep me');

    assert.throws(() => copyChromeProfile(source, source), /must not overlap/);
    assert.throws(() => copyChromeProfile(source, path.join(source, 'nested')), /must not overlap/);
    assert.throws(() => copyChromeProfile(source, root), /must not overlap/);
    assert.equal(readFileSync(path.join(source, 'profile-state'), 'utf8'), 'keep me');
  });

  test('validates the source before changing the destination', () => {
    const root = mkdtempSync(path.join(os.tmpdir(), 'browser-tools-profile-missing-source-'));
    const destination = path.join(root, 'destination');
    mkdirSync(destination);
    writeFileSync(path.join(destination, 'profile-state'), 'keep me');

    assert.throws(() => copyChromeProfile(path.join(root, 'missing'), destination));
    assert.equal(readFileSync(path.join(destination, 'profile-state'), 'utf8'), 'keep me');
  });

  test('preserves a symlinked destination directory', () => {
    const root = mkdtempSync(path.join(os.tmpdir(), 'browser-tools-profile-destination-link-'));
    const source = path.join(root, 'source');
    const destinationTarget = path.join(root, 'destination-target');
    const destinationLink = path.join(root, 'destination-link');
    mkdirSync(source);
    mkdirSync(destinationTarget);
    writeFileSync(path.join(source, 'new-state'), 'new');
    writeFileSync(path.join(destinationTarget, 'old-state'), 'old');
    symlinkSync('destination-target', destinationLink);

    copyChromeProfile(source, destinationLink);

    assert.equal(lstatSync(destinationLink).isSymbolicLink(), true);
    assert.equal(readlinkSync(destinationLink), 'destination-target');
    assert.equal(readFileSync(path.join(destinationTarget, 'new-state'), 'utf8'), 'new');
    assert.throws(() => readFileSync(path.join(destinationTarget, 'old-state'), 'utf8'));
  });

  test('replaces a symlink to a non-directory without changing its target', () => {
    const root = mkdtempSync(path.join(os.tmpdir(), 'browser-tools-profile-destination-file-link-'));
    const source = path.join(root, 'source');
    const destinationTarget = path.join(root, 'destination-target');
    const destinationLink = path.join(root, 'destination-link');
    mkdirSync(source);
    writeFileSync(path.join(source, 'new-state'), 'new');
    writeFileSync(destinationTarget, 'keep target');
    symlinkSync('destination-target', destinationLink);

    copyChromeProfile(source, destinationLink);

    assert.equal(lstatSync(destinationLink).isDirectory(), true);
    assert.equal(readFileSync(destinationTarget, 'utf8'), 'keep target');
    assert.equal(readFileSync(path.join(destinationLink, 'new-state'), 'utf8'), 'new');
  });
});

describe('isMainModule', () => {
  test('falls back to canonical paths when import.meta.main is unavailable', () => {
    const root = mkdtempSync(path.join(os.tmpdir(), 'browser-tools-main-module-'));
    const modulePath = path.join(root, 'browser-tools.ts');
    const launcherPath = path.join(root, 'browser-tools');
    writeFileSync(modulePath, 'fixture');
    symlinkSync('browser-tools.ts', launcherPath);

    assert.equal(isMainModule(null, launcherPath, pathToFileURL(modulePath).href), true);
    assert.equal(isMainModule(null, path.join(root, 'other'), pathToFileURL(modulePath).href), false);
  });
});
