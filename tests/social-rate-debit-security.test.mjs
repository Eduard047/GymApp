import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const activationPath =
  "supabase/migrations/20260809202432_activate_friend_social_api.sql";
const durableDebitPath =
  "supabase/migrations/20260810003804_persist_social_rate_debits_on_domain_errors.sql";
const deepHardeningPath =
  "supabase/migrations/20260902084252_harden_deep_scan_boundaries.sql";
const friendCodeBudgetPath =
  "supabase/migrations/20260902162407_meter_friend_code_requests.sql";

const sharedGatewayActions = [
  ["dashboard", "social_dashboard"],
  ["friend_details", "social_friend_details"],
  ["send_friend", "social_send_friend_request"],
  ["respond_friend", "social_respond_friend_request"],
  ["cancel_friend", "social_cancel_friend_request"],
  ["remove_friend", "social_remove_friend"],
  ["block_profile", "social_block_profile"],
  ["unblock_profile", "social_unblock_profile"],
  ["update_privacy", "social_update_privacy"],
  ["workout_inbox", "social_workout_inbox"],
  ["send_workout", "social_send_workout_invite"],
  ["respond_workout", "social_respond_workout_invite"],
  ["cancel_workout", "social_cancel_workout_invite"],
];

const protectedRpcs = [
  ["social_friend_details", "friend_details", "text"],
  [
    "social_respond_friend_request",
    "respond_friend",
    "text, text, bigint",
  ],
  ["social_cancel_friend_request", "cancel_friend", "text, bigint"],
  ["social_remove_friend", "remove_friend", "text, bigint"],
  ["social_block_profile", "block_profile", "text"],
  ["social_unblock_profile", "unblock_profile", "text"],
  [
    "social_update_privacy",
    "update_privacy",
    "boolean, boolean, boolean, boolean, bigint",
  ],
  [
    "social_respond_workout_invite",
    "respond_workout",
    "text, text, bigint",
  ],
  ["social_cancel_workout_invite", "cancel_workout", "text, bigint"],
];

function functionBody(sql, qualifiedName) {
  let start = sql.indexOf(`create or replace function ${qualifiedName}(`);
  if (start < 0) start = sql.indexOf(`create function ${qualifiedName}(`);
  assert.ok(start >= 0, `${qualifiedName} must exist`);
  const end = sql.indexOf("\n$function$;", start);
  assert.ok(end > start, `${qualifiedName} must use a bounded function body`);
  return sql.slice(start, end + "\n$function$;".length);
}

