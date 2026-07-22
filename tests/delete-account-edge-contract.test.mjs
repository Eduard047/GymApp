import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { access, readFile } from "node:fs/promises";
import { resolve } from "node:path";
import test from "node:test";

const sourcePath = "supabase/functions/delete-account/index.ts";
const deploymentContractPath =
  "supabase/functions/delete-account/deployment-contract.json";
const readmePath = "supabase/functions/delete-account/README.md";
const nestedIOSSourcePath =
  "ios/GymApp-iOS/supabase/functions/delete-account/index.ts";
const nestedIOSReadmePath =
  "ios/GymApp-iOS/supabase/functions/delete-account/README.md";
const iosSupabaseReadmePath = "ios/GymApp-iOS/supabase/README.md";
const edgeConfigPath = "supabase/config.toml";

const [
  source,
  deploymentContractRaw,
  readme,
  iosSupabaseReadme,
  edgeConfig,
] = await Promise.all([
  readFile(sourcePath, "utf8"),
  readFile(deploymentContractPath, "utf8"),
  readFile(readmePath, "utf8"),
  readFile(iosSupabaseReadmePath, "utf8"),
  readFile(edgeConfigPath, "utf8"),
]);
const deploymentContract = JSON.parse(deploymentContractRaw);

async function pathExists(path) {
  try {
    await access(resolve(path));
    return true;
  } catch (error) {
    if (error?.code === "ENOENT") return false;
    throw error;
  }
}

test("delete-account has one canonical Edge source with a pinned contract hash", async () => {
  assert.equal(deploymentContract.functionName, "delete-account");
  assert.equal(deploymentContract.repositorySource, sourcePath);
  assert.equal(
    createHash("sha256").update(source).digest("hex"),
    deploymentContract.repositorySourceSha256,
    "update repositoryContractVersion and its source hash whenever the Edge contract changes",
  );
  assert.equal(await pathExists(nestedIOSSourcePath), false);
  assert.equal(await pathExists(nestedIOSReadmePath), false);
  assert.match(readme, /canonical source of truth/i);
  assert.match(
    iosSupabaseReadme,
    /\.\.\/\.\.\/\.\.\/supabase\/functions\/delete-account\/README\.md/,
  );
});

test("live-session RPC remains between user verification and administrative deletion", () => {
  const authUserCall = source.indexOf("/auth/v1/user");
  const liveSessionCall = source.indexOf(
    "/rest/v1/rpc/require_live_session_for_account_deletion",
  );
  const administrativeDelete = source.indexOf("/auth/v1/admin/users/");

  assert.ok(authUserCall >= 0, "Auth user verification must remain present");
  assert.ok(
    liveSessionCall > authUserCall,
    "live-session RPC must run after Auth user verification",
  );
  assert.ok(
    administrativeDelete > liveSessionCall,
    "administrative deletion must run only after the live-session RPC",
  );
  assert.match(source, /Authorization: authorization/);
  assert.match(
    source,
    /liveSessionUserId\.toLowerCase\(\) !== authenticatedUser\.id\.toLowerCase\(\)/,
  );
  assert.match(source, /encodeURIComponent\(authenticatedUser\.id\)/);

  const functionSection = /\[functions\.delete-account\]([\s\S]*?)(?=\n\[|$)/
    .exec(edgeConfig)?.[1];
  assert.ok(
    functionSection,
    "delete-account must have an explicit function config",
  );
  assert.match(functionSection, /verify_jwt\s*=\s*true/);
});

test("known production state is represented by an enforceable release gate", async () => {
  const requiredMigration = await readFile(
    deploymentContract.requiredMigration,
    "utf8",
  );
  assert.match(
    requiredMigration,
    /require_live_session_for_account_deletion/,
  );

  const production = deploymentContract.knownProduction;
  const gate = deploymentContract.releaseGate;
  const productionIsCurrent = production.requiredMigrationApplied === true &&
    production.functionVersion >= gate.minimumProductionFunctionVersion &&
    production.implementsRepositoryContractVersion ===
      deploymentContract.repositoryContractVersion &&
    production.sourceSha256 === deploymentContract.repositorySourceSha256 &&
    production.verifyJwt === true;

  assert.equal(
    gate.deploymentRequired,
    !productionIsCurrent,
    "deploymentRequired must exactly reflect the pinned production snapshot",
  );
  if (gate.deploymentRequired) {
    assert.match(gate.reason, /apply the required migration/i);
    assert.match(gate.reason, /deploy the canonical repository source/i);
  }

  if (process.env.GYMAPP_ENFORCE_SUPABASE_RELEASE_GATE === "1") {
    assert.equal(
      productionIsCurrent,
      true,
      "release blocked: update production, then refresh deployment-contract.json from read-only deployment evidence",
    );
  }
});
