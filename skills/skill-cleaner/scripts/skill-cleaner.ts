#!/usr/bin/env -S node --experimental-strip-types
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

type Skill = {
  name: string;
  baseName: string;
  description: string;
  path: string;
  realPath: string;
  dir: string;
  root: string;
  realRoot: string;
  scope: string;
  enabled: boolean;
  descChars: number;
  lineChars: number;
  lineBytes: number;
  bodyHash: string;
  bodyKey: string;
  descKey: string;
};

type Usage = {
  dollar: number;
  fileRead: number;
  text: number;
};

type Budget = {
  model: string;
  contextTokens: number;
  contextSource: string;
  effectivePercent: number | null;
  effectiveContextTokens: number | null;
  budgetPercent: number;
  budgetTokens: number;
  effectiveBudgetTokens: number | null;
  renderedLineChars: number;
  estimatedTokens: number;
  charsPerToken: number;
  budgetUsedRatio: number;
  effectiveBudgetUsedRatio: number | null;
  contextUsedRatio: number;
  effectiveContextUsedRatio: number | null;
  remainingBudgetTokens: number;
  remainingEffectiveBudgetTokens: number | null;
};

const home = os.homedir();
const args = new Set(process.argv.slice(2));

function argValue(name: string, fallback: string): string {
  const raw = process.argv.slice(2);
  const index = raw.indexOf(name);
  return index >= 0 && raw[index + 1] ? raw[index + 1] : fallback;
}

const months = Number(argValue("--months", "3"));
const noLogs = args.has("--no-logs");
const deepLogs = args.has("--deep-logs");
const json = args.has("--json");
const includeAll = args.has("--all");
const model = argValue("--model", "gpt-5.5");
const budgetPercent = Number(argValue("--budget-percent", "2"));
const contextTokensOverride = argValue("--context-tokens", "");
const charsPerToken = Number(argValue("--chars-per-token", "4"));
const maxLogBytes = Number(argValue("--max-log-mb", "300")) * 1024 * 1024;
const cutoffMs = Date.now() - Math.max(0, months) * 31 * 24 * 60 * 60 * 1000;
const extraRoots = process.argv
  .slice(2)
  .flatMap((arg, index, all) => (arg === "--root" && all[index + 1] ? [all[index + 1]] : []));

function expandHome(input: string): string {
  return input.replace(/^~(?=$|\/)/, home);
}

function exists(input: string): boolean {
  try {
    fs.accessSync(input);
    return true;
  } catch {
    return false;
  }
}

function numberArg(value: string, fallback: number): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

function findModelRecord(value: unknown, target: string): Record<string, unknown> | null {
  if (Array.isArray(value)) {
    for (const item of value) {
      const found = findModelRecord(item, target);
      if (found) return found;
    }
    return null;
  }
  if (!value || typeof value !== "object") return null;
  const record = value as Record<string, unknown>;
  const names = [record.slug, record.id, record.model, record.name]
    .filter((item): item is string => typeof item === "string")
    .map((item) => item.toLowerCase());
  if (names.includes(target.toLowerCase())) return record;
  for (const item of Object.values(record)) {
    const found = findModelRecord(item, target);
    if (found) return found;
  }
  return null;
}

function codexModelContext(modelName: string): {
  tokens: number;
  source: string;
  effectivePercent: number | null;
} {
  const override = numberArg(contextTokensOverride, 0);
  if (override > 0) return { tokens: override, source: "--context-tokens", effectivePercent: null };

  const cache = path.join(home, ".codex/models_cache.json");
  if (exists(cache)) {
    try {
      const record = findModelRecord(JSON.parse(fs.readFileSync(cache, "utf8")), modelName);
      const tokens = Number(record?.context_window);
      const effectivePercent = Number(record?.effective_context_window_percent);
      if (Number.isFinite(tokens) && tokens > 0) {
        return {
          tokens,
          source: cache,
          effectivePercent: Number.isFinite(effectivePercent) && effectivePercent > 0 ? effectivePercent : null,
        };
      }
    } catch {}
  }

  return { tokens: 272_000, source: "fallback:gpt-5.5", effectivePercent: 95 };
}

