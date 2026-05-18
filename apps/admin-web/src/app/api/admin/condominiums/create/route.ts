import { NextResponse } from "next/server";
import { AdminEdgeError } from "@/lib/admin-edge";
import { createAdminCondominium } from "@/lib/admin/condominiums";
import { authErrorResponse } from "@/lib/auth/api";
import { requireBackofficeRole } from "@/lib/auth/session";

export async function POST(request: Request) {
  try {
    await requireBackofficeRole(["ADMIN", "CONSULTOR"]);
    const body = await request.json();
    const data = await createAdminCondominium(body);

    return NextResponse.json(data, { status: 201 });
  } catch (error) {
    const authResponse = authErrorResponse(error);
    if (authResponse) return authResponse;

    const message = error instanceof Error ? error.message : "Failed to create condominium";
    const status = error instanceof AdminEdgeError ? error.status : 500;
    return NextResponse.json({ error: message }, { status });
  }
}
