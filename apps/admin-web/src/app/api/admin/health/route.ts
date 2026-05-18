import { NextResponse } from "next/server";
import { AdminEdgeError } from "@/lib/admin-edge";
import { listAdminCondominiums } from "@/lib/admin/condominiums";

export async function GET() {
  const checks = {
    supabaseUrl: Boolean(process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL),
    adminSecret: Boolean(process.env.ADMIN_API_SECRET),
    publicAnonKey: Boolean(process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY),
  };

  try {
    const condominiums = await listAdminCondominiums();

    return NextResponse.json({
      ok: checks.supabaseUrl && checks.adminSecret,
      checks,
      condominiums_count: condominiums.length,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Health check failed";
    const status = error instanceof AdminEdgeError ? error.status : 500;

    return NextResponse.json(
      {
        ok: false,
        checks,
        error: message,
      },
      { status },
    );
  }
}
