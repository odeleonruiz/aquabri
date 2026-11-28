(() => {
  'use strict';

  const app = document.getElementById('app');
  const boton = document.getElementById('aq-asistencia-abrir');
  const modal = document.getElementById('aq-asistencia-modal');
  const titulo = document.getElementById('aq-asistencia-titulo');
  const estadoTexto = document.getElementById('aq-asistencia-estado');
  const mensaje = document.getElementById('aq-asistencia-mensaje');
  const marcar = document.getElementById('aq-asistencia-marcar');
  const cerrar = document.getElementById('aq-asistencia-cerrar');
  const salir = document.getElementById('aq-asistencia-salir');
  const reintentar = document.getElementById('aq-asistencia-reintentar');
  const panel = document.getElementById('aq-asistencia-jefe');
  const ubicacion = document.getElementById('aq-asistencia-ubicacion');
  const activar = document.getElementById('aq-asistencia-activar');
  const fecha = document.getElementById('aq-asistencia-fecha');
  const registros = document.getElementById('aq-asistencia-registros');
  const hora = new Intl.DateTimeFormat('es-GT', {
    timeZone: 'America/Guatemala', hour: 'numeric', minute: '2-digit'
  });
  let estado;
  let consultando = false;
  let guardando = false;
  let obligatorio = false;
  let ultimoIntento = 0;

  const esJefe = () => CU?.rol === 'jefe';

  function abrir() {
    if (!modal.open) modal.showModal();
  }

  function renderizar() {
    const jefe = esJefe();
    const vigenteHoy = estado?.hoy === hoy();
    const registrada = vigenteHoy ? estado?.marca : null;
    obligatorio = !jefe && Boolean(estado?.vigente && !registrada);
    boton.hidden = !jefe && Boolean(estado && !estado.vigente);
    titulo.textContent = jefe ? 'Asistencia del personal' : obligatorio ? 'Marca tu entrada' : 'Mi asistencia';
    panel.hidden = !jefe;
    cerrar.hidden = obligatorio;
    salir.hidden = !obligatorio;
    marcar.hidden = jefe || !estado?.vigente || Boolean(registrada?.salida);
    marcar.disabled = guardando || !vigenteHoy;
    marcar.textContent = registrada ? 'Marcar salida' : 'Marcar entrada';
    ubicacion.disabled = guardando || !estado;
    activar.disabled = guardando || !estado?.ubicacion_guardada;
    activar.textContent = estado?.activo ? 'Desactivar marcación' : 'Activar marcación';

    if (jefe && estado) {
      estadoTexto.textContent = `${estado.activo ? 'Activada' : 'Desactivada'} · ${estado.radio_metros} m · ${estado.ubicacion_guardada ? 'Ubicación guardada' : 'Ubicación pendiente'}`;
    } else if (registrada) {
      estadoTexto.textContent = `Entrada ${hora.format(new Date(registrada.entrada))}` +
        (registrada.salida ? ` · Salida ${hora.format(new Date(registrada.salida))}` : '');
    } else if (estado?.vigente) {
      estadoTexto.textContent = 'Registra tu entrada desde el negocio para continuar.';
    } else {
      estadoTexto.textContent = estado ? 'La marcación no está activa para hoy.' : 'Consultando asistencia…';
    }
    if (obligatorio) abrir();
  }

  async function rpc(nombre, parametros = {}) {
    const {data, error} = await sb.rpc(nombre, parametros).abortSignal(AbortSignal.timeout(10000));
    if (error) {
      const detalle = ['22023', '42501'].includes(error.code) ? error.message : 'No se pudo conectar con asistencia. Vuelve a intentar.';
      throw new Error(detalle);
    }
    return data;
  }

  function mostrarRegistros(items) {
    registros.replaceChildren();
    if (!items.length) {
      const vacio = document.createElement('p');
      vacio.textContent = 'Sin marcaciones para esta fecha.';
      registros.append(vacio);
      return;
    }
    for (const item of items) {
      const fila = document.createElement('div');
      fila.className = 'aq-asistencia-fila';
      const nombre = document.createElement('strong');
      nombre.textContent = item.nombre;
      const horas = document.createElement('span');
      horas.textContent = `Entrada ${hora.format(new Date(item.entrada))} · ${item.salida ? 'Salida ' + hora.format(new Date(item.salida)) : 'Salida pendiente'}`;
      fila.append(nombre, horas);
      registros.append(fila);
    }
  }

  async function actualizar({inicial = false, informe = false} = {}) {
    if (!CU?.id || consultando) return;
    consultando = true;
    fecha.disabled = true;
    ultimoIntento = Date.now();
    reintentar.hidden = true;
    try {
      const fechaInforme = informe && esJefe() ? fecha.value || hoy() : null;
      estado = await rpc('aq_asistencia_estado_v1', {p_fecha: fechaInforme});
      if (!fecha.value) fecha.value = estado.hoy;
      if (fechaInforme) mostrarRegistros(estado.registros);
      mensaje.textContent = '';
      renderizar();
      return true;
    } catch (error) {
      renderizar();
      if (!estado) estadoTexto.textContent = 'Estado de asistencia sin confirmar.';
      mensaje.textContent = error.message;
      reintentar.hidden = false;
    } finally {
      consultando = false;
      fecha.disabled = false;
      if (inicial) app.inert = false;
    }
  }

  function coordenadas() {
    return new Promise((resolve, reject) => {
      if (!navigator.geolocation) {
        reject(new Error('Este dispositivo no tiene acceso a la ubicación.'));
        return;
      }
      navigator.geolocation.getCurrentPosition(({coords}) => resolve({
        p_lat: coords.latitude, p_lon: coords.longitude, p_precision: coords.accuracy
      }), error => reject(new Error(error.code === 1
        ? 'Permite el acceso a la ubicación del navegador y vuelve a intentar.'
        : 'No se obtuvo la ubicación. Enciende el GPS y vuelve a intentar.')),
      {enableHighAccuracy: true, timeout: 15000, maximumAge: 0});
    });
  }

  async function guardar(accion, alConfirmar) {
    if (guardando || consultando) return;
    guardando = true;
    renderizar();
    mensaje.textContent = 'Guardando…';
    try {
      await accion();
      mensaje.textContent = '';
      if (await actualizar({informe: esJefe()})) alConfirmar?.();
    } catch (error) {
      await actualizar({informe: false});
      mensaje.textContent = error.message;
    } finally {
      guardando = false;
      renderizar();
    }
  }

  function revisarAlVolver() {
    if (!document.hidden && CU?.id && !guardando && Date.now() - ultimoIntento > 20000) {
      void actualizar({informe: esJefe() && modal.open});
    }
  }

  boton.addEventListener('click', () => {
    abrir();
    void actualizar({informe: esJefe()});
  });
  marcar.addEventListener('click', () => {
    const tipo = estado.marca ? 'salida' : 'entrada';
    const dia = estado.hoy;
    void guardar(async () => {
      mensaje.textContent = 'Obteniendo ubicación…';
      await rpc('aq_asistencia_marcar_v1', {p_tipo: tipo, p_fecha: dia, ...await coordenadas()});
    }, () => {
      if (tipo === 'entrada' && !obligatorio && modal.open) modal.close();
      showNotif(tipo === 'entrada' ? 'Entrada registrada' : 'Salida registrada');
    });
  });
  ubicacion.addEventListener('click', () => {
    if (estado.ubicacion_guardada && !confirm('¿Guardar tu ubicación actual como nuevo punto de marcación?')) return;
    void guardar(async () => {
      mensaje.textContent = 'Obteniendo ubicación del negocio…';
      await rpc('aq_asistencia_configurar_v1', {p_accion: 'ubicacion', ...await coordenadas()});
    });
  });
  activar.addEventListener('click', () => {
    const accion = estado.activo ? 'desactivar' : 'activar';
    if (accion === 'activar' && !confirm('¿Pedir al personal que marque su entrada al acceder al sistema?')) return;
    void guardar(() => rpc('aq_asistencia_configurar_v1', {p_accion: accion}));
  });
  cerrar.addEventListener('click', () => modal.close());
  salir.addEventListener('click', () => void doLogout());
  reintentar.addEventListener('click', () => {
    mensaje.textContent = '';
    void actualizar({informe: esJefe()});
  });
  fecha.addEventListener('change', () => {
    registros.replaceChildren();
    void actualizar({informe: true});
  });
  modal.addEventListener('cancel', event => {
    if (obligatorio || guardando) event.preventDefault();
  });
  document.addEventListener('visibilitychange', revisarAlVolver);
  window.addEventListener('focus', revisarAlVolver);
  setInterval(revisarAlVolver, 60000);

  window.aqIniciarAsistencia = () => {
    if (!esJefe()) app.inert = true;
    void actualizar({inicial: true});
  };
  if (app.classList.contains('show')) window.aqIniciarAsistencia();
})();
