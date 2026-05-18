import { NextResponse } from "next/server";
import { authenticateBackofficeUser, createBackofficeSession } from "@/lib/auth/session";

export async function POST(request: Request) {
  let body: { email?: string; password?: string };

  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "JSON inválido" }, { status: 400 });
  }

  const session = await authenticateBackofficeUser(body.email ?? "", body.password ?? "");

  if (!session) {
    return NextResponse.json({ error: "Email ou senha inválidos" }, { status: 401 });
  }

  await createBackofficeSession(session);

  return NextResponse.json({
    user: {
      email: session.email,
      name: session.name,
      role: session.role,
    },
  });
}
