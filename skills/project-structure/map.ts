#!/usr/bin/env node
// project-structure: compress a TypeScript repository into a single symbol-map file
// that an LLM agent can load whole to reason about structure, duplication, and refactors.
//
// Usage: node map.ts <repoRoot> [--out file] [--mode dense|skeleton|exports|sigs|full]
//                    [--include a,b,c] [--boundary x,y] [--include-tests] [--no-docs] [--fn-consts-only]
//
// Parse-only (no type-checking): ~15k files in <10s. Requires the target repo (or this
// skill dir) to provide the `typescript` package. Runs on Node >= 23.6 (type stripping);
// older Node: `npx tsx map.ts ...`.

import { createRequire } from 'node:module';
import { readFileSync, writeFileSync, readdirSync } from 'node:fs';
import { join, relative, resolve } from 'node:path';

type Mode = 'dense' | 'skeleton' | 'exports' | 'sigs' | 'full';

interface Options {
  repoRoot: string;
  out: string;
  mode: Mode;
  include: string[];
  boundary: string[];
  includeTests: boolean;
  noDocs: boolean;
  fnConstsOnly: boolean;
  reCounts: boolean;
  maxPerKind: number;
}

function parseArgs(argv: string[]): Options {
  const [repoArg, ...rest] = argv;
  if (!repoArg || repoArg.startsWith('--')) {
    console.error('usage: node map.ts <repoRoot> [--out file] [--mode dense|skeleton|exports|sigs|full] [--include a,b] [--boundary x,y] [--include-tests] [--no-docs] [--fn-consts-only]');
    process.exit(2);
  }
  const opts: Options = {
    repoRoot: resolve(repoArg),
    out: 'project-structure-map.txt',
    mode: 'dense',
    include: [],
    boundary: [],
    includeTests: false,
    noDocs: false,
    fnConstsOnly: false,
    reCounts: false,
    maxPerKind: 0,
  };
  for (let i = 0; i < rest.length; i++) {
    const a = rest[i];
    if (a === '--out') opts.out = rest[++i];
    else if (a === '--mode') opts.mode = rest[++i] as Mode;
    else if (a === '--include') opts.include = rest[++i].split(',').filter(Boolean);
    else if (a === '--boundary') opts.boundary = rest[++i].split(',').filter(Boolean);
    else if (a === '--include-tests') opts.includeTests = true;
    else if (a === '--no-docs') opts.noDocs = true;
    else if (a === '--fn-consts-only') opts.fnConstsOnly = true;
    else if (a === '--re-counts') opts.reCounts = true;
    else if (a === '--max-per-kind') opts.maxPerKind = Number(rest[++i]) || 0;
    else {
      console.error(`unknown option: ${a}`);
      process.exit(2);
    }
  }
  if (!['dense', 'skeleton', 'exports', 'sigs', 'full'].includes(opts.mode)) {
    console.error(`invalid --mode: ${opts.mode}`);
    process.exit(2);
  }
  return opts;
}

function loadTypescript(repoRoot: string): any {
  for (const from of [join(repoRoot, 'package.json'), import.meta.url]) {
    try {
      return createRequire(from)('typescript');
    } catch {
      /* try next */
    }
  }
  console.error('Cannot resolve the `typescript` package from the target repo or the skill directory.');
  console.error('Fix: run `npm i typescript` in either location.');
  process.exit(2);
}

const opts = parseArgs(process.argv.slice(2));
const ts = loadTypescript(opts.repoRoot);

const SKIP_DIRS = new Set(['node_modules', 'dist', 'out', '.git', 'coverage', 'build', '.next', 'fixtures', '__fixtures__', 'vendor']);
const TEST_INFRA_DIRS = ['test-support', 'test-helpers', 'e2e', 'test', 'tests', '__tests__', 'testing'];
if (!opts.includeTests) for (const d of TEST_INFRA_DIRS) SKIP_DIRS.add(d);

const MAX_SIG = 400;
const MAX_TYPE_BODY = 600;
const MAX_DOC = 140;

