import { NextResponse } from "next/server";
import { listAdminCondominiums } from "@/lib/admin/condominiums";

export async function GET() {
  try {
    const data = await listAdminCondominiums();
    return NextResponse.json(data);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Failed to load condominiums";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
