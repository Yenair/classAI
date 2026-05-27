import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { verify } from "https://deno.land/x/djwt@v2.8/mod.ts";

/** Convert a plain string secret into a CryptoKey for HS256 JWT verification. */
export function getHmacKey(secret: string): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["verify"],
  );
}

/**
 * Validates a JWT and checks that the token_version in the JWT matches
 * the teacher's current token_version in the database.
 *
 * @returns The verified JWT claims (including teacher_id, school_id, etc.)
 * @throws An object with { error, code, status } properties if validation fails.
 */
export async function validateTokenVersion(
  token: string,
  supabaseUrl: string,
  serviceRoleKey: string,
  jwtSecret: string,
): Promise<Record<string, unknown>> {
  const cryptoKey = await getHmacKey(jwtSecret);
  let claims: Record<string, unknown>;
  try {
    claims = await verify(token, cryptoKey, "HS256");
  } catch {
    throw { error: "Invalid or expired JWT", code: "invalid_jwt", status: 401 };
  }

  const teacherId = claims.teacher_id as string;
  if (!teacherId) {
    throw { error: "Invalid token: no teacher_id claim", code: "invalid_jwt", status: 401 };
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey);

  const { data: teacher, error: teacherError } = await supabase
    .from("teachers")
    .select("id, token_version")
    .eq("id", teacherId)
    .maybeSingle();

  if (teacherError || !teacher) {
    throw { error: "Teacher not found", code: "teacher_not_found", status: 404 };
  }

  const jwtTokenVersion = (claims.token_version as number) ?? 0;
  const dbTokenVersion = (teacher.token_version as number) ?? 1;

  if (jwtTokenVersion !== dbTokenVersion) {
    throw {
      error: "Session expired",
      code: "token_version_mismatch",
      status: 401,
    };
  }

  return claims;
}
