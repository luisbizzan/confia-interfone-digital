import { NextResponse } from "next/server";
import { getBackofficeSession } from "@/lib/auth/session";

export async function GET() {
  const session = await getBackofficeSession();

  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  return NextResponse.json({
    email: session.email,
    name: session.name,
    role: session.role,
  });
}
