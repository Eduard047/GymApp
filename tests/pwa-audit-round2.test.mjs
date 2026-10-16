import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const [styles, app, appBundle, stylesBundle] = await Promise.all([
  readFile("pwa/styles.css", "utf8"),
  readFile("pwa/app.js", "utf8"),
  readFile("pwa/app.v143.js", "utf8"),
  readFile("pwa/styles.v110.css", "utf8")
]);

function rules(selector) {
  const escaped = selector.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return [...styles.matchAll(new RegExp(`(?:^|\\n|,\\s*)${escaped}\\s*(?:,[^{}]*)?\\{([^}]*)\\}`, "g"))].map(match => match[1]);
}

function token(name, theme) {
  const blocks = [...styles.matchAll(/(:root(?:\[data-theme="dark"\])?)\s*\{([^}]*)\}/g)];
  const block = blocks.filter(match => (theme === "dark") === match[1].includes("dark")).find(match => match[2].includes(`${name}:`));
  return new RegExp(`${name}:\\s*(#[0-9a-f]{6})`, "i").exec(block[2])[1];
}

function luminance(hex) {
  const channels = [1, 3, 5].map(index => parseInt(hex.slice(index, index + 2), 16) / 255)
    .map(value => value <= 0.03928 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4);
  return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2];
}

function contrast(a, b) {
  const [high, low] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (high + 0.05) / (low + 0.05);
}

const SELECTED_SELECTORS = [
  ".segmented .selected",
  ".auth-mode-switch button.selected",
  ".progress-hub-switch button.selected",
  ".theme-option.selected",
  ".workouts-controls .segmented .selected",
  ".training-history-period button.selected",
  ".exercise-muscle-chips .chip.selected",
  ".chip.selected",
  ".mapping-grid .mapping-chip.selected",
  ".smart-effort-chips .chip.selected",
  ".active-live-tabs button.selected"
];

test("every segmented control and chip group shares one accent-fill selected style", () => {
  for (const selector of SELECTED_SELECTORS) {
    const declarations = rules(selector).join("\n");
    assert.match(declarations, /background:\s*var\(--brand-fill\)/, selector);
    assert.match(declarations, /color:\s*(?:var\(--on-accent\)|#ffffff)/, selector);
    assert.doesNotMatch(declarations, /color-mix|gradient/, selector);
  }
  assert.match(rules(".segmented .selected").join(""), /border-color:\s*var\(--brand-fill\)/);
  assert.match(rules(".period-tabs .selected").join(""), /background:\s*var\(--brand-fill\)/);
});

test("unselected segments and chips sit on surface-strong with primary text", () => {
  const block = styles.slice(styles.indexOf("/* One selected treatment"));
  assert.match(block, /\.theme-options \{ background: var\(--surface-2\); \}/);
  assert.match(block, /\.exercise-muscle-chips \.chip:not\(\.selected\)[\s\S]*?\{\s*color: var\(--text\);[^}]*background: var\(--surface-2\);/);
  assert.match(rules(".theme-option").join(""), /color:\s*var\(--text\)/);
  assert.match(rules(".progress-hub-switch button").join(""), /color:\s*var\(--text\)/);
});

test("selected label contrast on the accent fill is at least 4.5:1 in light and dark", () => {
  for (const theme of ["light", "dark"]) {
    const fill = token("--brand-fill", theme);
    assert.ok(contrast("#ffffff", fill) >= 4.5, `${theme} on-accent on ${fill}`);
  }
});

test("unselected label contrast on surface-strong is at least 4.5:1 in light and dark", () => {
  for (const theme of ["light", "dark"]) {
    assert.ok(contrast(token("--text", theme), token("--surface-2", theme)) >= 4.5, theme);
  }
});

test("desktop content is capped at 640 for lists and 960 for dashboards, centred", () => {
  const desktop = styles.slice(styles.lastIndexOf("@media (min-width: 900px)"));
  assert.match(desktop, /\.root-route-shell \.screen-exercises,\s*\.root-route-shell \.screen-leaderboard \{ width: min\(calc\(100% - 144px\), 640px\); \}/);
  assert.match(desktop, /\.root-route-shell \.screen-workouts,\s*\.root-route-shell \.screen-progress \{ width: min\(calc\(100% - 144px\), 960px\); \}/);
  assert.match(desktop, /\.root-route-shell \.screen-exercises \.exercise-list \{ grid-template-columns: minmax\(0, 1fr\); \}/);
  assert.match(rules(".root-route-shell .screen").join("") || styles, /margin-inline:\s*auto/);
  assert.doesNotMatch(styles.slice(0, styles.indexOf("@media (min-width: 900px)")), /\.screen \{[^}]*max-width/);
});

test("mission progress uses the accent mark and only the completed check is success coloured", () => {
  const block = styles.slice(styles.indexOf("/* Progress is always the accent mark"));
  assert.match(block, /\.progress span,\s*\.bar-fill \{ background: var\(--hero-accent\); \}/);
  assert.match(block, /\.mission-row \.progress span,\s*\.mission-row\.highlighted \.progress span \{ background: var\(--hero-accent\); \}/);
  assert.match(block, /\.mission-row\.highlighted \.mission-card-icon,\s*\.mission-completed-pill \.small-icon \{ color: var\(--mint\); \}/);
  assert.match(block, /\.mission-completed-pill \{\s*color: var\(--text\);/);
});

test("Weekly review rows follow the 12 and 16 rhythm", () => {
  assert.match(styles, /\.training-week-review \{ display: grid; gap: 12px; \}/);
  assert.match(styles, /\.training-week-review > p \{ margin: 0; \}/);
  assert.match(styles, /\.training-week-review > \.training-settings-link \{ margin-block: -14px; \}/);
  assert.match(styles, /\.training-week-sessions \{ margin-top: 4px; border-top: 1px solid var\(--outline-variant\); \}/);
});

test("the shipped bundles are byte copies of the working files", () => {
  assert.equal(appBundle, app);
  assert.equal(stylesBundle, styles);
});
