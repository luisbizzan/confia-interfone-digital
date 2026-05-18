import { NextResponse } from "next/server";
import { BackofficeAuthError } from "@/lib/auth/session";

export function authErrorResponse(error: unknown) {
  if (error instanceof BackofficeAuthError) {
    return NextResponse.json({ error: error.message }, { status: error.status });
  }

  return null;
}
