import { NextResponse } from "next/server";
import { AdminEdgeError } from "@/lib/admin-edge";
import { createAdminUnitMember } from "@/lib/admin/condominiums";

export async function POST(request: Request) {
  try {
    const body = await request.json();
    const data = await createAdminUnitMember(body);

    return NextResponse.json(data, { status: 201 });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Failed to create unit member";
    const status = error instanceof AdminEdgeError ? error.status : 500;
    return NextResponse.json({ error: message }, { status });
  }
}