function walkFiles(root: string, predicate: (file: string) => boolean, maxDepth = 8): string[] {
  const out: string[] = [];
  const seen = new Set<string>();
  function walk(dir: string, depth: number) {
    if (depth > maxDepth) return;
    let real = dir;
    try {
      real = fs.realpathSync(dir);
    } catch {
      return;
    }
    if (seen.has(real)) return;
    seen.add(real);
    let entries: fs.Dirent[];
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const entry of entries) {
      if (entry.name === "node_modules" || entry.name === ".git") continue;
      const file = path.join(dir, entry.name);
      if (entry.isDirectory() || entry.isSymbolicLink()) {
        let stat: fs.Stats;
        try {
          stat = fs.statSync(file);
        } catch {
          continue;
        }
        if (stat.isDirectory()) walk(file, depth + 1);
      } else if (entry.isFile() && predicate(file)) {
        out.push(file);
      }
    }
  }
  if (exists(root)) walk(root, 0);
  return out;
}

function sanitizeSingleLine(value: string): string {
  return value.replace(/[\r\n\t]+/g, " ").replace(/\s+/g, " ").trim();
}

function parseYamlScalar(raw: string): string {
  const value = raw.trim();
  if (
    (value.startsWith('"') && value.endsWith('"')) ||
    (value.startsWith("'") && value.endsWith("'"))
  ) {
    return value.slice(1, -1);
  }
  return value;
}

function parseFrontmatter(file: string): { name?: string; description?: string; body: string } | null {
  const text = fs.readFileSync(file, "utf8");
  const lines = text.split(/\r?\n/);
  if (lines[0]?.trim() !== "---") return null;
  const fm: string[] = [];
  let end = -1;
  for (let i = 1; i < lines.length; i++) {
    if (lines[i]?.trim() === "---") {
      end = i;
      break;
    }
    fm.push(lines[i] ?? "");
  }
  if (end < 0) return null;
  let name: string | undefined;
  let description: string | undefined;
  for (let i = 0; i < fm.length; i++) {
    const line = fm[i] ?? "";
    const match = /^([A-Za-z0-9_-]+):\s*(.*)$/.exec(line);
    if (!match) continue;
    const key = match[1];
    const raw = match[2] ?? "";
    if (key === "name") name = sanitizeSingleLine(parseYamlScalar(raw));
    if (key === "description") {
      if (raw.trim() === "|" || raw.trim() === ">") {
        const block: string[] = [];
        for (let j = i + 1; j < fm.length; j++) {
          if (/^[A-Za-z0-9_-]+:\s*/.test(fm[j] ?? "")) break;
          block.push((fm[j] ?? "").replace(/^\s{2}/, ""));
        }
        description = sanitizeSingleLine(block.join(" "));
      } else {
        description = sanitizeSingleLine(parseYamlScalar(raw));
      }
    }
  }
  return { name, description, body: lines.slice(end + 1).join("\n") };
}

function fnv1a(input: string): string {
  let hash = 0x811c9dc5;
  for (let i = 0; i < input.length; i++) {
    hash ^= input.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193);
  }
  return (hash >>> 0).toString(16).padStart(8, "0");
}