const isTestFile = (name: string): boolean =>
  !opts.includeTests && (/\.(test|spec|e2e\.test)\.tsx?$/.test(name) || /(test-support|test-helpers|test-utils)/.test(name));

function* walk(dir: string): Generator<string> {
  let entries;
  try {
    entries = readdirSync(dir, { withFileTypes: true });
  } catch {
    return;
  }
  for (const e of entries) {
    if (e.name.startsWith('.')) continue;
    const p = join(dir, e.name);
    if (e.isDirectory()) {
      if (SKIP_DIRS.has(e.name)) continue;
      yield* walk(p);
    } else if (/\.(ts|tsx)$/.test(e.name) && !/\.d\.ts$/.test(e.name) && !isTestFile(e.name)) {
      yield p;
    }
  }
}

const squash = (s: string): string => s.replace(/\s+/g, ' ').trim();
const cap = (s: string, n: number): string => (s.length > n ? s.slice(0, n) + '…' : s);

function docFirstLine(node: any, sf: any): string {
  if (opts.noDocs) return '';
  const ranges = ts.getLeadingCommentRanges(sf.text, node.getFullStart());
  if (!ranges?.length) return '';
  const r = ranges[ranges.length - 1];
  const text = sf.text
    .slice(r.pos, r.end)
    .replace(/^\/\*\*?/, '')
    .replace(/\*\/$/, '')
    .replace(/^\s*\*\s?/gm, '')
    .replace(/^\/\/\s?/gm, '');
  const line = text
    .split('\n')
    .map((l: string) => l.trim())
    .find((l: string) => l && !l.startsWith('@'));
  return line ? cap(line, MAX_DOC) : '';
}

function sigText(node: any, sf: any): string {
  const end = node.body ? node.body.getStart(sf) : node.getEnd();
  return cap(squash(sf.text.slice(node.getStart(sf), end)), MAX_SIG);
}

const isExported = (node: any): boolean =>
  node.modifiers?.some((m: any) => m.kind === ts.SyntaxKind.ExportKeyword) ?? false;

const isFnValued = (d: any): boolean =>
  d.initializer && (ts.isArrowFunction(d.initializer) || ts.isFunctionExpression(d.initializer));

function classShape(node: any, sf: any): string {
  const name = node.name?.text ?? '(anon)';
  const heritage = node.heritageClauses?.map((h: any) => squash(h.getText(sf))).join(' ') ?? '';
  const members: string[] = [];
  for (const m of node.members) {
    const mods = m.modifiers?.map((x: any) => x.getText(sf)) ?? [];
    if (mods.includes('private')) continue;
    if (ts.isConstructorDeclaration(m)) {
      members.push(squash('constructor' + sf.text.slice(m.parameters.pos - 1, m.body ? m.body.getStart(sf) : m.getEnd())));
    } else if (ts.isMethodDeclaration(m) || ts.isGetAccessorDeclaration(m) || ts.isSetAccessorDeclaration(m)) {
      members.push(sigText(m, sf));
    } else if (ts.isPropertyDeclaration(m) && m.type) {
      members.push(squash(m.name.getText(sf) + ': ' + m.type.getText(sf)));
    }
  }
  return `class ${name}${heritage ? ' ' + heritage : ''} { ${cap(members.join('; '), MAX_TYPE_BODY)} }`;
}

// dense: [kind, name] tuples grouped per file; other modes: rendered lines
type DenseEntry = [string, string];
const denseDirs = new Map<string, string[]>();
const out: string[] = [];

function emitDense(file: string, entries: DenseEntry[]): void {
  const rel = relative(opts.repoRoot, file);
  const dir = rel.slice(0, rel.lastIndexOf('/') + 1);
  const base = rel.slice(dir.length).replace(/\.tsx?$/, '');
  const byKind = new Map<string, string[]>();
  for (const [k, n] of entries) {
    if (!byKind.has(k)) byKind.set(k, []);
    byKind.get(k)!.push(n);
  }
  // --re-counts: barrel targets collapse to a count; facade detail costs more than it informs at recon tier
  if (opts.reCounts && byKind.has('re')) byKind.set('re', [String(byKind.get('re')!.length)]);
  const capList = (ns: string[]): string =>
    opts.maxPerKind && ns.length > opts.maxPerKind
      ? ns.slice(0, opts.maxPerKind).join(',') + `+${ns.length - opts.maxPerKind}`
      : ns.join(',');
  const parts = [...byKind.entries()].map(([k, ns]) => `${k}:${capList(ns)}`);
  if (!denseDirs.has(dir)) denseDirs.set(dir, []);
  denseDirs.get(dir)!.push(`${base} ${parts.join(' ')}`);
}

