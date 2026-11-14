'use strict';
const $=id=>document.getElementById(id);
let csrf='',hls=null,poll=null,gesture=null,sequence=0,heartbeat=null,limit=null,controlReady=false;
let desiredX=0,desiredY=0,playGeneration=0,connectingGeneration=null;
let wantsVideo=false,userPaused=false,resumeWhenVisible=false,recoveryTimer=null,recoveryAttempts=0,autoStopped=false;
let recoveryPending=false;
let lastStatus=null;const diagnosticEvents=[];
function noteDiagnostic(event,details={}){diagnosticEvents.push({horario:new Date().toISOString(),evento:event,...details});if(diagnosticEvents.length>40)diagnosticEvents.shift()}
let lastLease=0,statusChecking=false,lastClock=0,lastAdvance=0,stableSince=0;
const message=t=>{$('message').textContent=t};
function videoAppearance(connected){$('video-empty').hidden=connected;$('connection-label').textContent=connected?'Conectada':'Desconectada';$('connection-label').dataset.live=String(connected);if(!connected)$('resolution').textContent=''}
$('video').addEventListener('loadedmetadata',()=>{const v=$('video');if(v.videoWidth)$('resolution').textContent=v.videoWidth+' × '+v.videoHeight});
$('show-password').addEventListener('click',()=>{const reveal=$('password').type==='password';$('password').type=reveal?'text':'password';$('show-password').textContent=reveal?'Ocultar':'Mostrar';$('show-password').setAttribute('aria-pressed',String(reveal))});
async function api(path,body){
 const requestCSRF=csrf;const controller=new AbortController();const timer=setTimeout(()=>controller.abort(),path==='prepare'?20000:path==='play'||path==='alerts/test'?12000:8000);
 try{const res=await fetch('/api/'+path,{method:body===undefined?'GET':'POST',headers:body===undefined?{}:{'Content-Type':'application/json','X-CSRF':requestCSRF},body:body===undefined?undefined:JSON.stringify(body),cache:'no-store',signal:controller.signal});
 const data=await res.json();if(!res.ok){const codes={senha_incorreta_ou_ponte_nao_configurada:'Confira sua senha remota e se a ponte foi configurada.',aguarde_antes_de_tentar:'Muitas tentativas. Aguarde 15 minutos.',entre_com_sua_senha:'Entre novamente com sua senha.'};const error=Error(codes[data.erro]||'A ponte não confirmou a operação. Confira a conexão e tente novamente.');error.status=res.status;throw error}if(path==='status')lastStatus={horario:new Date().toISOString(),...data};else if(body!==undefined&&path!=='login')noteDiagnostic('operacao_confirmada',{operacao:path});return data;
 }catch(error){noteDiagnostic('falha_api',{operacao:path,status:error.status||0,codigo:error.name==='AbortError'?'tempo_esgotado':'operacao_nao_confirmada'});if(error.status===401&&path!=='login'&&requestCSRF===csrf){endSession();message(error.message)}if(error.name==='AbortError')throw Error('O notebook demorou a responder. Use Copiar diagnóstico e tente conectar novamente.');throw error}finally{clearTimeout(timer)}
}
function clearRecovery(){clearTimeout(recoveryTimer);recoveryTimer=null}
function detachVideo(){const video=$('video');video.onplaying=null;video.onerror=null;video.onended=null;if(hls){hls.destroy();hls=null}video.pause();video.removeAttribute('src');video.load();videoAppearance(false)}
function suspendVideo(){clearRecovery();++playGeneration;connectingGeneration=null;stopMove();detachVideo();$('play').disabled=false;$('play').hidden=false;$('watch').hidden=true;if(wantsVideo){$('play').textContent='Retomar vídeo';$('video-state').textContent='Vídeo pausado. A conexão será renovada ao retomar.'}}
function endSession(){wantsVideo=false;userPaused=false;resumeWhenVisible=false;autoStopped=false;suspendVideo();csrf='';controlReady=false;setControls();clearInterval(poll);poll=null;$('viewer').hidden=true;$('login').hidden=false;window.dispatchEvent(new Event('jortan-session-ended'))}
function progress(s){const stages={iniciando_conversor:'Iniciando o conversor no notebook…',aguardando_conexao_rtsp:'Aguardando o conversor conectar…',conectando_camera:'Conectando à câmera…',controle_rtsp_conectado:'Conexão com a câmera aberta…',negociando_rtsp:'Negociando o vídeo com a câmera…',resposta_rtsp:'Aguardando o vídeo da câmera…',compatibilidade_tcp_aplicada:'Preparando a compatibilidade da câmera…',recebendo_midia_rtsp:'Recebendo vídeo; aguardando a conversão…',convertendo_video:'Convertendo o vídeo para o navegador…'};const d=s.diagnosticoVideo||{};$('video-state').textContent=stages[d.etapa]||'Preparando vídeo no notebook…'}
function showViewer(){$('login').hidden=true;$('viewer').hidden=false;message('');window.dispatchEvent(new Event('jortan-authenticated'))}
$('login-form').addEventListener('submit',async e=>{e.preventDefault();$('enter').disabled=true;try{await api('login',{password:$('password').value});const verified=await api('session');if(!verified.authenticated)throw Error('O navegador não manteve o login. Permita cookies neste endereço e entre novamente.');csrf=verified.csrf;$('password').value='';showViewer()}catch(e){message(e.message)}finally{$('enter').disabled=false}});
function setControls(){document.querySelectorAll('.direction').forEach(b=>b.disabled=!controlReady);$('stop').disabled=!controlReady;$('prepare').hidden=controlReady}
$('prepare').addEventListener('click',async()=>{$('prepare').disabled=true;$('control-state').textContent='Confirmando a parada da câmera…';try{await api('prepare',{});controlReady=true;setControls();$('control-state').textContent='Controle conectado. Escolha a direção.'}catch(e){message(e.message)}finally{$('prepare').disabled=false}});
function scheduleRecovery(){
 if(!wantsVideo||userPaused||!csrf||document.hidden||recoveryTimer!==null||autoStopped)return;
 if(connectingGeneration!==null){recoveryPending=true;return}
 recoveryPending=false;noteDiagnostic('recuperacao_video',{tentativa:recoveryAttempts+1});
 stopMove();++playGeneration;detachVideo();$('watch').hidden=true;$('play').hidden=false;$('play').disabled=false;$('play').textContent='Reconectar';
 if(recoveryAttempts>=3){autoStopped=true;$('video-state').textContent='A conexão não voltou. Toque em Reconectar para tentar novamente.';return}
 const delay=[1000,3000,6000][recoveryAttempts++];$('video-state').textContent='Conexão interrompida. Reconectando o vídeo…';
 recoveryTimer=setTimeout(()=>{recoveryTimer=null;if(wantsVideo&&csrf&&!document.hidden)void connectVideo(false)},delay);
}
async function status(){
 if(document.hidden||!csrf||!wantsVideo||statusChecking||connectingGeneration!==null)return;
 statusChecking=true;const generation=playGeneration;
 try{
  const video=$('video');
  // The lease describes a foreground viewer, independently of mouse/touch input.
  if(!video.paused&&Date.now()-lastLease>=20000){await api('viewer-heartbeat',{});if(generation!==playGeneration)return;lastLease=Date.now()}
  const s=await api('status');if(generation!==playGeneration)return;
  if(s.erroVideo||!s.videoDisponivel){
   if(!video.paused)scheduleRecovery();
   else if(video.getAttribute('src')){detachVideo();$('watch').hidden=true;$('play').hidden=false;$('play').textContent='Retomar vídeo';$('video-state').textContent='Transmissão pausada. Toque em Retomar vídeo.'}
  }else if(!video.paused){
   const now=Date.now();if(video.currentTime!==lastClock){lastClock=video.currentTime;lastAdvance=now;if(stableSince&&now-stableSince>20000)recoveryAttempts=0}
   else if(lastAdvance&&now-lastAdvance>25000)scheduleRecovery();
  }
  if(s.erroControle){controlReady=false;setControls();$('control-state').textContent='Conecte o controle novamente.'}
 }catch(error){if(error.status!==401&&generation===playGeneration)scheduleRecovery()}
 finally{statusChecking=false}
}
async function connectVideo(manual=true){
 if(!csrf||document.hidden||connectingGeneration!==null)return;
 if(manual){recoveryAttempts=0;autoStopped=false}
 wantsVideo=true;userPaused=false;recoveryPending=false;noteDiagnostic('conectar_video',{manual});clearRecovery();const generation=++playGeneration;connectingGeneration=generation;stopMove();detachVideo();
 $('play').disabled=true;$('play').hidden=false;$('watch').hidden=true;$('connection-label').textContent='Conectando';message('');$('video-state').textContent='Preparando vídeo no notebook…';
 let preparing=null,checking=false;
 if(!poll)poll=setInterval(status,5000);
 try{
  preparing=setInterval(()=>{if(generation===playGeneration&&!checking){checking=true;api('status').then(s=>{if(generation===playGeneration&&preparing!==null)progress(s)}).catch(()=>{}).finally(()=>{checking=false})}},2500);
  await api('play',{});if(generation!==playGeneration)return;clearInterval(preparing);preparing=null;
  const deadline=Date.now()+50000;let ready=false;
  while(Date.now()<deadline&&generation===playGeneration&&!document.hidden){const s=await api('status');if(generation!==playGeneration)return;if(s.videoDisponivel){ready=true;break}progress(s);if(s.erroVideo){const codes={camera_sem_resposta:'A câmera não respondeu ao notebook. Confira se ela já iniciou e está na rede de casa.',camera_recusou_conexao:'A câmera recusou o acesso ao vídeo. Aguarde a inicialização e confira a porta na ponte.',camera_fora_da_rede:'O notebook não encontrou a câmera na rede.',camera_sem_conexao:'O notebook não conseguiu alcançar a câmera. Confira a conexão e o endereço nas configurações da ponte.',autenticacao_camera_recusada:'A câmera não aceitou o acesso. Confira as credenciais nas configurações da ponte.'};throw Error((codes[s.erroVideo]||'O notebook não conseguiu preparar o vídeo.')+' Use Copiar diagnóstico para conferir.');}await new Promise(r=>setTimeout(r,1000))}
  if(generation!==playGeneration||document.hidden)return;if(!ready)throw Error('O vídeo não ficou pronto a tempo. Toque em Copiar diagnóstico.');
  const video=$('video');lastClock=video.currentTime;lastAdvance=Date.now();stableSince=0;lastLease=0;
  video.onplaying=()=>{if(generation!==playGeneration)return;videoAppearance(true);lastClock=video.currentTime;lastAdvance=Date.now();stableSince=Date.now();$('video-state').textContent='Vídeo conectado · acesso remoto';$('watch').hidden=true;$('play').hidden=false;$('play').textContent='Reconectar';$('play').classList.add('secondary')};
  video.onerror=()=>{if(generation===playGeneration)scheduleRecovery()};video.onended=video.onerror;
  const nativeHls=video.canPlayType('application/vnd.apple.mpegurl');const apple=/iPad|iPhone|iPod/.test(navigator.userAgent)||(navigator.platform==='MacIntel'&&navigator.maxTouchPoints>1);
  if(nativeHls&&apple)video.src='/hls/live.m3u8';
  else if(window.Hls&&Hls.isSupported()){
   const currentHls=hls=new Hls({maxBufferLength:8,liveSyncDurationCount:3});
   currentHls.on(Hls.Events.ERROR,(_,d)=>{if(generation!==playGeneration)return;if(d.fatal||d.response?.code===404||d.response?.code===401)scheduleRecovery()});
   currentHls.loadSource('/hls/live.m3u8');currentHls.attachMedia(video);
  }else if(nativeHls)video.src='/hls/live.m3u8';else throw Error('No iPhone, abra este endereço no Safari.');
  $('watch').hidden=false;$('watch').textContent='Reproduzir vídeo';$('play').hidden=false;if(manual)video.scrollIntoView({block:'center'});
  video.play().catch(()=>{if(generation===playGeneration){$('watch').hidden=false;$('video-state').textContent='Toque em Reproduzir vídeo para começar.'}});$('audio').disabled=false;$('pause').disabled=false;$('fullscreen').disabled=false;
 }catch(error){if(generation===playGeneration){videoAppearance(false);message(error.message);$('video-state').textContent='Não foi possível preparar o vídeo.';if(error.status!==401){connectingGeneration=null;scheduleRecovery()}}}
 finally{clearInterval(preparing);preparing=null;if(connectingGeneration===generation)connectingGeneration=null;if(generation===playGeneration){$('play').disabled=false;if(recoveryPending)scheduleRecovery()}}
}
$('video').addEventListener('pause',()=>{const video=$('video');if(!document.hidden&&connectingGeneration===null&&recoveryTimer===null&&video.getAttribute('src')&&!video.error&&!video.ended){if(hls)hls.stopLoad();$('video-state').textContent='Vídeo pausado. Toque em reproduzir para retomar.'}});
$('video').addEventListener('play',()=>{userPaused=false;if(hls)hls.startLoad(-1)});
for(const id of ['pause','stage-pause'])$(id).addEventListener('click',()=>{userPaused=!$('video').paused;noteDiagnostic(userPaused?'pausa_solicitada':'retomada_solicitada')});
$('play').addEventListener('click',()=>void connectVideo(true));
$('watch').addEventListener('click',()=>{const video=$('video');if(!video.getAttribute('src')||video.error){void connectVideo(true);return}video.play().catch(()=>scheduleRecovery())});
$('audio').addEventListener('click',()=>{$('video').muted=!$('video').muted;$('audio').textContent=$('video').muted?'Ouvir câmera':'Silenciar câmera'});
function sendDirection(x,y,stop=false){if(!gesture)return;const body={x,y,gesture,seq:++sequence,stop};fetch('/api/ptz',{method:'POST',headers:{'Content-Type':'application/json','X-CSRF':csrf},body:JSON.stringify(body),keepalive:stop,cache:'no-store'}).then(r=>{if(!r.ok&&!stop){stopMove();controlReady=false;setControls();message('Controle interrompido. Conecte novamente.')}}).catch(()=>{if(!stop){stopMove();message('Conexão com a ponte interrompida.')}})}
function stopMove(){clearInterval(heartbeat);clearTimeout(limit);if(gesture){sendDirection(0,0,true);gesture=null}document.querySelectorAll('.direction').forEach(b=>b.removeAttribute('aria-pressed'))}
function beginMove(x,y){if(!controlReady)return;if(!gesture){gesture=crypto.randomUUID().replaceAll('-','');sequence=0;heartbeat=setInterval(()=>sendDirection(desiredX,desiredY),500);limit=setTimeout(stopMove,5000)}desiredX=x;desiredY=y;sendDirection(x,y)}
function startMove(b){if(gesture)return;b.setAttribute('aria-pressed','true');beginMove(Number(b.dataset.x),Number(b.dataset.y))}
for(const b of document.querySelectorAll('.direction')){b.addEventListener('pointerdown',e=>{e.preventDefault();b.setPointerCapture(e.pointerId);startMove(b)});for(const ev of ['pointerup','pointercancel','lostpointercapture'])b.addEventListener(ev,stopMove);b.addEventListener('keydown',e=>{if([' ','Enter'].includes(e.key)&&!e.repeat){e.preventDefault();startMove(b)}});b.addEventListener('keyup',stopMove);b.addEventListener('blur',stopMove)}
$('stop').addEventListener('click',()=>{if(!gesture){gesture=crypto.randomUUID().replaceAll('-','');sequence=0}stopMove()});for(const ev of ['pagehide','blur'])window.addEventListener(ev,stopMove);function parkVideo(){resumeWhenVisible=resumeWhenVisible||(wantsVideo&&!userPaused);suspendVideo()}
function resumeVideo(){const resume=resumeWhenVisible;resumeWhenVisible=false;if(resume&&wantsVideo&&csrf&&!document.hidden&&!autoStopped)void connectVideo(false)}
document.addEventListener('visibilitychange',()=>{noteDiagnostic(document.hidden?'pagina_oculta':'pagina_visivel');if(document.hidden)parkVideo();else resumeVideo()});
window.addEventListener('pagehide',parkVideo);window.addEventListener('pageshow',e=>{if(e.persisted)resumeVideo()});
window.addEventListener('online',()=>{if(wantsVideo&&csrf&&!document.hidden&&!autoStopped)scheduleRecovery()});
$('logout').addEventListener('click',async()=>{const pending=api('logout',{});endSession();try{await pending}catch{}});
api('session').then(s=>{if(s.authenticated){csrf=s.csrf;showViewer()}else if(!s.configured)message('Conclua a configuração da ponte no notebook.');}).catch(e=>message(e.message));
$('diagnostic').addEventListener('click',async()=>{
 const button=$('diagnostic');button.disabled=true;let bridgeState='sem_sessao';
 try{
  if(csrf){try{await api('status');bridgeState='consultado_agora'}catch{bridgeState='consulta_indisponivel'}}
  const video=$('video');const report=JSON.stringify({produto:'Ninho Monitor · Ponte',versaoVisualizador:'1.5.2',horario:new Date().toISOString(),consultaPonte:bridgeState,ultimaConsulta:lastStatus,navegador:{online:navigator.onLine,paginaOculta:document.hidden,videoSolicitado:wantsVideo,pausaSolicitada:userPaused,conectando:connectingGeneration!==null,tentativas:recoveryAttempts,recuperacaoPendente:recoveryPending,reconexaoAutomaticaEncerrada:autoStopped,video:{pausado:video.paused,pronto:video.readyState,rede:video.networkState,erro:video.error?.code||null,tempo:Math.round(video.currentTime||0)}},eventos:diagnosticEvents,observacao:'Sem senha, endereço, assinatura push ou logs brutos. Última consulta pode estar desatualizada; não comprova movimento físico ou entrega de notificação.'},null,2);
  try{await navigator.clipboard.writeText(report);message('Diagnóstico copiado.')}catch{const field=$('diagnostic-text');field.hidden=false;field.value=report;field.focus();field.select();message('Selecione e copie o diagnóstico abaixo.')}
 }finally{button.disabled=false}
});
$('diagnostic-video').addEventListener('click',()=>{if(!$('diagnostic').disabled)$('diagnostic').click()});
if('serviceWorker'in navigator)navigator.serviceWorker.register('/sw.js').catch(()=>{});

