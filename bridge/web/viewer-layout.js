'use strict';
(()=>{
 const stage=document.getElementById('viewer-stage'),video=document.getElementById('video');
 const button=id=>document.getElementById(id);let expanded=false,previousFocus=null,scrollPosition=0;
 function update(){
  const portrait=expanded&&innerHeight>innerWidth;
  stage.classList.toggle('stage-rotated',portrait);button('stage-flip').hidden=!portrait;
  button('stage-toolbar').hidden=!expanded;
 }
 function pauseLabels(){const text=video.paused?'Retomar':'Pausar';button('pause').textContent=text;button('stage-pause').textContent=text}
 function togglePause(){if(video.paused)button('watch').click();else video.pause();pauseLabels()}
 async function close(){
  if(!expanded)return;resetPad();expanded=false;stage.classList.remove('stage-expanded','stage-rotated');document.body.classList.remove('viewer-expanded');stage.removeAttribute('role');stage.removeAttribute('aria-modal');
  update();if(document.fullscreenElement===stage)await document.exitFullscreen().catch(()=>{});
  try{screen.orientation?.unlock?.()}catch{}
  if(document.getElementById('viewer').hidden){window.scrollTo(0,0);button('password').focus({preventScroll:true})}else{window.scrollTo(0,scrollPosition);previousFocus?.focus({preventScroll:true})}
 }
 async function open(){
  if(expanded)return;resetPad();previousFocus=document.activeElement;scrollPosition=scrollY;expanded=true;stage.classList.add('stage-expanded');stage.dataset.side='right';document.body.classList.add('viewer-expanded');stage.setAttribute('role','dialog');stage.setAttribute('aria-modal','true');stage.setAttribute('aria-label','Câmera em paisagem');update();button('stage-close').focus();
  // Orientation locking is optional. CSS supplies a landscape viewing surface
  // when the browser/iPhone keeps its viewport locked in portrait.
  if(stage.requestFullscreen){try{await stage.requestFullscreen()}catch{}}
  if(!expanded){if(document.fullscreenElement===stage)await document.exitFullscreen().catch(()=>{});return}
  try{await screen.orientation?.lock?.('landscape')}catch{}
  update();
 }
 button('fullscreen').addEventListener('click',()=>void open());button('stage-close').addEventListener('click',()=>void close());
 button('stage-flip').addEventListener('click',()=>{resetPad();stage.dataset.side=stage.dataset.side==='left'?'right':'left'});
 button('pause').addEventListener('click',togglePause);button('stage-pause').addEventListener('click',togglePause);
 video.addEventListener('pause',pauseLabels);video.addEventListener('playing',pauseLabels);
 addEventListener('resize',()=>{if(expanded){resetPad();update()}});document.addEventListener('fullscreenchange',()=>{if(expanded&&!document.fullscreenElement)void close()});
 addEventListener('jortan-session-ended',()=>void close());
 document.addEventListener('keydown',e=>{
  if(!expanded)return;if(e.key==='Escape'){e.preventDefault();void close()}
  if(e.key==='Tab'){const items=[...stage.querySelectorAll('button,select,a[href]')].filter(el=>!el.disabled&&el.getClientRects().length);const first=items[0],last=items.at(-1);if(e.shiftKey&&document.activeElement===first){e.preventDefault();last?.focus()}else if(!e.shiftKey&&document.activeElement===last){e.preventDefault();first?.focus()}}
 });
})();
