import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const activationPath =
  "supabase/migrations/20260809202432_activate_friend_social_api.sql";
const durableDebitPath =
  "supabase/migrations/20260810003804_persist_social_rate_debits_on_domain_errors.sql";

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
  const start = sql.indexOf(`create or replace function ${qualifiedName}(`);
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
  assert.ok(debitIndex >= 0, `${action} must debit through social_require_caller`);

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
        `revoke all on function public\\.${name}\\(${escapedSignature}\\)\\s+from public, anon, authenticated, service_role`,
      ),
    );
    assert.match(
      durableDebit,
      new RegExp(
        `grant execute on function public\\.${name}\\(${escapedSignature}\\)\\s+to authenticated`,
      ),
    );
  }
});
