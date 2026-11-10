import "server-only";
import { Pool } from "pg";

declare global {
  var __pgPool: Pool | undefined;
}

/** Lazy getter for a shared PostgreSQL connection pool. */
export function getDbPool(): Pool {
  if (!globalThis.__pgPool) {
    const connectionString = process.env.DATABASE_URL;
    if (!connectionString) {
      throw new Error("DATABASE_URL is not set in the environment");
    }

    const pool = new Pool({
      connectionString,
      max: 10,
      idleTimeoutMillis: 30_000,
      connectionTimeoutMillis: 2_000,
    });

    pool.on("error", (err) => {
      console.error("PostgreSQL idle client error:", err);
    });

    globalThis.__pgPool = pool;
  }
  return globalThis.__pgPool;
}
