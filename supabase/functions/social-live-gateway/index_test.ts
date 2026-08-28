import {
  parseGatewayRequest,
  ROUTES,
  serviceRoleFetch,
  verifiedSessionIdFromJwt,
} from "./index.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

function assertEquals(
  actual: unknown,
  expected: unknown,
  message: string,
): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `${message}: ${JSON.stringify(actual)} != ${JSON.stringify(expected)}`,
    );
  }
}

const context = {
  userId: "11111111-1111-4111-8111-111111111111",
  sessionId: "22222222-2222-4222-8222-222222222222",
};
const roomId = `lr_${"a".repeat(32)}`;
const operationId = "33333333-3333-4333-8333-333333333333";

Deno.test("live gateway routes map the public envelope to exact service-only RPC arguments", () => {
  const cases: Array<
    [string, Record<string, unknown>, string, Record<string, unknown>]
  > = [
    ["live_inbox", {}, "social_live_workout_inbox", {}],
    [
      "live_send_invite",
      {
        profileId: `p_${"b".repeat(32)}`,
        clientRequestId: operationId,
        workout: { version: 1 },
      },
      "social_send_live_workout_invite",
      {
        p_profile_id: `p_${"b".repeat(32)}`,
        p_client_request_id: operationId,
        p_workout: { version: 1 },
      },
    ],
    [
      "live_respond_invite",
      {
        roomId,
        decision: "accept",
        expectedRoomRevision: 2,
        clientOperationId: operationId,
      },
      "social_respond_live_workout_invite",
      {
        p_room_id: roomId,
        p_decision: "accept",
        p_expected_room_revision: 2,
        p_client_operation_id: operationId,
      },
    ],
    [
      "live_start",
      { roomId, expectedRoomRevision: 3, clientOperationId: operationId },
      "social_start_live_workout",
      {
        p_room_id: roomId,
        p_expected_room_revision: 3,
        p_client_operation_id: operationId,
      },
    ],
    ["live_snapshot", { roomId }, "social_live_workout_snapshot", {
      p_room_id: roomId,
    }],
    [
      "live_apply",
      {
        roomId,
        clientOperationId: operationId,
        expectedProgressRevision: 4,
        operation: { kind: "finish" },
      },
      "social_apply_live_workout_operation",
      {
        p_room_id: roomId,
        p_client_operation_id: operationId,
        p_expected_progress_revision: 4,
        p_operation: { kind: "finish" },
      },
    ],
    [
      "live_finish",
      { roomId, clientOperationId: operationId, expectedProgressRevision: 5 },
      "social_finish_live_workout",
      {
        p_room_id: roomId,
        p_client_operation_id: operationId,
        p_expected_progress_revision: 5,
      },
    ],
    [
      "live_leave",
      { roomId, clientOperationId: operationId, expectedMembershipRevision: 6 },
      "social_leave_live_workout",
      {
        p_room_id: roomId,
        p_client_operation_id: operationId,
        p_expected_membership_revision: 6,
      },
    ],
    [
      "live_cancel",
      { roomId, clientOperationId: operationId, expectedRoomRevision: 7 },
      "social_cancel_live_workout",
      {
        p_room_id: roomId,
        p_client_operation_id: operationId,
        p_expected_room_revision: 7,
      },
    ],
  ];
  for (const [action, payload, rpc, expected] of cases) {
    const route = ROUTES[action];
    assert(route.serviceOnly, `${action} must use the service-only client`);
    assertEquals(route.rpc, rpc, `${action} RPC`);
    assertEquals(route.args(payload, context), {
      p_caller_user_id: context.userId,
      p_session_id: context.sessionId,
      ...expected,
    }, `${action} args`);
  }
});

Deno.test("gateway envelope and payloads are exact-key allowlists", () => {
  assertEquals(
    parseGatewayRequest({ version: 1, action: "live_inbox", payload: {} }),
    {
      action: "live_inbox",
      payload: {},
    },
    "valid envelope",
  );
  for (
    const invalid of [
      { version: 1, action: "live_inbox", payload: {}, extra: true },
      { version: 2, action: "live_inbox", payload: {} },
      { version: 1, action: "unknown", payload: {} },
    ]
  ) {
    let rejected = false;
    try {
      parseGatewayRequest(invalid);
    } catch {
      rejected = true;
    }
    assert(rejected, "invalid envelope must be rejected");
  }
  let rejected = false;
  try {
    ROUTES.live_start.args(
      {
        roomId,
        expectedRoomRevision: 1,
        clientOperationId: operationId,
        extra: true,
      },
      context,
    );
  } catch {
    rejected = true;
  }
  assert(rejected, "extra payload keys must be rejected");
});

Deno.test("session id is read only from a structurally valid JWT payload after Auth verification", () => {
  const header = btoa(JSON.stringify({ alg: "none" })).replaceAll("=", "");
  const payload = btoa(JSON.stringify({ session_id: context.sessionId }))
    .replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
  assertEquals(
    verifiedSessionIdFromJwt(`${header}.${payload}.x`),
    context.sessionId,
    "session id",
  );
  assertEquals(
    verifiedSessionIdFromJwt(`${header}.e30.x`),
    null,
    "missing session id",
  );
  assertEquals(verifiedSessionIdFromJwt("not-a-jwt"), null, "malformed JWT");
});

Deno.test("service RPC transport treats sb_secret as apikey-only", async () => {
  const captures: Headers[] = [];
  const baseFetch: typeof fetch = (_input, init) => {
    const initHeaders = init && "headers" in init ? init.headers : undefined;
    captures.push(new Headers(initHeaders));
    return Promise.resolve(new Response("{}", { status: 200 }));
  };
  const modern = `sb_secret_${"a".repeat(48)}`;
  await serviceRoleFetch(modern, baseFetch)(
    "https://example.test/rest/v1/rpc/test",
    {
      headers: { Authorization: `Bearer ${modern}` },
    },
  );
  assert(
    captures.at(-1)?.get("apikey") === modern,
    "modern secret must stay in apikey",
  );
  assert(
    !captures.at(-1)?.has("Authorization"),
    "modern secret must not be sent as a JWT",
  );
});
