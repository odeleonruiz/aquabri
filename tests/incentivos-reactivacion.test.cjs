const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const js = fs.readFileSync('js/aq-incentivos-reactivacion.js','utf8');
const resumen = fs.readFileSync('js/aq-incentivos-clientes-resumen.js','utf8');
const index = fs.readFileSync('index.html','utf8');
new vm.Script(js);
assert.match(resumen,/aqReactivarIncentivo\(/,'En clientes finalizados debe verse el botón Reactivar');
assert.match(index,/aq-incentivos-reactivacion.js/,'La aplicación debe cargar el nuevo script');

let rol='jefe';
let registros=[
  {id:4,cliente_id:358,captador_empleado_id:9,modalidad:'equipo',equipo_id:1,monto_unitario:2,precio_minimo:9,activo:false},
  {id:3,cliente_id:355,captador_empleado_id:9,modalidad:'equipo',equipo_id:1,monto_unitario:2,precio_minimo:9,activo:true}
];
let guardar=0;
let consultar=0;
let refrescar=0;
let respuesta={data:{incentivo_id:18,desde:'2026-11-22'},error:null};
let confirmando=true;
const alertas=[];
const contexto={
 window:{},console,
 get CU(){return {rol}},
 get aqIncCache(){return {incentivos:registros,equipos:[{id:1,nombre:'Equipo 1'}]}},
 aqIncNombreCli:id=>'Cliente '+id,
 aqIncNombreEmp:id=>'Empleado '+id,
 aqIncFmt:n=>'Q'+Number(n).toFixed(2),
 aqIncAuth:()=>({p_token:'token-de-prueba',p_uid:1}),
 confirm:()=>{consultar++;return confirmando;},
 showNotif:(m)=>alertas.push(m),
 sb:{rpc:async (name,payload)=>{assert.equal(name,'aq_reactivar_incentivo_jefe_v1');assert.equal(payload.p_confirmado,true);guardar++;return respuesta;}},
 aqIncRecargar:async()=>{refrescar++},
 aqIncVistaClientesRefrescar:async()=>{},
};
vm.createContext(contexto);
vm.runInContext(js,contexto);

(async()=>{
  await contexto.window.aqReactivarIncentivo(4);
  assert.equal(guardar,1,'Una reactivación debe enviar una sola solicitud');
  assert.equal(refrescar,1,'Debe recargar lista al confirmar');

  await contexto.window.aqReactivarIncentivo(3);
  assert.equal(guardar,1,'No debe reactivar cliente ya activo');

  rol='vendedor';
  await contexto.window.aqReactivarIncentivo(4);
  assert.equal(guardar,1,'Solo jefe puede abrir reactivación');

  rol='jefe';confirmando=false;
  await contexto.window.aqReactivarIncentivo(4);
  assert.equal(guardar,1,'Cancelar confirmación no debe guardar');

  confirmando=true;
  respuesta={data:null,error:new Error('No se puede duplicar')};
  await contexto.window.aqReactivarIncentivo(4);
  assert.equal(refrescar,1,'Error de servidor no debe hacer recarga de éxito');
  assert.ok(alertas.some(m=>/No se pudo reactivar/.test(m)));
  console.log('Pruebas de reactivación de incentivos: OK');
})().catch(e=>{console.error(e);process.exitCode=1});
