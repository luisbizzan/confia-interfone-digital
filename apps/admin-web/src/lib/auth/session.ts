import "server-only";

import { cookies } from "next/headers";
import { createHmac, timingSafeEqual } from "node:crypto";

export type BackofficeRole = "ADMIN" | "CONSULTOR";

export type BackofficeSession = {
  email: string;
  name: string;
  role: BackofficeRole;
  expiresAt: number;
};

export class BackofficeAuthError extends Error {
  status: 401 | 403;

  constructor(message: string, status: 401 | 403) {
    super(message);
    this.name = "BackofficeAuthError";
    this.status = status;
  }
}

type BackofficeUser = {
  email: string;
  password: string;
  name?: string;
  role: BackofficeRole;
};

export const sessionCookieName = "confia_backoffice_session";
const sessionDurationMs = 1000 * 60 * 60 * 10;

function sessionSecret() {
  const secret = process.env.BACKOFFICE_SESSION_SECRET ?? process.env.ADMIN_API_SECRET;

  if (!secret) {
    throw new Error("BACKOFFICE_SESSION_SECRET is not configured");
  }

  return secret;
}

function configuredUsers() {
  const raw = process.env.BACKOFFICE_USERS_JSON;

  if (!raw) {
    return [];
  }

  const users = JSON.parse(raw) as BackofficeUser[];
  return users.map((user) => ({
    ...user,
    email: user.email.toLowerCase().trim(),
  }));
}

function sign(payload: string) {
  return createHmac("sha256", sessionSecret()).update(payload).digest("base64url");
}

function encodeSession(session: BackofficeSession) {
  const payload = Buffer.from(JSON.stringify(session)).toString("base64url");
  return `${payload}.${sign(payload)}`;
}

function decodeSession(value?: string) {
  if (!value) return null;

  const [payload, signature] = value.split(".");
  if (!payload || !signature) return null;

  const expected = sign(payload);
  const providedBuffer = Buffer.from(signature);
  const expectedBuffer = Buffer.from(expected);

  if (providedBuffer.length !== expectedBuffer.length || !timingSafeEqual(providedBuffer, expectedBuffer)) {
    return null;
  }

  const session = JSON.parse(Buffer.from(payload, "base64url").toString("utf8")) as BackofficeSession;
  if (session.expiresAt < Date.now()) return null;

  return session;
}

export async function authenticateBackofficeUser(email: string, password: string) {
  const normalizedEmail = email.toLowerCase().trim();
  const user = configuredUsers().find((item) => item.email === normalizedEmail);

  if (!user || user.password !== password) {
    return null;
  }

  return {
    email: user.email,
    name: user.name ?? user.email,
    role: user.role,
    expiresAt: Date.now() + sessionDurationMs,
  } satisfies BackofficeSession;
}

export async function createBackofficeSession(session: BackofficeSession) {
  const cookieStore = await cookies();

  cookieStore.set(sessionCookieName, encodeSession(session), {
    httpOnly: true,
    sameSite: "lax",
    secure: process.env.NODE_ENV === "production",
    path: "/",
    maxAge: Math.floor(sessionDurationMs / 1000),
  });
}

export async function clearBackofficeSession() {
  const cookieStore = await cookies();
  cookieStore.delete(sessionCookieName);
}

export async function getBackofficeSession() {
  const cookieStore = await cookies();
  return decodeSession(cookieStore.get(sessionCookieName)?.value);
}

export async function requireBackofficeSession() {
  const session = await getBackofficeSession();

  if (!session) {
    throw new BackofficeAuthError("Sessão expirada ou ausente", 401);
  }

  return session;
}

export async function requireBackofficeRole(roles: BackofficeRole[]) {
  const session = await requireBackofficeSession();

  if (!roles.includes(session.role)) {
    throw new BackofficeAuthError("Acesso negado para este perfil", 403);
  }

  return session;
}
