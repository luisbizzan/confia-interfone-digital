import { NextResponse } from "next/server";
import { AdminEdgeError } from "@/lib/admin-edge";
import { listAdminCondominiums } from "@/lib/admin/condominiums";
import { authErrorResponse } from "@/lib/auth/api";
import { requireBackofficeSession } from "@/lib/auth/session";

export async function GET() {
  try {
    await requireBackofficeSession();
    const data = await listAdminCondominiums();
    return NextResponse.json(data);
  } catch (error) {
    const authResponse = authErrorResponse(error);
    if (authResponse) return authResponse;

    const message = error instanceof Error ? error.message : "Failed to load condominiums";
    const status = error instanceof AdminEdgeError ? error.status : 500;
    return NextResponse.json({ error: message }, { status });
  }
}