const pad=$('joystick'),knob=$('knob');let padPointer=null,padExpired=false,padLimit=null;
function resetPad(){padPointer=null;padExpired=false;clearTimeout(padLimit);knob.style.transform='';stopMove()}
function padMove(e){if(e.pointerId!==padPointer||padExpired||!controlReady)return;const rect=pad.getBoundingClientRect();let x=e.clientX-rect.left-rect.width/2,y=e.clientY-rect.top-rect.height/2;const stage=document.querySelector('#viewer-stage');if(stage.classList.contains('stage-rotated')){const direction=stage.dataset.side==='left'?-1:1;[x,y]=[direction*y,-direction*x]}const travel=rect.width/3;const length=Math.hypot(x,y);if(length>travel){x=x/length*travel;y=y/length*travel}knob.style.transform=`translate(${x}px,${y}px)`;if(length<16){stopMove();return}const sector=(Math.round(Math.atan2(-y,x)/(Math.PI/4))+8)%8;const dirs=[[1,0],[1,1],[0,1],[-1,1],[-1,0],[-1,-1],[0,-1],[1,-1]];const [dx,dy]=dirs[sector];if(!gesture||dx!==desiredX||dy!==desiredY)beginMove(dx,dy)}
pad.addEventListener('pointerdown',e=>{if(!controlReady||padPointer!==null)return;e.preventDefault();padPointer=e.pointerId;padExpired=false;pad.setPointerCapture(e.pointerId);padLimit=setTimeout(()=>{padExpired=true;stopMove();knob.style.transform=''},5000);padMove(e)});pad.addEventListener('pointermove',padMove);for(const ev of ['pointerup','pointercancel','lostpointercapture'])pad.addEventListener(ev,resetPad);
$('control-style').addEventListener('change',()=>{resetPad();const usePad=$('control-style').value==='joystick';pad.hidden=!usePad;document.querySelector('.directions').classList.toggle('joystick-mode',usePad);try{localStorage.setItem('jortan-control-style',usePad?'joystick':'arrows')}catch{}});
try{if(localStorage.getItem('jortan-control-style')==='joystick'){$('control-style').value='joystick';$('control-style').dispatchEvent(new Event('change'))}}catch{}
$('stop').addEventListener('click',resetPad);for(const ev of ['pagehide','blur'])window.addEventListener(ev,resetPad);
