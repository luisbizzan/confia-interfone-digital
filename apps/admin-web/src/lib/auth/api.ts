import { NextResponse } from "next/server";

export function authErrorResponse(error: unknown) {
  const message = error instanceof Error ? error.message : "Unauthorized";

  if (message === "Forbidden") {
    return NextResponse.json({ error: "Acesso negado para este perfil" }, { status: 403 });
  }

  if (message === "Unauthorized") {
    return NextResponse.json({ error: "Sessão expirada ou ausente" }, { status: 401 });
  }

  return null;
}
