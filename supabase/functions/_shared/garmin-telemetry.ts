type TelemetryRpcResult = {
  error?: { code?: unknown } | null;
};

type TelemetryWarning = (
  message: string,
  details: { code: string },
) => void;

type TelemetryScheduler = (task: Promise<void>) => void;

function safeWarning(warn: TelemetryWarning, code: string): void {
  try {
    warn("Garmin capability telemetry failed", { code });
  } catch {
    // Diagnostics must never change the authenticated fetch/ack result.
  }
}

function boundedErrorCode(value: unknown): string {
  if (typeof value !== "string" || !/^[A-Za-z0-9_]{1,32}$/.test(value)) {
    return "unknown";
  }
  return value;
}

/**
 * Resolve a telemetry attempt without ever rejecting. Callers must invoke this
 * only after their authorization/state RPC; the scheduler controls lifetime.
 */
export async function recordBestEffortGarminTelemetry(
  operation: () => PromiseLike<TelemetryRpcResult>,
  warn: TelemetryWarning = console.warn,
): Promise<void> {
  try {
    const result = await operation();
    if (!result.error || result.error.code === "PGRST202") return;
    safeWarning(warn, boundedErrorCode(result.error.code));
  } catch {
    safeWarning(warn, "transport_error");
  }
}

/** Schedule telemetry without putting its network latency on the response. */
export function scheduleBestEffortGarminTelemetry(
  operation: () => PromiseLike<TelemetryRpcResult>,
  schedule: TelemetryScheduler,
  warn: TelemetryWarning = console.warn,
): void {
  const task = recordBestEffortGarminTelemetry(operation, warn);
  try {
    schedule(task);
  } catch {
    // The task itself catches all outcomes. A missing/broken scheduler must not
    // turn an already-authorized fetch or committed acknowledgement into 500.
  }
}