function normalizeWords(input: string): string {
  return input
    .toLowerCase()
    .replace(/[`"'’().,;:!?/\\[\]{}_-]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function wordSet(input: string): Set<string> {
  return new Set(normalizeWords(input).split(" ").filter((word) => word.length >= 2));
}

function jaccard(a: Set<string>, b: Set<string>): number {
  if (a.size === 0 && b.size === 0) return 1;
  let intersection = 0;
  for (const item of a) {
    if (b.has(item)) intersection++;
  }
  return intersection / (a.size + b.size - intersection);
}

function skillRootScope(root: string): string {
  const normalized = root.split(path.sep).join("/");
  if (normalized.includes("/.codex/plugins/cache")) return "codex-plugin";
  if (normalized.includes("/.codex/skills")) return "codex";
  if (normalized.includes("/Projects/agent-scripts/skills")) return "agent-scripts";
  if (normalized.includes("/.agents/skills")) return "repo";
  if (normalized.includes("/Dropbox/")) return "dropbox";
  return "extra";
}

function deletePriority(skill: Skill): number {
  if (skill.path.includes("/.codex/skills/.system/")) return 0;
  if (skill.path.includes("/.codex/skills/") && !skill.realPath.includes("/Projects/agent-scripts/")) return 1;
  if (skill.path.includes("/.codex/plugins/cache/") && !skill.path.includes("/plugin-install-")) return 2;
  if (skill.path.includes("/.codex/plugins/cache/")) return 3;
  if (skill.realPath.includes("/Projects/agent-scripts/skills/")) return 4;
  if (skill.realPath.includes("/.agents/skills/")) return 5;
  return 6;
}

function preferredKeepSkill(list: Skill[]): Skill {
  return [...list].sort((a, b) => {
    const byPriority = deletePriority(a) - deletePriority(b);
    if (byPriority !== 0) return byPriority;
    return a.realPath.length - b.realPath.length || a.realPath.localeCompare(b.realPath);
  })[0]!;
}

function displayPathPriority(skill: Skill): number {
  if (skill.path.includes("/.codex/skills/agent-scripts/")) return 10;
  if (skill.path === skill.realPath) return 0;
  return 1;
}

function preferredDisplaySkill(a: Skill, b: Skill): Skill {
  const byDisplay = displayPathPriority(a) - displayPathPriority(b);
  if (byDisplay < 0) return a;
  if (byDisplay > 0) return b;
  return a.path.length <= b.path.length ? a : b;
}

function pluginPrefixFor(file: string): string | null {
  const parts = file.split(path.sep);
  const cache = parts.indexOf("cache");
  const skills = parts.lastIndexOf("skills");
  if (cache >= 0 && skills > cache + 1) {
    const maybePlugin = parts[cache + 2];
    if (maybePlugin && maybePlugin !== "plugin-install-VGdwGs") return maybePlugin;
    return parts[cache + 3] ?? null;
  }
  return null;
}

function configState(): { disabledPaths: Set<string>; disabledPlugins: Set<string> } {
  const disabledPaths = new Set<string>();
  const disabledPlugins = new Set<string>();
  const config = path.join(home, ".codex/config.toml");
  if (!exists(config)) return { disabledPaths, disabledPlugins };
  const lines = fs.readFileSync(config, "utf8").split(/\r?\n/);
  let block = "";
  let currentPath = "";
  for (const line of lines) {
    const skillBlock = /^\[\[skills\.config\]\]/.test(line);
    const pluginBlock = /^\[plugins\."([^"]+)"\]/.exec(line);
    if (skillBlock) {
      block = "skill";
      currentPath = "";
      continue;
    }
    if (pluginBlock) {
      block = `plugin:${pluginBlock[1]}`;
      continue;
    }
    if (block === "skill") {
      const pathMatch = /^path\s*=\s*"([^"]+)"/.exec(line);
      if (pathMatch) currentPath = expandHome(pathMatch[1] ?? "");
      if (/^enabled\s*=\s*false/.test(line) && currentPath) disabledPaths.add(currentPath);
    } else if (block.startsWith("plugin:") && /^enabled\s*=\s*false/.test(line)) {
      disabledPlugins.add(block.slice("plugin:".length));
    }
  }
  return { disabledPaths, disabledPlugins };
}

function discoverRoots(): string[] {
  const rootsByRealPath = new Map<string, string>();
  [
    path.join(home, ".codex/skills"),
    path.join(home, ".codex/plugins/cache"),
    path.join(home, "Projects/agent-scripts/skills"),
    ...extraRoots.map(expandHome),
  ].forEach((root) => {
    if (!exists(root)) return;
    const real = fs.realpathSync(root);
    const current = rootsByRealPath.get(real);
    if (!current || root.length < current.length) rootsByRealPath.set(real, root);
  });
  const projects = path.join(home, "Projects");
  if (exists(projects)) {
    for (const entry of fs.readdirSync(projects, { withFileTypes: true })) {
      if (!entry.isDirectory() && !entry.isSymbolicLink()) continue;
      const skillRoot = path.join(projects, entry.name, ".agents/skills");
      if (exists(skillRoot)) {
        const real = fs.realpathSync(skillRoot);
        const current = rootsByRealPath.get(real);
        if (!current || skillRoot.length < current.length) rootsByRealPath.set(real, skillRoot);
      }
    }
  }
  return [...rootsByRealPath.values()].sort();
}

function discoverSkills(): Skill[] {
  const { disabledPaths, disabledPlugins } = configState();
  const skillsByRealPath = new Map<string, Skill>();
  for (const root of discoverRoots()) {
    for (const file of walkFiles(root, (candidate) => path.basename(candidate) === "SKILL.md", 10)) {
      const parsed = parseFrontmatter(file);
      if (!parsed) continue;
      const baseName = parsed.name || path.basename(path.dirname(file));
      const pluginPrefix = pluginPrefixFor(file);
      const name = pluginPrefix ? `${pluginPrefix}:${baseName}` : baseName;
      const description = parsed.description ?? "";
      const rendered = description
        ? `- ${name}: ${description} (file: ${file})`
        : `- ${name}: (file: ${file})`;
      const disabledByPath = disabledPaths.has(file);
      const disabledByPlugin =
        pluginPrefix != null && [...disabledPlugins].some((plugin) => plugin.startsWith(pluginPrefix));
      const bodyKey = normalizeWords(parsed.body);
      const skill: Skill = {
        name,
        baseName,
        description,
        path: file,
        realPath: fs.realpathSync(file),
        dir: path.dirname(file),
        root,
        realRoot: fs.realpathSync(root),
        scope: skillRootScope(root),
        enabled: !disabledByPath && !disabledByPlugin,
        descChars: [...description].length,
        lineChars: [...`${rendered}\n`].length,
        lineBytes: Buffer.byteLength(`${rendered}\n`, "utf8"),
        bodyHash: fnv1a(bodyKey),
        bodyKey,
        descKey: normalizeWords(description),
      };
      const existing = skillsByRealPath.get(skill.realPath);
      skillsByRealPath.set(skill.realPath, existing ? preferredDisplaySkill(existing, skill) : skill);
    }
  }
  return [...skillsByRealPath.values()];
}

function recentLogFiles(): string[] {
  if (noLogs) return [];
  const files = new Set<string>();
  const roots = [path.join(home, ".codex/sessions")];
  if (deepLogs) {
    roots.push(
      path.join(home, ".codex/archived_sessions"),
      path.join(home, ".openclaw"),
      path.join(home, ".clawd"),
    );
  }
  const history = path.join(home, ".codex/history.jsonl");
  if (exists(history)) files.add(history);
  for (const root of roots) {
    for (const file of walkRecentFiles(root, (candidate) => candidate.endsWith(".jsonl") || candidate.endsWith(".log"), 8)) {
      try {
        if (fs.statSync(file).mtimeMs >= cutoffMs) files.add(file);
      } catch {}
    }
  }
  return [...files].sort();
}

function walkRecentFiles(root: string, predicate: (file: string) => boolean, maxDepth = 8): string[] {
  const out: string[] = [];
  function walk(dir: string, depth: number) {
    if (depth > maxDepth) return;
    let entries: fs.Dirent[];
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const entry of entries) {
      const file = path.join(dir, entry.name);
      let stat: fs.Stats;
      try {
        stat = fs.statSync(file);
      } catch {
        continue;
      }
      if (entry.isDirectory()) {
        if (depth > 0 && stat.mtimeMs < cutoffMs) continue;
        walk(file, depth + 1);
      } else if (entry.isFile() && stat.mtimeMs >= cutoffMs && predicate(file)) {
        out.push(file);
      }
    }
  }
  if (exists(root)) walk(root, 0);
  return out;
}

function scanUsage(skills: Skill[], logFiles: string[]): Map<string, Usage> {
  const aliases = new Map<string, string[]>();
  for (const skill of skills) {
    const values = new Set([skill.name, skill.baseName, skill.name.split(":").at(-1) ?? skill.name]);
    aliases.set(skill.name, [...values].map((value) => value.toLowerCase()));
  }
  const usage = new Map<string, Usage>();
  for (const skill of skills) usage.set(skill.name, { dollar: 0, fileRead: 0, text: 0 });
  let consumedBytes = 0;
  for (const file of logFiles) {
    let text = "";
    try {
      const stat = fs.statSync(file);
      if (stat.size > 150 * 1024 * 1024) continue;
      if (consumedBytes + stat.size > maxLogBytes) break;
      consumedBytes += stat.size;
      text = fs.readFileSync(file, "utf8");
    } catch {
      continue;
    }
    const dollarCounts = countTokens(
      [...text.matchAll(/\$([A-Za-z][A-Za-z0-9_.:-]{1,80})/g)].map((m) => (m[1] ?? "").toLowerCase()),
    );
    const pathCounts = countTokens(
      [...text.matchAll(/(?:^|[/"'`\\])(?:\.agents\/)?skills\/([^/"'`\\\s]+)\/SKILL\.md/g)].map((m) =>
        (m[1] ?? "").toLowerCase()
      ),
    );
    const textCounts = countTokens(
      [...text.matchAll(/\b(?:use|using|load|read)\s+`?\$?([A-Za-z][A-Za-z0-9_.:-]{1,80})`?/gi)].map((m) =>
        (m[1] ?? "").toLowerCase()
      ),
    );
    for (const [name, names] of aliases) {
      const item = usage.get(name);
      if (!item) continue;
      for (const candidate of names) {
        item.dollar += dollarCounts.get(candidate) ?? 0;
        item.fileRead += pathCounts.get(candidate) ?? 0;
        item.text += textCounts.get(candidate) ?? 0;
      }
    }
  }
  return usage;
}

