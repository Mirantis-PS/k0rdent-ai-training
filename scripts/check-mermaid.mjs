#!/usr/bin/env node
/**
 * Validate every ```mermaid block in the curriculum against mermaid's own parser.
 *
 * This is the same gate GitHub uses to decide whether to draw a diagram or show a
 * red "syntax error" box, so a clean run here means the diagrams render on GitHub.
 *
 * Usage:
 *   cd scripts && npm install          # one time
 *   node check-mermaid.mjs             # scan ../curriculum recursively
 *   node check-mermaid.mjs FILE...     # scan specific files
 *
 * Exits non-zero if any block fails, so it works as a pre-commit hook or CI step.
 *
 * The most common failure by far is an unquoted special character in a node label.
 * Mermaid's flowchart lexer is shape-driven: `[` opens a label and it scans for the
 * matching `]`, so a bare `(` reads as the start of a different shape (`([` stadium,
 * `[(` cylinder) and you get "Expecting ... got 'PS'". Wrap the label in double
 * quotes -- A["text (with parens)"] -- to put the lexer in string mode, where `(`,
 * `[`, `<`, `:` and `/` are all just characters. `<br/>` still works inside quotes
 * because line-break expansion happens at render time, not in the lexer.
 */
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative, extname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { JSDOM } from 'jsdom';

const HERE = fileURLToPath(new URL('.', import.meta.url));
const REPO_ROOT = join(HERE, '..');

// Mermaid targets the browser, so give it a DOM before importing it.
const dom = new JSDOM('<!DOCTYPE html><body></body>', { pretendToBeVisual: true });
globalThis.window = dom.window;
globalThis.document = dom.window.document;
globalThis.SVGElement = dom.window.SVGElement;
globalThis.Element = dom.window.Element;
globalThis.HTMLElement = dom.window.HTMLElement;
// `navigator` is a getter-only global on modern Node, so it needs defineProperty.
Object.defineProperty(globalThis, 'navigator', {
  value: dom.window.navigator,
  configurable: true,
});
// Parsing never emits HTML, so a pass-through sanitizer is enough.
globalThis.DOMPurify = { sanitize: (s) => s, addHook: () => {}, setConfig: () => {} };

const mermaid = (await import('mermaid')).default;
mermaid.initialize({ startOnLoad: false, securityLevel: 'strict' });

/** Collect every fenced mermaid block with the line number it starts on. */
function mermaidBlocks(text) {
  const blocks = [];
  const lines = text.split('\n');
  let open = null;
  lines.forEach((line, i) => {
    if (open === null && /^\s*```mermaid\s*$/.test(line)) {
      open = { start: i + 1, body: [] };
    } else if (open !== null && /^\s*```\s*$/.test(line)) {
      blocks.push({ start: open.start, code: open.body.join('\n') });
      open = null;
    } else if (open !== null) {
      open.body.push(line);
    }
  });
  return blocks;
}

function markdownFilesUnder(dir) {
  const found = [];
  for (const entry of readdirSync(dir)) {
    if (entry === 'node_modules' || entry.startsWith('.')) continue;
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) found.push(...markdownFilesUnder(full));
    else if (extname(full) === '.md') found.push(full);
  }
  return found;
}

const args = process.argv.slice(2);
const files = args.length ? args : markdownFilesUnder(join(REPO_ROOT, 'curriculum'));

let checked = 0;
const failures = [];

for (const file of files) {
  const blocks = mermaidBlocks(readFileSync(file, 'utf8'));
  if (!blocks.length) continue;
  for (const block of blocks) {
    checked++;
    try {
      await mermaid.parse(block.code);
    } catch (err) {
      const detail = String(err?.message ?? err).split('\n').slice(0, 4).join(' ');
      failures.push({ file: relative(REPO_ROOT, file), line: block.start, detail });
    }
  }
}

if (failures.length) {
  for (const f of failures) {
    console.error(`FAIL ${f.file}:${f.line}\n     ${f.detail}\n`);
  }
  console.error(`${failures.length} of ${checked} mermaid block(s) failed to parse.`);
  process.exit(1);
}

console.log(`OK: ${checked} mermaid block(s) across ${files.length} file(s) parse cleanly.`);
