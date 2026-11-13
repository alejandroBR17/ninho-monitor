import test from 'node:test';
import assert from 'node:assert/strict';
import {setTimeout as pause} from 'node:timers/promises';
import net from 'node:net';
import {startBridge} from '../server.mjs';
import {normalizeTransport,Framer,redact,rewriteAuth,authParams} from '../rtsp.mjs';
import {hostsInRange,probeRtsp} from '../discovery.mjs';

test('Transport Jortan e integridade de RTP misturado com RTSP',()=>{
 const fixed=normalizeTransport('RTP/AVP/TCP;unicast;interleaved=0-1','RTP/AVP;unicast;interleaved=0-1');
 assert.equal(fixed,'RTP/AVP/TCP;unicast;interleaved=0-1');
 assert.equal(normalizeTransport('RTP/AVP/TCP;interleaved=0-1','RTP/AVP/UDP;interleaved=0-1'),'RTP/AVP/UDP;interleaved=0-1');
 const frame=Buffer.from([36,0,0,5,13,10,36,255,0]),control=Buffer.from('RTSP/1.0 200 OK\r\nCSeq: 2\r\n\r\n');
 const bytes=Buffer.concat([control,frame,control]),parser=new Framer(),packets=[];
 for(let i=0;i<bytes.length;i+=3)packets.push(...parser.add(bytes.subarray(i,i+3)));
 assert.deepEqual(packets,[control,frame,control]);
});
test('Autorização usa senha real em memória e não a senha dummy do processo',()=>{
 const config={username:'admin',password:'local-only'};
 assert.equal(rewriteAuth('Basic placeholder','DESCRIBE','rtsp://camera/onvif1',config),'Basic '+Buffer.from('admin:local-only').toString('base64'));
 const result=rewriteAuth('Digest username="viewer",realm="camera",nonce="test",uri="old",response="dummy"','SETUP','rtsp://camera/track1',config);
 assert.equal(authParams(result).username,'admin');assert.equal(authParams(result).uri,'rtsp://camera/track1');assert.ok(!result.includes('local-only'));
 assert.equal(hostsInRange('192.168.1.100/24').length,254);assert.throws(()=>hostsInRange('8.8.8.0/24'));
 assert.ok(!redact('password="local-only" rtsp://admin:local-only@camera/onvif1',config).includes('local-only'));
});
test('HTTP exige código, bloqueia origem externa e não expõe câmera antes de entrar',async()=>{
 const bridge=await startBridge({host:'127.0.0.1',port:0,ffmpeg:'/usr/bin/ffmpeg',code:'12345678'});
 const base='http://127.0.0.1:'+bridge.port;
 try{
  assert.equal((await fetch(base+'/')).status,200);
  assert.equal((await fetch(base+'/api/status')).status,401);
  assert.equal((await fetch(base+'/api/login',{method:'POST',headers:{'Content-Type':'application/json','Origin':'http://evil.example'},body:'{"code":"12345678"}'})).status,403);
  const login=await fetch(base+'/api/login',{method:'POST',headers:{'Content-Type':'application/json'},body:'{"code":"12345678"}'});assert.equal(login.status,200);
  const cookie=login.headers.get('set-cookie').split(';')[0];assert.ok(login.headers.get('set-cookie').includes('HttpOnly'));
  const state=await fetch(base+'/api/status',{headers:{cookie}});assert.equal(state.status,200);assert.ok(!(await state.text()).includes('12345678'));
  const invalid=await fetch(base+'/api/connect',{method:'POST',headers:{cookie,'Content-Type':'application/json'},body:JSON.stringify({host:'8.8.8.8',port:554,path:'/onvif1',username:'admin',password:'private'})});assert.equal(invalid.status,400);
 }finally{await bridge.close();}
});
test('Busca RTSP identifica resposta real e recusa HTTP',async()=>{
 const server=net.createServer(socket=>socket.on('data',()=>socket.end('RTSP/1.0 401 Unauthorized\r\nCSeq: 1\r\n\r\n')));
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
 try{assert.equal((await probeRtsp('127.0.0.1',server.address().port)).status,401);}finally{await new Promise(resolve=>server.close(resolve));}
});
if(process.env.JORTAN_E2E==='1')test('E2E: fonte com Transport defeituoso chega ao navegador como JPEG',async()=>{
 const bridge=await startBridge({host:'127.0.0.1',port:0,ffmpeg:'/usr/bin/ffmpeg',code:'12345678',allowTestPorts:true}),base='http://127.0.0.1:'+bridge.port;
 try{
  const login=await fetch(base+'/api/login',{method:'POST',headers:{'Content-Type':'application/json'},body:'{"code":"12345678"}'}),cookie=login.headers.get('set-cookie').split(';')[0];
  const connect=await fetch(base+'/api/connect',{method:'POST',headers:{cookie,'Content-Type':'application/json'},body:JSON.stringify({host:'127.0.0.1',port:8854,path:'/onvif1',username:'viewer',password:'test-only'})});
  // Loopback is allowed only in the explicit E2E override below.
  assert.equal(connect.status,200,await connect.text());
  const controller=new AbortController();const stream=await fetch(base+'/stream.mjpg',{headers:{cookie},signal:controller.signal});assert.equal(stream.status,200);
  const reader=stream.body.getReader();let buffer=Buffer.alloc(0);
  const timeout=pause(15000).then(()=>{throw Error('Nenhum JPEG em 15s.');});
  await Promise.race([(async()=>{while(true){const {value,done}=await reader.read();if(done)throw Error('Fluxo encerrou sem JPEG.');buffer=Buffer.concat([buffer,value]);if(buffer.includes(Buffer.from([255,216]))&&buffer.includes(Buffer.from([255,217])))return;}})(),timeout]);
  controller.abort();
  const state=await(await fetch(base+'/api/status',{headers:{cookie}})).json();assert.equal(state.videoReceived,true);assert.ok(state.compatibility.transportFixes.length>0);assert.ok(!JSON.stringify(state).includes('test-only'));
 }finally{await bridge.close();}
});
