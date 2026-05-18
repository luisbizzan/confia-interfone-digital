import { NextResponse } from "next/server";
import { clearBackofficeSession } from "@/lib/auth/session";

export async function POST() {
  await clearBackofficeSession();
  return NextResponse.json({ ok: true });
}
