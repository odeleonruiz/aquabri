const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');

const src = fs.readFileSync(path.join(__dirname, '..', 'js', 'aq-incentivos-clientes-resumen.js'), 'utf8');
const index = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');
assert.ok(index.includes('js/aq-incentivos-clientes-resumen.js'));
new vm.Script(src);

const nodes = new Map();
const el = (id, more={}) => ({id, innerHTML:'', value:'', className:'', addEventListener(){}, ...more});
nodes.set('aq-inc-lista',el('aq-inc-lista', {parentNode:{
  insertBefore(bar){
    nodes.set(bar.id,bar);
    for(const [id, value] of [
      ['aq-inc-cli-desde','2000-01-01'],['aq-inc-cli-hasta',''],
      ['aq-inc-cli-buscar',''],['aq-inc-cli-estado','todos'],['aq-inc-cli-mes',''],['aq-inc-cli-historico',''],
      ['aq-inc-cli-actualizar',''],['aq-inc-cli-totales','']]) nodes.set(id,el(id,{value}));
  }}}));
const document = {
  getElementById: id => nodes.get(id)||null,
  createElement: tag => el(''),
  head: {appendChild(n){if(n.id)nodes.set(n.id,n);}}
};
const movimientos = [
  {id:1,venta_id:11,venta_item_id:101,cliente_id:5,empleado_id:9,cantidad:3,importe_empleado:3,pago_id:null,precio_venta:9,fecha:'2026-11-01'},
  {id:2,venta_id:11,venta_item_id:101,cliente_id:5,empleado_id:10,cantidad:3,importe_empleado:3,pago_id:null,precio_venta:9,fecha:'2026-11-01'},
  {id:3,venta_id:12,venta_item_id:102,cliente_id:5,empleado_id:9,cantidad:1,importe_empleado:1,pago_id:null,precio_venta:9,fecha:'2026-11-02'},
  {id:4,venta_id:12,venta_item_id:102,cliente_id:5,empleado_id:10,cantidad:1,importe_empleado:1,pago_id:null,precio_venta:9,fecha:'2026-11-02'},
  {id:5,venta_id:13,venta_item_id:103,cliente_id:5,empleado_id:9,cantidad:2,importe_empleado:2,pago_id:null,precio_venta:9,fecha:'2026-11-02'}
];
const context = {
  window: {aqIncPintar() {}},
  document,
  console,
  aqIncCache: {
    equipos:[{id:1,nombre:'Equipo 1',empleado_a_id:9,empleado_b_id:10}],
    incentivos:[
      {id:1,cliente_id:5,producto_id:1,captador_empleado_id:9,equipo_id:1,modalidad:'equipo',monto_unitario:2,activo:false,desde:'2026-10-01',hasta:'2026-11-01'},
      {id:2,cliente_id:5,producto_id:1,captador_empleado_id:9,equipo_id:1,modalidad:'equipo',monto_unitario:2,activo:true,desde:'2026-11-01',hasta:null}
    ]
  },
  CU: {rol:'jefe'},
  aqIncAuth: () => ({p_token:'test',p_uid:1}),
  aqIncHtml: s => String(s ?? '').replaceAll('&','&amp;').replaceAll('<','&lt;'),
  aqIncFmt: n => 'Q' + Number(n).toFixed(2),
  aqIncNombreCli: () => 'Daniel Perú',
  aqIncNombreEmp: n => 'Empleado ' + n,
  hoy: () => '2026-11-22',
  sb: {
    rpc: async () => ({data:movimientos,error:null}),
    from: table => ({select: () => ({in:async () => ({
      data:table==='ventas'?[{id:11,estado:'Pagada'},{id:12,estado:'Crédito'},{id:13,estado:'Cancelada'}]:
        [{venta_id:12,monto:20,pagado:0}],error:null
    })})})
  }
};
vm.runInNewContext(src,context);
context.window.aqIncPintar();

setTimeout(() => {
  try{
    const html = nodes.get('aq-inc-lista').innerHTML;
    assert.equal((html.match(/Daniel Perú<\/strong>/g)||[]).length,1,'Solo una fila por cliente');
    assert.match(html,/Garrafones válidos<b>4<\/b>/,'Sin duplicar cantidades de equipo 50/50');
    assert.match(html,/Generado<b>Q8.00<\/b>/,'Suma solo el movimiento por cada empleado');
    assert.match(html,/Pendiente liquidable<b>Q6.00<\/b>/,'No liquida créditos pendientes');
    assert.match(html,/Retenido crédito<b>Q2.00<\/b>/,'Crédito pendiente se separa');
    assert.match(html,/Historial de autorizaciones \(2\)/);
    assert.ok(!html.includes('Q10.00</b>'),'Excluye ventas canceladas');
    console.log('Prueba de clientes e incentivos: OK');
  } catch (error) {console.error(error);process.exitCode=1;}
}, 30);
