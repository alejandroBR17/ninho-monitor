import net from 'node:net';
export function ipNumber(value){const parts=String(value).split('.');if(parts.length!==4||parts.some(x=>!/^\d{1,3}$/.test(x)||Number(x)>255||String(Number(x))!==x))throw Error('IP inválido.');return parts.reduce((sum,x)=>sum*256+Number(x),0);}
export function privateIp(value){try{const ip=ipNumber(value);return Math.floor(ip/16777216)===10||Math.floor(ip/1048576)===0xac1||Math.floor(ip/65536)===0xc0a8||Math.floor(ip/65536)===0xa9fe;}catch{return false;}}
export function hostsInRange(cidr){const [address,prefixText,...extra]=String(cidr).split('/'),prefix=Number(prefixText);if(extra.length||!Number.isInteger(prefix)||prefix<24||prefix>32)throw Error('Use uma faixa /24 até /32.');const ip=ipNumber(address),size=2**(32-prefix),base=Math.floor(ip/size)*size;const text=n=>[24,16,8,0].map(shift=>Math.floor(n/2**shift)%256).join('.');if(!privateIp(text(base))||!privateIp(text(base+size-1)))throw Error('Use apenas sua rede privada.');const start=prefix>=31?base:base+1,end=prefix>=31?base+size-1:base+size-2;return Array.from({length:end-start+1},(_,i)=>text(start+i));}
export function probeRtsp(host,port,{sockets=new Set(),timeout=600}={}){return new Promise(resolve=>{
  const socket=net.connect({host,port});sockets.add(socket);let done=false,bytes=Buffer.alloc(0);
  const finish=status=>{if(done)return;done=true;socket.destroy();sockets.delete(socket);resolve(status?{host,port,status}:null);};
  socket.setTimeout(timeout,()=>finish(null));socket.on('error',()=>finish(null));socket.on('close',()=>finish(null));
  socket.once('connect',()=>socket.write(`OPTIONS rtsp://${host}:${port}/ RTSP/1.0\r\nCSeq: 1\r\nUser-Agent: JortanViewer-Discovery/1.3\r\n\r\n`));
  socket.on('data',data=>{bytes=Buffer.concat([bytes,data]);if(bytes.length>16384)return finish(null);const end=bytes.indexOf('\r\n');if(end<0)return;const match=/^RTSP\/1\.[01]\s+(\d{3})(?:\s|$)/.exec(bytes.subarray(0,end).toString('latin1'));finish(match?Number(match[1]):null);});
});}
export function searchNetwork(cidr,ports=[554,8554],probe=probeRtsp){
  const hosts=hostsInRange(cidr),jobs=hosts.flatMap(host=>ports.map(port=>({host,port}))),sockets=new Set();
  const state={running:true,completed:0,total:jobs.length,devices:[],cancelled:false,range:cidr};let cursor=0;
  const cancel=()=>{state.cancelled=true;for(const socket of sockets)socket.destroy();};
  const worker=async()=>{while(!state.cancelled&&cursor<jobs.length){const job=jobs[cursor++];const result=await probe(job.host,job.port,{sockets});if(result&&!state.cancelled)state.devices.push(result);state.completed++;}};
  const done=Promise.all(Array.from({length:Math.min(24,jobs.length)},worker)).finally(()=>state.running=false);
  return {state,cancel,done};
}