function countTokens(values: string[]): Map<string, number> {
  const map = new Map<string, number>();
  for (const value of values) map.set(value, (map.get(value) ?? 0) + 1);
  return map;
}

function suggestDescription(skill: Skill): string {
  const source = normalizeWords(`${skill.baseName} ${skill.description}`);
  const cues: string[] = [];
  const add = (label: string, pattern: RegExp) => {
    if (pattern.test(source) && !cues.includes(label)) cues.push(label);
  };
  add("OpenClaw", /\bopenclaw|claw|clawd\b/);
  add("GitHub", /\b(github|issue|pr|ci)\b|pull request/);
  add("Slack", /\bslack\b/);
  add("Discord", /\bdiscord\b/);
  add("Gmail", /\bgmail|email\b/);
  add("Google", /\b(google|drive|calendar|docs|sheets|slides)\b/);
  add("Cloudflare", /\b(cloudflare|worker|wrangler)\b|durable object/);
  add("release", /\b(release|publish|ship|notar)/);
  add("debug", /\b(debug|trace|inspect|profile|diagnos)/);
  add("search", /\b(search|archive|crawl|sync|history)\b/);
  add("deploy", /\b(deploy|ops|server|ssh|vm)\b/);
  add("docs", /\b(doc|docs|markdown|write|review)\b/);
  const verbs = cues.length ? cues.slice(0, 5).join(", ") : skill.baseName.replace(/-/g, " ");
  return `${verbs}: ${shortAction(source)}.`;
}

