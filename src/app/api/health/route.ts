
import { getDbPool } from "@/lib/db";

export const runtime = "nodejs";

export async function GET(): Promise<Response> {
  try {
    await getDbPool().query("SELECT 1");
    return Response.json(
      { status: "ok" },
      { status: 200, headers: { "Cache-Control": "no-store" } }
    );
  } catch (err) {
    console.error("Health-check DB error:", err);
    return Response.json(
      { status: "error" },
      { status: 503, headers: { "Cache-Control": "no-store" } }
    );
  }
}
