import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const kotlin = "app/src/main/java/com/example/gymapp";
const push = await readFile(`${kotlin}/push/AndroidPushManager.kt`, "utf8");
const mainActivity = await readFile(`${kotlin}/MainActivity.kt`, "utf8");

const body = (source, signature) => {
  const start = source.indexOf(signature);
  assert.notEqual(start, -1, `missing ${signature}`);
  const open = source.indexOf("{", start);
  let depth = 0;
  for (let i = open; i < source.length; i += 1) {
    if (source[i] === "{") depth += 1;
    if (source[i] === "}" && --depth === 0) return source.slice(open, i + 1);
  }
  throw new Error(`unterminated ${signature}`);
};

test("friend and live push notifications use the in-app language", () => {
  assert.match(push, /^import com\.example\.gymapp\.util\.withAppLanguage$/m);
  const show = body(push, "private fun showNotification(");
  assert.match(show, /val localized = applicationContext\.withAppLanguage\(\)/);
  assert.match(show, /\.setContentTitle\(localized\.getString\(title\)\)/);
  assert.match(show, /\.setContentText\(localized\.getString\(body\)\)/);
  assert.doesNotMatch(show, /applicationContext\.getString\(/);
});

test("the push channel name and description follow the in-app language", () => {
  const channel = body(push, "private fun createNotificationChannel(");
  assert.match(channel, /val localized = applicationContext\.withAppLanguage\(\)/);
  assert.match(channel, /PUSH_CHANNEL_ID,\s*localized\.getString\(R\.string\.push_channel_name\)/);
  assert.match(channel, /description = localized\.getString\(R\.string\.push_channel_description\)/);
  assert.doesNotMatch(channel, /applicationContext\.getString\(/);
});

test("the push channel is recreated on resume so a language change renames it", () => {
  // AppCompat recreates the activity after setApplicationLocales; onResume then refreshes.
  assert.match(mainActivity, /class MainActivity : AppCompatActivity\(\)/);
  const resume = body(mainActivity, "override fun onResume(");
  assert.match(resume, /pushManager\.refreshSystemState\(\)/);
  const refresh = body(push, "fun refreshSystemState(");
  assert.match(refresh, /if \(BuildConfig\.FIREBASE_CONFIGURED\) createNotificationChannel\(\)/);
});