function shortAction(source: string): string {
  if (/\btriage|review\b/.test(source)) return "triage, review, proof";
  if (/\bdebug|diagnos|inspect\b/.test(source)) return "debug, inspect, fix";
  if (/\bsearch|sync|archive\b/.test(source)) return "search, sync, summarize";
  if (/\bdeploy|release|publish|ship\b/.test(source)) return "deploy, release, verify";
  if (/\bcreate|scaffold|build\b/.test(source)) return "create, build, validate";
  return "audit, clean, verify";
}

function groupBy<T>(items: T[], key: (item: T) => string): Map<string, T[]> {
  const map = new Map<string, T[]>();
  for (const item of items) {
    const value = key(item);
    map.set(value, [...(map.get(value) ?? []), item]);
  }
  return map;
}

function similarity(a: Skill, b: Skill): { description: number; body: number; overall: number } {
  const description = jaccard(wordSet(a.description), wordSet(b.description));
  const body = a.bodyHash === b.bodyHash ? 1 : jaccard(wordSet(a.bodyKey), wordSet(b.bodyKey));
  return {
    description,
    body,
    overall: body * 0.8 + description * 0.2,
  };
}

function formatPct(value: number): string {
  return `${Math.round(value * 100)}%`;
}

function formatOnePct(value: number): string {
  return `${(value * 100).toFixed(1)}%`;
}

function formatNumber(value: number): string {
  return Math.round(value).toLocaleString("en-US");
}