function emitFile(file: string, sf: any): boolean {
  const lines: string[] = [];
  const dense: DenseEntry[] = [];
  const importCount = sf.statements.filter((s: any) => ts.isImportDeclaration(s)).length;

  for (const st of sf.statements) {
    const exp = isExported(st);
    if (opts.mode !== 'full' && !exp && !ts.isExportDeclaration(st)) continue;
    const tag = exp ? '' : 'internal ';
    const doc = docFirstLine(st, sf);
    const suffix = doc && opts.mode !== 'skeleton' ? `  // ${doc}` : '';

    if (opts.mode === 'dense') {
      if (ts.isFunctionDeclaration(st) && st.name) dense.push(['fn', st.name.text]);
      else if (ts.isClassDeclaration(st) && st.name) dense.push(['cl', st.name.text]);
      else if (ts.isInterfaceDeclaration(st) || ts.isTypeAliasDeclaration(st) || ts.isEnumDeclaration(st)) dense.push(['ty', st.name.text]);
      else if (ts.isVariableStatement(st)) {
        for (const d of st.declarationList.declarations) {
          if (opts.fnConstsOnly && !isFnValued(d)) continue;
          dense.push([isFnValued(d) ? 'fn' : 'c', d.name.getText(sf)]);
        }
      } else if (ts.isExportDeclaration(st) && st.moduleSpecifier) {
        dense.push(['re', squash(st.moduleSpecifier.getText(sf)).replace(/["']/g, '')]);
      }
      continue;
    }

    if (opts.mode === 'skeleton') {
      if (ts.isFunctionDeclaration(st) && st.name) lines.push(`fn ${st.name.text}`);
      else if (ts.isClassDeclaration(st) && st.name) lines.push(`class ${st.name.text}`);
      else if (ts.isInterfaceDeclaration(st)) lines.push(`interface ${st.name.text}`);
      else if (ts.isTypeAliasDeclaration(st)) lines.push(`type ${st.name.text}`);
      else if (ts.isEnumDeclaration(st)) lines.push(`enum ${st.name.text}`);
      else if (ts.isVariableStatement(st)) for (const d of st.declarationList.declarations) lines.push(`const ${d.name.getText(sf)}`);
      else if (ts.isExportDeclaration(st)) lines.push(cap(squash(st.getText(sf)), 120));
      continue;
    }

    if (ts.isFunctionDeclaration(st) && st.name) {
      lines.push(`${tag}${sigText(st, sf)}${suffix}`);
    } else if (ts.isClassDeclaration(st)) {
      lines.push(`${tag}${classShape(st, sf)}${suffix}`);
    } else if (ts.isInterfaceDeclaration(st)) {
      if (opts.mode === 'sigs') {
        lines.push(`${tag}interface ${st.name.text} { ${st.members.map((m: any) => m.name?.getText(sf) ?? '?').join(', ')} }${suffix}`);
      } else {
        lines.push(`${tag}${cap(squash(st.getText(sf)), MAX_TYPE_BODY)}${suffix}`);
      }
    } else if (ts.isTypeAliasDeclaration(st)) {
      if (opts.mode === 'sigs' && ts.isTypeLiteralNode(st.type)) {
        lines.push(`${tag}type ${st.name.text} { ${st.type.members.map((m: any) => m.name?.getText(sf) ?? '?').join(', ')} }${suffix}`);
      } else if (opts.mode === 'sigs') {
        lines.push(`${tag}type ${st.name.text} = ${cap(squash(st.type.getText(sf)), 200)}${suffix}`);
      } else {
        lines.push(`${tag}${cap(squash(st.getText(sf)), MAX_TYPE_BODY)}${suffix}`);
      }
    } else if (ts.isEnumDeclaration(st)) {
      lines.push(`${tag}enum ${st.name.text} { ${st.members.map((m: any) => m.name.getText(sf)).join(', ')} }${suffix}`);
    } else if (ts.isVariableStatement(st)) {
      for (const d of st.declarationList.declarations) {
        if (opts.fnConstsOnly && !isFnValued(d)) continue;
        const name = d.name.getText(sf);
        let ann = '';
        if (d.type) ann = ': ' + squash(d.type.getText(sf));
        else if (d.initializer) {
          if (isFnValued(d)) {
            const fn = d.initializer;
            ann = ' = ' + squash(sf.text.slice(fn.getStart(sf), fn.body ? fn.body.getStart(sf) : fn.getEnd())) + '…';
          } else {
            ann = ` = <${ts.SyntaxKind[d.initializer.kind]}>`;
          }
        }
        ann = cap(ann, MAX_SIG);
        if (exp || ann.includes('=>') || ann.startsWith(': ')) {
          lines.push(`${tag}const ${name}${ann}${suffix}`);
        }
      }
    } else if (ts.isExportDeclaration(st)) {
      lines.push(squash(st.getText(sf)));
    }
  }

  if (opts.mode === 'dense') {
    if (dense.length === 0) return false;
    emitDense(file, dense);
    return true;
  }
  if (lines.length === 0) return false;
  out.push(`## ${relative(opts.repoRoot, file)}  [imports:${importCount}]`);
  out.push(...lines, '');
  return true;
}

// --- main ---
const t0 = Date.now();
const boundarySet = new Set(opts.boundary);
let roots = opts.include;
if (roots.length === 0) {
  roots = readdirSync(opts.repoRoot, { withFileTypes: true })
    .filter((e) => e.isDirectory() && !e.name.startsWith('.') && !SKIP_DIRS.has(e.name) && !boundarySet.has(e.name))
    .map((e) => e.name);
}
roots = roots.filter((r) => !boundarySet.has(r));

let files = 0;
let emitted = 0;
for (const root of roots) {
  for (const file of walk(join(opts.repoRoot, root))) {
    files++;
    try {
      const text = readFileSync(file, 'utf8');
      const sf = ts.createSourceFile(file, text, ts.ScriptTarget.Latest, true, /\.tsx$/.test(file) ? ts.ScriptKind.TSX : ts.ScriptKind.TS);
      if (emitFile(file, sf)) emitted++;
    } catch {
      /* unparseable file: skip */
    }
  }
}

if (opts.mode === 'dense') {
  for (const [dir, fileLines] of [...denseDirs.entries()].sort()) {
    out.push(`# ${dir}`, ...fileLines, '');
  }
}

// Boundary dirs: named children with one-line package descriptions, no symbol content.
for (const b of opts.boundary) {
  let children: string[];
  try {
    children = readdirSync(join(opts.repoRoot, b), { withFileTypes: true })
      .filter((e) => e.isDirectory() && !e.name.startsWith('.'))
      .map((e) => e.name);
  } catch {
    continue;
  }
  out.push(`# boundary ${b}/ (${children.length} modules, contents omitted)`);
  for (const c of children) {
    let desc = '';
    try {
      desc = String(JSON.parse(readFileSync(join(opts.repoRoot, b, c, 'package.json'), 'utf8')).description ?? '');
    } catch {
      /* no package.json: name only */
    }
    out.push(desc ? `${c} — ${cap(desc, 120)}` : c);
  }
  out.push('');
}

const result = out.join('\n');
writeFileSync(opts.out, result);
console.log(
  JSON.stringify({
    mode: opts.mode,
    roots,
    boundary: opts.boundary,
    files,
    emitted,
    bytes: result.length,
    approxTokens: Math.round(result.length / 4),
    out: opts.out,
    ms: Date.now() - t0,
  }),
);
