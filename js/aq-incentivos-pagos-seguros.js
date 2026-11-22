/* Aquabri System · Control financiero y liquidación segura de incentivos.
   Los incentivos se devengan al vender y ya afectan la utilidad del período.
   Liquidar NO vuelve a crear otro gasto, solo registra el pago y su salida de caja si corresponde.
*/
(function () {
  'use strict';
  const $ = id => document.getElementById(id);
  const inFlight = new Set();
  let secuencia = 0;
  const escapeHtml = valor => typeof aqIncHtml === 'function'
    ? aqIncHtml(valor) : String(valor ?? '').replaceAll('&','&amp;').replaceAll('<','&lt;');
  const fmt = x => typeof aqIncFmt === 'function' ? aqIncFmt(x) : 'Q ' + Number(x || 0).toFixed(2);
  const actual = () => typeof hoy === 'function' ? hoy() : new Date().toISOString().slice(0,10);
  const mes = () => actual().slice(0,7) + '-01';
  const empleado = id => typeof aqIncNombreEmp === 'function' ? aqIncNombreEmp(id) : 'Empleado #' + id;
  const parametros = () => ({
    p_desde: $('aq-inc-desde')?.value || mes(),
    p_hasta: $('aq-inc-hasta')?.value || actual()
  });

  function preparar() {
    const reporte = $('aq-inc-reporte'), origen = $('aq-inc-origen');
    if (!reporte) return;
    if (origen && !origen.dataset.aqSeguro) {
      origen.dataset.aqSeguro = '1';
      origen.innerHTML = '<option value="">Selecciona el medio de pago</option>' +
        '<option value="caja">Efectivo de caja — descontar del cuadre</option>' +
        '<option value="externo">Fuera de caja — transferencia u otra cuenta</option>';
      origen.value = '';
    }
    if ($('aq-inc-control-contable')) return;
    const box = document.createElement('section');
    box.id = 'aq-inc-control-contable';
    box.className = 'card';
    box.style.marginTop = '14px';
    box.style.padding = '13px';
    box.innerHTML = '<div class="card-title">📊 Control financiero de incentivos</div>' +
      '<p class="tmuted" style="font-size:11px;line-height:1.5;margin:7px 0 10px">' +
      'Los incentivos se reconocen como costo cuando se generan por ventas válidas. ' +
      'Al liquidar no se registra un segundo gasto. Solo se registra el pago y, si corresponde, la salida de efectivo de la caja abierta.</p>' +
      '<button type="button" class="btn bsm bp" id="aq-inc-control-refrescar">↻ Actualizar control financiero</button>' +
      '<div id="aq-inc-control-cifras" aria-live="polite" style="margin-top:11px">Consultando…</div>' +
      '<div id="aq-inc-control-pagos" style="margin-top:10px"></div>';
    reporte.insertAdjacentElement('afterend', box);
    $('aq-inc-control-refrescar').addEventListener('click', actualizar);
    for (const id of ['aq-inc-desde','aq-inc-hasta']) {
      $(id)?.addEventListener('change',actualizar);
    }
  }

  function tarjetas(t) {
    const datos = [
      ['Incentivos devengados por ventas',t.generado],
      ['Pendientes para pagar',t.pendiente],
      ['Retenidos por crédito',t.retenido_credito],
      ['Pagos efectuados en el período',t.pagos_realizados],
      ['Salidas de efectivo de caja',t.pagos_caja],
      ['Pagos desde otra cuenta',t.pagos_fuera_caja]
    ];
    return '<div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(145px,1fr));gap:9px;">' +
      datos.map(([titulo,monto]) => '<div style="border:1px solid var(--borde,#b5cbd5);border-radius:9px;padding:10px;">' +
         '<div style="font-size:10px;line-height:1.35;color:var(--gris,#586f80)">' + escapeHtml(titulo) + '</div>' +
         '<b style="font-size:15px;display:block;margin-top:5px;color:var(--texto,#123)">' + fmt(monto) + '</b></div>').join('') +
      '</div>';
  }

  async function actualizar() {
    preparar();
    const destino = $('aq-inc-control-cifras'), pagos = $('aq-inc-control-pagos');
    if (!destino || typeof CU === 'undefined' || !CU || CU.rol !== 'jefe') return;
    const {p_desde,p_hasta} = parametros();
    const actualizacion = ++secuencia;
    destino.textContent = 'Consultando el libro de incentivos y los pagos registrados…';
    pagos.innerHTML = '';
    try {
      if (p_desde>p_hasta || p_hasta>actual()) throw new Error('Revisa las fechas seleccionadas.');
      const {data,error} = await sb.rpc('aq_control_incentivos_contable_v1',{
        ...aqIncAuth(), p_desde,p_hasta
      });
      if (error) throw error;
      if (actualizacion!==secuencia) return;
      destino.innerHTML = tarjetas(data || {});
      const historial = Array.isArray(data?.ultimos_pagos) ? data.ultimos_pagos : [];
      pagos.innerHTML = '<b style="font-size:12px">Historial de liquidaciones de incentivos</b>' +
        (historial.length
          ? '<div class="tbl-wrap"><table><thead><tr><th>Pago</th><th>Fecha</th><th>Empleado</th><th>Período liquidado</th><th>Importe</th><th>Medio de pago</th></tr></thead><tbody>' +
            historial.map(p => {
              const fecha = p.pagado_en ? new Date(p.pagado_en).toLocaleDateString('es-GT',{timeZone:'America/Guatemala'}) : '—';
              return '<tr><td>#' + Number(p.id) + '</td><td>' + escapeHtml(fecha) + '</td><td>' +
                escapeHtml(empleado(p.empleado_id)) + '</td><td>' + escapeHtml(p.desde) + ' al ' +
                escapeHtml(p.hasta) + '</td><td><b>' + fmt(p.monto) + '</b></td><td>' +
                (p.origen_pago==='caja' ? 'Efectivo de caja' : 'Fuera de caja') + '</td></tr>';
            }).join('') + '</tbody></table></div>'
          : '<p class="tmuted" style="margin:8px 0">Aún no hay pagos registrados en estas fechas.</p>') +
        '<p class="tmuted" style="font-size:11px;line-height:1.5;margin-top:9px">' +
        'Devengados y pendientes se filtran por fecha de venta; los pagos y salidas se filtran por fecha en que se liquidaron. ' +
        'Los pagos fuera de caja no descuentan el cajón ni constituyen automáticamente una conciliación bancaria. ' +
        'Para pagar, pulsa <b>Consultar</b> en “Consulta de incentivos devengados”, y luego <b>Liquidar</b> junto al empleado.</p>';
    } catch (error) {
      if (actualizacion!==secuencia) return;
      destino.textContent = 'No se pudo consultar el control financiero: ' + (error?.message || 'error desconocido') +
        '. No se modificaron pagos ni caja.';
    }
  }

  function nonceSeguro() {
    if (!globalThis.crypto || typeof crypto.getRandomValues !== 'function') {
      throw new Error('El navegador no permite crear una referencia segura de pago.');
    }
    const random = new Uint8Array(24);
    crypto.getRandomValues(random);
    return Array.from(random,x=>x.toString(16).padStart(2,'0')).join('');
  }

  async function liquidar(empleadoId) {
    if (typeof CU==='undefined' || !CU || CU.rol!=='jefe') {
      showNotif('Solo el jefe puede pagar incentivos.','#c62828');
      return;
    }
    preparar();
    const {p_desde,p_hasta} = parametros();
    const origen = $('aq-inc-origen')?.value || '';
    if (!['caja','externo'].includes(origen)) {
      showNotif('Primero selecciona si pagaste en efectivo de caja o desde otra cuenta.','#c62828');
      $('aq-inc-origen')?.focus();
      return;
    }
    if (p_desde>p_hasta || p_hasta>actual()) {
      showNotif('Corrige las fechas para liquidar incentivos.','#c62828');
      return;
    }
    const key = [Number(empleadoId),p_desde,p_hasta,origen].join(':');
    if (inFlight.has(key)) return;
    inFlight.add(key);
    try {
      const p_empleado = Number(empleadoId);
      const previa = await sb.rpc('aq_previa_liquidacion_incentivos_v1',{
        ...aqIncAuth(),p_empleado,p_desde,p_hasta
      });
      if (previa.error) throw previa.error;
      const monto = Number(previa.data?.monto || 0);
      const retenido = Number(previa.data?.retenido_credito || 0);
      if (monto <= 0) {
        showNotif('No hay incentivos pendientes y cobrados para este empleado en el período.','#e65100');
        await actualizar();
        return;
      }
      const medio = origen==='caja'
        ? 'EFECTIVO de tu caja abierta. El sistema descontará el importe una sola vez.'
        : 'FUERA DE CAJA (transferencia/otra cuenta). Se registrará el pago sin descontar efectivo.';
      const mensaje = 'Empleado: ' + empleado(p_empleado) +
        '\\nPeríodo de ventas: ' + p_desde + ' al ' + p_hasta +
        '\\nIncentivos listos para pagar: ' + fmt(monto) +
        '\\nRetenido por créditos pendientes: ' + fmt(retenido) +
        '\\nMedio de pago: ' + medio +
        '\\n\\n¿CONFIRMAS que entregaste o entregarás ese dinero y deseas registrar la liquidación?';
      if (!confirm(mensaje)) return;
      const almacenamiento = 'aq-inc-pago-v3:' + key;
      let nonce = sessionStorage.getItem(almacenamiento);
      if (!nonce) {
        nonce = nonceSeguro();
        sessionStorage.setItem(almacenamiento,nonce);
      }
      const resultado = await sb.rpc('aq_liquidar_incentivos_contable_v3',{
        ...aqIncAuth(),p_nonce:nonce,p_empleado,p_desde,p_hasta,p_origen:origen
      });
      if (resultado.error) throw resultado.error;
      sessionStorage.removeItem(almacenamiento);
      const pagado = Number(resultado.data?.monto || 0);
      if (pagado > 0) {
        showNotif('✅ Liquidación registrada: ' + fmt(pagado) +
           (resultado.data?.repetida ? ' · Pago anterior identificado, no duplicado' : '') +
           ' · Comprobante #' + resultado.data?.pago_id);
      } else {
        showNotif('No había saldo liquidable. No se descontó dinero de caja.','#e65100');
      }
      if (typeof aqReporteIncentivos === 'function') await aqReporteIncentivos();
      if (typeof aqIncVistaClientesRefrescar === 'function') await aqIncVistaClientesRefrescar();
      await actualizar();
    } catch(error) {
      console.error('Liquidación no confirmada:',error);
      showNotif('No se pudo confirmar la liquidación: ' + (error?.message || 'error de red') +
        '. Revisa el historial antes de reintentar; se conserva la referencia para evitar duplicados.','#c62828');
      await actualizar();
    } finally {
      inFlight.delete(key);
    }
  }

  if (typeof window.aqIncPintar === 'function') {
    const anterior = window.aqIncPintar;
    window.aqIncPintar = function () {
      anterior.apply(this,arguments);
      preparar();
      actualizar();
    };
  }
  if (typeof window.aqReporteIncentivos === 'function') {
    const reporteAnterior = window.aqReporteIncentivos;
    window.aqReporteIncentivos = async function () {
      const resultado = await reporteAnterior.apply(this,arguments);
      await actualizar();
      return resultado;
    };
  }
  // Sustituye la ruta antigua que insertaba una columna inexistente en gastos
  // por la liquidación atómica validada e idempotente del servidor.
  window.aqPagarIncentivo = liquidar;
  if (document.readyState==='loading') document.addEventListener('DOMContentLoaded',preparar);
  else preparar();
})();