function skillBudget(renderedLineChars: number): Budget {
  const context = codexModelContext(model);
  const tokenRatio = numberArg(String(charsPerToken), 4);
  const percent = numberArg(String(budgetPercent), 2);
  const effectiveContextTokens = context.effectivePercent
    ? Math.floor(context.tokens * (context.effectivePercent / 100))
    : null;
  const budgetTokens = Math.floor(context.tokens * (percent / 100));
  const effectiveBudgetTokens = effectiveContextTokens
    ? Math.floor(effectiveContextTokens * (percent / 100))
    : null;
  const estimatedTokens = Math.ceil(renderedLineChars / tokenRatio);
  return {
    model,
    contextTokens: context.tokens,
    contextSource: context.source,
    effectivePercent: context.effectivePercent,
    effectiveContextTokens,
    budgetPercent: percent,
    budgetTokens,
    effectiveBudgetTokens,
    renderedLineChars,
    estimatedTokens,
    charsPerToken: tokenRatio,
    budgetUsedRatio: estimatedTokens / budgetTokens,
    effectiveBudgetUsedRatio: effectiveBudgetTokens ? estimatedTokens / effectiveBudgetTokens : null,
    contextUsedRatio: estimatedTokens / context.tokens,
    effectiveContextUsedRatio: effectiveContextTokens ? estimatedTokens / effectiveContextTokens : null,
    remainingBudgetTokens: budgetTokens - estimatedTokens,
    remainingEffectiveBudgetTokens: effectiveBudgetTokens ? effectiveBudgetTokens - estimatedTokens : null,
  };
}

function isLikelyCopy(score: { description: number; body: number }): boolean {
  return score.body >= 0.95 || (score.body >= 0.85 && score.description >= 0.85);
}

function duplicateDeleteSuggestions(groups: [string, Skill[]][]): string[] {
  const lines: string[] = [];
  for (const [name, list] of groups.slice(0, 80)) {
    const keep = preferredKeepSkill(list);
    const candidates = list
      .filter((skill) => skill.realPath !== keep.realPath)
      .map((skill) => ({ skill, score: similarity(keep, skill) }))
      .filter(({ score }) => isLikelyCopy(score))
      .sort((a, b) => b.score.body - a.score.body || b.score.description - a.score.description);
    if (candidates.length === 0) continue;
    lines.push(`- ${name}`);
    lines.push(`  keep: ${keep.scope}: ${keep.path}`);
    for (const { skill, score } of candidates) {
      lines.push(
        `  delete: ${skill.scope}: ${skill.path} (similarity body=${formatPct(score.body)}, description=${formatPct(score.description)})`,
      );
    }
  }
  return lines.length ? lines : ["- none"];
}

