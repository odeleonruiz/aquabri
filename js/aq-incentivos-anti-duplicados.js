/* Aquabri System · evitar incentivos duplicados (cliente ID)
   Una autorización previa, incluso finalizada, impide volver a autorizar
   desde este formulario. No modifica registros históricos. La BD impone
   la misma regla con trigger + índice único parcial para activos. */
(function () {
  'use strict';
  const $ = id => document.getElementById(id);
  let guardando = false;
  const todas = () => typeof aqIncCache !== 'undefined' && Array.isArray(aqIncCache?.incentivos)
    ? aqIncCache.incentivos : [];
  const existentes = id => todas().filter(i => Number(i.cliente_id) === Number(id));
  const nombreCliente = id => typeof aqIncNombreCli === 'function' ? aqIncNombreCli(id) : 'Cliente #' + id;

  function elementoAviso() {
    const origen = $('aq-inc-creado');
    if (!origen || !origen.parentNode) return null;
    let aviso = $('aq-inc-aviso-duplicado');
    if (!aviso) {
      aviso = document.createElement('p');
      aviso.id = 'aq-inc-aviso-duplicado';
      aviso.setAttribute('role','status');
      aviso.setAttribute('aria-live','polite');
      aviso.style.cssText = 'font-size:12px;line-height:1.5;font-weight:700;margin:7px 0;color:#b42318';
      origen.insertAdjacentElement('afterend', aviso);
    }
    return aviso;
  }

  function revisarSeleccion() {
    const cliente = Number($('aq-inc-cliente')?.value || 0);
    const encontrados = cliente ? existentes(cliente) : [];
    const activo = encontrados.find(i => i.activo);
    const ultimo = activo || encontrados.slice().sort((a,b) => Number(b.id)-Number(a.id))[0];
    const boton = document.querySelector('button[onclick*="aqGuardarIncentivo"]');
    const aviso = elementoAviso();
    if (ultimo) {
      const estado = ultimo.activo ? 'ACTIVO' : 'FINALIZADO';
      const mensaje = '⚠️ ' + nombreCliente(cliente) + ' ya fue agregado a incentivos (registro #' +
        ultimo.id + ', ' + estado + '). No puedes volver a registrarlo: se conservará el historial anterior.';
      if (aviso) aviso.textContent = mensaje;
      if (boton) {
        boton.disabled = true;
        boton.title = 'Cliente ya registrado: el sistema impide duplicar el incentivo';
      }
    } else {
      if (aviso) aviso.textContent = '';
      if (boton) {
        boton.disabled = false;
        boton.title = '';
      }
    }
    return ultimo;
  }

  // Aviso visible al elegir un cliente de la lista o de las sugerencias.
  for (const fn of ['aqIncSeleccionarCliente','aqIncSeleccionarListaClientes']) {
    if (typeof window[fn] !== 'function') continue;
    const anteriorSeleccionar = window[fn];
    window[fn] = function () {
      const resultado = anteriorSeleccionar.apply(this, arguments);
      const previo = revisarSeleccion();
      if (previo) showNotif('Este cliente ya fue agregado a incentivos. No se puede duplicar.', '#c62828');
      return resultado;
    };
  }

  if (typeof window.aqIncMostrarCaptacion === 'function') {
    const anterior = window.aqIncMostrarCaptacion;
    window.aqIncMostrarCaptacion = function () {
      const r = anterior.apply(this,arguments);
      revisarSeleccion();
      return r;
    };
  }
  if (typeof window.aqIncPintar === 'function') {
    const anterior = window.aqIncPintar;
    window.aqIncPintar = function () {
      const r = anterior.apply(this,arguments);
      revisarSeleccion();
      return r;
    };
  }
  if (typeof window.aqGuardarIncentivo === 'function') {
    const anterior = window.aqGuardarIncentivo;
    window.aqGuardarIncentivo = async function () {
      if (guardando) return;
      const cliente = Number($('aq-inc-cliente')?.value || 0);
      if (!cliente) return anterior.apply(this,arguments);
      if (revisarSeleccion()) {
        showNotif('Este cliente ya tiene un incentivo registrado. No se creó otro.','#c62828');
        return;
      }
      guardando = true;
      try {
        // Reconsulta al servidor: otro usuario puede haber autorizado este cliente
        // mientras la pantalla estaba abierta. El trigger de BD es el último control.
        const {data,error} = await sb.rpc('aq_estado_incentivos',aqIncAuth());
        if (error) throw error;
        if (!data || !Array.isArray(data.incentivos)) throw new Error('No se pudieron verificar los incentivos existentes.');
        aqIncCache = data;
        if (revisarSeleccion()) {
          showNotif('Este cliente ya fue agregado a incentivos. No se registró otra comisión.','#c62828');
          return;
        }
        await anterior.apply(this,arguments);
        revisarSeleccion();
      } catch (error) {
        console.error('Error al comprobar incentivos duplicados',error);
        showNotif('No se autorizó el incentivo: '+(error?.message||'no se pudo verificar al cliente'),'#c62828');
      } finally {
        guardando = false;
      }
    };
  }
  window.aqIncComprobarDuplicadoCliente = revisarSeleccion;
})();
