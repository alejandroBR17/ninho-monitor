import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import fs from 'node:fs';
import crypto from 'node:crypto';
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {createRelay,redact} from './rtsp.mjs';
import {privateIp,searchNetwork} from './discovery.mjs';
const directory=path.dirname(fileURLToPath(import.meta.url));
export async function startBridge({port=8765,ffmpeg=process.env.JORTAN_FFMPEG??path.join(directory,'vendor','ffmpeg.exe'),host='0.0.0.0',code=crypto.randomInt(10000000,100000000).toString(),allowTestPorts=false}={}){
  const addresses=Object.values(os.networkInterfaces()).flat().filter(item=>item?.family==='IPv4'&&!item.internal&&privateIp(item.address)).map(item=>item.address);
  const validHosts=new Set(['127.0.0.1','localhost','::1',...addresses]);const sessions=new Map(),attempts=new Map();
  let config=null,child=null,relay=null,scan=null,stopping=null,currentGeneration=0,lastFrame=null;
  const viewers=new Set();let stopWhenIdle; let connecting = Promise.resolve();
  const state={version:'1.3.0',phase:'idle',message:'Configure sua câmera para assistir.',videoReceived:false,frames:0,logs:[],compatibility:null,config:null};
  function log(text){const safe=redact(text,config??{});state.logs.push(safe.slice(0,2500));if(state.logs.length>160)state.logs.splice(40,1);}
  const headers={'Cache-Control':'no-store','X-Content-Type-Options':'nosniff','Referrer-Policy':'no-referrer','Content-Security-Policy':"default-src 'self'; img-src 'self' data:; style-src 'self'; script-src 'self'; frame-ancestors 'none'"};
  const json=(res,value,status=200)=>{res.writeHead(status,{...headers,'Content-Type':'application/json; charset=utf-8'});res.end(JSON.stringify(value));};
  function authorized(req){const token=/jortan_session=([a-f0-9]+)/.exec(req.headers.cookie??'')?.[1];const expires=sessions.get(token);if(!expires||expires<Date.now()){if(token)sessions.delete(token);return false;}return true;}
  async function body(req){let text='';for await(const bytes of req){text+=bytes;if(text.length>8192)throw Error('Requisição grande demais.');}return JSON.parse(text||'{}');}
  async function stopVideo({idle=false}={}){
    if(stopping)return stopping;
    stopping=(async()=>{
      currentGeneration++;const previous=child;child=null;
      if(previous){previous.kill();await Promise.race([new Promise(resolve=>previous.once('close',resolve)),new Promise(resolve=>setTimeout(resolve,1000))]);}
      await relay?.close();relay=null;lastFrame=null;
      for(const viewer of viewers)viewer.end();viewers.clear();
      state.phase='idle';state.videoReceived=false;if(!idle)state.message='Conexão encerrada.';
    })().finally(()=>stopping=null);return stopping;
  }
  function publishFrame(frame,generation){
    if(generation!==currentGeneration)return;
    lastFrame=frame;state.frames++;state.videoReceived=true;state.phase='live';state.message='Ao vivo · TCP';
    const packet=Buffer.concat([Buffer.from(`--jortan\r\nContent-Type: image/jpeg\r\nContent-Length: ${frame.length}\r\n\r\n`),frame,Buffer.from('\r\n')]);
    for(const viewer of viewers){if(viewer.writableLength>2*1024*1024){viewer.destroy();viewers.delete(viewer);}else viewer.write(packet);}
  }
  async function connect(next){
    if(!(privateIp(next.host)||(allowTestPorts&&next.host==='127.0.0.1'))||!Number.isInteger(Number(next.port))||Number(next.port)<1||Number(next.port)>65535)throw Error('Informe um IP privado e uma porta válida.');
    if(typeof next.path!=='string'||!next.path.startsWith('/')||next.path.startsWith('//')||/[\r\n\s#]/.test(next.path)||next.path.length>512)throw Error('Caminho RTSP inválido.');
    if(typeof next.username!=='string'||!next.username||next.username.length>128||typeof next.password!=='string'||next.password.length>256)throw Error('Usuário ou senha inválidos.');
    if(!fs.existsSync(ffmpeg))throw Error('FFmpeg não encontrado no pacote. Extraia o ZIP inteiro antes de iniciar.');
    await stopVideo({idle:true});const generation=++currentGeneration;
    config={host:next.host,port:Number(next.port),path:next.path,username:next.username,password:next.password};
    state.config={host:config.host,port:config.port,path:config.path.split('?')[0],};
    state.phase='connecting';state.message='Conectando à câmera…';state.logs=[];state.frames=0;
    const prepared=await createRelay(config,value=>{if(generation===currentGeneration)state.compatibility=value;});
    if(generation!==currentGeneration){await prepared.close();return;} relay=prepared;
    const economy=next.quality!=='standard';
    const process=spawn(ffmpeg,['-hide_banner','-loglevel','warning','-rtsp_transport','tcp','-rw_timeout','10000000','-i',relay.uri,
      '-an','-vf',economy?'fps=5,scale=640:-2':'fps=8,scale=960:-2','-q:v',economy?'8':'6','-f','image2pipe','-vcodec','mjpeg','pipe:1'],{windowsHide:true,stdio:['ignore','pipe','pipe']});
    child=process;let buffer=Buffer.alloc(0),lastAt=Date.now();
    const watch=setInterval(()=>{
      if(generation!==currentGeneration)return;
      if(Date.now()-lastAt>25000){state.phase='failed';state.message='Nenhum quadro de vídeo chegou ou o fluxo parou. Consulte o diagnóstico.';log('Tempo limite: nenhum quadro JPEG em 25 segundos.');process.kill();}
    },1000);watch.unref();
    process.stdout.on('data',data=>{
      try{buffer=Buffer.concat([buffer,data]);if(buffer.length>10*1024*1024)throw Error('Quadro excedeu o limite.');
        while(buffer.length){const start=buffer.indexOf(Buffer.from([255,216]));if(start<0){buffer=buffer.subarray(Math.max(0,buffer.length-1));break;}
          const end=buffer.indexOf(Buffer.from([255,217]),start+2);if(end<0){buffer=buffer.subarray(start);break;}
          const frame=buffer.subarray(start,end+2);buffer=buffer.subarray(end+2);lastAt=Date.now();publishFrame(frame,generation);}
      }catch(error){log(error.message);process.kill();}
    });
    process.stderr.on('data',bytes=>{if(generation===currentGeneration)log(bytes.toString());});
    process.on('error',error=>{clearInterval(watch);if(generation===currentGeneration){log(error.message);state.phase='failed';state.message='Não foi possível iniciar o vídeo. Consulte o diagnóstico.';}});
    process.on('close',exit=>{
      clearInterval(watch);if(generation!==currentGeneration)return;
      state.exitCode=exit;state.phase='failed';state.message='O vídeo foi encerrado. Confira a câmera e o diagnóstico.';
      for(const viewer of viewers)viewer.end();viewers.clear();lastFrame=null;
      void relay?.close().catch(error=>log(error.message));
    });
    clearTimeout(stopWhenIdle);stopWhenIdle=setTimeout(()=>{if(viewers.size===0)void stopVideo({idle:true});},30000);stopWhenIdle.unref();
  }
  const server=http.createServer(async(req,res)=>{
    try{
      const peer=(req.socket.remoteAddress??'').replace(/^::ffff:/,'');
      if(!['127.0.0.1','::1'].includes(peer)&&!privateIp(peer))return json(res,{error:'Use a rede local.'},403);
      const requestHost=String(req.headers.host??'').replace(/:\d+$/,'').replace(/^\[|\]$/g,'');
      if(!validHosts.has(requestHost))return json(res,{error:'Host não permitido.'},403);
      const url=new URL(req.url,'http://localhost');
      if(req.method==='POST'&&req.headers.origin&&new URL(req.headers.origin).host!==req.headers.host)return json(res,{error:'Origem não permitida.'},403);
      if(url.pathname==='/api/login'&&req.method==='POST'){
        const key=req.socket.remoteAddress??'',entry=attempts.get(key)??{count:0,start:Date.now()};
        if(Date.now()-entry.start>60000){entry.count=0;entry.start=Date.now();}entry.count++;attempts.set(key,entry);
        if(entry.count>8)return json(res,{error:'Muitas tentativas. Aguarde um minuto.'},429);
        const input=await body(req);const incoming=Buffer.from(String(input.code??'')),expected=Buffer.from(code);
        if(incoming.length!==expected.length||!crypto.timingSafeEqual(incoming,expected))return json(res,{error:'Código incorreto. Confira a janela da ponte no PC.'},401);
        const token=crypto.randomBytes(32).toString('hex');sessions.set(token,Date.now()+12*3600000);
        res.setHeader('Set-Cookie',`jortan_session=${token}; HttpOnly; SameSite=Strict; Path=/; Max-Age=43200`);return json(res,{ok:true});
      }
      if(url.pathname.startsWith('/api/')||url.pathname==='/stream.mjpg'){
        if(!authorized(req))return json(res,{error:'Entre com o código exibido no PC.'},401);
        if(url.pathname==='/api/status')return json(res,{...state,search:scan?.state??null,addresses:addresses.map(address=>`http://${address}:${server.address().port}`)});
        if(url.pathname==='/api/diagnostic'){res.setHeader('Content-Disposition','attachment; filename="jortan-web-diagnostico.json"');return json(res,{product:'Jortan Web Bridge 1.3.0',...state,search:scan?.state??null});}
        if(url.pathname==='/api/connect'&&req.method==='POST'){const input=await body(req);const pending=connecting.then(()=>connect(input));connecting=pending.catch(()=>{});await pending;return json(res,{ok:true});}
        if(url.pathname==='/api/disconnect'&&req.method==='POST'){await stopVideo();return json(res,{ok:true});}
        if(url.pathname==='/api/search'&&req.method==='POST'){
          const input=await body(req);if(scan?.state.running)return json(res,{error:'Já existe uma busca em andamento.'},409);
          const ports=allowTestPorts&&Array.isArray(input.ports)?input.ports:[554,8554];
          if(ports.length>3||ports.some(p=>!Number.isInteger(p)||p<1||p>65535))throw Error('Portas inválidas.');
          scan=searchNetwork(input.range,ports);scan.done.catch(error=>{scan.state.error=error.message;scan.state.running=false;});return json(res,{ok:true});
        }
        if(url.pathname==='/api/search/cancel'&&req.method==='POST'){scan?.cancel();return json(res,{ok:true});}
        if(url.pathname==='/stream.mjpg'){
          if(!child)return json(res,{error:'Inicie a conexão primeiro.'},409);
          clearTimeout(stopWhenIdle);res.writeHead(200,{...headers,'Content-Type':'multipart/x-mixed-replace; boundary=jortan','Connection':'keep-alive'});viewers.add(res);
          if(lastFrame)res.write(Buffer.concat([Buffer.from(`--jortan\r\nContent-Type: image/jpeg\r\nContent-Length: ${lastFrame.length}\r\n\r\n`),lastFrame,Buffer.from('\r\n')]));
          req.on('close',()=>{viewers.delete(res);if(!viewers.size){clearTimeout(stopWhenIdle);stopWhenIdle=setTimeout(()=>{if(!viewers.size)void stopVideo({idle:true});},5000);stopWhenIdle.unref();}});return;
        }
        return json(res,{error:'Não encontrado.'},404);
      }
      const files={'/':'index.html','/app.js':'app.js','/style.css':'style.css'};const file=files[url.pathname];if(!file)return json(res,{error:'Não encontrado.'},404);
      res.writeHead(200,{...headers,'Content-Type':file.endsWith('.js')?'text/javascript; charset=utf-8':file.endsWith('.css')?'text/css; charset=utf-8':'text/html; charset=utf-8'});fs.createReadStream(path.join(directory,'public',file)).pipe(res);
    }catch(error){json(res,{error:redact(error.message,config??{})},400);}
  });
  await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(port,host,resolve);});
  return {server,code,port:server.address().port,addresses,async close(){scan?.cancel();clearTimeout(stopWhenIdle);await stopVideo();for(const session of sessions.keys())sessions.delete(session);server.closeAllConnections();await new Promise(resolve=>server.close(resolve));}};
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
  const bridge=await startBridge();
  console.log('\nJORTAN VIEWER — PONTE PARA IPHONE / NAVEGADOR\n');
  console.log(`Abra no PC: http://127.0.0.1:${bridge.port}`);
  for(const address of bridge.addresses)console.log(`No celular, abra no Safari/Chrome: http://${address}:${bridge.port}`);
  console.log(`\nCódigo de acesso: ${bridge.code}\nMantenha esta janela e o PC ligados.\n`);
  const shutdown=async()=>{await bridge.close();process.exit(0);};process.on('SIGINT',shutdown);process.on('SIGTERM',shutdown);
}
