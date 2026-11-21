import { createClient } from 'npm:@supabase/supabase-js@2';

const origenes = new Set(['https://odeleonruiz.github.io','https://localhost','http://localhost','capacitor://localhost']);
Deno.serve(async (req) => {
  const origin = req.headers.get('Origin');
  if (origin && !origenes.has(origin)) return new Response(null, { status: 403 });
  const cors = {
    'Access-Control-Allow-Origin': origin || 'https://odeleonruiz.github.io',
    'Access-Control-Allow-Headers': 'content-type, apikey, authorization, x-client-info',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Vary': 'Origin'
  };
  function reply(body: unknown, status = 200) {
    return new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });
  }
  if (req.method === 'OPTIONS') return new Response(null, { headers: cors });
  if (req.method !== 'POST') return reply({ error: 'Método no permitido' }, 405);
  try {
    const match = /^Bearer (\S+)$/i.exec(req.headers.get('Authorization') || '');
    if (!match) return reply({ error: 'Inicia sesión' }, 401);
    const url = Deno.env.get('SUPABASE_URL');
    const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!url || !key) return reply({ error: 'Configuración incompleta' }, 500);
    const admin = createClient(url, key, { auth: { persistSession: false } });
    const { data: { user }, error: authError } = await admin.auth.getUser(match[1]);
    if (authError || !user || user.is_anonymous) return reply({ error: 'Sesión inválida o vencida' }, 401);
    const { data: usuario } = await admin.from('usuarios').select('rol').eq('auth_uid', user.id).maybeSingle();
    if (!usuario || !['jefe', 'inventario'].includes(usuario.rol)) return reply({ error: 'Sin permiso para editar fotografías' }, 403);
    const { producto_id, accion, imagen } = await req.json();
    if (!Number.isSafeInteger(producto_id) || producto_id <= 0) return reply({ error: 'Producto inválido' }, 400);
    const { data: producto } = await admin.from('productos').select('id').eq('id', Number(producto_id)).maybeSingle();
    if (!producto) return reply({ error: 'Producto no encontrado' }, 404);
    const path = `producto-${Number(producto_id)}.webp`;
    if (accion === 'eliminar') {
      const { error } = await admin.storage.from('productos-imagenes').remove([path]);
      if (error) throw error;
    } else if (accion === 'subir') {
      if (typeof imagen !== 'string' || imagen.length > 2_000_000 || !/^[A-Za-z0-9+/]+={0,2}$/.test(imagen)) return reply({ error: 'Imagen inválida o demasiado grande' }, 400);
      const bytes = Uint8Array.from(atob(imagen), c => c.charCodeAt(0));
      if (bytes.length > 1_500_000 || bytes.length < 16 || bytes[0] !== 0x52 || bytes[1] !== 0x49 || bytes[2] !== 0x46 || bytes[3] !== 0x46 || bytes[8] !== 0x57 || bytes[9] !== 0x45 || bytes[10] !== 0x42 || bytes[11] !== 0x50) return reply({ error: 'Se requiere imagen WebP válida (máx. 1.5 MB)' }, 400);
      const { data: bucket, error: bucketError } = await admin.storage.getBucket('productos-imagenes');
      if (!bucket && (String(bucketError?.statusCode) === '404' || bucketError?.message === 'Bucket not found')) {
        const { error: createError } = await admin.storage.createBucket('productos-imagenes', {
          public: true, allowedMimeTypes: ['image/webp'], fileSizeLimit: 1500000
        });
        if (createError && !(await admin.storage.getBucket('productos-imagenes')).data) throw createError;
      } else if (bucketError) throw bucketError;
      const { error } = await admin.storage.from('productos-imagenes').upload(path, bytes, { contentType: 'image/webp', upsert: true, cacheControl: '60' });
      if (error) throw error;
    } else return reply({ error: 'Acción inválida' }, 400);
    return reply({ ok: true });
  } catch (e) {
    console.error(e);
    return reply({ error: 'No se pudo guardar la imagen' }, 500);
  }
});
