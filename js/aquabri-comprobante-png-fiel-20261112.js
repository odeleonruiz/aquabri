/* AQUABRI · Comprobante sencillo · 2026-11-13
   Restaurar tres acciones: Compartir nativo, Descargar y Cerrar.
   No modifica ventas, caja, datos ni servicios Supabase.
   La imagen conserva el comprobante realmente visible. */
(function(){
  'use strict';
  let trabajo=null;
  let compartirPendiente=null;
  const esperar=ms=>new Promise(resolve=>setTimeout(resolve,ms));
  const estaAbierto=id=>!!document.getElementById(id)?.classList.contains('open');
  const documento=()=>window.aqDocumentoVisible?.();
  const nombre=()=>{
    const original=window.aqNombrePNGComprobante?.()||'aquabri_comprobante.png';
    return String(original).replace(/\.png$/i,'.jpg');
  };
  function aviso(msg){
    if(typeof window.showNotif==='function')window.showNotif(msg,'#b42318');
    else console.warn('AQUABRI comprobante:',msg);
  }
  function botones(ocupados){
    for(const id of ['modal-ticket','modal-saldo_pendiente']){
      const modal=document.getElementById(id);
      if(!modal?.classList.contains('open'))continue;
      modal.querySelectorAll('button[onclick*="compartirImagenComprobante"],button[onclick*="descargarTicketPDF"]').forEach(btn=>{
        // No reemplazar nunca el texto, no añadir controles ni ventanitas.
        // No impedir el toque del usuario: si el JPG sigue generándose,
        // el toque quedará pendiente y se intentará compartir al terminar.
        btn.disabled=false;
        if(ocupados)btn.setAttribute('aria-busy','true');
        else btn.removeAttribute('aria-busy');
      });
    }
  }
  const idDe=el=>el?.innerHTML||'';
  async function cargarImagenes(el){
    const imgs=Array.from(el.querySelectorAll('img'));
    await Promise.all(imgs.map(img=>{
      if(img.complete)return Promise.resolve();
      return Promise.race([
        new Promise(resolve=>{
          img.addEventListener('load',resolve,{once:true});
          img.addEventListener('error',resolve,{once:true});
        }),
        esperar(1000)
      ]);
    }));
  }
  async function canvasExacto(el){
    if(!el?.isConnected)throw Error('Comprobante no disponible.');
    // La librería está guardada localmente; se precarga desde el inicio.
    const pintar=await window.cargarHtml2Canvas();
    if(document.fonts?.ready)await Promise.race([document.fonts.ready,esperar(450)]);
    await cargarImagenes(el);
    const r=el.getBoundingClientRect();
    const width=Math.ceil(r.width);
    const height=Math.ceil(Math.max(r.height,el.scrollHeight));
    if(width<50||height<50)throw Error('No está visible el comprobante.');
    // Captura a resolución suficiente sin agotar memoria en teléfonos.
    const escala=Math.max(.65,Math.min(window.devicePixelRatio||1,1.25,
      Math.sqrt(4500000/(width*height)),6000/height,6000/width));
    // html2canvas clona el documento de la aplicación (mucho mayor que el
    // recibo). Omitir ramas de la interfaz que no son el ticket reduce la
    // clonación sin alterar las hojas de estilo ni el contenido del recibo.
    const ruta=new Set();
    for(let nodo=el;nodo;nodo=nodo.parentElement)ruta.add(nodo);
    const ignorar=nodo=>{
      if(nodo?.ownerDocument?.head?.contains(nodo))return false;
      return !ruta.has(nodo)&&!el.contains(nodo);
    };
    const opts={
      backgroundColor:'#ffffff',width,height,scale:escala,
      windowWidth:window.innerWidth,windowHeight:window.innerHeight,
      ignoreElements:ignorar,
      useCORS:true,allowTaint:false,imageTimeout:1200,
      logging:false,foreignObjectRendering:false
    };
    let timeout;
    try{
      const imagen=await Promise.race([
        pintar(el,opts),
        new Promise((_,rechazar)=>{
          timeout=setTimeout(()=>rechazar(Error('No se pudo capturar el comprobante.')),12000);
        })
      ]);
      if(!imagen||imagen.width<50||imagen.height<50)throw Error('Imagen vacía.');
      return imagen;
    }finally{clearTimeout(timeout);}
  }
  async function convertirJPG(canvas){
    return await new Promise((resolve,reject)=>{
      let finalizado=false;
      let timeout;
      const terminar=(blob,error)=>{
        if(finalizado)return;
        finalizado=true;
        clearTimeout(timeout);
        if(blob?.size>100&&blob.type==='image/jpeg')resolve(blob);
        else reject(error||Error('No se pudo convertir el comprobante.'));
      };
      const alternativa=()=>{
        if(finalizado)return;
        try{
          const url=canvas.toDataURL('image/jpeg',.92);
          if(!url.startsWith('data:image/jpeg;base64,'))throw Error('JPG inválido.');
          const bin=atob(url.split(',')[1]);
          const data=new Uint8Array(bin.length);
          for(let i=0;i<bin.length;i++)data[i]=bin.charCodeAt(i);
          terminar(new Blob([data],{type:'image/jpeg'}));
        }catch(e){terminar(null,e);}
      };
      timeout=setTimeout(alternativa,1800);
      try{
        if(typeof canvas.toBlob!=='function')return alternativa();
        canvas.toBlob(blob=>blob?.size>100&&blob.type==='image/jpeg'
          ?terminar(blob):alternativa(),'image/jpeg',.92);
      }catch(e){alternativa();}
    });
  }
  function preparar(el){
    if(!el)return Promise.reject(Error('No hay comprobante visible.'));
    const id=idDe(el);
    if(trabajo?.el===el&&trabajo.id===id)return trabajo.promesa;
    const nuevo={el,id,blob:null,promesa:null};
    trabajo=nuevo;
    botones(true);
    nuevo.promesa=(async()=>{
      const canvas=await canvasExacto(el);
      const blob=await convertirJPG(canvas);
      if(trabajo!==nuevo||idDe(el)!==id||!el.isConnected)
        throw Error('El comprobante cambió.');
      nuevo.blob=blob;
      botones(false);
      return blob;
    })();
    nuevo.promesa.catch(e=>{
      if(trabajo===nuevo){
        trabajo=null;
        botones(false); // Permitir reintentar con el mismo botón.
        console.warn('Comprobante AQUABRI:',e);
      }
    });
    return nuevo.promesa;
  }
  function listo(el){
    return trabajo?.el===el&&trabajo.id===idDe(el)?trabajo.blob:null;
  }
  function descargar(blob,filename){
    const url=URL.createObjectURL(blob);
    const a=document.createElement('a');
    a.href=url;a.download=filename;a.style.display='none';
    document.body.appendChild(a);
    a.click();a.remove();
    setTimeout(()=>URL.revokeObjectURL(url),60000);
  }
  function compartirNativo(blob,filename){
    if(typeof File!=='function'||typeof navigator.share!=='function'){
      aviso('Este navegador no admite compartir archivos. Usa Descargar.');
      return;
    }
    try{
      const archivo=new File([blob],filename,{type:'image/jpeg'});
      if(typeof navigator.canShare==='function'&&!navigator.canShare({files:[archivo]})){
        aviso('No se pueden compartir imágenes desde este navegador. Usa Descargar.');
        return;
      }
      // CRÍTICO: ejecutar navigator.share en este toque, sin await previo.
      navigator.share({files:[archivo],title:'Comprobante AQUABRI'})
        .catch(e=>{if(e?.name!=='AbortError'){console.warn('Compartir comprobante:',e);aviso('No se abrió el menú nativo. Intenta nuevamente.');}});
    }catch(e){console.warn('Compartir comprobante:',e);aviso('No se pudo compartir. Usa Descargar.');}
  }
  window.aqPrecalentarPNGComprobante=function(el){
    if(el)preparar(el).catch(()=>{});
  };
  window.compartirImagenComprobante=function(){
    if(!window.aqValidarDetalleVentaComprobante?.())return false;
    const el=documento();
    if(!el)return false;
    const blob=listo(el);
    if(blob){
      // Imagen preparada: abrir hoja nativa en este mismo gesto, SIN esperas.
      compartirNativo(blob,nombre());
      return false;
    }
    // El usuario ya tocó Compartir: no obligarlo a tocar dos veces.
    // Si la captura termina mientras sigue activa la autorización temporal
    // del toque de Safari, abrir la hoja automáticamente.
    const id=idDe(el);
    if(compartirPendiente?.el===el&&compartirPendiente.id===id)return false;
    const solicitud={el,id};
    compartirPendiente=solicitud;
    preparar(el).then(imagen=>{
      if(compartirPendiente!==solicitud||documento()!==el||idDe(el)!==id)return;
      if(navigator.userActivation?.isActive===false){
        aviso('Imagen lista. Toca Compartir otra vez para abrir el menú del iPhone.');
        return;
      }
      compartirNativo(imagen,nombre());
    }).catch(e=>{
      if(compartirPendiente===solicitud){
        console.warn('No se pudo preparar el comprobante:',e);
        aviso('No se pudo preparar la imagen. Intenta Compartir otra vez.');
      }
    }).finally(()=>{
      if(compartirPendiente===solicitud)compartirPendiente=null;
    });
    return false;
  };
  window.descargarTicketPDF=function(){
    if(!window.aqValidarDetalleVentaComprobante?.())return false;
    const el=documento();
    if(!el)return false;
    const blob=listo(el);
    if(blob){
      // iPhone/Safari instalado puede bloquear descargas programáticas de blob.
      // Usar su menú nativo: Guardar en Archivos / Guardar imagen.
      const ios=/iPhone|iPad|iPod/i.test(navigator.userAgent||'')||
        (/Macintosh/.test(navigator.userAgent||'')&&navigator.maxTouchPoints>1);
      if(ios&&typeof navigator.share==='function')compartirNativo(blob,nombre());
      else descargar(blob,nombre());
    }else preparar(el).catch(()=>aviso('No se pudo descargar el comprobante.'));
    return false;
  };
  // En los documentos abiertos de saldo/crédito la vista puede actualizarse
  // sin pasar por openModal. Solo vigilar cambios del ticket, no botones.
  function vigilar(){
    for(const [modalId,areaId] of [
      ['modal-ticket','ticket-print-area'],
      ['modal-saldo_pendiente','saldo_pendiente-print-area']
    ]){
      const area=document.getElementById(areaId);
      if(!area||typeof MutationObserver!=='function')continue;
      const observer=new MutationObserver(()=>{
        if(!estaAbierto(modalId))return;
        const el=documento();
        if(el)preparar(el).catch(()=>{});
      });
      observer.observe(area,{childList:true,subtree:true});
    }
  }
  const inicio=()=>{
    window.cargarHtml2Canvas?.().catch(()=>{});
    vigilar();
  };
  if(document.readyState==='loading')
    document.addEventListener('DOMContentLoaded',inicio,{once:true});
  else inicio();
})();