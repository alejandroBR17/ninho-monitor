import net from 'node:net';
import crypto from 'node:crypto';
export function normalizeTransport(requested,received){
  const a=/(?:^|;)\s*interleaved=(\d+-\d+)/i.exec(requested)?.[1];
  const b=/(?:^|;)\s*interleaved=(\d+-\d+)/i.exec(received)?.[1];
  return /^RTP\/AVP\/TCP;/i.test(requested)&&a&&a===b&&/^RTP\/AVP;/i.test(received)&&!/(?:server_port|client_port|multicast)/i.test(received)
    ?received.replace(/^RTP\/AVP/i,'RTP/AVP/TCP'):received;
}
export class Framer{
  buffer=Buffer.alloc(0);
  add(data){
    this.buffer=Buffer.concat([this.buffer,data]);if(this.buffer.length>2097152)throw Error('Mensagem RTSP grande demais.');
    const packets=[];
    while(this.buffer.length){
      let length;
      if(this.buffer[0]===36){if(this.buffer.length<4)break;length=4+this.buffer.readUInt16BE(2);}
      else{const end=this.buffer.indexOf('\r\n\r\n');if(end<0){if(this.buffer.length>65536)throw Error('Cabeçalho RTSP grande demais.');break;}
        const match=/^Content-Length:\s*(\d+)/im.exec(this.buffer.subarray(0,end).toString('latin1'));
        length=end+4+(match?Number(match[1]):0);if(length>1048576)throw Error('Corpo RTSP grande demais.');}
      if(this.buffer.length<length)break;
      packets.push(this.buffer.subarray(0,length));this.buffer=this.buffer.subarray(length);
    }return packets;
  }
}
export function message(packet){
  const end=packet.indexOf('\r\n\r\n');if(end<0)throw Error('Resposta RTSP incompleta.');
  const lines=packet.subarray(0,end).toString('latin1').split('\r\n');
  const headers=new Map(),names=new Map();
  for(const line of lines.slice(1)){const colon=line.indexOf(':');if(colon<1)continue;
    const key=line.slice(0,colon).toLowerCase();names.set(key,line.slice(0,colon));headers.set(key,headers.has(key)?`${headers.get(key)}, ${line.slice(colon+1).trim()}`:line.slice(colon+1).trim());}
  return {line:lines[0],headers,names,body:packet.subarray(end+4)};
}
export function encode(msg){
  if(msg.body.length||msg.headers.has('content-length'))msg.headers.set('content-length',String(msg.body.length));
  return Buffer.concat([Buffer.from(msg.line+'\r\n'+[...msg.headers].map(([k,v])=>`${msg.names.get(k)??(k==='content-length'?'Content-Length':k)}: ${v}\r\n`).join('')+'\r\n','latin1'),msg.body]);
}
export function authParams(header){const values={};for(const match of header.matchAll(/(\w+)\s*=\s*(?:"([^"]*)"|([^,\s]+))/g))values[match[1].toLowerCase()]=match[2]??match[3];return values;}
export function rewriteAuth(header,method,target,config){
  if(/^Basic /i.test(header))return 'Basic '+Buffer.from(`${config.username}:${config.password}`).toString('base64');
  if(!/^Digest /i.test(header))throw Error('Autenticação RTSP não suportada.');
  const values=authParams(header);const algorithm=(values.algorithm??'MD5').toUpperCase();
  if(!['MD5','MD5-SESS','SHA-256','SHA-256-SESS'].includes(algorithm)||!values.realm||!values.nonce||values.qop&&values.qop!=='auth')throw Error('Desafio Digest não suportado.');
  const hash=s=>crypto.createHash(algorithm.startsWith('SHA-256')?'sha256':'md5').update(s).digest('hex');
  let ha1=hash(`${config.username}:${values.realm}:${config.password}`);
  if(algorithm.endsWith('-SESS'))ha1=hash(`${ha1}:${values.nonce}:${values.cnonce}`);
  const ha2=hash(`${method}:${target}`);
  values.username=config.username;values.uri=target;
  values.response=values.qop?hash(`${ha1}:${values.nonce}:${values.nc}:${values.cnonce}:auth:${ha2}`):hash(`${ha1}:${values.nonce}:${ha2}`);
  const quote=s=>s.replaceAll('\\','\\\\').replaceAll('"','\\"');
  return 'Digest '+Object.entries(values).map(([k,v])=>['qop','nc','algorithm'].includes(k)?`${k}=${v}`:`${k}="${quote(v)}"`).join(', ');
}
export function redact(text,config={}){
  let result=String(text).replace(/rtsp:\/\/[^\s<>"']+/gi,'rtsp://[omitido]').replace(/(?:Proxy-)?Authorization\s*:[^\r\n]*/gi,'Authorization: [omitida]')
    .replace(/\b(username|password|passwd|nonce|cnonce|response|opaque)\s*=\s*(?:"[^"]*"|[^\s,;]+)/gi,'$1=[omitido]');
  for(const value of [config.password,config.password&&encodeURIComponent(config.password),config.password&&Buffer.from(`${config.username}:${config.password}`).toString('base64')].filter(Boolean))result=result.replaceAll(value,'[omitido]');
  return result;
}
export async function createRelay(config,onUpdate=()=>{}){
  const token=crypto.randomBytes(16).toString('hex'),sockets=new Set();
  const status={scope:'loopback_no_PC',transportFixes:[],responses:[],rtpPackets:0,rtpBytes:0};
  let closed=false,active=false;
  const snapshot=()=>onUpdate(structuredClone(status));
  const origin=`rtsp://${config.host}:${config.port}`;
  const camera=new URL(config.path,origin);camera.username='';camera.password='';
  const server=net.createServer(client=>{
    if(closed||active){client.destroy();return;}active=true;sockets.add(client);
    let upstream=null,session=null,lastAuth=null,lastSeq=0,teardown=false,released=false;
    const pending=new Map(),requests=new Framer(),replies=new Framer();
    const cleanup=()=>{
      if(released)return;released=true;
      if(upstream&&!upstream.destroyed&&session&&!teardown){
        try{const auth=lastAuth?rewriteAuth(lastAuth,'TEARDOWN',camera.toString(),config):null;
          upstream.end(`TEARDOWN ${camera} RTSP/1.0\r\nCSeq: ${++lastSeq}\r\nSession: ${session}\r\n${auth?'Authorization: '+auth+'\r\n':''}\r\n`);
          setTimeout(()=>upstream.destroy(),250).unref();}catch{upstream.destroy();}
      }else upstream?.destroy();
      client.destroy();sockets.delete(client);if(upstream)sockets.delete(upstream);active=false;
    };
    const fail=error=>{if(!closed){status.error={type:error.code??error.name,message:redact(error.message,config)};snapshot();}cleanup();};
    client.on('error',fail);client.on('close',cleanup);
    let queued=Promise.resolve();
    client.on('data',data=>{
      client.pause();
      queued=queued.then(async()=>{
        for(const packet of requests.add(data)){
          if(closed||released)return;
          if(packet[0]===36){upstream?.write(packet);continue;}
          const msg=message(packet),[method,address,version]=msg.line.split(' '),local=new URL(address);
          if(local.hostname!=='127.0.0.1'||Number(local.port)!==server.address().port||!local.pathname.startsWith('/'+token+'/'))throw Error('Destino RTSP local inválido.');
          const remote=new URL(local.pathname.slice(token.length+1)+local.search,origin);
          msg.line=`${method} ${remote} ${version}`;
          if(msg.headers.has('authorization')){lastAuth=rewriteAuth(msg.headers.get('authorization'),method,remote.toString(),config);msg.headers.set('authorization',lastAuth);}
          const seq=msg.headers.get('cseq')??'';lastSeq=Number(seq)||lastSeq;
          if(method==='SETUP')pending.set(seq,msg.headers.get('transport')??'');if(method==='TEARDOWN')teardown=true;
          if(!upstream){
            upstream=net.connect({host:config.host,port:config.port});sockets.add(upstream);
            upstream.setTimeout(10000,()=>fail(Error('Tempo limite de comunicação com a câmera.')));
            upstream.on('error',fail);upstream.on('close',()=>{if(!released)cleanup();});
            upstream.on('data',bytes=>{
              try{for(const part of replies.add(bytes)){
                if(part[0]===36){status.rtpPackets++;status.rtpBytes+=part.length-4;client.write(part);if(status.rtpPackets===1)snapshot();continue;}
                const reply=message(part),sequence=reply.headers.get('cseq')??'',transport=reply.headers.get('transport');
                if(transport){const normalized=normalizeTransport(pending.get(sequence)??'',transport);if(normalized!==transport){status.transportFixes.push({received:transport,normalized});reply.headers.set('transport',normalized);}}
                if(reply.headers.has('session'))session=reply.headers.get('session').split(';')[0];
                if(status.responses.length<40)status.responses.push({status:reply.line,cseq:sequence,transportCamera:transport??null,transportPlayer:reply.headers.get('transport')??null});
                const rewrite=value=>value.replace(/rtsp:\/\/[^\s<>"',;]+/gi,url=>{
                  const target=new URL(url);if(target.hostname!==config.host)return url;
                  return `rtsp://127.0.0.1:${server.address().port}/${token}${target.pathname}${target.search}`;
                });
                for(const key of ['content-base','content-location','location','rtp-info'])if(reply.headers.has(key))reply.headers.set(key,rewrite(reply.headers.get(key)));
                if(reply.headers.get('content-type')?.includes('application/sdp'))reply.body=Buffer.from(rewrite(reply.body.toString('utf8')));
                client.write(encode(reply));snapshot();
              }}catch(error){fail(error);}
            });
            await new Promise((resolve,reject)=>{upstream.once('connect',resolve);upstream.once('error',reject);});
          }
          upstream.write(encode(msg));
        }
      }).catch(fail).finally(()=>{if(!closed&&!released)client.resume();});
    });
  });
  await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(0,'127.0.0.1',resolve);});
  const local=new URL(`rtsp://127.0.0.1:${server.address().port}/${token}${camera.pathname}${camera.search}`);
  // The native process sees only dummy credentials. The real password remains
  // in this Node process and is substituted when authorizing upstream requests.
  local.username='viewer';local.password='local-placeholder';
  return {uri:local.toString(),status,async close(){if(closed)return;closed=true;for(const socket of sockets)socket.destroy();sockets.clear();await new Promise(resolve=>server.close(resolve));}};
}
