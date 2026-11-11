import "server-only";
import bcrypt from "bcryptjs";

// C8: only a salted bcrypt hash is stored in users.password_hash.
// Cost 10 = 2^10 hashing rounds: slow enough to make guessing expensive,
// fast enough (~50-100 ms) for a login request.
const BCRYPT_COST = 10;

// bcrypt only uses the first 72 bytes of a password; anything longer
// would be silently ignored, so the API rejects it instead.
export const PASSWORD_MIN_LENGTH = 8;
export const PASSWORD_MAX_BYTES = 72;

/** Hash a plain-text password. The salt is generated and stored inside the hash. */
export function hashPassword(plain: string): Promise<string> {
  return bcrypt.hash(plain, BCRYPT_COST);
}

/** Compare a plain-text password with a stored hash. Never throws. */
export async function verifyPassword(plain: string, hash: string): Promise<boolean> {
  try {
    return await bcrypt.compare(plain, hash);
  } catch {
    // A malformed hash (e.g. a placeholder) simply does not match.
    return false;
  }
}

// Used when the email does not exist: comparing against a real hash takes
// the same time as a wrong password, so response time does not reveal
// which emails are registered.
export const DUMMY_HASH = bcrypt.hashSync("dummy-password-for-timing", BCRYPT_COST);
