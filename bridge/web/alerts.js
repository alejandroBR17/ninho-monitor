'use strict';
(()=>{
 const el=id=>document.getElementById(id);let poll=null,loading=false,dirty=false,seen=null,registration=null;
 const pushText=text=>{el('push-state').textContent=text};
 const apple=/iPad|iPhone|iPod/.test(navigator.userAgent)||(navigator.platform==='MacIntel'&&navigator.maxTouchPoints>1);
 const installed=()=>matchMedia('(display-mode: standalone)').matches||navigator.standalone===true;
 function supported(){return 'Notification'in window&&'serviceWorker'in navigator&&'PushManager'in window&&(!apple||installed())}
 function paint(s){const states={desativado:'Monitoramento desligado no modo atual.',aguardando_video:'Monitoramento ativo. Aguardando imagem da câmera…',monitorando:'Monitorando a imagem no notebook.'};el('motion-state').textContent=states[s.state]||'Verificando monitoramento…';if(s.error)el('motion-state').textContent+=' Confira as configurações e o teste de notificação.';if(s.lastEvent?.id&&s.lastEvent.id!==seen){el('motion-event').textContent='Último movimento às '+new Date(s.lastEvent.horario).toLocaleTimeString('pt-BR');seen=s.lastEvent.id}}
 async function refresh(){if(loading||!csrf||document.hidden)return;loading=true;try{paint(await api('alerts'))}catch(e){if(csrf)el('motion-state').textContent='Sem confirmação de monitoramento. Confira a conexão e o notebook.'}finally{loading=false}}
 async function reg(){
  if(!registration)registration=await navigator.serviceWorker.register('/sw.js');
  const worker=registration.installing||registration.waiting;
  if(worker&&worker.state!=='activated')await new Promise((resolve,reject)=>{
   const timer=setTimeout(()=>reject(Error('worker timeout')),12000);
   worker.addEventListener('statechange',()=>{
    if(worker.state==='activated'){clearTimeout(timer);resolve()}
    else if(worker.state==='redundant'){clearTimeout(timer);reject(Error('worker unavailable'))}
   });
  });
  return await navigator.serviceWorker.ready;
 }
 async function deviceState(){if(!supported()){pushText(apple?'No iPhone, abra o Ninho pelo ícone da Tela de Início (iOS 16.4 ou superior) para ativar notificações.':'Este navegador não oferece notificações push. O movimento continua aparecendo nesta página.');return}try{const r=await reg(),s=await r.pushManager.getSubscription();el('test-push').disabled=!s;el('disable-push').hidden=!s;if(s)pushText('Este aparelho tem uma assinatura de notificação. Use Enviar teste para conferir a entrega.')}catch{pushText('Não foi possível preparar as notificações neste navegador.')}}
 function start(){if(poll)clearInterval(poll);dirty=false;seen=null;void refresh();void deviceState();poll=setInterval(refresh,5000)}
 addEventListener('jortan-authenticated',start);addEventListener('jortan-session-ended',()=>{clearInterval(poll);poll=null;registration=null;seen=null;el('motion-event').textContent='';el('motion-state').textContent='Entre para consultar o monitoramento.'});if(!el('viewer').hidden)start();addEventListener('jortan-home-changed',()=>void refresh());
 function decode(value){const s=atob(value.replace(/-/g,'+').replace(/_/g,'/'));return Uint8Array.from(s,c=>c.charCodeAt(0))}
 el('enable-push').addEventListener('click',async()=>{
  if(!supported()){void deviceState();return}el('enable-push').disabled=true;
  try{
   // Permission is requested only from this explicit user gesture.
   const permission=await Notification.requestPermission();if(permission!=='granted'){pushText('Notificações não autorizadas. Você pode rever a permissão nas configurações deste aplicativo.');return}
   const key=await api('alerts/key',{}),r=await reg();let s=await r.pushManager.getSubscription();let oldKey='';try{oldKey=localStorage.getItem('jortan-push-key')||''}catch{}
   if(s&&oldKey!==key.publicKey){await s.unsubscribe();s=null}
   if(!s)s=await r.pushManager.subscribe({userVisibleOnly:true,applicationServerKey:decode(key.publicKey)});
   await api('alerts/subscribe',s.toJSON());try{localStorage.setItem('jortan-push-key',key.publicKey)}catch{}
   el('test-push').disabled=false;el('disable-push').hidden=false;pushText('Notificações ativadas neste aparelho. Ative o monitoramento e use Enviar teste para conferir.');
  }catch{pushText('Não foi possível ativar. No iPhone, abra pela Tela de Início e confira as permissões e a conexão.')}finally{el('enable-push').disabled=false}
 });
 el('test-push').addEventListener('click',async()=>{el('test-push').disabled=true;try{const s=await(await reg()).pushManager.getSubscription();if(!s)throw Error();await api('alerts/test',{endpoint:s.endpoint});pushText('Teste aceito pelo serviço de notificações. Confira a chegada neste aparelho.')}catch{pushText('O serviço não confirmou o teste. Tente ativar as notificações novamente.')}finally{el('test-push').disabled=false}});
 el('disable-push').addEventListener('click',async()=>{try{const s=await(await reg()).pushManager.getSubscription();if(s){const endpoint=s.endpoint;await s.unsubscribe();await api('alerts/unsubscribe',{endpoint})}el('test-push').disabled=true;el('disable-push').hidden=true;pushText('Notificações desativadas neste aparelho.')}catch{pushText('Não foi possível confirmar a desativação. Confira as permissões deste aplicativo.')}});
})();
