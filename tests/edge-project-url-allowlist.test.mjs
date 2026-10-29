import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const files = [
  "supabase/functions/delete-account/index.ts",
  "supabase/functions/social-live-gateway/index.ts",
  "supabase/functions/push-dispatch/index.ts",
];

// Pull the real normalizeProjectUrl out of each Edge source and run it, so the
// test pins the shipped code instead of a copy of it.
async function load(path) {
  const source = await readFile(path, "utf8");
  const start = source.indexOf("function normalizeProjectUrl(");
  assert.notEqual(start, -1, `${path} must define normalizeProjectUrl`);
  assert.equal(
    source.indexOf("function normalizeProjectUrl(", start + 1),
    -1,
    `${path} must define normalizeProjectUrl once`,
  );
  const end = source.indexOf("\n}\n", start);
  const text = source.slice(start, end + 3);
  const js = text.replace("(raw: string): string | null", "(raw)");
  assert.doesNotMatch(js, /: string|\bas\b/, `${path}: unsupported TypeScript left`);
  return { text, fn: new Function(`${js}\nreturn normalizeProjectUrl;`)() };
}

const copies = await Promise.all(files.map(async (path) => ({
  path,
  ...await load(path),
})));

test("all three Edge Functions keep one identical project URL allowlist", () => {
  const canonical = (text) => text.replace(/\s+/g, " ");
  for (const copy of copies.slice(1)) {
    assert.equal(
      canonical(copy.text),
      canonical(copies[0].text),
      `${copy.path} drifted from ${copies[0].path}`,
    );
  }
});

test("SUPABASE_URL is accepted only as https, localhost, 127.0.0.1 or kong", () => {
  const accepted = {
    "https://project.supabase.co": "https://project.supabase.co",
    "https://project.supabase.co/": "https://project.supabase.co",
    "https://kong": "https://kong",
    "http://127.0.0.1:54321": "http://127.0.0.1:54321",
    "http://localhost:54321": "http://localhost:54321",
    "http://kong:8000": "http://kong:8000",
    "http://kong:8000/rest/v1": "http://kong:8000",
  };
  const rejected = [
    "",
    "not a url",
    "http://project.supabase.co",
    "http://kong.example.com:8000",
    "http://kong.internal",
    "http://mykong:8000",
    "http://kong-evil:8000",
    "http://evil.com/kong",
    "http://evil.com#kong",
    "http://kong@evil.com:8000",
    "http://kong:8000@evil.com",
    "http://KONG.evil.com",
    "http://0.0.0.0:54321",
    "http://[::1]:54321",
    "http://host.docker.internal:54321",
    "http://supabase_kong_gymapp:8000",
    "ftp://example.com",
    "ws://project.supabase.co",
  ];
  for (const { path, fn } of copies) {
    for (const [input, origin] of Object.entries(accepted)) {
      assert.equal(fn(input), origin, `${path}: ${input}`);
    }
    for (const input of rejected) {
      assert.equal(fn(input), null, `${path}: ${input}`);
    }
  }
});
