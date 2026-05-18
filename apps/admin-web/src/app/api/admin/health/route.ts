import { NextResponse } from "next/server";
import { AdminEdgeError } from "@/lib/admin-edge";
import { listAdminCondominiums } from "@/lib/admin/condominiums";
import { authErrorResponse } from "@/lib/auth/api";
import { requireBackofficeSession } from "@/lib/auth/session";

export async function GET() {
  try {
    await requireBackofficeSession();
  } catch (error) {
    const authResponse = authErrorResponse(error);
    if (authResponse) return authResponse;
  }

  const checks = {
    supabaseUrl: Boolean(process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL),
    adminSecret: Boolean(process.env.ADMIN_API_SECRET),
    publicAnonKey: Boolean(process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY),
    backofficeUsers: Boolean(process.env.BACKOFFICE_USERS_JSON),
    sessionSecret: Boolean(process.env.BACKOFFICE_SESSION_SECRET ?? process.env.ADMIN_API_SECRET),
  };

  try {
    const condominiums = await listAdminCondominiums();

    return NextResponse.json({
      ok: checks.supabaseUrl && checks.adminSecret && checks.backofficeUsers && checks.sessionSecret,
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
