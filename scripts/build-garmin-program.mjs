import { spawnSync } from "node:child_process";
import { createHash, createPrivateKey, createPublicKey } from "node:crypto";
import { cp, mkdir, mkdtemp, readFile, readdir, rename, rm, stat, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { buildOptimizedProject, getConfig } from "@markw65/monkeyc-optimizer";
import { optimizeProgram, readPrg, SectionKinds } from "@markw65/monkeyc-optimizer/sdk-util.js";
import { prepareGarminSources } from "./lib/garmin-build-sources.mjs";
import { pruneUnusedGarminDiagnostics } from "./lib/garmin-prune-diagnostics.mjs";
import { splitGarminStoreStatics } from "./lib/garmin-store-statics.mjs";

const projectRoot = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const garminRoot = path.join(projectRoot, "garmin");
const outputRoot = path.join(garminRoot, "build");
const releaseFingerprint = "926b106c47125ddc97aef9801ffd4812f54562140122bb30f792493ed92adb47";
const values = new Set(["--sdk", "--developer-key", "--output", "--device", "--java-home"]);
const flags = new Set(["--export", "--test"]);

function parseArgs(args) {
  const result = {};
  for (let index = 0; index < args.length; index += 1) {
    const key = args[index];
    if (Object.hasOwn(result, key)) throw new Error(`Duplicate argument ${key}`);
    if (flags.has(key)) result[key] = true;
    else if (values.has(key) && args[index + 1] && !args[index + 1].startsWith("--")) {
      result[key] = args[++index];
    } else throw new Error(`Invalid Garmin build argument: ${key}`);
  }
  for (const key of ["--sdk", "--developer-key", "--output"]) {
    if (!result[key]) throw new Error(`Missing ${key}`);
  }
  if (result["--export"] && result["--test"]) throw new Error("Export cannot contain tests");
  if (!result["--export"] && !/^[a-z0-9]+$/.test(result["--device"] ?? "")) {
    throw new Error("A native Garmin device identifier is required");
  }
  return result;
}

async function verifyExportKey(keyPath) {
  const bytes = await readFile(keyPath);
  let key;
  try {
    try { key = createPrivateKey({ key: bytes, format: "der", type: "pkcs8" }); }
    catch { key = createPrivateKey({ key: bytes, format: "der", type: "pkcs1" }); }
    const publicDer = createPublicKey(key).export({ format: "der", type: "spki" });
    if (createHash("sha256").update(publicDer).digest("hex") !== releaseFingerprint) {
      throw new Error("Unapproved signer");
    }
  } catch {
    throw new Error("Garmin export signer does not match the pinned Store identity");
  } finally {
    bytes.fill(0);
  }
}

async function addTextTest(sourceRoot, phrases) {
  const literal = text => JSON.stringify(text);
  const rows = phrases.map(phrase => `[${phrase.id}, ${phrase.values.map(literal).join(", ")}]`);
  const exerciseLabels = JSON.parse(await readFile(
    path.join(garminRoot, "resources", "exercise-labels.json"), "utf8"));
  const exerciseRows = Object.entries(exerciseLabels).map(([name, labels]) =>
    `[${[name, ...labels].map(literal).join(", ")}]`);
  await writeFile(path.join(sourceRoot, "GymBuildTextTests.mc"), `using Toybox.Test;
using Toybox.Lang;
(:test)
function nativeUiTextPreservesEveryLanguageAndWhitespace(logger as Test.Logger) as Lang.Boolean {
    var previous = GymStore.language;
    var rows = [${rows.join(",\n        ")}];
    var languages = ["en", "uk", "ru", "unknown"];
    for (var languageIndex = 0; languageIndex < languages.size(); languageIndex += 1) {
        GymStore.language = languages[languageIndex];
        var expectedIndex = languageIndex == 3 ? 1 : languageIndex + 1;
        for (var index = 0; index < rows.size(); index += 1) {
            if (!GymText.get(rows[index][0]).equals(rows[index][expectedIndex])) {
                logger.debug("UI text mismatch: " + rows[index][0].toString() + " / " + GymStore.language);
                logger.debug("Expected: [" + rows[index][expectedIndex] + "] actual: [" + GymText.get(rows[index][0]) + "]");
                logger.debug("Language index: " + languageIndex.toString() + " expected index: " + expectedIndex.toString());
                GymStore.language = previous;
                return false;
            }
        }
    }
    GymStore.language = previous;
    return true;
}

(:test)
function nativeExerciseLabelsPreserveEveryLanguageAndCustomName(logger as Test.Logger) as Lang.Boolean {
    var previous = GymStore.language;
    var rows = [${exerciseRows.join(",\n        ")}];
    var languages = ["en", "uk", "ru", "unknown"];
    for (var languageIndex = 0; languageIndex < languages.size(); languageIndex += 1) {
        GymStore.language = languages[languageIndex];
        var expectedIndex = languageIndex == 3 ? 0 : languageIndex;
        for (var index = 0; index < rows.size(); index += 1) {
            if (!GymStore.localizedExerciseName(rows[index][0]).equals(rows[index][expectedIndex])) {
                logger.debug("Exercise label mismatch: " + rows[index][0] + " / " + GymStore.language);
                GymStore.language = previous;
                return false;
            }
        }
        var custom = ["u0", "u15", "u100", "eBench Press", "~Bench Press", "Curl|Custom"];
        for (var index = 0; index < custom.size(); index += 1) {
            if (!GymStore.localizedExerciseName(custom[index]).equals(custom[index])) {
                GymStore.language = previous;
                return false;
            }
        }
    }
    GymStore.language = previous;
    return true;
}
`);
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const exportBuild = !!args["--export"];
  const testBuild = !!args["--test"];
  const keyPath = path.resolve(args["--developer-key"]);
  const sdkPath = path.resolve(args["--sdk"]) + path.sep;
  const output = path.resolve(args["--output"]);
  if (path.extname(output) !== (exportBuild ? ".iq" : ".prg")) {
    throw new Error("Output type does not match the build mode");
  }
  if (!(await stat(keyPath)).isFile()) throw new Error("Developer key must be a file");
  if (exportBuild) await verifyExportKey(keyPath);
  await mkdir(outputRoot, { recursive: true });
  const temporaryRoot = await mkdtemp(path.join(outputRoot, ".program-"));
  try {
    const sourceRoot = path.join(temporaryRoot, "project");
    await mkdir(sourceRoot);
    for (const name of await readdir(garminRoot)) {
      if (name === "source" || name === "manifest.xml" || name.endsWith(".jungle") ||
          name === "resources" || name.startsWith("resources-")) {
        await cp(path.join(garminRoot, name), path.join(sourceRoot, name), { recursive: true });
      }
    }
    const phrases = await prepareGarminSources(sourceRoot);
    if (testBuild) await addTextTest(path.join(sourceRoot, "source"), phrases);
    const config = await getConfig({
      ignore_settings_files: true,
      workspace: sourceRoot,
      jungleFiles: path.join(sourceRoot, "monkey.jungle"),
      outputPath: path.join(temporaryRoot, "sources"),
      buildDir: path.join(temporaryRoot, "compiler"),
      developerKeyPath: keyPath,
      sdkPath,
      javaPath: args["--java-home"] || process.env.JAVA_HOME,
      simulatorBuild: testBuild,
      releaseBuild: !testBuild,
      testBuild,
      // Type propagation in 1.2.6 incorrectly folds a loop-dependent choice.
      // Keep that pass and single-use propagation disabled. Native SDK tests
      // exercise the remaining size passes and the final PRG together.
      skipOptimization: false,
      propagateTypes: false,
      singleUseCopyProp: false,
      minimizeLocals: true,
      sizeBasedPRE: true,
      minimizeModules: true,
      typeCheckLevel: "Gradual",
      compilerWarnings: true,
      optimizationLevel: "Slow",
      trustDeclaredTypes: false,
      preserveNullAssignments: true,
      iterateOptimizer: true,
      postBuildOptimizer: false,
      allowForbiddenOpts: false,
      returnCommand: true
    });
    const command = await buildOptimizedProject(exportBuild ? null : args["--device"], config);
    if (Object.values(command.diagnostics ?? {}).flat().some(item => item.type === "ERROR")) {
      throw new Error("Garmin source analysis failed");
    }
    await pruneUnusedGarminDiagnostics(path.join(temporaryRoot, "sources"));
    await splitGarminStoreStatics(path.join(temporaryRoot, "sources"));
    const rawRoot = path.join(temporaryRoot, "raw");
    const finalRoot = path.join(temporaryRoot, "final");
    await mkdir(rawRoot);
    await mkdir(finalRoot);
    const raw = path.join(rawRoot, path.basename(output));
    const prepared = path.join(finalRoot, path.basename(output));
    const outputIndex = command.args.indexOf("-o");
    if (outputIndex < 0) throw new Error("Compiler output argument is missing");
    command.args[outputIndex + 1] = raw;
    const compiled = spawnSync(command.exe, command.args, { stdio: "inherit", shell: false });
    if (compiled.error || compiled.status !== 0) throw new Error("Garmin compilation failed");
    await optimizeProgram(raw, keyPath, prepared, {
      sdkPath, allowForbiddenOpts: false, removeArgc: false,
      // Bytecode PRE frees native callback/serialization headroom. Preserve
      // explicit null releases and SDK argument checks in the final program.
      postBuildPRE: true, preserveNullAssignments: true
    });
    if (!exportBuild) {
      const [before, after] = await Promise.all([readPrg(raw), readPrg(prepared)]);
      const size = value => value[SectionKinds.TEXT] + value[SectionKinds.DATA];
      if (!(size(after) > 0) || size(after) > size(before)) {
        throw new Error("Garmin program size verification failed");
      }
      console.log(`Garmin code and data: ${size(after)} bytes`);
    }
    await mkdir(path.dirname(output), { recursive: true });
    for (const name of await readdir(finalRoot)) {
      await rename(path.join(finalRoot, name), path.join(path.dirname(output), name));
    }
  } finally {
    await rm(temporaryRoot, { recursive: true, force: true });
  }
}

main().catch(error => {
  console.error(error.message);
  process.exitCode = 1;
});
