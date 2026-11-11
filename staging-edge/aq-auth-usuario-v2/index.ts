import { createClient } from "npm:@supabase/supabase-js@2.58.0";

// Puente de ingreso AQUABRI: la interfaz sigue solicitando usuario y contraseña.
// El correo real vinculado a Auth nunca se entrega ni se consulta desde el navegador.
const allowedOrigins = new Set([
  "https://odeleonruiz.github.io",
  "http://127.0.0.1:8765",
  "http://localhost:8765",
  "https://aquabri-staging-preview.vercel.app",
]);
const respond = (status: number, data: Record<string, unknown>, origin: string) =>
  new Response(JSON.stringify(data), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      "vary": "Origin",
      ...(allowedOrigins.has(origin) ? { "access-control-allow-origin": origin } : {}),
    },
  });

async function hmacHex(pepper: string, subject: string) {
  const key = await crypto.subtle.importKey(
    "raw", new TextEncoder().encode(pepper),
    { name: "HMAC", hash: "SHA-256" }, false, ["sign"],
  );
  const hash = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(subject));
  return Array.from(new Uint8Array(hash), x => x.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (request: Request) => {
  const origin = request.headers.get("origin") || "";
  if (!allowedOrigins.has(origin)) return respond(403, { error: "Origen no autorizado" }, origin);
  if (request.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: {
        "access-control-allow-origin": origin,
        "access-control-allow-methods": "POST, OPTIONS",
        "access-control-allow-headers": "content-type, apikey, authorization",
        "access-control-max-age": "600",
        "vary": "Origin",
      },
    });
  }
  if (request.method !== "POST") return respond(405, { error: "Método no permitido" }, origin);
  const invalid = () => respond(401, { error: "Usuario o contraseña incorrectos" }, origin);
  try {
    const url = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    if (!url || !serviceKey || !anonKey) return respond(503, { error: "Servicio de acceso no configurado" }, origin);
    const contentLength = Number(request.headers.get("content-length") || "0");
    if (contentLength > 4096) return respond(413, { error: "Solicitud demasiado grande" }, origin);
    const body = await request.json().catch(() => null);
    const username = typeof body?.usuario === "string" ? body.usuario.trim() : "";
    const password = typeof body?.contrasena === "string" ? body.contrasena : "";
    if (!username || username.length > 100 || !password || password.length > 256) return invalid();

    const admin = createClient(url, serviceKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    // Para evitar enumeración y ataques de contraseñas: límite por cuenta + ventana,
    // incluso si se consulta un usuario inexistente. Nunca guardar IP o clave en claro.
    const cuenta = await hmacHex(serviceKey, "cuenta:" + username.toLowerCase());
    const { data: allowed, error: limitError } = await admin.rpc("aq_auth_login_admitir_intento", { p_clave: cuenta });
    if (limitError) return respond(503, { error: "Verificación temporalmente no disponible" }, origin);
    if (allowed !== true) return respond(429, { error: "Demasiados intentos. Vuelve a intentarlo más tarde" }, origin);

    const { data: record, error: userError } = await admin
      .from("usuarios").select("auth_uid").eq("usuario", username).maybeSingle();
    if (userError || !record?.auth_uid) return invalid();

    const { data: identity, error: authError } = await admin.auth.admin.getUserById(record.auth_uid);
    // Nuevas cuentas AQUABRI: teléfono +502 verificado mediante SMS al activarlas.
    // El SMS NO se solicita en el inicio de sesión cotidiano.
    // Se conserva el correo verificado como respaldo para identidades anteriores de staging.
    const phone = identity?.user?.phone || "";
    const phoneVerified = Boolean(identity?.user?.phone_confirmed_at) && /^\+?502\d{8}$/.test(phone);
    const email = identity?.user?.email || "";
    const emailVerified = Boolean(identity?.user?.email_confirmed_at);
    if (authError || !identity?.user || (!phoneVerified && !emailVerified)) return invalid();

    const publicAuth = createClient(url, anonKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const credentials = phoneVerified ? { phone: phone.startsWith("+") ? phone : "+" + phone, password } : { email, password };
    const { data: result, error: loginError } = await publicAuth.auth.signInWithPassword(credentials);
    if (loginError || result.user?.id !== record.auth_uid || !result.session) return invalid();

    return respond(200, {
      access_token: result.session.access_token,
      refresh_token: result.session.refresh_token,
      token_type: "bearer",
      expires_in: result.session.expires_in,
    }, origin);
  } catch {
    return respond(503, { error: "No se pudo verificar el acceso. Intenta nuevamente" }, origin);
  }
});
