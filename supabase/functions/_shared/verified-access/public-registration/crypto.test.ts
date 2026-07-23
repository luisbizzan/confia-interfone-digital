import {
  encryptValue,
  keyedFingerprint,
  randomOpaqueToken,
  sha256Fingerprint,
} from "./crypto.ts";

const KEY = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";

Deno.test("creates opaque 256-bit URL-safe tokens and versioned hashes", async () => {
  const token = randomOpaqueToken();
  match(token, /^[A-Za-z0-9_-]{43}$/);
  match(await sha256Fingerprint(token), /^v1:[0-9a-f]{64}$/);
});

Deno.test("separates HMAC purposes and tenant-bound AES-GCM ciphertext", async () => {
  const first = await keyedFingerprint(KEY, "tenant-a:CPF", "52998224725");
  const second = await keyedFingerprint(KEY, "tenant-b:CPF", "52998224725");
  match(first, /^v1:[0-9a-f]{64}$/);
  if (first === second) throw new Error("tenant contexts must not collide");
  const encrypted = await encryptValue(
    KEY,
    "tenant-a",
    "full_name",
    "Maria Teste",
  );
  match(encrypted, /^\\x[0-9a-f]+$/);
  if (encrypted.includes("Maria")) throw new Error("plaintext leaked");
});

function match(value: string, pattern: RegExp) {
  if (!pattern.test(value)) {
    throw new Error(`${value} does not match ${pattern}`);
  }
}
