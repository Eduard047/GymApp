import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const graph = await readFile("app/src/main/java/com/example/gymapp/navigation/GymNavGraph.kt", "utf8");

function functionBody(source, signature) {
  const start = source.indexOf(signature);
  assert.notEqual(start, -1, `${signature} must exist`);
  const open = source.indexOf("{", source.indexOf(")", start));
  let depth = 0;
  for (let i = open; i < source.length; i += 1) {
    if (source[i] === "{") depth += 1;
    if (source[i] === "}") {
      depth -= 1;
      if (depth === 0) return source.slice(open, i + 1);
    }
  }
  throw new Error(`${signature} body is not closed`);
}

test("Android records both cloud baselines even when the upload caller is cancelled after the server write", () => {
  const upload = functionBody(graph, "suspend fun uploadCloudAutosaveSnapshot(");
  const save = upload.indexOf("authManager.saveRemoteState(");
  const guard = upload.indexOf("withContext(NonCancellable) {");
  assert.ok(save > -1, "upload must write the remote state");
  assert.ok(guard > save, "the NonCancellable block must start after the remote write, not wrap it");

  const guarded = functionBody(upload.slice(guard), "withContext(NonCancellable)");
  assert.match(guarded, /isSameCloudSessionGeneration\(/, "the session generation check stays before the baseline writes");
  assert.match(guarded, /cloudSyncBaselineStore\.write\(session\.userId, stateDigest\)/);
  assert.match(guarded, /recordWorkoutMergeBaselineFromState\(/);
  assert.doesNotMatch(guarded, /saveRemoteState|syncActivityOnlyFromBaseline/, "no network call runs under NonCancellable");
  assert.ok(
    guarded.indexOf("isSameCloudSessionGeneration(") < guarded.indexOf("cloudSyncBaselineStore.write("),
    "session check must run before the baseline write"
  );
});
