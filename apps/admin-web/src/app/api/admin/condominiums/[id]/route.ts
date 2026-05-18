import { NextResponse } from "next/server";
import { AdminEdgeError } from "@/lib/admin-edge";
import { getAdminCondominium } from "@/lib/admin/condominiums";
import { authErrorResponse } from "@/lib/auth/api";
import { requireBackofficeSession } from "@/lib/auth/session";

type RouteContext = {
  params: Promise<{ id: string }>;
};

export async function GET(_request: Request, context: RouteContext) {
  try {
    await requireBackofficeSession();
    const { id } = await context.params;
    const data = await getAdminCondominium(id);

    return NextResponse.json(data);
  } catch (error) {
    const authResponse = authErrorResponse(error);
    if (authResponse) return authResponse;

    const message = error instanceof Error ? error.message : "Failed to load condominium";
    const status = error instanceof AdminEdgeError ? error.status : 500;
    return NextResponse.json({ error: message }, { status });
  }
}
