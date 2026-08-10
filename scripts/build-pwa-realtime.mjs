import { build } from "esbuild";

await build({
  entryPoints: ["scripts/pwa-realtime-entry.js"],
  outfile: "pwa/supabase-realtime.js",
  bundle: true,
  platform: "browser",
  target: "es2022",
  format: "iife",
  globalName: "GymSupabaseRealtime",
  legalComments: "inline",
  banner: {
    js: "/* @supabase/realtime-js 2.110.2 | MIT | https://github.com/supabase/supabase-js */"
  }
});
