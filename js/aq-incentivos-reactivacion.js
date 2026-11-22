/* Aquabri · Reactivación controlada de incentivos.
 * Solo el jefe puede reactivar un cliente finalizado. El servidor crea
 * una autorización distinta y conserva el historial anterior.
 */
(function () {
  'use strict';
  let enCurso = false;
  const escapeText = value => String(value == null ? '' : value);
  const clienteNombre = id => typeof aqIncNombreCli === 'function'
    ? aqIncNombreCli(id) : ('Cliente #' + id);
  const empleadoNombre = id => typeof aqIncNombreEmp === 'function'
    ? aqIncNombreEmp(id) : ('Empleado #' + id);
  const monto = valor => typeof aqIncFmt === 'function'
    ? aqIncFmt(valor) : 'Q ' + Number(valor || 0).toFixed(2);

  window.aqReactivarIncentivo = async function (incentivoId) {
    if (enCurso) return;
    if (typeof CU === 'undefined' || !CU || CU.rol !== 'jefe') {
      showNotif('Solo el jefe puede reactivar incentivos.','#c62828');
      return;
    }
    const historial = typeof aqIncCache !== 'undefined' && Array.isArray(aqIncCache?.incentivos)
      ? aqIncCache.incentivos : [];
    const id = Number(incentivoId);
    const original = historial.find(x => Number(x.id) === id);
    if (!original) {
      showNotif('No se encontró el incentivo. Actualiza la lista.','#c62828');
      return;
    }
    const relacionados = historial.filter(x => Number(x.cliente_id) === Number(original.cliente_id));
    if (original.activo || relacionados.some(x => x.activo)) {
      showNotif('El cliente ya tiene un incentivo activo; no se puede reactivar.','#c62828');
      return;
    }
    const masReciente = relacionados.slice().sort((a,b)=>Number(b.id)-Number(a.id))[0];
    if (Number(masReciente?.id) !== id) {
      showNotif('Selecciona la autorización finalizada más reciente de este cliente.','#c62828');
      return;
    }

    const equipo = original.modalidad === 'equipo'
      ? (typeof aqIncCache !== 'undefined'
          ? (aqIncCache.equipos||[]).find(e => Number(e.id) === Number(original.equipo_id))
          : null)
      : null;
    const beneficiario = original.modalidad === 'equipo'
      ? ('Equipo ' + (equipo?.nombre||('#' + original.equipo_id)) + ' · 50/50')
      : ('Individual · ' + empleadoNombre(original.beneficiario_empleado_id));
    const mensaje = 'REACTIVAR INCENTIVO\n\n' +
      'Cliente: ' + escapeText(clienteNombre(original.cliente_id)) + '\n' +
      'Captador: ' + escapeText(empleadoNombre(original.captador_empleado_id)) + '\n' +
      'Beneficiarios: ' + beneficiario + '\n' +
      'Tarifa: ' + monto(original.monto_unitario) + ' por garrafón\n' +
      'Precio mínimo: ' + monto(original.precio_minimo) + '\n\n' +
      'Se abrirá un PERÍODO NUEVO con las mismas condiciones y se conservará el historial cerrado.\n' +
      'Las ventas anteriores NO generarán nuevas comisiones. No se duplicarán pagos.\n\n' +
      '¿Confirmas que deseas reactivar este incentivo?';
    if (!confirm(mensaje)) return;
    enCurso = true;
    try {
      // No confiar únicamente en el estado visible; el servidor comprueba de
      // nuevo privilegios, historial, último registro, equipo y concurrencia.
      const {data,error} = await sb.rpc('aq_reactivar_incentivo_jefe_v1', {
        ...aqIncAuth(),p_incentivo:id,p_confirmado:true
      });
      if (error) throw error;
      if (!data || !Number(data.incentivo_id)) throw new Error('No llegó confirmación del servidor.');
      showNotif('✅ Incentivo reactivado para ' +
        clienteNombre(original.cliente_id) +
        '. Nuevo registro #' + data.incentivo_id +
        ', desde ' + data.desde + '.');
      if (typeof aqIncRecargar === 'function') await aqIncRecargar();
      if (typeof aqIncVistaClientesRefrescar === 'function') await aqIncVistaClientesRefrescar();
    } catch (error) {
      console.warn('No se pudo reactivar incentivo',error);
      showNotif('No se pudo reactivar: ' + (error?.message || 'error desconocido') +
        '. No se modificaron comisiones anteriores.','#c62828');
    } finally {
      enCurso = false;
    }
  };
})();
