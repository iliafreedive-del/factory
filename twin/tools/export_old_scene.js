/* Снимок сцены старой игры (index.html, сверенной по фото в PR 2–21) для двойника на Blender + Godot.
 *
 * Открывает копию index.html в Playwright, выносит в window нужные переменные, снимает все видимые меши
 * (крыши включены) в метрах плана и сохраняет:
 *   old_scene.glb — геометрия с цветами и метками «здание|часть|номер»;
 *   meta.json     — здания и комнаты, карточки INFO, подписи, зоны, шаги, люди.
 * Старую игру не меняет: правки делаются только в копии index_r.html в рабочей папке.
 *
 * Подготовка рабочей папки WORK (один раз):
 *   npm i three@0.128.0  →  cp node_modules/three/build/three.min.js node_modules/three/examples/js/exporters/GLTFExporter.js WORK/
 * Запуск: node twin/tools/export_old_scene.js WORK
 * Дальше: blender -b -P twin/blender/build_factory.py -- WORK/old_scene.glb factory.glb factory.blend
 *         python3 twin/tools/make_twin_data.py WORK/meta.json
 */
const path=require('path');
const WORK=path.resolve(process.argv[2]||'.');
{
 const fs0=require('fs');
 let h=fs0.readFileSync(path.join(__dirname,'..','..','index.html'),'utf8');
 h=h.replace('<script src="https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js"></script>','<script src="three.min.js"></script><script src="GLTFExporter.js"></script>');
 h=h.replace("requestAnimationFrame(frameLoop);\n})();","requestAnimationFrame(frameLoop);\nObject.assign(window,{ofCeil,zonePads,yard,flowGroup,train,scene,renderer,buildings,INFO,PLAN,STEPS,ZSTEPS,labels,hits,WX,WZ,unSx,toPlan,X,Z,camT,camS,setTop,gvSet,anims,setRoofMode:m=>{roofMode=m;buildings.forEach(b=>b.open=false)}});\n})();");
 if(!h.includes('setRoofMode:'))throw new Error('index.html изменился: не нашлось места для вставки');
 // Машины и прицепы: старая игра рисует их вместе со всем двором, двойник ставит их сам (Blender, по фото и twin/tools/vehicles.json).
 // Здесь каждый готовый прицеп и каждая легковая только записываются (место, поворот, вид) и не рисуются; рамы и прицепы
 // в работе (stage) остаются как были. Кары, ГАЗель, грузовики на маршрутах и поезд в старой игре ездят — в снимке их нет,
 // у двойника свои кары из симуляции. Вызовы ГСЧ не меняются: обёртки зовут то же, что и раньше.
 const VEH=`;const __V=[];window.__V=__V;
function __vrec(kind,b,x,z,ry,o){const m=b.base.clone().multiply(b.mat(x,0,z,0,ry,0,1,1,1)),e=m.elements;
 const L=(new Error().stack||'').split('\\n').map(s=>(s.match(/index_r\\.html:(\\d+)/)||[])[1]).filter(Boolean).map(Number).slice(2);
 __V.push({kind,x:e[12],y:e[13],z:e[14],ry:Math.atan2(e[8],e[0]),lines:L,o:JSON.parse(JSON.stringify(o||{}))})}
trailer=(T=>function(b,x,z,ry,o={}){if(o.stage)return T(b,x,z,ry,o);__vrec('trailer',b,x,z,ry,o)})(trailer);
platN=(T=>function(b,x,z,ry){__vrec('plat',b,x,z,ry,{})})(platN);
boatN=(T=>function(b,x,z,ry){__vrec('boat',b,x,z,ry,{})})(boatN);
carE=(T=>function(b,x,z,ry,o){__vrec('car',b,x,z,ry,o)})(carE);
pathMover=(T=>function(obj,...a){obj.userData.__mover=1;return T(obj,...a)})(pathMover);
shuttle=(T=>function(obj,...a){obj.userData.__mover=1;return T(obj,...a)})(shuttle);
`;
 const A0='\nconst world=new Batch();\n';
 if(h.split(A0).length!==2)throw new Error('index.html изменился: нет строки const world=new Batch()');
 h=h.replace(A0,'\nconst world=new Batch();'+VEH.replace(/\n/g,'')+'\n');
 const C0='const car=(b,x,z,ry,o)=>b.at(x,z,ry,()=>{';
 if(h.split(C0).length!==2)throw new Error('index.html изменился: нет const car=');
 h=h.replace(C0,'const car=(b,x,z,ry,o)=>__vrec("car",b,x,z,ry,o)||false&&b.at(x,z,ry,()=>{');
 fs0.writeFileSync(path.join(WORK,'index_r.html'),h);
}
const {chromium}=require('playwright');const fs=require('fs');
(async()=>{
 const b=await chromium.launch({args:['--use-angle=swiftshader','--enable-unsafe-swiftshader','--ignore-gpu-blocklist']});
 const ctx=await b.newContext({acceptDownloads:true,viewport:{width:800,height:600}});
 const p=await ctx.newPage();
 p.on('pageerror',e=>console.log('ERR',e.message));
 await p.goto('file://'+WORK+'/index_r.html');
 await p.waitForFunction(()=>typeof window.gvSet==='function',null,{polling:500,timeout:120000});
 await p.evaluate(()=>{setRoofMode(2)});
 await p.waitForTimeout(3000);
 const meta=await p.evaluate(()=>{
  const OX=X(213),OZ=Z(205);
  const visChain=o=>{for(let q=o;q;q=q.parent){if(q===flowGroup||q===train||q.userData.__mover)return false;if(!q.visible&&!q.userData.__roof)return false}return true};
  const tag=new Map();
  buildings.forEach(B=>{
    B.g.traverse(o=>{if(o.isMesh)tag.set(o,{b:B.cfg.id,part:'int'})});
    const mark=(obj,part)=>{if(!obj)return;obj.traverse(o=>{if(o.isMesh)tag.set(o,{b:B.cfg.id,part})})};
    mark(B.walls,'walls');mark(B.walls2,'walls2');mark(B.fl2,'fl2');mark(B.roofIn,'roofIn');mark(B.roof,'roof');
    [B.roof,B.roofIn].forEach(r=>{if(r){r.visible=true;r.userData.__roof=1;if(r.material){r.material.opacity=1;r.material.transparent=false}}});
  });
  // потолки 2 этажа Офиса 1 в старой игре гаснут вместе с крышей (ofCeil) — в двойнике они часть крыши
  ofCeil.forEach(m=>tag.set(m,{b:'b1o',part:'roofIn'}));
  zonePads.forEach(m=>tag.set(m,{b:'zone',part:m.userData.id||'pad'}));
  tag.set(yard,{b:'yard',part:'yard'});
  const zones=zonePads.map(m=>({id:m.userData.id,x:m.position.x-OX,z:m.position.z-OZ,w:m.scale.x,d:m.scale.z,color:'#'+m.material.color.getHexString()}));
  const root=new THREE.Scene();const out=[];let n=0;const workers=[];
  scene.updateMatrixWorld(true);
  scene.traverse(o=>{
    if(!o.isMesh||o.isSprite)return;if(!visChain(o)&&!zonePads.includes(o))return;
    let w=null;for(let q=o;q;q=q.parent)if(q.userData&&q.userData.w!==undefined){w=q;break}
    let t=tag.get(o)||{b:'world',part:w?'worker':'world'};
    const m=new THREE.Mesh(o.geometry,o.material);
    o.matrixWorld.decompose(m.position,m.quaternion,m.scale);
    m.position.x-=OX;m.position.z-=OZ;
    const mat=Array.isArray(o.material)?o.material[0]:o.material;
    m.name=[t.b,t.part,n++].join('|');
    m.userData={b:t.b,part:t.part,op:mat&&mat.transparent?mat.opacity:1,vc:!!(mat&&mat.vertexColors)};
    if(w){m.userData.wid=w.uuid}
    root.add(m);
  });
  scene.traverse(q=>{if(q.userData&&q.userData.w!==undefined&&q.isGroup){const v=new THREE.Vector3();q.getWorldPosition(v);workers.push({uuid:q.uuid,w:q.userData.w,x:v.x-OX,y:v.y,z:v.z-OZ,ry:q.rotation.y})}});
  window.__root=root;
  const L=labels.map(l=>({id:l.el.dataset.id||null,t:l.el.textContent,kind:l.kind,x:l.p?l.p.x-OX:null,y:l.p?l.p.y:null,z:l.p?l.p.z-OZ:null,b:l.b?l.b.cfg.id:null}));
  const B=buildings.map(B=>({id:B.cfg.id,name:B.cfg.name,locked:!!B.cfg.locked,r:[B.r.x1-OX,B.r.z1-OZ,B.r.x2-OX,B.r.z2-OZ],rooms:B.rooms.map(r=>({id:r.id,name:r.name,step:r.step||null,fl:r.fl||1,r:[r.R.x1-OX,r.R.z1-OZ,r.R.x2-OX,r.R.z2-OZ]}))}));
  const vehicles=window.__V.map(v=>({...v,x:+(v.x-OX).toFixed(3),y:+v.y.toFixed(3),z:+(v.z-OZ).toFixed(3),ry:+v.ry.toFixed(4)}));
  return {zones,count:root.children.length,labels:L,buildings:B,INFO,STEPS,ZSTEPS,workers,vehicles,origin:[OX,OZ]};
 });
 console.log('meshes',meta.count,'labels',meta.labels.length,'workers',meta.workers.length);
 fs.writeFileSync(path.join(WORK,'meta.json'),JSON.stringify(meta));
 const dl=p.waitForEvent('download',{timeout:600000});
 await p.evaluate(()=>{new THREE.GLTFExporter().parse(window.__root,res=>{const blob=new Blob([res],{type:'application/octet-stream'});const a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download='old_scene.glb';document.body.appendChild(a);a.click()},{binary:true,onlyVisible:false,maxTextureSize:1024})});
 const d=await dl;await d.saveAs(path.join(WORK,'old_scene.glb'));
 console.log('saved',fs.statSync(path.join(WORK,'old_scene.glb')).size);
 await b.close();
})();
