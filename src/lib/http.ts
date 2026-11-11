import "server-only";

/** An error that should reach the client with this status and message. */
export class HttpError extends Error {
  constructor(
    public readonly status: number,
    message: string,
  ) {
    super(message);
  }
}

/** Parse a JSON request body, or fail with 400 instead of a 500. */
export async function readJson(request: Request): Promise<Record<string, unknown>> {
  try {
    const body: unknown = await request.json();
    if (body && typeof body === "object" && !Array.isArray(body)) {
      return body as Record<string, unknown>;
    }
  } catch {
    // fall through
  }
  throw new HttpError(400, "Request body must be a JSON object");
}

/**
 * Turn any error into a JSON response. HttpErrors keep their status and
 * message; everything else becomes a generic 500, so SQL, stack traces
 * and secrets never reach the client (they are logged on the server).
 */
export function errorResponse(err: unknown): Response {
  if (err instanceof HttpError) {
    return Response.json({ error: err.message }, { status: err.status });
  }
  console.error("Unhandled API error:", err);
  return Response.json({ error: "Internal server error" }, { status: 500 });
}
