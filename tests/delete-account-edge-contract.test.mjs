import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { access, readFile } from "node:fs/promises";
import { resolve } from "node:path";
import test from "node:test";

const sourcePath = "supabase/functions/delete-account/index.ts";
const sharedSourcePath = "supabase/functions/_shared/preauth-budget.ts";
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
  sharedSource,
  deploymentContractRaw,
  readme,
  iosSupabaseReadme,
  edgeConfig,
] = await Promise.all([
  readFile(sourcePath, "utf8"),
  readFile(sharedSourcePath, "utf8"),
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
  assert.equal(deploymentContract.repositorySharedSource, sharedSourcePath);
  assert.equal(
    createHash("sha256").update(source).digest("hex"),
    deploymentContract.repositorySourceSha256,
    "update repositoryContractVersion and its source hash whenever the Edge contract changes",
  );
  assert.equal(
    createHash("sha256").update(sharedSource).digest("hex"),
    deploymentContract.repositorySharedSourceSha256,
    "pin the shared verified-identity budget source whenever it changes",
  );
  assert.equal(await pathExists(nestedIOSSourcePath), false);
  assert.equal(await pathExists(nestedIOSReadmePath), false);
  assert.match(readme, /canonical source of truth/i);
  assert.match(
    iosSupabaseReadme,
    /\.\.\/\.\.\/\.\.\/supabase\/functions\/delete-account\/README\.md/,
  );
});

test("one-time deletion grant remains between user verification and administrative deletion", () => {
  const authUserCall = source.indexOf("/auth/v1/user");
  const liveSessionCall = source.indexOf(
    "/rest/v1/rpc/consume_account_deletion_grant",
  );
  const administrativeDelete = source.indexOf("/auth/v1/admin/users/");

  assert.ok(authUserCall >= 0, "Auth user verification must remain present");
  assert.ok(
    liveSessionCall > authUserCall,
    "one-time grant consumption must run after Auth user verification",
  );
  assert.ok(
    administrativeDelete > liveSessionCall,
    "administrative deletion must run only after one-time grant consumption",
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
  const identityBudgetMigration = await readFile(
    deploymentContract.identityBudgetMigration,
    "utf8",
  );
  assert.match(
    requiredMigration,
    /consume_account_deletion_grant/,
  );
  assert.match(identityBudgetMigration, /Invalid verified identity/);
  const isolatedLimiterBody = identityBudgetMigration.match(
    /as \$function\$\s*([\s\S]*?)\$function\$;/,
  )?.[1];
  assert.ok(isolatedLimiterBody);
  assert.doesNotMatch(isolatedLimiterBody, /global_(?:hash|limit)/);

  const production = deploymentContract.knownProduction;
  const gate = deploymentContract.releaseGate;
  const productionIsCurrent = production.requiredMigrationApplied === true &&
    production.identityBudgetMigrationApplied === true &&
    production.functionVersion >= gate.minimumProductionFunctionVersion &&
    production.implementsRepositoryContractVersion ===
      deploymentContract.repositoryContractVersion &&
    production.sourceSha256 === deploymentContract.repositorySourceSha256 &&
    production.sharedSourceSha256 ===
      deploymentContract.repositorySharedSourceSha256 &&
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
