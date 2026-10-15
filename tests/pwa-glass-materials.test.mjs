import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const [css, bundle, indexHtml, worker] = await Promise.all([
  readFile("pwa/styles.css", "utf8"),
  readFile("pwa/styles.v103.css", "utf8"),
  readFile("pwa/index.html", "utf8"),
  readFile("pwa/sw.js", "utf8")
]);

const NO_BACKDROP = "@supports not ((backdrop-filter: blur(1px)) or (-webkit-backdrop-filter: blur(1px)))";
const REDUCED = "@media (prefers-reduced-transparency: reduce)";

// Bodies of every at-rule that starts with `header`, matched by brace balance.
function atRuleBodies(source, header) {
  const bodies = [];
  let from = 0;
  for (;;) {
    const start = source.indexOf(header, from);
    if (start < 0) return bodies;
    const open = source.indexOf("{", start);
    let depth = 1;
    let i = open + 1;
    while (depth > 0 && i < source.length) {
      if (source[i] === "{") depth += 1;
      else if (source[i] === "}") depth -= 1;
      i += 1;
    }
    bodies.push(source.slice(open + 1, i - 1));
    from = i;
  }
}

function hasSolidFallback(bodies, selector, property) {
  const rule = new RegExp(`(?:^|[\\s,}])${selector.replace(/[.\[\]]/g, "\\$&")}\\b[^{}]*\\{[^}]*${property}:\\s*var\\(--[a-z-]+\\)`);
  return bodies.some(body => rule.test(body));
}

const GLASS = [
  { selector: ".topbar", property: "background" },
  { selector: ".bottom-nav", property: "background" },
  { selector: ".modal-panel", property: "background" },
  { selector: ".toast", property: "background" }
];

test("every glass element has a solid no-backdrop-filter fallback", () => {
  const bodies = atRuleBodies(css, NO_BACKDROP);
  for (const { selector, property } of GLASS) {
    assert.ok(hasSolidFallback(bodies, selector, property), `${selector} needs an @supports-not solid ${property}`);
  }
});

test("every glass element drops its blur and goes solid under reduced transparency", () => {
  const bodies = atRuleBodies(css, REDUCED);
  for (const { selector, property } of GLASS) {
    assert.ok(hasSolidFallback(bodies, selector, property), `${selector} needs a reduced-transparency solid ${property}`);
    assert.ok(
      bodies.some(body => new RegExp(`${selector.replace(".", "\\.")}[^{]*\\{[^}]*backdrop-filter:\\s*none`).test(body)),
      `${selector} needs backdrop-filter: none under reduced transparency`
    );
  }
});

test("bar material uses blur 20 and saturate 150 on both bars; sheet and chip keep their values", () => {
  const rule = selector => css.match(new RegExp(`\\n${selector.replace(".", "\\.")} \\{[^}]*\\}`))[0];
  for (const selector of [".topbar", ".bottom-nav"]) {
    assert.match(rule(selector), /-webkit-backdrop-filter: blur\(20px\) saturate\(150%\);/, selector);
    assert.match(rule(selector), /\n  backdrop-filter: blur\(20px\) saturate\(150%\);/, selector);
  }
  assert.match(css, /\.modal-panel \{[^}]*backdrop-filter: blur\(28px\) saturate\(160%\)/);
  assert.match(css, /\.toast \{[^}]*backdrop-filter: blur\(14px\) saturate\(140%\)/);
  assert.doesNotMatch(css, /blur\(18px\)|blur\(22px\)/);
});

test("landscape safe-area insets keep content, sheets and toasts clear of the notch", () => {
  assert.match(css, /body \{[^}]*padding: env\(safe-area-inset-top\) env\(safe-area-inset-right\) 0 env\(safe-area-inset-left\);/);
  assert.match(css, /\.modal \{[^}]*padding: 0 env\(safe-area-inset-right\) 0 env\(safe-area-inset-left\);/);
  assert.match(css, /\.toast-region \{[^}]*left: max\(16px, env\(safe-area-inset-left\)\);[^}]*right: max\(16px, env\(safe-area-inset-right\)\);/);
  assert.match(css, /\.bottom-nav \{[^}]*left: calc\(12px \+ env\(safe-area-inset-left\)\);[^}]*right: calc\(12px \+ env\(safe-area-inset-right\)\);/);
});

test("document declares light and dark color schemes while explicit themes keep winning in CSS", () => {
  assert.match(indexHtml, /<meta name="color-scheme" content="light dark">/);
  assert.match(css, /:root \{\s*color-scheme: light;/);
  assert.match(css, /:root\[data-theme="dark"\] \{\s*color-scheme: dark;/);
});

test("the glass stylesheet ships as the immutable v103 bundle", () => {
  assert.equal(bundle, css);
  assert.ok(indexHtml.includes('href="./styles.v103.css"'));
  assert.ok(worker.includes('"./styles.v103.css"'));
});
