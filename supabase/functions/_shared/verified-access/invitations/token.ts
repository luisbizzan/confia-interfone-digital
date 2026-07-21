export type OpaqueInvitationToken = Readonly<{ raw: string; hash: string }>;

export async function createOpaqueInvitationToken(): Promise<
  OpaqueInvitationToken
> {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  const raw = bytesToBase64Url(bytes);
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(raw),
  );
  const hash = Array.from(
    new Uint8Array(digest),
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
  return { raw, hash: `v1:${hash}` };
}

function bytesToBase64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(
    /=+$/,
    "",
  );
}
