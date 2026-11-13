/* AQUABRI · Compartir comprobantes JPG · 2026-11-13
   Sólo captura y comparte la vista REAL; no escribe en Supabase ni cambia ventas. */
(function(){
'use strict';
let actual=null, enlaceURL=null, enlaceNombre='';
const esIOS=()=>/iP(hone|ad|od)/.test(navigator.userAgent||'') ||
  (/Macintosh/.test(navigator.userAgent||'')&&navigator.maxTouchPoints>1);
const delay=ms=>new Promise(r=>setTimeout(r,ms));
const visible=()=>window.aqDocumentoVisible();
function firma(el){
  if(!el)return '';
  // El CSS responsive puede reajustar décimas el ancho en Safari sin que
  // cambie el comprobante. Evitar invalidar y recapturar por ese motivo.
  return el.innerHTML;
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
    a.style.cssText='display:none;margin:9px 0;padding:10px;text-align:center;background:#e8f5e9;color:#166534;border-radius:8px;font-weight:700;text-decoration:underline';
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
// El teléfono prepara la foto apenas se abre el comprobante: no se exige
// tocar Compartir dos veces ni se abre una ventana de espera adicional.
function botones(estadoActual){
  for(const id of ['modal-ticket','modal-saldo_pendiente']){
    const modal=document.getElementById(id);
    if(!modal?.classList.contains('open'))continue;
    const controles=modal.querySelectorAll('button[onclick*="compartirImagenComprobante"],button[onclick*="descargarTicketPDF"]');
    controles.forEach(btn=>{
      if(!btn.dataset.aqJpgOriginal)btn.dataset.aqJpgOriginal=btn.innerHTML;
      btn.disabled=estadoActual==='preparando';
      if(estadoActual==='preparando'){
        btn.textContent='⏳ Preparando comprobante…';
        btn.setAttribute('aria-busy','true');
      }else{
        btn.innerHTML=btn.dataset.aqJpgOriginal;
        btn.removeAttribute('aria-busy');
        btn.title=estadoActual==='error'?'Toca para reintentar preparar el comprobante':'';
      }
    });
  }
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
  await Promise.race([
    new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r))),
    delay(450)
  ]);
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
  if(actual?.el===el&&actual.id===id&&actual.promesa){
    botones(actual.blob?'listo':'preparando');
    return actual.promesa;
  }
  // No reutilizar imagen de otro comprobante.
  const t={el,id,blob:null,promesa:null};
  actual=t;
  const anterior=document.querySelector('.aq-jpg-descarga-directa');
  if(anterior)anterior.remove();
  estado('');
  botones('preparando');
  t.promesa=(async()=>{
    const blob=await Promise.race([
      (async()=>{
        const canvas=await capturar(el);
        return await jpegBlob(canvas);
      })(),
      delay(18000).then(()=>{throw Error('La preparación no respondió. Toca de nuevo.');})
    ]);
    if(actual!==t||firma(el)!==id)throw Error('El comprobante cambió. Intenta de nuevo.');
    t.blob=blob;
    enlace(blob,nombreJPG());
    botones('listo');
    estado('');
    return blob;
  })();
  t.promesa.catch(err=>{
    if(actual===t){
      actual=null;
      botones('error');
      estado('No se pudo preparar la imagen. Toca Compartir o Descargar para reintentar.');
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
  a.style.display='block';
  a.focus();
  notificar('Tu celular no abrió Compartir. Usa «Guardar imagen JPG» como alternativa.');
}
window.aqCapturarComprobanteEnCanvas=capturar;
window.aqPrecalentarPNGComprobante=function(el){preparar(el).catch(()=>{});};
window.compartirImagenComprobante=function(){
  if(!window.aqValidarDetalleVentaComprobante())return false;
  const el=visible(),nombre=nombreJPG();
  if(!el)return false;
  const blob=listo(el);
  if(blob){
    // Safari iPhone y Chrome Android: hoja nativa en el mismo toque.
    compartir(blob,nombre).then(resultado=>{
      if(resultado==='fallo'||resultado==='sin_soporte')alternativa(blob,nombre);
    });
  }else{
    // Si el botón estaba habilitado después de un error, prepara la imagen.
    // Nunca abrir un diálogo artificial ni ofrecer un JPG con diseño distinto.
    preparar(el).catch(e=>notificar('No se pudo crear la imagen: '+(e?.message||e),'#c62828'));
  }
  return false;
};
window.descargarTicketPDF=function(){
  if(!window.aqValidarDetalleVentaComprobante())return false;
  const el=visible(),nombre=nombreJPG();
  if(!el)return false;
  const blob=listo(el);
  if(!blob){
    preparar(el).catch(e=>notificar('Error preparando comprobante: '+(e?.message||e),'#c62828'));
    return false;
  }
  // iOS no siempre admite un download de blob desde una PWA. Con el JPG
  // ya listo, la hoja nativa permite "Guardar imagen" o "Guardar en Archivos".
  if(esIOS()&&typeof navigator.share==='function'){
    compartir(blob,nombre).then(resultado=>{
      if(resultado==='fallo'||resultado==='sin_soporte'){
        const a=enlace(blob,nombre);
        if(a){a.style.display='block';a.click();}
      }
    });
    return false;
  }
  const a=enlace(blob,nombre);
  if(!a){notificar('No se encontró el botón para guardar.','#c62828');return false;}
  a.click();
  // En Android/PC, descarga directa; conservar acceso alternativo si se bloqueó.
  notificar('Se solicitó guardar el JPG.','#2e7d32');
  return false;
};
const preload=()=>window.cargarHtml2Canvas?.().catch(e=>console.warn('Precarga JPG:',e));
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',preload,{once:true});
else preload();
})();