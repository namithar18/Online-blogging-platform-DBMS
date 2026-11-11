import "server-only";
import type { PoolClient } from "pg";
import { getDbPool } from "@/lib/db";

/**
 * Run fn inside BEGIN ... COMMIT on ONE pooled connection; any error
 * means ROLLBACK, so either every statement takes effect or none does.
 *
 * fn must send all its statements through the client it is given: a
 * plain pool.query() could run on a different connection, outside this
 * transaction.
 */
export async function withTransaction<T>(fn: (client: PoolClient) => Promise<T>): Promise<T> {
  const client = await getDbPool().connect();
  let connectionBroken = false;
  try {
    await client.query("BEGIN");
    const result = await fn(client);
    await client.query("COMMIT");
    return result;
  } catch (err) {
    try {
      await client.query("ROLLBACK");
    } catch {
      connectionBroken = true;
    }
    throw err;
  } finally {
    // release(true) closes a broken connection instead of returning it
    // to the pool for the next request.
    client.release(connectionBroken);
  }
}
