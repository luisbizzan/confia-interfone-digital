import {
  providerFailure,
  type ProviderResult,
  providerSuccess,
} from "../result.ts";

Deno.test("ProviderResult is discriminated by ok", () => {
  const success: ProviderResult<number> = providerSuccess(42);
  const failure: ProviderResult<number> = providerFailure({
    code: "TIMEOUT",
    retryable: true,
    correlationId: "correlation-result",
  });

  assert(success.ok);
  assertEquals(success.value, 42);
  assert(!failure.ok);
  assertEquals(failure.error.code, "TIMEOUT");
});

Deno.test("expected provider failures are returned and never thrown", async () => {
  let thrown = false;
  let result: ProviderResult<never> | undefined;
  try {
    result = await Promise.resolve(providerFailure({
      code: "UNAVAILABLE",
      retryable: true,
      correlationId: "correlation-no-throw",
    }));
  } catch {
    thrown = true;
  }

  assert(!thrown);
  assert(result !== undefined && !result.ok);
  assertEquals(result.error.code, "UNAVAILABLE");
});

function assert(
  condition: unknown,
  message = "Assertion failed",
): asserts condition {
  if (!condition) throw new Error(message);
}

function assertEquals<T>(actual: T, expected: T): void {
  if (!Object.is(actual, expected)) {
    throw new Error(`Expected ${String(expected)}, received ${String(actual)}`);
  }
}
