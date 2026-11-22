/* Aquabri · Comisiones ordinarias (porcentaje) - pagos mensuales atómicos.
   No permite que la interfaz cree 3 filas independientes y reporte éxito parcial.
   El servidor valida la comisión del mes, pagos anteriores y saldo de caja.
*/
(function () {
  'use strict';
  const id=id=>document.getElementById(id);
  const ocupado=new Set();
  const fecha=()=>typeof hoy==='function'?hoy():new Date().toISOString().slice(0,10);
  const importe=n=>typeof fQ==='function'?fQ(Number(n)||0):'Q'+Number(n||0).toFixed(2);

  function normalizarMes(valor) {
    const texto=String(valor||'');
    if (/^\d{4}-\d{2}$/.test(texto)) return texto;
    const m=texto.match(/^(\d{4}-\d{2})-(\d{2})_(\d{4}-\d{2})-(\d{2})$/);
    if (!m || m[2]!=='01' || m[1]!==m[3]) return null;
    const mes=m[1];
    const ultimo=new Date(Number(mes.slice(0,4)),Number(mes.slice(5)),0).getDate();
    const hasta=mes+'-'+m[4];
    const fechaFinalMes=mes+'-'+String(ultimo).padStart(2,'0');
    // Pagar mes completo o mes hasta hoy; jamás un rango parcial arbitrario.
    if (hasta===fechaFinalMes || (mes===fecha().slice(0,7) && hasta===fecha())) return mes;
    return null;
  }

  function prepararModal(mes) {
    const modal=id('modal-pago-comision');
    if (!modal) return;
    const body=modal.querySelector('.gf');
    if (!body) return;
    const inputFecha=id('pc-fecha');
    if (inputFecha) {
      inputFecha.value=fecha();
      inputFecha.setAttribute('readonly','readonly');
      inputFecha.title='El servidor asigna automáticamente la fecha de pago de hoy.';
    }
    if (!id('pc-origen-seguro')) {
      body.insertAdjacentHTML('beforeend',
        '<div class="fg" style="grid-column:1/-1">' +
        '<label>¿Desde dónde se hará el pago?</label>' +
        '<select id="pc-origen-seguro" required>' +
        '<option value="">Selecciona un medio de pago</option>' +
        '<option value="caja">Efectivo de Caja (sale del cajón del jefe)</option>' +
        '<option value="externo">Fuera de caja (transferencia u otra cuenta)</option>' +
        '</select><small style="font-size:10px;color:var(--gris)">Se registrará en Gastos y RRHH una sola vez; Caja solo si pagas en efectivo.</small></div>'
      );
    }
    modal.dataset.aqMesPagoSeguro=mes;
  }

  const pagarMesAnterior=window.pagarComisionRRHH;
  if(typeof pagarMesAnterior==='function') {
    window.pagarComisionRRHH=function(empId,nombre,monto,mes) {
      pagarMesAnterior.apply(this,arguments);
      prepararModal(mes);
    };
  }

  const pagarPeriodoAnterior=window.pagarComision;
  if(typeof pagarPeriodoAnterior==='function') {
    window.pagarComision=function(empId,nombre,monto,periodo) {
      const mes=normalizarMes(periodo);
      if (!mes) {
        showNotif('Para evitar pagos repetidos, registra comisiones por mes completo desde RRHH → Comisiones.','#e65100');
        return;
      }
      pagarPeriodoAnterior.apply(this,arguments);
      prepararModal(mes);
    };
  }

  function nonceSeguro() {
    if (!globalThis.crypto || typeof crypto.getRandomValues!=='function') {
      throw new Error('El navegador no permite crear una referencia segura de pago');
    }
    const b=new Uint8Array(24);
    crypto.getRandomValues(b);
    return Array.from(b,v=>v.toString(16).padStart(2,'0')).join('');
  }

  async function registrar(empId,nombre,periodo) {
    if(typeof CU==='undefined' || !CU || CU.rol!=='jefe') {
      showNotif('Solo el jefe puede registrar este pago','#c62828');return;
    }
    const modal=id('modal-pago-comision');
    const mes=normalizarMes(modal?.dataset?.aqMesPagoSeguro || periodo);
    const p_empleado=Number(empId);
    const p_monto=Number(id('pc-monto')?.value||0);
    const origen=id('pc-origen-seguro')?.value;
    const p_notas=String(id('pc-notas')?.value||'').trim();
    const fechaElegida=id('pc-fecha')?.value;
    if(!mes || !Number.isFinite(p_monto) || p_monto<=0 || Math.round(p_monto*100)!==p_monto*100 ||
      p_notas.length>250 || fechaElegida!==fecha()) {
      showNotif('Revisa el mes, monto de comisión y fecha actual.','#c62828');return;
    }
    if(!['caja','externo'].includes(origen)) {
      showNotif('Selecciona el medio de pago (Caja u otra cuenta).','#c62828');
      id('pc-origen-seguro')?.focus();return;
    }
    const llave=[p_empleado,mes,p_monto.toFixed(2),origen,p_notas].join('|');
    if(ocupado.has(llave)) return;
    ocupado.add(llave);
    try {
      const previa=await sb.rpc('aq_previa_pago_comision_normal_v1',{
        p_token:localStorage.getItem('aqb_token')||'',p_uid:Number(CU?.id)||0,
        p_empleado,p_mes:mes
      });
      if(previa.error) throw previa.error;
      const pendiente=Number(previa.data?.pendiente||0);
      if(p_monto>pendiente+0.00001) {
        throw new Error('La comisión pendiente verificada es '+importe(pendiente)+'. Recalcula antes de pagar.');
      }
      const mensaje='Empleado: '+nombre+
        '\nMes: '+mes+
        '\nComisión generada: '+importe(previa.data?.generado)+
        '\nPagada anteriormente: '+importe(previa.data?.pagado)+
        '\nPendiente: '+importe(pendiente)+
        '\nPagar ahora: '+importe(p_monto)+
        '\nOrigen: '+(origen==='caja'?'EFECTIVO DE CAJA':'FUERA DE CAJA')+
        '\n\n¿Confirmas este pago? Se guardará como comisión pagada, gasto y movimiento de caja únicamente si es efectivo.';
      if(!confirm(mensaje)) return;
      const almacenamiento='aq-pago-normal-v1:'+llave;
      let p_nonce=sessionStorage.getItem(almacenamiento);
      if(!p_nonce) {
        p_nonce=nonceSeguro();
        sessionStorage.setItem(almacenamiento,p_nonce);
      }
      const r=await sb.rpc('aq_pagar_comision_normal_v1',{
        p_token:localStorage.getItem('aqb_token')||'',p_uid:Number(CU?.id)||0,
        p_nonce,p_empleado,p_mes:mes,p_monto,p_origen:origen,p_notas
      });
      if(r.error) throw r.error;
      sessionStorage.removeItem(almacenamiento);
      modal?.classList.remove('open');
      showNotif('✅ Pago registrado '+importe(r.data?.monto)+' · Comprobante de comisión #' +r.data?.pago_id+
        (r.data?.repetida?' · Ya existía; no se duplicó':''));
      if(typeof loadAll==='function')await loadAll();
      if(typeof renderComisionesRRHH==='function')await renderComisionesRRHH();
      if(typeof renderHistorialComisionesRRHH==='function')await renderHistorialComisionesRRHH();
      if(typeof renderHistorialComisiones==='function')await renderHistorialComisiones();
      if(typeof renderPagos==='function')await renderPagos();
    } catch(error) {
      console.error('Pago ordinario no confirmado:',error);
      showNotif('No se pudo registrar: '+(error?.message||'error desconocido')+
        '. Verifica historial antes de reintentar. La referencia se conserva para impedir duplicados.','#c62828');
    } finally {
      ocupado.delete(llave);
    }
  }

  window.confirmarPagoComisionRRHH=registrar;
  window.confirmarPagoComision=registrar;
})();
