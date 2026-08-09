import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const baseMigrationPath =
  "supabase/migrations/20260711084556_create_leaderboard_public.sql";
const boundMigrationPath =
  "supabase/migrations/20260722011000_bound_leaderboard_reports.sql";
const iosCloudClientPath =
  "ios/GymApp-iOS/GymApp/Services/CloudSyncService.swift";

const [baseMigration, boundMigration, iosCloudClient] = await Promise.all([
  readFile(baseMigrationPath, "utf8"),
  readFile(boundMigrationPath, "utf8"),
  readFile(iosCloudClientPath, "utf8")
]);

function section(source, startMarker, endMarker) {
  const start = source.indexOf(startMarker);
  const end = source.indexOf(endMarker, start + startMarker.length);
  assert.ok(start >= 0, `missing start marker: ${startMarker}`);
  assert.ok(end > start, `missing end marker: ${endMarker}`);
  return source.slice(start, end);
}

const triggerFunction = section(
  boundMigration,
  "create or replace function public.prepare_leaderboard_report()",
  "comment on function public.prepare_leaderboard_report()"
);

test("legacy report admission stays server-bounded while current iOS no longer exposes global reports", () => {
  const lockAt = triggerFunction.indexOf("pg_catalog.pg_advisory_xact_lock");
  const targetLookupAt = triggerFunction.indexOf("from public.profiles as profile");
  const pendingCheckAt = triggerFunction.indexOf("if exists (");
  const pendingCheckEnd = triggerFunction.indexOf(") then", pendingCheckAt);
  const insertFieldsAt = triggerFunction.indexOf("new.id :=");

  assert.ok(lockAt >= 0, "missing transaction-scoped report admission lock");
  assert.ok(
    lockAt < targetLookupAt && targetLookupAt < pendingCheckAt,
    "the reporter lock must precede all target-dependent admission work"
  );
  assert.ok(
    pendingCheckAt < insertFieldsAt,
    "the pending check must run before server fields are accepted"
  );
  assert.match(
    triggerFunction,
    /pg_catalog\.pg_advisory_xact_lock\(\s*pg_catalog\.hashtextextended\(caller_user_id::text,\s*719924\s*\)\s*\)/
  );
  assert.equal(
    triggerFunction.match(/pg_catalog\.pg_advisory_xact_lock/g)?.length,
    1,
    "report admission must use one lock domain rather than ordered pair locks"
  );
  assert.doesNotMatch(
    triggerFunction.slice(lockAt, triggerFunction.indexOf(");", lockAt) + 2),
    /target_user_id|reported_profile_id|reported_display_name|target_display_name|new\.reason/,
    "target, snapshot, and reason variants must not select different lock domains"
  );

  const lockDomain = (reporter) => reporter;
  const forwardBatch = ["target-a", "target-b"].map(() => lockDomain("reporter-a"));
  const reverseBatch = ["target-b", "target-a"].map(() => lockDomain("reporter-a"));
  assert.deepEqual(forwardBatch, ["reporter-a", "reporter-a"]);
  assert.deepEqual(reverseBatch, forwardBatch);
  assert.equal(
    new Set([...forwardBatch, ...reverseBatch]).size,
    1,
    "reversed batches from one reporter must contend on one re-entrant lock"
  );

  assert.ok(pendingCheckEnd > pendingCheckAt, "pending report check is incomplete");
  assert.doesNotMatch(
    triggerFunction.slice(pendingCheckAt, pendingCheckEnd),
    /reported_display_name|target_display_name/,
    "mutable display-name snapshots must not reopen a pending admission key"
  );
  assert.match(
    triggerFunction,
    /from public\.leaderboard_reports as report[\s\S]*report\.reporter_user_id = caller_user_id[\s\S]*report\.reported_profile_id = new\.reported_profile_id[\s\S]*report\.reason = new\.reason[\s\S]*report\.status = 'pending'/
  );
  assert.match(
    triggerFunction,
    /errcode = '23505'[\s\S]*message = 'Duplicate pending leaderboard report\.'/
  );
  assert.doesNotMatch(iosCloudClient, /leaderboard_reports|reportLeaderboardProfile|reportAlreadySubmitted/);
});

