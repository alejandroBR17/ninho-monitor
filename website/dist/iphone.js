'use strict';
document.getElementById('copy').addEventListener('click',async()=>{
  const status=document.getElementById('status');
  try{await navigator.clipboard.writeText('rtsp://192.168.1.100:554/onvif1');status.textContent='Copiado. Cole no campo de fluxo de rede do VLC.';}
  catch{const selection=window.getSelection();const range=document.createRange();range.selectNodeContents(document.getElementById('address'));selection.removeAllRanges();selection.addRange(range);status.textContent='Selecione e copie o endereço acima.';}
});
