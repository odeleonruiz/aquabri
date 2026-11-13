/* AQUABRI · Comprobantes PNG fieles · 2026-11-12
   Solo afecta captura, descarga y compartir. No modifica ventas ni Supabase. */
(function(){
'use strict';
let actual=null;
let ultimaVistaUrl=null;
const tiempoMaximo=15000;
const espera=(ms)=>new Promise(resolve=>setTimeout(resolve,ms));

function elemento(){
  return window.aqDocumentoVisible();
}
function firma(el){
  const rect=el.getBoundingClientRect();
  return el.innerHTML+'|'+Math.round(rect.width*10)+'|'+
    document.documentElement.getAttribute('data-aq-theme');
}
function pie(){
  const m=document.getElementById('modal-saldo_pendiente');
  const id=m?.classList.contains('open')?'modal-saldo_pendiente':'modal-ticket';
  return document.querySelector('#'+id+' .mfoot');
}
function limpiarVista(){
  document.querySelectorAll('.aq-vista-png-real-v2').forEach(e=>e.remove());
  if(ultimaVistaUrl){
    const anterior=ultimaVistaUrl;
    ultimaVistaUrl=null;
    setTimeout(()=>URL.revokeObjectURL(anterior),120000);
  }
}
function botones(estado){
  for(const id of ['modal-ticket','modal-saldo_pendiente']){
    const m=document.getElementById(id);
    if(!m?.classList.contains('open'))continue;
    m.querySelectorAll('button[onclick*="compartirImagenComprobante"]').forEach(b=>{
      if(!b.dataset.aqTextoOriginal) b.dataset.aqTextoOriginal=b.innerHTML;
      b.disabled=false;
      if(estado==='preparando'){
        b.innerHTML=b.dataset.aqTextoOriginal;
        b.title='La imagen del mismo comprobante se está preparando';
      }else if(estado==='error'){
        b.innerHTML=b.dataset.aqTextoOriginal;
        b.title='Falló la captura; toca para reintentar';
      }else{
        b.innerHTML=b.dataset.aqTextoOriginal;
        b.title='PNG listo: comparte la misma imagen que ves en el comprobante';
      }
    });
  }
}
function vistaPNG(blob){
  const zona=pie();
  if(!zona)return;
  limpiarVista();
  const url=URL.createObjectURL(blob);
  ultimaVistaUrl=url;
  const detalles=document.createElement('details');
  detalles.className='aq-vista-png-real-v2';
  detalles.style.cssText='margin:10px 0;padding:10px;border:1px solid #bbd4f4;border-radius:9px;background:#f4f8ff;color:#193f70;font:12px system-ui,sans-serif;';
  const titulo=document.createElement('summary');
  titulo.textContent='👁 Ver la imagen exacta que se enviará';
  titulo.style.cssText='cursor:pointer;font-weight:700;padding:5px;';
  const img=document.createElement('img');
  img.src=url;img.alt='Imagen PNG real del comprobante AQUABRI';
  img.style.cssText='display:block;width:100%;height:auto;margin-top:9px;background:white;border:1px solid #d6dee8;border-radius:7px;-webkit-touch-callout:default';
  const texto=document.createElement('p');
  texto.textContent='Esta vista y el archivo enviado a WhatsApp usan exactamente el mismo PNG.';
  texto.style.cssText='margin:7px 0 0;color:#45617b';
  detalles.append(titulo,img,texto);
  zona.insertAdjacentElement('afterend',detalles);
}
async function esperarImagen(img){
  // Nunca bloquearse esperando 'load' de una imagen que ya terminó con error.
  if(img.complete)return;
  try{
    if(typeof img.decode==='function'){
      await Promise.race([img.decode().catch(()=>{}),espera(2200)]);
      if(img.complete)return;
    }
    await Promise.race([
      new Promise(resolve=>{
        img.addEventListener('load',resolve,{once:true});
        img.addEventListener('error',resolve,{once:true});
      }),
      espera(2200)
    ]);
  }catch(e){console.warn('Imagen del comprobante aún no disponible',e);}
}
async function capturarExactamente(el){
  if(!el||!el.isConnected)throw new Error('No hay un comprobante visible');
  const rect=el.getBoundingClientRect();
  const ancho=Math.max(1,Math.ceil(rect.width));
  const alto=Math.max(Math.ceil(rect.height),Math.ceil(el.scrollHeight));
  if(ancho<60||alto<60)throw new Error('El comprobante todavía no está visible');
  const libreria=await window.cargarHtml2Canvas();
  if(document.fonts?.ready)await Promise.race([document.fonts.ready,espera(2200)]);
  await Promise.all(Array.from(el.querySelectorAll('img')).map(esperarImagen));
  if(!el.isConnected)throw new Error('Se cerró el comprobante antes de capturarlo');
  // El tamaño del viewport del clon DEBE ser el del teléfono, no la altura
  // del ticket: forzar un alto mayor cambia los estilos responsive de Safari.
  const maxEscala=Math.min(2,Math.max(1,window.devicePixelRatio||1.5));
  const escala=Math.max(0.6,Math.min(maxEscala,
    Math.sqrt(8500000/(ancho*alto)),8192/alto,8192/ancho));
  const opciones={
    backgroundColor:'#ffffff',width:ancho,height:alto,
    windowWidth:window.innerWidth,windowHeight:window.innerHeight,
    scale:escala,useCORS:true,allowTaint:false,imageTimeout:4500,logging:false,
    foreignObjectRendering:false
  };
  let temporizador;
  try{
    const capturar=async()=>{
      try{return await libreria(el,opciones);}
      catch(err){
        console.warn('Captura principal falló; reintentando sin cambiar diseño:',err);
        return await libreria(el,{...opciones,scale:Math.min(1,escala),imageTimeout:1600});
      }
    };
    const canvas=await Promise.race([
      capturar(),
      new Promise((_,reject)=>{
        temporizador=setTimeout(()=>reject(new Error('La captura tardó demasiado')),tiempoMaximo);
      })
    ]);
    if(!canvas||canvas.width<60||canvas.height<60)
      throw new Error('No se pudo generar el PNG con el diseño original');
    // No usar el antiguo dibujo de texto como reemplazo: cambia el comprobante.
    return canvas;
  }finally{clearTimeout(temporizador);}
}
function preparar(el){
  if(!el)return Promise.reject(new Error('No se encontró el comprobante'));
  const id=firma(el);
  if(actual&&actual.el===el&&actual.id===id&&actual.promesa)return actual.promesa;
  limpiarVista();
  const trabajo={el,id,blob:null,promesa:null};
  actual=trabajo;
  botones('preparando');
  trabajo.promesa=(async()=>{
    const canvas=await capturarExactamente(el);
    const blob=await window.aqCanvasBlobSeguro(canvas);
    if(!blob||blob.size<100)throw new Error('El archivo PNG está vacío');
    if(actual===trabajo&&firma(el)===id){
      trabajo.blob=blob;
      botones('listo');
    }
    if(actual!==trabajo||firma(el)!==id)
      throw new Error('El comprobante cambió durante la captura');
    return blob;
  })();
  trabajo.promesa.catch(err=>{
    if(actual===trabajo){
      actual=null;
      botones('error');
      console.error('Comprobante PNG AQUABRI:',err);
      if(typeof window.showNotif==='function')window.showNotif('No se preparó el PNG; toca Compartir para reintentar.','#c62828');
    }
  });
  return trabajo.promesa;
}
function blobListo(el){
  return actual&&actual.el===el&&actual.id===firma(el)?actual.blob:null;
}
window.aqCapturarComprobanteEnCanvas=capturarExactamente;
window.aqPrecalentarPNGComprobante=function(el){
  preparar(el).catch(()=>{});
};
window.descargarTicketPDF=async function(){
  if(!window.aqValidarDetalleVentaComprobante())return false;
  const el=elemento();
  const btn=document.activeElement instanceof HTMLButtonElement?document.activeElement:null;
  if(btn){btn.disabled=true;}
  try{
    const png=await preparar(el);
    const enlaces=window.aqMostrarEnlacesComprobante(png,window.aqNombrePNGComprobante());
    window.aqSolicitarDescargaPNG(enlaces);
    window.showNotif('✅ Imagen PNG lista para descargar.','#2e7d32');
    return true;
  }catch(err){
    alert('No se pudo generar el mismo comprobante: '+(err?.message||err));
    return false;
  }finally{if(btn)btn.disabled=false;}
};
function mostrarPanelCompartir(el,nombre){
  document.getElementById('aq-panel-compartir-fiel')?.remove();
  const capa=document.createElement('div');
  capa.id='aq-panel-compartir-fiel';
  capa.setAttribute('role','dialog');
  capa.setAttribute('aria-label','Compartir comprobante AQUABRI');
  capa.style.cssText='position:fixed;inset:0;z-index:2147483647;display:flex;align-items:center;justify-content:center;background:#162737dc;padding:14px;box-sizing:border-box';
  const panel=document.createElement('div');
  panel.style.cssText='width:min(100%,490px);max-height:92dvh;overflow:auto;border-radius:13px;background:#fff;color:#203246;padding:17px;box-sizing:border-box;font:14px system-ui,sans-serif';
  const titulo=document.createElement('h3');titulo.textContent='Compartir comprobante';titulo.style.margin='0 0 8px';
  const estado=document.createElement('p');estado.textContent='Preparando la imagen original…';estado.setAttribute('role','status');
  const imagen=document.createElement('img');imagen.alt='Vista del PNG que vas a compartir';
  imagen.style.cssText='display:none;width:100%;max-height:52dvh;object-fit:contain;background:#fff;border:1px solid #dde4ed;border-radius:8px;margin:8px 0';
  const acciones=document.createElement('div');acciones.style.cssText='display:flex;gap:9px;flex-wrap:wrap;margin-top:12px';
  const compartir=document.createElement('button');compartir.type='button';compartir.textContent='Compartir imagen';
  compartir.disabled=true;compartir.style.cssText='padding:11px 14px;border:0;border-radius:8px;background:#25d366;color:#12351f;font-weight:700;cursor:pointer';
  const descargar=document.createElement('a');descargar.textContent='Descargar PNG';
  descargar.style.cssText='display:none;padding:11px 14px;border-radius:8px;background:#e7f1ff;color:#164c86;text-decoration:none;font-weight:700';
  const cerrar=document.createElement('button');cerrar.type='button';cerrar.textContent='Cerrar';
  cerrar.style.cssText='padding:11px 14px;border:0;border-radius:8px;background:#e5e9ee;color:#334155;cursor:pointer';
  let url=null;
  function salir(){
    capa.remove();
    if(url)setTimeout(()=>URL.revokeObjectURL(url),120000);
  }
  cerrar.onclick=salir;
  acciones.append(compartir,descargar,cerrar);
  panel.append(titulo,estado,imagen,acciones);capa.append(panel);document.body.appendChild(capa);
  preparar(el).then(blob=>{
    if(!capa.isConnected)return;
    url=URL.createObjectURL(blob);
    imagen.src=url;imagen.style.display='block';
    descargar.href=url;descargar.download=nombre;descargar.style.display='inline-block';
    compartir.disabled=false;estado.textContent='Imagen lista: es el mismo comprobante que ves en AQUABRI.';
    compartir.onclick=async()=>{
      // navigator.share se llama DIRECTAMENTE dentro del toque del botón.
      const resultado=await window.aqCompartirPNG(blob,nombre);
      if(resultado==='compartido'||resultado==='cancelado'){salir();return;}
      salir();
      window.aqAbrirAlternativaCompartirPNG(blob,nombre,
        window.aqErrorCompartirPNG||'El celular no permite compartir archivos');
    };
  }).catch(err=>{
    if(!capa.isConnected)return;
    estado.textContent='No se pudo generar el diseño original: '+(err?.message||err);
    compartir.disabled=false;compartir.textContent='Reintentar PNG';
    compartir.onclick=()=>{salir();mostrarPanelCompartir(el,nombre);};
  });
}
window.compartirImagenComprobante=async function(){
  if(!window.aqValidarDetalleVentaComprobante())return false;
  const el=elemento();
  if(!el)return false;
  const nombre=window.aqNombrePNGComprobante();
  const png=blobListo(el);
  if(!png){
    // Si aún se está preparando, mostrar progreso real y un botón que conserva
    // el gesto del usuario para la hoja nativa de iPhone/Android.
    mostrarPanelCompartir(el,nombre);
    return false;
  }
  const estado=await window.aqCompartirPNG(png,nombre);
  if(estado==='compartido')return true;
  if(estado==='cancelado')return false;
  window.aqAbrirAlternativaCompartirPNG(png,nombre,
    window.aqErrorCompartirPNG||'El navegador no abrió el menú de compartir');
  return false;
};
const precargar=()=>{window.cargarHtml2Canvas?.().catch(err=>console.warn('Capturador PNG pendiente:',err));};
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',precargar,{once:true});
else precargar();
})();