function render(skills: Skill[], usage: Map<string, Usage>, logFiles: string[]): string {
  const enabled = skills.filter((skill) => skill.enabled || includeAll);
  const roots = groupBy(skills, (skill) => skill.root);
  const byBase = [...groupBy(enabled, (skill) => skill.baseName.toLowerCase()).entries()].filter(([, list]) => list.length > 1);
  const byBody = [...groupBy(enabled, (skill) => skill.bodyHash).entries()].filter(([hash, list]) => hash !== "811c9dc5" && list.length > 1);
  const longDescriptions = enabled
    .filter((skill) => skill.descChars >= 110 || skill.lineChars >= 180)
    .sort((a, b) => b.descChars - a.descChars)
    .slice(0, 30);
  const unused = enabled
    .filter((skill) => {
      const item = usage.get(skill.name);
      return !item || item.dollar + item.fileRead + item.text === 0;
    })
    .filter((skill) => !["codex", "codex-plugin"].includes(skill.scope))
    .sort((a, b) => a.scope.localeCompare(b.scope) || a.name.localeCompare(b.name))
    .slice(0, 80);
  const totalLineChars = enabled.reduce((sum, skill) => sum + skill.lineChars, 0);
  const totalDescChars = enabled.reduce((sum, skill) => sum + skill.descChars, 0);
  const budget = skillBudget(totalLineChars);
  const lines: string[] = [];
  lines.push("# Skill Cleaner Report", "");
  lines.push(`generated: ${new Date().toISOString()}`);
  lines.push(`months: ${months}`);
  lines.push(`skills: ${skills.length} discovered, ${enabled.length} considered`);
  lines.push(`description_chars: ${totalDescChars}`);
  lines.push(`rendered_line_chars: ${totalLineChars}`);
  lines.push(`log_files_scanned: ${logFiles.length}`, "");

  lines.push("## Skill Budget", "");
  lines.push(`model: ${budget.model}`);
  lines.push(`context_tokens: ${formatNumber(budget.contextTokens)}`);
  lines.push(`context_source: ${budget.contextSource}`);
  lines.push(`${budget.budgetPercent}%_budget_tokens: ${formatNumber(budget.budgetTokens)}`);
  lines.push(
    `used_tokens_estimate: ${formatNumber(budget.estimatedTokens)} (${formatNumber(budget.renderedLineChars)} rendered chars / ${budget.charsPerToken})`,
  );
  lines.push(`used_of_2%_budget: ${formatOnePct(budget.budgetUsedRatio)}`);
  lines.push(`used_of_context: ${formatOnePct(budget.contextUsedRatio)}`);
  lines.push(`remaining_2%_budget_tokens: ${formatNumber(budget.remainingBudgetTokens)}`);
  if (budget.effectiveContextTokens && budget.effectiveBudgetTokens && budget.remainingEffectiveBudgetTokens != null) {
    lines.push(`effective_context_tokens: ${formatNumber(budget.effectiveContextTokens)} (${budget.effectivePercent}%)`);
    lines.push(`effective_2%_budget_tokens: ${formatNumber(budget.effectiveBudgetTokens)}`);
    lines.push(`used_of_effective_2%_budget: ${formatOnePct(budget.effectiveBudgetUsedRatio ?? 0)}`);
    lines.push(`remaining_effective_2%_budget_tokens: ${formatNumber(budget.remainingEffectiveBudgetTokens)}`);
  }
  lines.push("");

  lines.push("## Description Candidates", "");
  for (const skill of longDescriptions) {
    lines.push(`- ${skill.name}`);
    lines.push(`  path: ${skill.path}`);
    lines.push(`  chars: description=${skill.descChars}, rendered_line=${skill.lineChars}`);
    lines.push(`  current: ${skill.description}`);
    lines.push(`  suggested: ${suggestDescription(skill)}`);
  }
  if (longDescriptions.length === 0) lines.push("- none");
  lines.push("");

  lines.push("## Duplicates By Name", "");
  for (const [name, list] of byBase.slice(0, 40)) {
    lines.push(`- ${name}`);
    const keep = preferredKeepSkill(list);
    lines.push(`  keep-default: ${keep.scope}: ${keep.path}`);
    for (const skill of list) {
      const score = skill.realPath === keep.realPath ? { body: 1, description: 1 } : similarity(keep, skill);
      lines.push(
        `  - ${skill.scope}: ${skill.path} (body=${formatPct(score.body)}, description=${formatPct(score.description)})`,
      );
    }
  }
  if (byBase.length === 0) lines.push("- none");
  lines.push("");

  lines.push("## Duplicate Delete Suggestions", "");
  lines.push(...duplicateDeleteSuggestions(byBase));
  lines.push("");

  lines.push("## Duplicates By Body Hash", "");
  for (const [, list] of byBody.slice(0, 30)) {
    lines.push(`- ${list.map((skill) => skill.name).join(", ")}`);
    for (const skill of list) lines.push(`  - ${skill.scope}: ${skill.path}`);
  }
  if (byBody.length === 0) lines.push("- none");
  lines.push("");

  lines.push("## Unused Candidates", "");
  for (const skill of unused) {
    const item = usage.get(skill.name) ?? { dollar: 0, fileRead: 0, text: 0 };
    lines.push(`- ${skill.name}: ${skill.scope}; usage=$${item.dollar}, reads=${item.fileRead}, text=${item.text}; ${skill.path}`);
  }
  if (unused.length === 0) lines.push("- none");
  lines.push("");

  lines.push("## Root Summary", "");
  for (const [root, list] of [...roots.entries()].sort((a, b) => b[1].length - a[1].length)) {
    const disabled = list.filter((skill) => !skill.enabled).length;
    lines.push(`- ${root}: ${list.length} skills${disabled ? `, ${disabled} disabled` : ""}`);
  }
  return lines.join("\n");
}

const skills = discoverSkills();
const logFiles = recentLogFiles();
const usage = scanUsage(skills, logFiles);
const consideredSkills = skills.filter((skill) => skill.enabled || includeAll);
const budget = skillBudget(consideredSkills.reduce((sum, skill) => sum + skill.lineChars, 0));
const output = json
  ? JSON.stringify({ skills, usage: Object.fromEntries(usage), logFiles, budget }, null, 2)
  : render(skills, usage, logFiles);
console.log(output);
