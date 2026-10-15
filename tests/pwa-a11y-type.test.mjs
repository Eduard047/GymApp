import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const raw = await readFile("pwa/styles.css", "utf8");
const css = raw.replace(/\/\*[\s\S]*?\*\//g, "");

// Declarations that may keep a px value. Empty: every text size, line height and tracking is relative.
const PX_TEXT_EXCEPTIONS = [];

function declarations(property) {
  const found = [];
  const re = new RegExp(`(?:^|[;{\\s])${property}\\s*:\\s*([^;}]+)`, "g");
  let match;
  while ((match = re.exec(css))) found.push(match[1].trim());
  return found;
}

function atRuleBodies(source, header) {
  const bodies = [];
  let from = 0;
  for (;;) {
    const start = source.indexOf(header, from);
    if (start < 0) return bodies;
    const open = source.indexOf("{", start);
    let depth = 1;
    let i = open + 1;
    while (depth && i < source.length) {
      if (source[i] === "{") depth += 1;
      else if (source[i] === "}") depth -= 1;
      i += 1;
    }
    bodies.push(source.slice(open + 1, i - 1));
    from = i;
  }
}

test("font sizes, line heights and letter spacing use no px", () => {
  for (const property of ["font-size", "line-height", "letter-spacing"]) {
    const offenders = declarations(property).filter(value => /\d(?:\.\d+)?px\b/.test(value) && !PX_TEXT_EXCEPTIONS.includes(`${property}:${value}`));
    assert.deepEqual(offenders, [], `${property} still uses px`);
  }
  assert.ok(declarations("font-size").length > 200, "font-size declarations are present");
});

test("the root font size is not overridden so rem follows the browser setting", () => {
  assert.doesNotMatch(css, /(?:^|[}\s])html\s*\{[^}]*font-size/);
  assert.doesNotMatch(css, /:root\s*\{[^}]*\bfont-size\s*:/);
});

test("the font stack starts with the platform system faces", () => {
  const stack = /--?[\s\S]*?font-family:\s*(-apple-system[^;]+);/.exec(css)?.[1] ?? "";
  assert.match(stack, /^-apple-system, BlinkMacSystemFont, system-ui, "Segoe UI", "Noto Sans", sans-serif$/);
});

test("text inputs, selects and textareas never compute below 16px", () => {
  const base = /\n\n(?:input,\s*select,\s*textarea)\s*\{([^}]*min-height: 56px[^}]*)\}/.exec(css)?.[1] ?? "";
  assert.match(base, /font-size:\s*max\(1rem,\s*1em\)/);
  // Every rule that resets the font on an input-like element restores the floor.
  for (const selector of [".exercise-search-field input[type=\"search\"]", ".voice-workout-dictation textarea"]) {
    const body = new RegExp(`${selector.replace(/[.*+?^${}()|[\]\\"]/g, "\\$&")}\\s*\\{([^}]*)\\}`).exec(css)?.[1] ?? "";
    assert.match(body, /font:\s*inherit;[\s\S]*font-size:\s*max\(1rem,\s*1em\)/, selector);
  }
  // Any explicit size on an input-like selector is at least 1rem.
  const ruleRe = /([^{}]+)\{([^{}]*)\}/g;
  let match;
  while ((match = ruleRe.exec(css))) {
    const [, selector, body] = match;
    if (!/(?:^|[\s,>+~])(?:input|select|textarea)\b|-input\b/.test(selector.trim())) continue;
    const size = /(?:^|[;\s])font-size:\s*([^;]+)/.exec(body)?.[1].trim();
    if (!size) continue;
    const rem = /^(\d*\.?\d+)rem$/.exec(size);
    assert.ok(size.startsWith("max(1rem") || (rem && Number(rem[1]) >= 1), `${selector.trim()} font-size ${size}`);
  }
});

test("prefers-contrast: more strengthens borders, text, focus and glass", () => {
  const blocks = atRuleBodies(css, "@media (prefers-contrast: more)");
  assert.equal(blocks.length, 1);
  const [block] = blocks;
  assert.match(block, /--outline:\s*color-mix\(in srgb, var\(--text\)/);
  for (const token of ["--line", "--outline-variant", "--topbar-outline", "--nav-outline", "--hero-outline"]) {
    assert.match(block, new RegExp(`${token}:\\s*var\\(--outline\\)`), token);
  }
  assert.match(block, /--muted:\s*var\(--text\)/);
  assert.match(block, /--hero-muted:\s*var\(--hero-text\)/);
  assert.match(block, /:root\[data-theme="dark"\]/);
  assert.match(block, /outline:\s*2px solid var\(--text\)/);
  assert.match(block, /backdrop-filter:\s*none/);
  assert.match(block, /\.topbar \{ background: var\(--background\); \}/);
  assert.match(block, /\.bottom-nav \{ background: var\(--surface\); \}/);
  assert.doesNotMatch(block, /gradient\(/);
  assert.doesNotMatch(block, /#[0-9a-fA-F]{3,8}\b|rgba?\(/, "no new colors in the contrast block");
});

test("no transition on all properties and no gradients", () => {
  assert.doesNotMatch(css, /transition\s*:\s*all\b/);
  assert.doesNotMatch(css, /transition-property\s*:\s*all\b/);
  assert.doesNotMatch(css, /(?:linear|radial|conic)-gradient\(/);
});

test("small controls keep a 44px hit area", () => {
  assert.match(css, /\.toggle-row \{[^}]*min-height: 44px/);
  assert.match(css, /\.hero-text-button,\s*\n\.garmin-header \.hero-text-button \{[^}]*min-height: 44px/);
  assert.match(css, /\.focus-lens-details > summary \{ min-height: 44px/);
  assert.match(css, /\.exercise-search-field \.icon-button::before \{[^}]*inset: -2px/);
  assert.match(css, /\.set-editor-step::before \{[^}]*inset: 0 -4px/);
});
