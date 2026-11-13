/* AQUABRI · Compartir comprobantes JPG · 2026-11-13
   Sólo captura y comparte la vista REAL; no escribe en Supabase ni cambia ventas. */
(function(){
'use strict';
let actual=null, enlaceURL=null, enlaceNombre='';
const delay=ms=>new Promise(r=>setTimeout(r,ms));
const visible=()=>window.aqDocumentoVisible();
function firma(el){
  if(!el)return '';
  const r=el.getBoundingClientRect();
  return el.innerHTML+'|'+Math.round(r.width*10)+'|'+
    document.documentElement.getAttribute('data-aq-theme');
}
function pie(){
  const saldo=document.getElementById('modal-saldo_pendiente');
  const id=saldo?.classList.contains('open')?'modal-saldo_pendiente':'modal-ticket';
  return document.querySelector('#'+id+' .mfoot');
}
function nombreJPG(){
  return String(window.aqNombrePNGComprobante?.()||'aquabri_comprobante.png')
    .replace(/\.png$/i,'.jpg');
}
function notificar(texto,color){
  if(typeof window.showNotif==='function')window.showNotif(texto,color||'#1565c0');
}
function enlace(blob,nombre){
  const zona=pie();
  if(!zona)return null;
  let a=zona.parentElement.querySelector('.aq-jpg-descarga-directa');
  if(!a){
    a=document.createElement('a');
    a.className='aq-jpg-descarga-directa';
    a.textContent='⬇ Guardar imagen JPG';
    a.style.cssText='display:block;margin:9px 0;padding:10px;text-align:center;background:#e8f5e9;color:#166534;border-radius:8px;font-weight:700;text-decoration:underline';
    zona.insertAdjacentElement('afterend',a);
  }
  if(enlaceURL&&enlaceNombre!==nombre){
    const anterior=enlaceURL;
    setTimeout(()=>URL.revokeObjectURL(anterior),120000);
    enlaceURL=null;
  }
  if(!enlaceURL||a.dataset.aqFirma!==actual?.id){
    if(enlaceURL)setTimeout(()=>URL.revokeObjectURL(enlaceURL),120000);
    enlaceURL=URL.createObjectURL(blob);
  }
  a.href=enlaceURL;
  a.download=nombre;
  a.dataset.aqFirma=actual?.id||'';
  enlaceNombre=nombre;
  return a;
}
function estado(texto){
  const zona=pie();
  if(!zona)return;
  let n=zona.parentElement.querySelector('.aq-jpg-estado');
  if(!n){
    n=document.createElement('div');
    n.className='aq-jpg-estado';
    n.setAttribute('role','status');
    n.style.cssText='font:12px system-ui,sans-serif;text-align:center;color:#315273;margin:5px 0';
    zona.insertAdjacentElement('beforebegin',n);
  }
  n.textContent=texto||'';
}
async function esperarImagen(img){
  if(img.complete)return;
  try{
    await Promise.race([
      typeof img.decode==='function'?img.decode().catch(()=>{}):
        new Promise(r=>{img.addEventListener('load',r,{once:true});img.addEventListener('error',r,{once:true});}),
      delay(2200)
    ]);
  }catch(e){}
}
async function capturar(el){
  if(!el||!el.isConnected)throw Error('No hay comprobante abierto.');
  const lib=await window.cargarHtml2Canvas();
  // Esperar a que Safari termine layout/fuentes/logotipo.
  await new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r)));
  if(document.fonts?.ready)await Promise.race([document.fonts.ready,delay(2200)]);
  await Promise.all(Array.from(el.querySelectorAll('img')).map(esperarImagen));
  if(!el.isConnected)throw Error('Se cerró el comprobante.');
  const rect=el.getBoundingClientRect();
  const width=Math.ceil(rect.width),height=Math.ceil(Math.max(rect.height,el.scrollHeight));
  if(width<60||height<60)throw Error('El comprobante aún no está visible.');
  const scale=Math.max(.65,Math.min(2,window.devicePixelRatio||1.5,
    Math.sqrt(7500000/(width*height)),8192/width,8192/height));
  const opts={
    backgroundColor:'#fff',width,height,scale,
    windowWidth:window.innerWidth,windowHeight:window.innerHeight,
    useCORS:true,allowTaint:false,imageTimeout:3800,logging:false,
    foreignObjectRendering:false
  };
  let t;
  try{
    const run=async()=>{
      try{return await lib(el,opts);}
      catch(e){
        console.warn('JPG AQUABRI: reintentando captura visual',e);
        return await lib(el,{...opts,scale:Math.min(1,scale),imageTimeout:1400});
      }
    };
    const canvas=await Promise.race([
      run(),
      new Promise((_,reject)=>{t=setTimeout(()=>reject(Error('La captura tardó demasiado.')),14000);})
    ]);
    if(!canvas||canvas.width<60||canvas.height<60)
      throw Error('No se pudo capturar el comprobante original.');
    return canvas;
  }finally{clearTimeout(t);}
}
function jpegBlob(canvas){
  return new Promise((resolve,reject)=>{
    let terminado=false;
    const finish=(blob,err)=>{
      if(terminado)return;
      terminado=true;clearTimeout(timer);
      if(blob&&blob.size>100&&blob.type==='image/jpeg')resolve(blob);
      else reject(err||Error('El teléfono no pudo guardar el JPG.'));
    };
    const respaldo=()=>{
      if(terminado)return;
      try{
        const data=canvas.toDataURL('image/jpeg',.94);
        if(!data.startsWith('data:image/jpeg;base64,'))
          throw Error('El navegador no admitió JPEG.');
        const bin=atob(data.split(',')[1]);
        const bytes=new Uint8Array(bin.length);
        for(let i=0;i<bin.length;i++)bytes[i]=bin.charCodeAt(i);
        finish(new Blob([bytes],{type:'image/jpeg'}));
      }catch(e){finish(null,e);}
    };
    const timer=setTimeout(respaldo,2500);
    try{
      if(typeof canvas.toBlob!=='function'){respaldo();return;}
      canvas.toBlob(blob=>{
        if(blob?.size>100&&blob.type==='image/jpeg')finish(blob);
        else respaldo();
      },'image/jpeg',.94);
    }catch(e){respaldo();}
  });
}
function preparar(el){
  if(!el)return Promise.reject(Error('No hay comprobante abierto.'));
  const id=firma(el);
  if(actual?.el===el&&actual.id===id&&actual.promesa)return actual.promesa;
  // No reutilizar imagen de otro comprobante.
  const t={el,id,blob:null,promesa:null};
  actual=t;
  const anterior=document.querySelector('.aq-jpg-descarga-directa');
  if(anterior)anterior.remove();
  estado('');
  t.promesa=(async()=>{
    const canvas=await capturar(el);
    const blob=await jpegBlob(canvas);
    if(actual!==t||firma(el)!==id)throw Error('El comprobante cambió. Intenta de nuevo.');
    t.blob=blob;
    enlace(blob,nombreJPG());
    estado('');
    return blob;
  })();
  t.promesa.catch(err=>{
    if(actual===t){
      actual=null;
      estado('');
      console.warn('AQUABRI JPG:',err);
    }
  });
  return t.promesa;
}
function listo(el){
  return actual?.el===el&&actual.id===firma(el)?actual.blob:null;
}
async function compartir(blob,nombre){
  if(typeof File!=='function'||typeof navigator.share!=='function')return 'sin_soporte';
  try{
    const file=new File([blob],nombre,{type:'image/jpeg'});
    if(navigator.canShare&&!navigator.canShare({files:[file]}))return 'sin_soporte';
    // Llamar navigator.share sin trabajo asíncrono previo, durante el toque.
    await navigator.share({files:[file],title:'Comprobante AQUABRI'});
    return 'compartido';
  }catch(e){
    if(e?.name==='AbortError')return 'cancelado';
    console.warn('Compartir JPG:',e);
    return 'fallo';
  }
}
function alternativa(blob,nombre){
  const a=enlace(blob,nombre);
  if(!a)return;
  a.focus();
  notificar('Imagen JPG lista. Toca «Guardar imagen JPG» para guardarla o compartirla.');
}
window.aqCapturarComprobanteEnCanvas=capturar;
window.aqPrecalentarPNGComprobante=function(el){preparar(el).catch(()=>{});};
window.compartirImagenComprobante=function(){
  if(!window.aqValidarDetalleVentaComprobante())return false;
  const el=visible(),nombre=nombreJPG();
  if(!el)return false;
  const blob=listo(el);
  if(blob){
    // Ruta rápida habitual: un toque -> hoja nativa (WhatsApp, Guardar Imagen).
    compartir(blob,nombre).then(resultado=>{
      if(resultado==='fallo'||resultado==='sin_soporte')alternativa(blob,nombre);
    });
  }else{
    // Sin cuadro extra: terminar la imagen y presentar el acceso directo.
    estado('Preparando JPG…');
    preparar(el).then(async imagen=>{
      estado('');
      // Puede perder la activación del toque en Safari: en ese caso dejar enlace.
      const resultado=await compartir(imagen,nombre);
      if(resultado==='fallo'||resultado==='sin_soporte')alternativa(imagen,nombre);
    }).catch(e=>{
      estado('No se pudo generar la imagen. Vuelve a tocar Compartir.');
      notificar('Error al generar JPG: '+(e?.message||e),'#c62828');
    });
  }
  return false;
};
window.descargarTicketPDF=function(){
  if(!window.aqValidarDetalleVentaComprobante())return false;
  const el=visible(),nombre=nombreJPG();
  if(!el)return false;
  const descargar=blob=>{
    const a=enlace(blob,nombre);
    if(!a)throw Error('No se encontró el botón para guardar.');
    // En Android/PC se descarga; en Safari queda además el enlace real para tocar.
    a.click();
    notificar('Imagen JPG lista. Si no se guardó, toca «Guardar imagen JPG».','#2e7d32');
  };
  const blob=listo(el);
  if(blob){try{descargar(blob);}catch(e){notificar(e.message,'#c62828');}}
  else{
    estado('Preparando JPG…');
    preparar(el).then(descargar).catch(e=>{
      estado('No se pudo generar el JPG.');
      notificar('Error al guardar JPG: '+(e?.message||e),'#c62828');
    });
  }
  return false;
};
const preload=()=>window.cargarHtml2Canvas?.().catch(e=>console.warn('Precarga JPG:',e));
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',preload,{once:true});
else preload();
})();