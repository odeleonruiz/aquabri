/* AQUABRI · Resumen por cliente de incentivos (solo lectura, sin alterar pagos).
   Contabiliza el libro aq_incentivos_devengados, NO las autorizaciones históricas:
   una autorización finalizada no implica un segundo devengo. */
(function () {
  'use strict';
  if (typeof window.aqIncPintar !== 'function') return;
  const pintarAnterior = window.aqIncPintar;
  let datos = null, rangoCargado = '', solicitud = 0, errorActual = '';
  const $ = id => document.getElementById(id);
  const esc = t => typeof aqIncHtml === 'function' ? aqIncHtml(t) : String(t || '');
  const moneda = centavos => typeof aqIncFmt === 'function' ? aqIncFmt(centavos / 100) : 'Q' + (centavos / 100).toFixed(2);
  const cent = n => Math.round(Number(n || 0) * 100);
  const nombreCli = id => typeof aqIncNombreCli === 'function' ? aqIncNombreCli(id) : 'Cliente #' + id;
  const nombreEmp = id => typeof aqIncNombreEmp === 'function' ? aqIncNombreEmp(id) : 'Empleado #' + id;
  const fechaActual = () => typeof hoy === 'function' ? hoy() : new Date().toISOString().slice(0, 10);
  const primerDiaMes = () => fechaActual().slice(0, 7) + '-01';
  // No hay incentivos del año 2000; consultar desde la primera autorización real.
  const primeraAutorizacion = () => {
    const fechas = (aqIncCache.incentivos || []).map(i => String(i.desde || '')).filter(f => /^\d{4}-\d{2}-\d{2}$/.test(f) && f <= fechaActual()).sort();
    return fechas[0] || primerDiaMes();
  };
  const periodo = () => ({
    desde: $('aq-inc-cli-desde')?.value || primeraAutorizacion(),
    hasta: $('aq-inc-cli-hasta')?.value || fechaActual()
  });

  function ponerEstilos() {
    if ($('aq-inc-cli-css')) return;
    const style = document.createElement('style');
    style.id = 'aq-inc-cli-css';
    style.textContent = '.aq-inc-cli-panel{padding:12px;border:1px solid var(--borde,#bccbd3);border-radius:12px;margin:12px 0;background:var(--fondo,#f6fbff);font-size:12px;color:var(--texto,#16334c)}' +
      '.aq-inc-cli-controles{display:flex;align-items:end;gap:9px;flex-wrap:wrap;margin-top:10px}' +
      '.aq-inc-cli-controles label{display:flex;flex-direction:column;gap:4px;min-width:125px;font-size:11px;font-weight:600}' +
      '.aq-inc-cli-controles input,.aq-inc-cli-controles select{padding:9px 10px;border:1px solid var(--borde,#b7c8d5);border-radius:8px;color:inherit;background:var(--fondo,#fff);min-height:37px;font-size:12px}' +
      '.aq-inc-cli-controles input[type=search]{width:220px;max-width:100%}' +
      '.aq-inc-cli-ayuda{font-size:11px;color:var(--gris,#536a7e);line-height:1.6;margin:7px 0 0}' +
      '.aq-inc-cli-totales{display:flex;gap:13px;flex-wrap:wrap;margin:12px 0 5px;font-size:11px}' +
      '.aq-inc-cli-totales b{font-size:13px}' +
      '.aq-inc-cli-fila{padding:12px 6px;border-bottom:1px solid var(--borde,#ccd6dc);color:var(--texto,#15344d)}' +
      '.aq-inc-cli-cabecera{display:flex;align-items:start;justify-content:space-between;gap:10px;flex-wrap:wrap}' +
      '.aq-inc-cli-fila strong{font-size:13px}' +
      '.aq-inc-cli-numeros{display:flex;gap:13px;flex-wrap:wrap;margin:8px 0 4px;font-size:11px}' +
      '.aq-inc-cli-numeros span{display:inline-flex;flex-direction:column;gap:3px}' +
      '.aq-inc-cli-numeros b{font-size:13px}' +
      '.aq-inc-cli-estado{font-size:10px;font-weight:700;white-space:nowrap}' +
      '.aq-inc-cli-cabecera small{display:block;color:var(--gris,#536a7e);margin-top:3px;line-height:1.5}' +
      '.aq-inc-cli-detalle{margin:8px 0 0;font-size:11px}' +
      '.aq-inc-cli-detalle summary{cursor:pointer;font-weight:700;padding:5px 0}' +
      '.aq-inc-cli-detalle th,.aq-inc-cli-detalle td{white-space:nowrap;padding:7px 9px;text-align:left}' +
      '.aq-inc-cli-config{margin-top:6px;padding:7px;border-left:3px solid var(--borde,#96b6c6);font-size:11px}' +
      'html[data-aq-theme="dark"] .aq-inc-cli-panel,html[data-aq-theme="dark"] .aq-inc-cli-controles input,html[data-aq-theme="dark"] .aq-inc-cli-controles select{background:#1e344b!important;color:#e3f3ff!important;border-color:#42617f!important}' +
      'html[data-aq-theme="dark"] .aq-inc-cli-fila{color:#e3f3ff;border-color:#42617f}' +
      'html[data-aq-theme="dark"] .aq-inc-cli-cabecera small,html[data-aq-theme="dark"] .aq-inc-cli-ayuda{color:#b7cfe1}' +
      '.aq-inc-cli-grupo{border:1px solid var(--borde,#b5c6d6);border-radius:10px;margin:12px 0;overflow:hidden}' +
      '.aq-inc-cli-grupo>summary{list-style:auto;cursor:pointer;padding:14px 16px;background:var(--fondo,#eef6fd);font-weight:700;font-size:13px;color:var(--texto,#16344e)}' +
      '.aq-inc-cli-grupo>summary small{font-weight:400;font-size:11px;color:var(--gris,#586f82)}' +
      '.aq-inc-cli-grupo-interior{padding:5px 13px}' +
      'html[data-aq-theme="dark"] .aq-inc-cli-grupo>summary{background:#1e344b;color:#e3f3ff}' +
      '@media(max-width:720px){.aq-inc-cli-controles label{min-width:110px}.aq-inc-cli-controles input[type=search]{width:100%}.aq-inc-cli-fila{padding:12px 3px}}';
    document.head.appendChild(style);
  }

  function prepararVista() {
    const lista = $('aq-inc-lista');
    if (!lista) return;
    ponerEstilos();
    if ($('aq-inc-cli-panel')) return;
    const barra = document.createElement('div');
    barra.id = 'aq-inc-cli-panel';
    barra.className = 'aq-inc-cli-panel';
    barra.innerHTML = '<b>Clientes con incentivo — resumen sin duplicados</b>' +
      '<div class="aq-inc-cli-controles">' +
      '<label>Desde<input id="aq-inc-cli-desde" type="date"></label>' +
      '<label>Hasta<input id="aq-inc-cli-hasta" type="date"></label>' +
      '<label>Buscar cliente<input id="aq-inc-cli-buscar" type="search" placeholder="Nombre del cliente"></label>' +
      '<label>Estado<select id="aq-inc-cli-estado"><option value="todos">Todos</option><option value="activo">Con incentivo activo</option><option value="cerrado">Solo finalizados</option></select></label>' +
      '<button type="button" class="btn bp bsm" id="aq-inc-cli-actualizar">↻ Consultar ventas</button>' +
      '<button type="button" class="btn bsm" id="aq-inc-cli-mes">Este mes</button>' +
      '<button type="button" class="btn bsm" id="aq-inc-cli-historico">Todo el historial</button></div>' +
      '<div id="aq-inc-cli-totales" class="aq-inc-cli-totales" aria-live="polite"></div>' +
      '<p class="aq-inc-cli-ayuda">El incentivo se genera únicamente en ventas autorizadas de garrafones a Q9 o más, registradas por el empleado o equipo beneficiario. En equipo se reparte 50/50. Los créditos no cobrados quedan retenidos; las ventas canceladas no se contabilizan. El historial finalizado se conserva, sin repetir clientes.</p>';
    lista.parentNode.insertBefore(barra, lista);
    $('aq-inc-cli-desde').value = primeraAutorizacion();
    $('aq-inc-cli-hasta').value = fechaActual();
    $('aq-inc-cli-actualizar').addEventListener('click', () => cargar(true));
    $('aq-inc-cli-mes').addEventListener('click', () => {
      $('aq-inc-cli-desde').value = primerDiaMes();
      $('aq-inc-cli-hasta').value = fechaActual();
      cargar(true);
    });
    $('aq-inc-cli-historico').addEventListener('click', () => {
      $('aq-inc-cli-desde').value = primeraAutorizacion();
      $('aq-inc-cli-hasta').value = fechaActual();
      cargar(true);
    });
    $('aq-inc-cli-desde').addEventListener('change', () => cargar(true));
    $('aq-inc-cli-hasta').addEventListener('change', () => cargar(true));
    $('aq-inc-cli-buscar').addEventListener('input', pintar);
    $('aq-inc-cli-estado').addEventListener('change', pintar);
  }

  function agruparAutorizaciones() {
    const grupos = new Map();
    (aqIncCache.incentivos || []).forEach(inc => {
      const id = Number(inc.cliente_id);
      if (!Number.isFinite(id) || id <= 0) return;
      if (!grupos.has(id)) grupos.set(id, { id, nombre: nombreCli(id), configuraciones: [] });
      grupos.get(id).configuraciones.push(inc);
    });
    return [...grupos.values()].map(g => {
      g.configuraciones.sort((a, b) => Number(b.id) - Number(a.id));
      g.activas = g.configuraciones.filter(x => x.activo);
      g.actual = g.activas[0] || g.configuraciones[0];
      return g;
    }).sort((a, b) => Number(Boolean(b.activas.length)) - Number(Boolean(a.activas.length)) || a.nombre.localeCompare(b.nombre, 'es'));
  }

  async function leerMovimientos(desde, hasta) {
    if (desde > hasta) throw new Error('El período inicial es posterior al período final.');
    if (typeof sb === 'undefined' || !sb) throw new Error('No se ha conectado a la base de datos.');
    const { data, error } = await sb.rpc('aq_movimientos_incentivos', { ...aqIncAuth(), p_desde: desde, p_hasta: hasta });
    if (error) throw error;
    if (!Array.isArray(data)) throw new Error('El servidor no devolvió una lista de movimientos.');
    const ventas = new Map(), creditos = new Map();
    const ids = [...new Set(data.map(x => Number(x.venta_id)).filter(x => Number.isFinite(x) && x > 0))];
    for (let i = 0; i < ids.length; i += 100) {
      const lote = ids.slice(i, i + 100);
      const [rv, rc] = await Promise.all([
        sb.from('ventas').select('id,estado').in('id', lote),
        sb.from('creditos').select('venta_id,monto,pagado').in('venta_id', lote)
      ]);
      if (rv.error) throw rv.error;
      if (rc.error) throw rc.error;
      (rv.data || []).forEach(v => ventas.set(Number(v.id), v));
      (rc.data || []).forEach(c => {
        const id = Number(c.venta_id);
        if (!creditos.has(id)) creditos.set(id, []);
        creditos.get(id).push(c);
      });
    }
    if (ids.some(id => !ventas.has(id))) throw new Error('No se pudo consultar el estado de todas las ventas; por seguridad no se muestran montos parciales.');

    const resumen = new Map(), vistos = new Set(), repetidos = [];
    for (const m of data) {
      const clave = (m.venta_item_id != null ? String(m.venta_item_id) : ('mov-' + m.id)) + '/' + String(m.empleado_id);
      if (vistos.has(clave)) { repetidos.push(clave); continue; }
      vistos.add(clave);
      const v = ventas.get(Number(m.venta_id));
      if (!v || ['Cancelada', 'Anulado'].includes(String(v.estado))) continue;
      const clienteId = Number(m.cliente_id), empleadoId = Number(m.empleado_id);
      if (!resumen.has(clienteId)) resumen.set(clienteId, { total: 0, pagado: 0, pendiente: 0, credito: 0, unidades: 0, vistosItems: new Set(), empleados: new Map(), movimientos: [] });
      const r = resumen.get(clienteId);
      if (!r.empleados.has(empleadoId)) r.empleados.set(empleadoId, { id: empleadoId, total: 0, pagado: 0, pendiente: 0, credito: 0, unidades: 0 });
      const e = r.empleados.get(empleadoId);
      const monto = cent(m.importe_empleado), unidades = Number(m.cantidad || 0);
      if (!Number.isFinite(monto) || !Number.isFinite(unidades)) throw new Error('Movimiento con importe o cantidad inválida.');
      const porCobrar = (creditos.get(Number(m.venta_id)) || []).some(c => Number(c.pagado || 0) < Number(c.monto || 0));
      const estado = m.pago_id ? 'Pagado' : porCobrar ? 'Retenido por crédito' : 'Pendiente';
      r.total += monto; e.total += monto; e.unidades += unidades;
      if (m.pago_id) { r.pagado += monto; e.pagado += monto; }
      else if (porCobrar) { r.credito += monto; e.credito += monto; }
      else { r.pendiente += monto; e.pendiente += monto; }
      const item = m.venta_item_id != null ? String(m.venta_item_id) : ('mov-' + m.id);
      if (!r.vistosItems.has(item)) { r.vistosItems.add(item); r.unidades += unidades; }
      r.movimientos.push({ id: m.id, ventaId: m.venta_id, fecha: m.fecha, empleadoId, unidades, precio: m.precio_venta, monto, estado });
    }
    return { resumen, repetidos };
  }

  function tarjeta(g, r) {
    const actual = g.actual, activa = g.activas.length > 0;
    const total = r || { total: 0, pagado: 0, pendiente: 0, credito: 0, unidades: 0, empleados: new Map(), movimientos: [] };
    const equipos = aqIncCache.equipos || [];
    const textoRegla = inc => inc.modalidad === 'equipo'
      ? 'Equipo ' + (equipos.find(eq => Number(eq.id) === Number(inc.equipo_id))?.nombre || ('#' + inc.equipo_id)) + ' · 50/50'
      : 'Individual: ' + nombreEmp(inc.beneficiario_empleado_id);
    const detalles = [...total.empleados.values()].sort((a, b) => a.id - b.id);
    const estado = activa ? '✅ Activo' : '⏹ Finalizado';
    const bot = activa
      ? g.activas.map(inc => '<button class="btn bd bsm" type="button" onclick="aqFinalizarIncentivo(' + Number(inc.id) + ')">Finalizar #' + Number(inc.id) + '</button>').join(' ')
      : '<button class="btn bp bsm" type="button" onclick="aqReactivarIncentivo(' + Number(actual.id) + ')">♻️ Reactivar incentivo</button>';
    const historial = g.configuraciones.length > 1
      ? '<details class="aq-inc-cli-detalle"><summary>Historial de autorizaciones (' + g.configuraciones.length + ')</summary>' +
        g.configuraciones.map(inc => '<div class="aq-inc-cli-config">#' + Number(inc.id) + ' · ' + esc(inc.activo ? 'Activo' : 'Finalizado') +
          ' · ' + esc(textoRegla(inc)) + ' · ' + moneda(cent(inc.monto_unitario)) +
          ' por garrafón · desde ' + esc(inc.desde || '-') + (inc.hasta ? ' hasta ' + esc(inc.hasta) : '') + '</div>').join('') + '</details>' : '';
    const empleados = detalles.length
      ? '<details class="aq-inc-cli-detalle"><summary>Desglose por empleado (' + detalles.length + ')</summary><div class="tbl-wrap"><table><thead><tr><th>Empleado</th><th>Unidades beneficiadas</th><th>Generado</th><th>Pagado</th><th>Pendiente</th><th>Retenido crédito</th></tr></thead><tbody>' +
        detalles.map(e => '<tr><td>' + esc(nombreEmp(e.id)) + '</td><td>' + e.unidades + '</td><td>' + moneda(e.total) + '</td><td>' + moneda(e.pagado) + '</td><td>' + moneda(e.pendiente) + '</td><td>' + moneda(e.credito) + '</td></tr>').join('') +
        '</tbody></table></div></details>' : '';
    const ventas = total.movimientos.length
      ? '<details class="aq-inc-cli-detalle"><summary>Ver ventas que generaron incentivo (' + total.movimientos.length + ' movimientos)</summary><div class="tbl-wrap"><table><thead><tr><th>Fecha</th><th>Venta</th><th>Empleado</th><th>Garrafones</th><th>Precio</th><th>Incentivo</th><th>Estado</th></tr></thead><tbody>' +
        total.movimientos.slice().sort((a, b) => String(b.fecha).localeCompare(String(a.fecha))).slice(0, 100).map(m => '<tr><td>' + esc(m.fecha) + '</td><td>#' + Number(m.ventaId) + '</td><td>' + esc(nombreEmp(m.empleadoId)) + '</td><td>' + m.unidades + '</td><td>' + moneda(cent(m.precio)) + '</td><td>' + moneda(m.monto) + '</td><td>' + esc(m.estado) + '</td></tr>').join('') +
        '</tbody></table></div>' + (total.movimientos.length > 100 ? '<p>Se muestran los últimos 100 movimientos. Acota las fechas para ver más.</p>' : '') + '</details>' : '';
    return '<div class="aq-inc-cli-fila"><div class="aq-inc-cli-cabecera"><div><strong>' + esc(g.nombre) + '</strong> <span class="aq-inc-cli-estado">' + estado + '</span>' +
      '<small>Captado por ' + esc(nombreEmp(actual.captador_empleado_id)) + ' · ' + esc(textoRegla(actual)) + ' · Tarifa vigente ' + moneda(cent(actual.monto_unitario)) + '/garrafón</small></div>' +
      '<div>' + bot + '</div></div>' +
      '<div class="aq-inc-cli-numeros"><span>Garrafones válidos<b>' + total.unidades + '</b></span><span>Generado<b>' + moneda(total.total) + '</b></span><span>Pagado<b>' + moneda(total.pagado) + '</b></span><span>Pendiente liquidable<b>' + moneda(total.pendiente) + '</b></span><span>Retenido crédito<b>' + moneda(total.credito) + '</b></span></div>' +
      empleados + ventas + historial + '</div>';
  }

  function pintar() {
    const lista = $('aq-inc-lista'), totales = $('aq-inc-cli-totales');
    if (!lista || !totales) return;
    if (errorActual) {
      lista.innerHTML = '<p class="tmuted">⚠️ No fue posible verificar el acumulado de ventas: ' + esc(errorActual) + '. No se han modificado los incentivos.</p>';
      totales.textContent = 'Montos no disponibles; no asumir Q0.';
      return;
    }
    if (!datos) { lista.innerHTML = '<p class="tmuted">Consultando ventas e incentivos…</p>'; return; }
    const filtro = $('aq-inc-cli-buscar')?.value.toLocaleLowerCase().trim() || '';
    const estado = $('aq-inc-cli-estado')?.value || 'todos';
    const grupos = agruparAutorizaciones().filter(g =>
      (!filtro || g.nombre.toLocaleLowerCase().includes(filtro)) &&
      (estado === 'todos' || (estado === 'activo' ? !!g.activas.length : !g.activas.length)));
    const suma = { total: 0, pagado: 0, pendiente: 0, credito: 0, unidades: 0 };
    grupos.forEach(g => {
      const r = datos.resumen.get(g.id);
      if (!r) return;
      Object.keys(suma).forEach(k => suma[k] += r[k] || 0);
    });
    totales.innerHTML = '<span>Clientes <b>' + grupos.length + '</b></span><span>Garrafones válidos <b>' + suma.unidades + '</b></span>' +
      '<span>Generado <b>' + moneda(suma.total) + '</b></span><span>Pagado <b>' + moneda(suma.pagado) + '</b></span>' +
      '<span>Pendiente liquidable <b>' + moneda(suma.pendiente) + '</b></span><span>Crédito sin cobrar <b>' + moneda(suma.credito) + '</b></span>';
    const activos = grupos.filter(g => g.activas.length > 0);
    const finalizados = grupos.filter(g => g.activas.length === 0);
    const buscar = Boolean(filtro);
    const abiertosActivos = Boolean(lista.querySelector?.('#aq-inc-grupo-activos')?.open) || buscar;
    const abiertosFinalizados = Boolean(lista.querySelector?.('#aq-inc-grupo-finalizados')?.open) || (buscar && finalizados.length > 0);
    const contenido = (arr, mensaje) => arr.length
      ? arr.map(g => tarjeta(g, datos.resumen.get(g.id))).join('')
      : '<p class="tmuted" style="padding:10px">' + mensaje + '</p>';
    lista.innerHTML =
      '<details id="aq-inc-grupo-activos" class="aq-inc-cli-grupo" ' + (abiertosActivos ? 'open' : '') + '>' +
      '<summary>✅ Clientes con incentivo activo (' + activos.length + ') <small>— clic para desplegar / ocultar</small></summary>' +
      '<div class="aq-inc-cli-grupo-interior">' +
      contenido(activos,'No hay clientes activos que coincidan con estos filtros.') + '</div></details>' +
      '<details id="aq-inc-grupo-finalizados" class="aq-inc-cli-grupo" ' + (abiertosFinalizados ? 'open' : '') + '>' +
      '<summary>📁 Clientes sin incentivo activo (' + finalizados.length + ') <small>— las autorizaciones anteriores están en cada historial</small></summary>' +
      '<div class="aq-inc-cli-grupo-interior">' +
      contenido(finalizados,'No hay incentivos finalizados para estos filtros.') + '</div></details>';
    if (datos.repetidos.length) {
      totales.innerHTML += '<span>⚠️ ' + datos.repetidos.length + ' movimiento(s) duplicado(s) detectado(s); se omitieron del total mostrado. Revisar contabilidad antes de pagar.</span>';
    }
  }

  async function cargar(forzar) {
    prepararVista();
    const lista = $('aq-inc-lista');
    if (!lista || typeof CU === 'undefined' || !CU || CU.rol !== 'jefe') return;
    const { desde, hasta } = periodo();
    const rango = desde + '|' + hasta;
    if (!forzar && datos && rangoCargado === rango) { pintar(); return; }
    datos = null; errorActual = '';
    lista.innerHTML = '<p class="tmuted">Consultando movimientos de ventas y pagos…</p>';
    const actual = ++solicitud;
    try {
      const resultado = await leerMovimientos(desde, hasta);
      if (actual !== solicitud) return;
      datos = resultado; rangoCargado = rango;
    } catch (error) {
      if (actual !== solicitud) return;
      console.warn('Resumen de incentivos por cliente no disponible:', error);
      errorActual = error?.message || 'Error de conexión';
    }
    pintar();
  }

  window.aqIncPintar = function () {
    pintarAnterior.apply(this, arguments);
    prepararVista();
    cargar(true);
  };
  window.aqIncVistaClientesRefrescar = () => cargar(true);
})();
