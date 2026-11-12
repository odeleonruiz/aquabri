/* AQUABRI · Comprobantes PNG fieles · 2026-11-12
   Solo afecta captura, descarga y compartir. No modifica ventas ni Supabase. */
(function(){
'use strict';
let actual=null;
let ultimaVistaUrl=null;
const tiempoMaximo=26000;
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
      b.disabled=estado==='preparando';
      if(estado==='preparando'){
        b.textContent='⏳ Generando imagen PNG…';
        b.title='La imagen del mismo comprobante se está preparando';
      }else if(estado==='error'){
        b.textContent='🔁 Reintentar compartir';
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
  if(img.complete && img.naturalWidth>0)return;
  await Promise.race([
    (async()=>{
      if(typeof img.decode==='function') {try {await img.decode();return;}catch(e){}}
      await new Promise(resolve=>{
        img.addEventListener('load',resolve,{once:true});
        img.addEventListener('error',resolve,{once:true});
      });
    })(),
    espera(4500)
  ]);
}
async function capturarExactamente(el){
  if(!el)throw new Error('No hay ningún comprobante abierto');
  const libreria=await window.cargarHtml2Canvas();
  if(document.fonts?.ready)await Promise.race([document.fonts.ready,espera(3000)]);
  await Promise.all(Array.from(el.querySelectorAll('img')).map(esperarImagen));
  // Capturar el documento visible, nunca reconstruir otro ticket a partir de texto.
  const rc=el.getBoundingClientRect();
  const ancho=Math.max(1,Math.ceil(rc.width));
  const alto=Math.max(Math.ceil(rc.height),Math.ceil(el.scrollHeight));
  if(ancho<60||alto<60)throw new Error('El comprobante todavía no está visible');
  let temporizador;
  try{
    const canvas=await Promise.race([
      libreria(el,{
        backgroundColor:'#ffffff',width:ancho,height:alto,
        windowWidth:document.documentElement.clientWidth||window.innerWidth,
        windowHeight:Math.max(document.documentElement.clientHeight,alto),
        scale:Math.min(2,Math.max(1,1400/ancho)),
        useCORS:true,allowTaint:false,imageTimeout:8000,logging:false
      }),
      new Promise((_,reject)=>{
        temporizador=setTimeout(()=>reject(new Error('La captura tardó demasiado')),tiempoMaximo);
      })
    ]);
    if(!canvas||canvas.width<60||canvas.height<60)throw new Error('El PNG resultó vacío');
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
      vistaPNG(blob);
      botones('listo');
    }
    return blob;
  })();
  trabajo.promesa.catch(err=>{
    if(actual===trabajo){
      actual=null;
      botones('error');
      console.error('Comprobante PNG AQUABRI:',err);
      window.showNotif('No se generó el PNG; toca Reintentar compartir.','#c62828');
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
window.compartirImagenComprobante=async function(){
  if(!window.aqValidarDetalleVentaComprobante())return false;
  const el=elemento();
  const png=el?blobListo(el):null;
  if(!png){
    try{
      await preparar(el);
      window.showNotif('✅ Imagen lista. Toca Compartir imagen para abrir WhatsApp.','#2e7d32');
    }catch(err){
      alert('No se pudo generar el comprobante: '+(err?.message||err));
    }
    return false;
  }
  // El menú nativo debe abrirse directamente desde el toque, sin esperar otra captura.
  const nombre=window.aqNombrePNGComprobante();
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