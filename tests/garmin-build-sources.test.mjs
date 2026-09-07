import assert from "node:assert/strict";
import { cp, mkdtemp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";
import { prepareGarminSources } from "../scripts/lib/garmin-build-sources.mjs";
import { pruneUnusedGarminDiagnostics } from "../scripts/lib/garmin-prune-diagnostics.mjs";

test("Garmin builds disable unsafe propagation and ignore external optimizer settings", async () => {
  const builder = await readFile("scripts/build-garmin-program.mjs", "utf8");
  assert.match(builder, /ignore_settings_files: true/);
  assert.match(builder, /propagateTypes: false/);
  assert.match(builder, /singleUseCopyProp: false/);
  assert.match(builder, /preserveNullAssignments: true/);
  assert.match(builder, /removeArgc: false/);
  assert.match(builder, /postBuildPRE: true/);
  assert.doesNotMatch(builder, /allowForbiddenOpts: true|trustDeclaredTypes: true/);
});

test("the pinned Garmin optimizer preserves SDK array construction", async () => {
  const workspace = await readFile("pnpm-workspace.yaml", "utf8");
  assert.match(workspace, /'@markw65\/monkeyc-optimizer@1\.2\.6': patches\//);
  const optimizer = path.dirname(fileURLToPath(import.meta.resolve("@markw65/monkeyc-optimizer/sdk-util.js")));
  const chunk = await readFile(path.join(optimizer, "chunk-YPHK67BN.cjs"), "utf8");
  assert.doesNotMatch(chunk, /changes = doArrayInits\(func, liveInState, context\)/);
  assert.match(chunk, /changes = localDCE\(func, context\)/);
  assert.match(chunk, /sizeBasedPRE2\(func, context\)/);
});

async function fixture(run) {
  const root = await mkdtemp(path.join(os.tmpdir(), "gymapp-build-source-"));
  try {
    await mkdir(path.join(root, "source"));
    await mkdir(path.join(root, "resources"));
    await run(root);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
}

test("Garmin diagnostic pruning preserves reads, reflection, evaluation and device groups", async () => {
  await fixture(async root => {
    const sample = `class GymSession {
      static var gyroScore = 0.0;
      static var motionNoiseFloor = 0.0;
      static var recording = false;
      static function reset() { gyroScore = 0.0; motionNoiseFloor = sample(); recording = false; }
    }`;
    for (const [name, extra] of [
      ["compact", ""],
      ["full", "class View { function render() { return GymSession.gyroScore; } }"],
      ["reflect", 'class View { function inspect() { return "gyroScore"; } }'],
      ["symbol", 'class View { function inspect() { return :gyroScore; } }'],
      ["shadow", "class View { function input(GymSession) { GymSession.gyroScore = 5; } }"]
    ]) {
      await mkdir(path.join(root, name));
      await writeFile(path.join(root, name, "sample.mc"), sample + extra);
    }
    await pruneUnusedGarminDiagnostics(root);
    const compact = await readFile(path.join(root, "compact/sample.mc"), "utf8");
    assert.doesNotMatch(compact, /gyroScore/);
    assert.match(compact, /motionNoiseFloor = sample\(\);/);
    assert.match(compact, /sample\(\);/);
    assert.match(compact, /static var recording = false/);
    for (const name of ["full", "reflect", "symbol", "shadow"]) {
      assert.match(await readFile(path.join(root, name, "sample.mc"), "utf8"), /static var gyroScore/);
    }
  });
});

test("Garmin text packing preserves whitespace, XML characters, languages and smaller resource bounds", async () => {
  await fixture(async root => {
    await writeFile(path.join(root, "source", "WorkoutView.mc"), `class WorkoutView {
      function text() {
        var a = GymStore.tr(" SETS ", " ПІДХОДИ ", " ПОДХОДЫ ");
        var b = GymStore.tr("A & B < C", "Є & І < Ї", "Е & И < Й");
        var c = GymStore.tr(" SETS ", " ПІДХОДИ ", " ПОДХОДЫ ");
        return GymStore.tr("A|B", "A~B", "A|B");
      }
    }`);
    const phrases = await prepareGarminSources(root);
    assert.equal(phrases.length, 2, "equal triples share a resource row");
    const xml = await readFile(path.join(root, "resources", "ui-text.xml"), "utf8");
    assert.equal([...xml.matchAll(/<string id="UiText\d+">/g)].length, 16);
    assert.match(xml, /\| SETS \| ПІДХОДИ \| ПОДХОДЫ ~/);
    assert.match(xml, /A &amp; B &lt; C/);
    const source = await readFile(path.join(root, "source", "WorkoutView.mc"), "utf8");
    assert.equal([...source.matchAll(/GymText\.get\(/g)].length, 3);
    assert.match(source, /GymStore\.tr\("A\|B", "A~B", "A\|B"\)/,
      "literal delimiters retain the original translation path");
    for (const phrase of phrases) {
      const bucket = xml.match(new RegExp(`<string id="UiText${phrase.id % 16}">([\\s\\S]*?)</string>`))[1];
      assert.ok(bucket.includes(`~u${phrase.id}|`));
      assert.ok(Buffer.byteLength(bucket) <= 800);
    }
  });
});

test("Garmin dictionary preparation preserves native live-record access and mutation order", async () => {
  await fixture(async root => {
    await writeFile(path.join(root, "source", "GymStore.mc"), `class GymStore {
      static function example(message, record, target) {
        var id = message.get("requestId");
        var name = record.get("exerciseName");
        target.put("id", message.get("requestId"));
        return name;
      }
    }`);
    await prepareGarminSources(root);
    const source = await readFile(path.join(root, "source", "GymStore.mc"), "utf8");
    assert.match(source, /var id = message\["requestId"\]/);
    assert.match(source, /record\.get\("exerciseName"\)/);
    assert.match(source, /target\["id"\] = message\["requestId"\]/);
    assert.ok(source.indexOf("var name") < source.indexOf('target["id"]'));
  });
});

test("Garmin binding string optimization preserves validation and shadowed input coercion", async () => {
  await fixture(async root => {
    await writeFile(path.join(root, "source", "GymStore.mc"), `class GymStore {
      static var accountBinding = null;
      static function boundValue() {
        if (!isValidAccountBinding(accountBinding)) { return null; }
        return accountBinding.toString();
      }
      static function inputValue(accountBinding as Lang.Number) {
        return accountBinding.toString();
      }
      static function localValue() {
        var deviceBinding = 12;
        return deviceBinding.toString();
      }
    }`);
    await prepareGarminSources(root);
    const source = await readFile(path.join(root, "source", "GymStore.mc"), "utf8");
    assert.match(source, /isValidAccountBinding\(accountBinding\)[\s\S]*return accountBinding;/);
    assert.match(source, /function inputValue[\s\S]*return accountBinding\.toString\(\);/);
    assert.match(source, /function localValue[\s\S]*return deviceBinding\.toString\(\);/);
  });
});

test("Garmin text preparation fails before emitting oversized native resource shards", async () => {
  await fixture(async root => {
    const huge = "x".repeat(801);
    await writeFile(path.join(root, "source", "WorkoutView.mc"),
      `class WorkoutView { function text() { return GymStore.tr("${huge}", "К", "К"); } }`);
    await assert.rejects(prepareGarminSources(root), /800-byte bound/);
  });
});

test("Garmin merged resources preserve the complete exercise catalog and isolate UI names", async () => {
  await fixture(async root => {
    await cp("garmin/source", path.join(root, "source"), { recursive: true });
    const original = await readFile("garmin/resources/strings.xml", "utf8");
    await writeFile(path.join(root, "resources", "strings.xml"), original);
    const phrases = await prepareGarminSources(root);
    const output = await readFile(path.join(root, "resources", "ui-text.xml"), "utf8");
    const catalog = JSON.parse(await readFile("garmin/resources/exercise-labels.json", "utf8"));
    const shards = [...output.matchAll(/<string id="UiText(\d+)">([\s\S]*?)<\/string>/g)];
    assert.equal(shards.length, 16);
    const found = {};
    for (const [, suffix, encoded] of shards) {
      const packed = encoded.replaceAll("&lt;", "<").replaceAll("&gt;", ">").replaceAll("&amp;", "&");
      assert.ok(Buffer.byteLength(packed) <= 800);
      for (const row of packed.slice(1, -1).split("~")) {
        const [key, ...values] = row.split("|");
        if (key.startsWith("e")) {
          const name = key.slice(1);
          assert.ok(!Object.hasOwn(found, name), "exercise rows must be unique");
          assert.equal([...Buffer.from(name)].reduce((sum, value) => (sum + value) % 16, 0), Number(suffix));
          found[name] = values;
        } else {
          assert.match(key, /^u\d+$/);
          const phrase = phrases.find(value => value.id === Number(key.slice(1)));
          assert.deepEqual(values, phrase.values);
          assert.equal(phrase.id % 16, Number(suffix));
        }
      }
    }
    assert.deepEqual(found, catalog);
    const strings = await readFile(path.join(root, "resources", "strings.xml"), "utf8");
    assert.doesNotMatch(strings, /ExerciseLabels/);
    const source = await readFile(path.join(root, "source", "GymStore.mc"), "utf8");
    assert.doesNotMatch(source, /Rez\.Strings\.ExerciseLabels|shards\[shard\]/);
    assert.match(source, /GymText\.resource\(shard\)/);
    assert.match(source, /"~e" \+ name \+ "\|"/);
  });
});

test("Garmin resource preparation rejects a partial exercise pool without changing sources", async () => {
  await fixture(async root => {
    const source = 'class WorkoutView { function text() { return GymStore.tr("OK", "ОК", "ОК"); } }';
    await writeFile(path.join(root, "source", "WorkoutView.mc"), source);
    const strings = '<strings><string id="ExerciseLabels00">~Curl|Згинання|Сгибание</string></strings>';
    await writeFile(path.join(root, "resources", "strings.xml"), strings);
    await assert.rejects(prepareGarminSources(root), /Incomplete exercise resource pool/);
    assert.equal(await readFile(path.join(root, "source", "WorkoutView.mc"), "utf8"), source);
    assert.equal(await readFile(path.join(root, "resources", "strings.xml"), "utf8"), strings);
  });
});


test("Garmin live-screen text uses bounded locale resources with exact original labels", async () => {
  await fixture(async root => {
    await cp("garmin/source", path.join(root, "source"), { recursive: true });
    await cp("garmin/resources/strings.xml", path.join(root, "resources", "strings.xml"));
    const phrases = await prepareGarminSources(root);
    const xml = await readFile(path.join(root, "resources", "ui-text.xml"), "utf8");
    const hot = phrases.filter(phrase => phrase.id >= 2048);
    assert.ok(hot.length > 0);
    for (const phrase of hot) {
      for (let language = 0; language < 3; language += 1) {
        const bucket = Math.floor((phrase.id - 2048) / 256) * 3 + language;
        const encoded = xml.match(new RegExp(`<string id="UiHot${bucket}">([\\s\\S]*?)</string>`))[1];
        const packed = encoded.replaceAll("&lt;", "<").replaceAll("&gt;", ">").replaceAll("&amp;", "&");
        assert.ok(Buffer.byteLength(packed) <= 600);
        assert.ok(packed.includes(`~u${phrase.id}|${phrase.values[language]}~`));
      }
    }
    assert.ok(hot.some(phrase => phrase.id >= 2304), "interactive screens span bounded shards");
  });
});