function normalizeSql(value) {
  return value
    .replace(/[ \t]+$/gm, "")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function unwrapDurableDebitBody(body, action) {
  const debit =
    `  caller_user_id := gymapp_private.social_require_caller('${action}');`;
  const debitIndex = body.indexOf(debit);
  assert.ok(
    debitIndex >= 0,
    `${action} must debit through social_require_caller`,
  );

  const nestedBegin = "\n\n  begin\n";
  const nestedBeginIndex = body.indexOf(
    nestedBegin,
    debitIndex + debit.length,
  );
  const handlerIndex = body.lastIndexOf("\n  exception\n");
  assert.ok(
    nestedBeginIndex > debitIndex && handlerIndex > nestedBeginIndex,
    `${action} must keep its debit outside the domain-error subtransaction`,
  );

  const prefix = body
    .slice(0, nestedBeginIndex)
    .replace(
      /  domain_error_code text;\n  domain_error_message text;\n  domain_error_detail text;\n  domain_error_hint text;\n/,
      "",
    );
  const businessBody = body
    .slice(nestedBeginIndex + nestedBegin.length, handlerIndex)
    .split("\n")
    .map((line) => (line.startsWith("  ") ? line.slice(2) : line))
    .join("\n");
  const handler = body.slice(handlerIndex);

  assert.match(
    handler,
    /^\n  exception\n    when sqlstate '22023' or sqlstate 'P0001' or sqlstate 'P0002' then\n      get stacked diagnostics[\s\S]*return gymapp_private\.social_domain_error_response\([\s\S]*\n  end;\nend\n\$function\$;$/,
    `${action} must catch only the reviewed domain SQLSTATEs`,
  );
  assert.doesNotMatch(handler, /when\s+others/i);

  return normalizeSql(`${prefix}\n${businessBody}\nend\n$function$;`);
}

test("social domain errors commit exactly the outer debit and keep the old RPC business contract", async () => {
  const [activation, durableDebit] = await Promise.all([
    readFile(activationPath, "utf8"),
    readFile(durableDebitPath, "utf8"),
  ]);

  for (const [name, action] of protectedRpcs) {
    const qualifiedName = `public.${name}`;
    const original = normalizeSql(functionBody(activation, qualifiedName));
    const replacement = functionBody(durableDebit, qualifiedName);

    assert.equal(
      unwrapDurableDebitBody(replacement, action),
      original,
      `${qualifiedName} must differ only by the durable-debit wrapper`,
    );
    assert.equal(
      (
        replacement.match(
          new RegExp(`social_require_caller\\('${action}'\\)`, "g"),
        ) || []
      ).length,
      1,
      `${qualifiedName} must charge once`,
    );
    assert.match(replacement, /security definer\s+set search_path = ''/);
  }

  const replacedPublicRpcs = [
    ...durableDebit.matchAll(
      /create or replace function public\.(social_[a-z_]+)\(/g,
    ),
  ].map((match) => match[1]);
  assert.deepEqual(
    replacedPublicRpcs.toSorted(),
    protectedRpcs.map(([name]) => name).toSorted(),
    "generic-send and read-only RPCs must remain untouched",
  );
});

test("domain responses preserve PostgREST status/body behavior without catching infrastructure failures", async () => {
  const durableDebit = await readFile(durableDebitPath, "utf8");
  const helper = functionBody(
    durableDebit,
    "gymapp_private.social_domain_error_response",
  );

  assert.match(helper, /security invoker\s+set search_path = ''/);
  assert.match(helper, /p_code not in \('22023', 'P0001', 'P0002'\)/);
  assert.match(helper, /'response\.status'/);
  assert.match(
    helper,
    /case when p_code = 'P0002' then '500' else '400' end/,
  );
  assert.match(
    helper,
    /'code', p_code,[\s\S]*'details', nullif\(p_detail, ''\),[\s\S]*'hint', nullif\(p_hint, ''\),[\s\S]*'message', p_message/,
  );
  assert.doesNotMatch(helper, /when\s+others/i);
  assert.doesNotMatch(
    durableDebit,
    /when sqlstate '(?:42501|40P01|57014|23505|54000)'/,
    "auth, cancellation, deadlock, constraint, and resource failures must still abort",
  );
  assert.match(
    durableDebit,
    /revoke all on function gymapp_private\.social_domain_error_response\(text, text, text, text\)\s+from public, anon, authenticated, service_role/,
  );

  for (const [name, , signature] of protectedRpcs) {
    const escapedSignature = signature.replaceAll(", ", ",\\s*");
    assert.match(
      durableDebit,
      new RegExp(
        `revoke all on function public\\.${name}\\(\\s*${escapedSignature}\\s*\\)\\s+from public, anon, authenticated, service_role`,
      ),
    );
    assert.match(
      durableDebit,
      new RegExp(
        `grant execute on function public\\.${name}\\(\\s*${escapedSignature}\\s*\\)\\s+to authenticated`,
      ),
    );
  }
});

test("direct social RPCs and service-only live routes share the same aggregate and action buckets", async () => {
  const hardening = await readFile(deepHardeningPath, "utf8");
  const sessionHash = functionBody(
    hardening,
    "gymapp_private.social_session_budget_hash",
  );
  const aggregateDebit = functionBody(
    hardening,
    "gymapp_private.social_session_aggregate_debit",
  );
  const sharedDebit = functionBody(
    hardening,
    "gymapp_private.social_live_debit_budget",
  );
  const directBoundary = functionBody(
    hardening,
    "gymapp_private.social_require_caller",
  );
  const serviceWrapper = functionBody(
    hardening,
    "public.social_live_gateway_debit",
  );
  const perimeterWrapper = functionBody(
    hardening,
    "public.social_gateway_perimeter_debit",
  );

  const sessionLock = aggregateDebit.indexOf("live_gateway_require_session(");
  const aggregate = aggregateDebit.indexOf("edge_preauth_debit(");
  const actionBucket = sharedDebit.indexOf(
    "social_live_gateway_debit_storage_v1(",
  );
  assert.ok(sessionLock >= 0 && sessionLock < aggregate);
  assert.ok(
    sharedDebit.indexOf("social_session_aggregate_debit(") >= 0 &&
      sharedDebit.indexOf("social_session_aggregate_debit(") < actionBucket,
  );
  assert.match(
    aggregateDebit,
    /p_route not in \('social_live', 'social_gateway'\)/,
  );
  assert.match(sharedDebit, /'social_live'/);
  assert.match(sessionHash, /'session:' \|\| p_session_id::text/);
  assert.match(serviceWrapper, /social_live_debit_budget\(/);
  assert.doesNotMatch(serviceWrapper, /social_live_gateway_debit_storage_v1\(/);
  assert.match(
    perimeterWrapper,
    /social_session_aggregate_debit\(\s*'social_gateway'/,
  );

  for (const [domainAction, gatewayAction] of sharedGatewayActions) {
    assert.match(
      directBoundary,
      new RegExp(`\\('${domainAction}', '${gatewayAction}'\\)`),
    );
  }
  assert.match(directBoundary, /social_live_debit_budget\(/);
  assert.match(
    directBoundary,
    /consume_social_rate_limit\(caller_user_id, p_action\)/,
  );
  assert.match(directBoundary, /errcode = 'PT429'/);
  assert.match(
    directBoundary,
    /consume_social_rate_limit\([\s\S]*when sqlstate 'P0001' then[\s\S]*errcode = 'PT429'/,
  );
  assert.match(
    hardening,
    /revoke all on function public\.social_live_gateway_debit\(uuid, uuid, text\)[\s\S]*grant execute on function public\.social_live_gateway_debit\(uuid, uuid, text\)\s+to service_role;/,
  );
  assert.match(
    hardening,
    /revoke all on function public\.social_gateway_perimeter_debit\(uuid, uuid\)[\s\S]*grant execute on function public\.social_gateway_perimeter_debit\(uuid, uuid\)\s+to service_role;/,
  );
});

test("later direct social RPCs durably restore aggregate, mapped-action, and domain debits on rejection", async () => {
  const hardening = await readFile(deepHardeningPath, "utf8");
  const beginDirect = functionBody(
    hardening,
    "gymapp_private.social_begin_direct_request",
  );
  const commitRejection = functionBody(
    hardening,
    "gymapp_private.social_commit_direct_rejection",
  );
  const friendPageStorage = functionBody(
    hardening,
    "gymapp_private.social_friend_workout_page_storage_v2",
  );
  const laterRpcs = [
    ["social_update_workout_detail_privacy", "update_privacy"],
    ["social_friend_workout_detail_capability", "friend_details"],
    ["social_friend_workout_page", "friend_details"],
    ["social_workout_inbox_page", "workout_inbox"],
  ];

  assert.match(beginDirect, /social_session_aggregate_debit\(/);
  assert.match(beginDirect, /request_count = budget\.request_count - 1/);
  assert.match(commitRejection, /social_live_debit_budget\(/);
  assert.match(
    hardening,
    /alter function public\.social_friend_workout_page_base_v1\([\s\S]*set schema gymapp_private/,
  );
  assert.match(
    friendPageStorage,
    /gymapp_private\.social_friend_workout_page_base_storage_v1\(/,
  );
  assert.doesNotMatch(
    friendPageStorage,
    /public\.social_friend_workout_page_base_v1/,
  );
  assert.ok(
    commitRejection.indexOf("social_live_debit_budget(") <
      commitRejection.indexOf(
        "perform gymapp_private.consume_social_rate_limit(",
      ),
  );
  assert.match(
    commitRejection,
    /begin[\s\S]*consume_social_rate_limit\([\s\S]*exception\s+when sqlstate 'P0001' then[\s\S]*'allowed', false/,
  );
  for (const [domainAction, gatewayAction] of sharedGatewayActions) {
    assert.match(
      commitRejection,
      new RegExp(`\\('${domainAction}', '${gatewayAction}'\\)`),
    );
  }

  for (const [name, action] of laterRpcs) {
    const wrapper = functionBody(hardening, `public.${name}`);
    const reservation = wrapper.indexOf("social_begin_direct_request()");
    const worker = wrapper.indexOf(`gymapp_private.${name}_storage_`);
    assert.ok(reservation >= 0 && worker > reservation);
    assert.match(wrapper, /when sqlstate 'PT429' then/);
    assert.match(
      wrapper,
      /when sqlstate '22023' or sqlstate 'P0001' or sqlstate 'P0002' then/,
    );
    assert.equal(
      (wrapper.match(
        new RegExp(`social_commit_direct_rejection\\(\\s*'${action}'`, "g"),
      ) ?? []).length,
      2,
      `${name} must durably restore both rate-limit and domain rejections`,
    );
    assert.match(
      wrapper,
      /rejection_result ->> 'allowed' <> 'true'[\s\S]*social_rate_limit_response/,
    );
    assert.doesNotMatch(wrapper, /when\s+others/i);
  }

  assert.match(
    hardening,
    /revoke all on function gymapp_private\.social_commit_direct_rejection\(text\)\s+from public, anon, authenticated, service_role/,
  );
});

test("every remaining public social_require_caller route uses the durable direct dispatcher", async () => {
  const hardening = await readFile(deepHardeningPath, "utf8");
  const dispatcher = functionBody(
    hardening,
    "gymapp_private.social_execute_direct_worker",
  );
  const routes = [
    ["social_dashboard", "dashboard", ""],
    ["social_friend_details", "friend_details", "text"],
    ["social_send_friend_request", "send_friend", "text"],
    ["social_respond_friend_request", "respond_friend", "text, text, bigint"],
    ["social_cancel_friend_request", "cancel_friend", "text, bigint"],
    ["social_remove_friend", "remove_friend", "text, bigint"],
    ["social_block_profile", "block_profile", "text"],
    ["social_unblock_profile", "unblock_profile", "text"],
    [
      "social_update_privacy",
      "update_privacy",
      "boolean, boolean, boolean, boolean, bigint",
    ],
    ["social_send_workout_invite", "send_workout", "text, uuid, jsonb"],
    ["social_workout_inbox", "workout_inbox", ""],
    [
      "social_respond_workout_invite",
      "respond_workout",
      "text, text, bigint",
    ],
    ["social_cancel_workout_invite", "cancel_workout", "text, bigint"],
    ["social_workout_detail_privacy", "update_privacy", ""],
    ["social_workout_invite_plan", "workout_inbox", "text, bigint"],
  ];

  assert.ok(
    dispatcher.indexOf("social_begin_direct_request()") <
      dispatcher.indexOf("case p_worker"),
  );
  assert.match(dispatcher, /when sqlstate 'PT429' then/);
  assert.match(
    dispatcher,
    /when sqlstate '22023' or sqlstate 'P0001' or sqlstate 'P0002' then/,
  );
  assert.equal(
    (dispatcher.match(/social_commit_direct_rejection\(/g) ?? []).length,
    2,
  );
  assert.doesNotMatch(dispatcher, /when\s+others/i);

  for (const [name, action, signature] of routes) {
    assert.match(
      dispatcher,
      new RegExp(`\\('${name}', '${action}'\\)`),
    );
    assert.match(
      dispatcher,
      new RegExp(`${name}_direct_storage_v1\\(`),
    );
    const wrapper = functionBody(hardening, `public.${name}`);
    assert.match(
      wrapper,
      new RegExp(`social_execute_direct_worker\\(\\s*'${name}'`),
    );
    assert.doesNotMatch(wrapper, /social_require_caller\(/);
    const escapedSignature = signature.replaceAll(", ", ",\\s*");
    const renderedSignature = `\\(\\s*${escapedSignature}\\s*\\)`;
    assert.match(
      hardening,
      new RegExp(
        `revoke all on function public\\.${name}${renderedSignature}\\s+from public, anon, authenticated, service_role`,
      ),
    );
    assert.match(
      hardening,
      new RegExp(
        `grant execute on function public\\.${name}${renderedSignature}\\s+to authenticated`,
      ),
    );
  }

  assert.match(
    hardening,
    /revoke all on function gymapp_private\.social_execute_direct_worker\(text, jsonb\)\s+from public, anon, authenticated, service_role/,
  );
});

test("friend-code lookup preserves v1 while sharing aggregate and bounded read-action debits", async () => {
  const migration = await readFile(friendCodeBudgetPath, "utf8");
  const worker = functionBody(
    migration,
    "gymapp_private.social_my_friend_code_direct_worker",
  );
  const wrapper = functionBody(migration, "public.social_my_friend_code");

  assert.match(
    migration,
    /alter function public\.social_my_friend_code\(\)[\s\S]*set schema gymapp_private/,
  );
  assert.match(
    migration,
    /rename to social_my_friend_code_storage_v1/,
  );
  assert.ok(
    worker.indexOf("social_begin_direct_request()") <
      worker.indexOf("social_require_caller('friend_details')"),
  );
  assert.ok(
    worker.indexOf("social_require_caller('friend_details')") <
      worker.indexOf("social_my_friend_code_storage_v1()"),
  );
  assert.equal(
    (worker.match(/social_commit_direct_rejection\(\s*'friend_details'/g) ?? [])
      .length,
    2,
  );
  assert.match(worker, /when sqlstate 'PT429' then/);
  assert.match(
    worker,
    /when sqlstate '22023' or sqlstate 'P0001' or sqlstate 'P0002' then/,
  );
  assert.doesNotMatch(worker, /when\s+others/i);
  assert.match(wrapper, /social_my_friend_code_direct_worker\(\)/);
  assert.doesNotMatch(wrapper, /social_my_friend_code_storage_v1/);
  assert.match(
    migration,
    /revoke all on function gymapp_private\.social_my_friend_code_storage_v1\(\)[\s\S]*from public, anon, authenticated, service_role/,
  );
  assert.match(
    migration,
    /grant execute on function public\.social_my_friend_code\(\)[\s\S]*to authenticated/,
  );
});