test("the transactional index rollout bounds write-lock acquisition and duration", () => {
  const beginAt = boundMigration.indexOf("begin;");
  const lockTimeoutAt = boundMigration.indexOf("set local lock_timeout = '5s';");
  const statementTimeoutAt = boundMigration.indexOf(
    "set local statement_timeout = '30s';"
  );
  const indexAt = boundMigration.indexOf(
    "create index leaderboard_reports_pending_reporter_target_reason_idx"
  );
  const commitAt = boundMigration.lastIndexOf("commit;");

  assert.ok(
    beginAt >= 0 &&
      beginAt < lockTimeoutAt &&
      lockTimeoutAt < statementTimeoutAt &&
      statementTimeoutAt < indexAt &&
      indexAt < commitAt,
    "the bounded index build must remain inside the migration transaction"
  );
  assert.doesNotMatch(
    boundMigration,
    /create index concurrently/i,
    "CONCURRENTLY cannot run inside this atomic migration transaction"
  );
  assert.match(boundMigration, /reviewed low-traffic window/);
  assert.match(boundMigration, /transaction back for a later retry/);
});

test("six fixed reasons bound future pending rows independently of display names", () => {
  const reasonConstraint = section(
    baseMigration,
    "reason text not null",
    "status text not null"
  );
  const allowedReasons = [
    ...reasonConstraint.matchAll(/'([a-z_]+)'/g)
  ].map((match) => match[1]);

  assert.deepEqual(allowedReasons, [
    "inappropriate_name",
    "hate_or_harassment",
    "impersonation",
    "spam_or_scam",
    "personal_information",
    "other"
  ]);
  for (const reason of allowedReasons) {
    assert.ok(triggerFunction.includes(`'${reason}'`), `trigger omitted ${reason}`);
  }
  assert.match(
    triggerFunction,
    /if new\.reason is null\s+or new\.reason not in \([\s\S]*'other'[\s\S]*\) then/
  );
  assert.match(
    boundMigration,
    /create index leaderboard_reports_pending_reporter_target_reason_idx\s+on public\.leaderboard_reports \(\s*reporter_user_id,\s*reported_profile_id,\s*reason\s*\)\s+where status = 'pending';/
  );

  const mutableNames = Array.from({ length: 100 }, (_, index) => `safe-name-${index}`);
  const admissionKeys = new Set(
    mutableNames.flatMap(() =>
      allowedReasons.map((reason) => ["reporter-a", "target-b", reason].join("|"))
    )
  );
  assert.equal(
    admissionKeys.size,
    6,
    "mutable name snapshots must not expand the six stable pending admission keys"
  );
});

test("the migration preserves report data and the existing authorization contract", () => {
  assert.match(triggerFunction, /caller_user_id := auth\.uid\(\)/);
  assert.match(triggerFunction, /where profile\.public_id = new\.reported_profile_id/);
  assert.match(triggerFunction, /if target_user_id = caller_user_id then/);
  assert.match(triggerFunction, /new\.reported_display_name := target_display_name/);
  assert.match(triggerFunction, /new\.status := 'pending'/);
  assert.match(triggerFunction, /new\.created_at := pg_catalog\.clock_timestamp\(\)/);
  assert.match(triggerFunction, /security definer\s+set search_path = ''/);

  assert.doesNotMatch(
    boundMigration,
    /\b(?:delete from|update|truncate table)\s+public\.leaderboard_reports/i
  );
  assert.doesNotMatch(
    boundMigration,
    /\b(?:grant|revoke)\b[\s\S]{0,100}\bon table public\.leaderboard_reports/i
  );
  assert.doesNotMatch(
    boundMigration,
    /\b(?:drop table|drop policy|alter policy|disable row level security)\b/i
  );
  assert.match(
    boundMigration,
    /revoke all on function public\.prepare_leaderboard_report\(\)\s+from public, anon, authenticated;/
  );
  assert.match(boundMigration, /relation\.relrowsecurity/);
  assert.match(
    boundMigration,
    /policy\.policyname = 'authenticated users can submit leaderboard reports'/
  );
  assert.match(
    baseMigration,
    /grant insert \(reported_profile_id, reason\)[\s\S]*to authenticated;/
  );
  assert.match(
    baseMigration,
    /grant select, insert, update, delete[\s\S]*to service_role;/
  );
});
