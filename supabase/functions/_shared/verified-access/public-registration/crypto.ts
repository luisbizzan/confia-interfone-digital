import { HttpError } from "./http.ts";

const encoder = new TextEncoder();

export type ProtectedValue = `\\x${string}`;

export function randomOpaqueToken(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return base64Url(bytes);
}

export async function sha256Fingerprint(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", encoder.encode(value));
  return `v1:${hex(new Uint8Array(digest))}`;
}

export async function keyedFingerprint(
  keyBase64: string,
  purpose: string,
  value: string,
): Promise<string> {
  const key = await importHmacKey(keyBase64);
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    encoder.encode(`${purpose}\u0000${value}`),
  );
  return `v1:${hex(new Uint8Array(signature))}`;
}

export async function encryptValue(
  keyBase64: string,
  tenantScope: string,
  field: string,
  value: string,
): Promise<ProtectedValue> {
  const raw = decodeKey(keyBase64);
  const key = await crypto.subtle.importKey("raw", raw, "AES-GCM", false, [
    "encrypt",
  ]);
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ciphertext = await crypto.subtle.encrypt(
    {
      name: "AES-GCM",
      iv,
      additionalData: encoder.encode(`${tenantScope}\u0000${field}`),
    },
    key,
    encoder.encode(value),
  );
  const envelope = new Uint8Array(iv.byteLength + ciphertext.byteLength);
  envelope.set(iv, 0);
  envelope.set(new Uint8Array(ciphertext), iv.byteLength);
  return `\\x${hex(envelope)}`;
}

export function requiredKey(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new HttpError(500, "INTERNAL_ERROR");
  decodeKey(value);
  return value;
}

function importHmacKey(value: string): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    "raw",
    decodeKey(value),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

function decodeKey(value: string): Uint8Array<ArrayBuffer> {
  let binary: string;
  try {
    binary = atob(value.replaceAll("-", "+").replaceAll("_", "/"));
  } catch {
    throw new HttpError(500, "INTERNAL_ERROR");
  }
  const bytes = new Uint8Array(new ArrayBuffer(binary.length));
  for (let index = 0; index < binary.length; index++) {
    bytes[index] = binary.charCodeAt(index);
  }
  if (bytes.byteLength !== 32) throw new HttpError(500, "INTERNAL_ERROR");
  return bytes;
}

function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(
    /=+$/,
    "",
  );
}

function hex(bytes: Uint8Array): string {
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join(
    "",
  );
}
