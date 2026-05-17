import { NextResponse } from "next/server";
import { AdminEdgeError } from "@/lib/admin-edge";
import { createAdminCondominium } from "@/lib/admin/condominiums";

export async function POST(request: Request) {
  try {
    const body = await request.json();
    const data = await createAdminCondominium(body);

    return NextResponse.json(data, { status: 201 });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Failed to create condominium";
    const status = error instanceof AdminEdgeError ? error.status : 500;
    return NextResponse.json({ error: message }, { status });
  }
}
