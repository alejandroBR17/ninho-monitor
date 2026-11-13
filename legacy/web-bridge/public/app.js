'use strict';
const byId=id=>document.getElementById(id);
let polling,streamAttached=false;
function showError(error){byId('error').hidden=false;byId('error').textContent=error.message??String(error);}
async function api(path,data){const response=await fetch('/api/'+path,{method:data===undefined?'GET':'POST',headers:data===undefined?{}:{'Content-Type':'application/json'},body:data===undefined?undefined:JSON.stringify(data)});const result=await response.json();if(!response.ok)throw Error(result.error??'A ponte não respondeu.');return result;}
function clearError(){byId('error').hidden=true;}
function attachStream(){if(streamAttached)return;streamAttached=true;byId('video').src='/stream.mjpg?start='+Date.now();byId('video').hidden=false;byId('placeholder').hidden=true;}
async function refresh(){try{const state=await api('status');byId('login').hidden=true;byId('viewer').hidden=false;byId('state').textContent=state.message;byId('phase').textContent=state.phase==='live'?'Ao vivo':state.phase==='connecting'?'Conectando':'Desconectada';if(['live','connecting'].includes(state.phase))attachStream();else{streamAttached=false;byId('video').removeAttribute('src');byId('video').hidden=true;byId('placeholder').hidden=false;}
  if(state.search){const search=state.search;byId('search-status').textContent=`${search.completed}/${search.total} testes · ${search.devices.length} resultado(s)${search.running?' · buscando…':''}`;byId('search-start').disabled=search.running;byId('results').replaceChildren();for(const result of search.devices){const button=document.createElement('button');button.type='button';button.textContent=`${result.host}:${result.port} · RTSP ${result.status}`;button.onclick=()=>{byId('host').value=result.host;byId('port').value=result.port;byId('search').hidden=true;void api('search/cancel',{});};byId('results').append(button);}}
  if(!byId('addresses').hasChildNodes()){for(const address of state.addresses){const link=document.createElement('a');link.href=address;link.textContent=address;byId('addresses').append(link,document.createElement('br'));}}
}catch(error){if(!polling)return;showError(error);}}
byId('login-form').addEventListener('submit',async event=>{event.preventDefault();clearError();try{await api('login',{code:byId('code').value});byId('code').value='';await refresh();if(!polling)polling=setInterval(refresh,1500);}catch(error){showError(error);}});
byId('camera-form').addEventListener('submit',async event=>{event.preventDefault();clearError();const button=event.submitter;button.disabled=true;try{await api('connect',{host:byId('host').value.trim(),port:Number(byId('port').value),username:byId('username').value,password:byId('password').value,path:byId('path').value.trim(),quality:byId('quality').value});streamAttached=false;await refresh();}catch(error){showError(error);}finally{button.disabled=false;}});
byId('disconnect').onclick=async()=>{try{await api('disconnect',{});await refresh();}catch(error){showError(error);}};
byId('show-search').onclick=()=>byId('search').hidden=!byId('search').hidden;
byId('search-start').onclick=async()=>{clearError();try{await api('search',{range:byId('range').value.trim()});await refresh();}catch(error){showError(error);}};
byId('search-cancel').onclick=async()=>{try{await api('search/cancel',{});await refresh();}catch(error){showError(error);}};
byId('fullscreen').onclick=()=>{const video=byId('video');if(video.webkitEnterFullscreen)video.webkitEnterFullscreen();else byId('video').parentElement.requestFullscreen?.().catch(showError);};
byId('video').onerror=()=>{streamAttached=false;byId('video').hidden=true;byId('placeholder').hidden=false;};
void api('status').then(()=>{polling=setInterval(refresh,1500);return refresh();}).catch(()=>{});
