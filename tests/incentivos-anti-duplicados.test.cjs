const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');

const src = fs.readFileSync('js/aq-incentivos-anti-duplicados.js', 'utf8');
new vm.Script(src);

const elementos = new Map();
const boton = { disabled:false, title:'' };
const origen = { id:'aq-inc-creado', parentNode:{}, insertAdjacentElement(where,elemento) {
  elementos.set(elemento.id,elemento);
} };
elementos.set('aq-inc-creado',origen);
const selector={id:'aq-inc-cliente',value:'358'};
elementos.set('aq-inc-cliente',selector);
let autorizaciones=0;
let resultadoServidor=null;
const avisos=[];
const c = {
 window: {
  aqIncMostrarCaptacion(){},
  aqIncPintar(){},
  async aqGuardarIncentivo(){autorizaciones++;},
 },
 aqIncCache:{
  incentivos:[
    {id:13,cliente_id:358,activo:true},
    {id:9,cliente_id:355,activo:false}
  ]
 },
 document:{
   getElementById: id=>elementos.get(id)||null,
   querySelector: css=> css.includes('aqGuardarIncentivo') ? boton : null,
   createElement: ()=>({
     id:'',style:{},textContent:'',setAttribute(){},insertAdjacentElement(){}
   }),
 },
 aqIncNombreCli: id=>id===358?'Daniel Perú':id===355?'Glendy Cabañas':'Cliente '+id,
 sb:{
  async rpc(nombre){
    assert.equal(nombre,'aq_estado_incentivos');
    return {data:resultadoServidor,error:null};
  }
 },
 aqIncAuth:()=>({p_uid:1,p_token:'test'}),
 showNotif: message=>avisos.push(message),
 console,
};
vm.runInNewContext(src,c);
const test=async()=>{
  c.window.aqIncMostrarCaptacion();
  assert.equal(boton.disabled,true,'Ya autorizado debe bloquear botón');
  assert.match(elementos.get('aq-inc-aviso-duplicado').textContent,/ya fue agregado/i);
  await c.window.aqGuardarIncentivo();
  assert.equal(autorizaciones,0,'No debe guardar un duplicado activo');

  selector.value='355';c.window.aqIncMostrarCaptacion();
  assert.equal(boton.disabled,true,'Autorización finalizada también debe impedir reautorizar accidentalmente');
  await c.window.aqGuardarIncentivo();
  assert.equal(autorizaciones,0);

  selector.value='777';c.window.aqIncMostrarCaptacion();
  assert.equal(boton.disabled,false,'Cliente nuevo debe poder autorizarse');
  resultadoServidor={incentivos:[...c.aqIncCache.incentivos,{id:15,cliente_id:777,activo:true}]};
  await c.window.aqGuardarIncentivo();
  assert.equal(autorizaciones,0,'Otro usuario autorizó mientras formulario abierto: bloquear');

  selector.value='888';c.window.aqIncMostrarCaptacion();
  resultadoServidor={incentivos:[...c.aqIncCache.incentivos]};
  await c.window.aqGuardarIncentivo();
  assert.equal(autorizaciones,1,'Cliente realmente nuevo puede autorizarse');
  assert.ok(avisos.some(x=>/ya tiene un incentivo registrado/.test(x)));
  console.log('Prueba anti-duplicados: OK');
};
test().catch(e=>{console.error(e);process.exitCode=1;});
