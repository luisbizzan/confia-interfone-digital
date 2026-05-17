import { NextResponse } from "next/server";
import { AdminEdgeError } from "@/lib/admin-edge";
import { getAdminCondominium } from "@/lib/admin/condominiums";

type RouteContext = {
  params: Promise<{ id: string }>;
};

export async function GET(_request: Request, context: RouteContext) {
  try {
    const { id } = await context.params;
    const data = await getAdminCondominium(id);

    return NextResponse.json(data);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Failed to load condominium";
    const status = error instanceof AdminEdgeError ? error.status : 500;
    return NextResponse.json({ error: message }, { status });
  }
}
