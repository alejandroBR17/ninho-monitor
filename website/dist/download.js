'use strict';
const prepare = document.getElementById('prepare');
const save = document.getElementById('save');
const progress = document.getElementById('progress');
const status = document.getElementById('status');
const cancel = document.getElementById('cancel');
const error = document.getElementById('error');
let controller;
let blobUrl;
cancel.addEventListener('click', () => controller?.abort());
prepare.addEventListener('click', async () => {
  controller = new AbortController();
  prepare.disabled = true;
  prepare.textContent = 'Preparando instalador…';
  progress.hidden = false;
  progress.value = 0;
  cancel.hidden = false;
  error.hidden = true;
  save.hidden = true;
  status.textContent = 'Mantenha esta página aberta enquanto o arquivo é preparado.';
  try {
    const response = await fetch('manifest.json?v=2.5.0-17', {signal: controller.signal, cache: 'no-store'});
    if (!response.ok) throw new Error('Não foi possível obter as informações do instalador.');
    const manifest = await response.json();
    const pieces = [];
    let downloaded = 0;
    for (const part of manifest.parts) {
      const file = await fetch(part.url, {signal: controller.signal});
      if (!file.ok) throw new Error('O download foi interrompido. Tente novamente.');
      const buffer = await file.arrayBuffer();
      if (buffer.byteLength !== part.size) throw new Error('O arquivo veio incompleto. Reabra a página no Chrome e tente novamente.');
      const digest = await crypto.subtle.digest('SHA-256', buffer);
      const hash = Array.from(new Uint8Array(digest), value => value.toString(16).padStart(2,'0')).join('');
      if (hash !== part.sha256) throw new Error('A verificação do arquivo falhou. Tente novamente.');
      pieces.push(new Blob([buffer]));
      downloaded += buffer.byteLength;
      const percent = Math.round(downloaded / manifest.size * 100);
      progress.value = percent;
      status.textContent = `Preparando instalador: ${percent}%`;
    }
    if (controller.signal.aborted) throw new DOMException('Cancelado', 'AbortError');
    if (downloaded !== manifest.size) throw new Error('O instalador não está completo. Tente novamente.');
    const apk = new Blob(pieces, {type:'application/vnd.android.package-archive'});
    if (blobUrl) URL.revokeObjectURL(blobUrl);
    blobUrl = URL.createObjectURL(apk);
    save.href = blobUrl;
    save.download = manifest.filename;
    save.hidden = false;
    prepare.hidden = true;
    status.textContent = 'Pronto! Toque em “Salvar APK no celular” acima. Depois, abra o arquivo em Downloads.';
    save.focus();
  } catch (cause) {
    if (cause.name === 'AbortError') {
      status.textContent = 'Preparação cancelada. Você pode tentar novamente.';
    } else {
      error.textContent = cause.message || 'Não foi possível preparar o instalador. Abra a página no Chrome e tente novamente.';
      error.hidden = false;
      status.textContent = 'O instalador não foi salvo.';
    }
    progress.hidden = true;
    prepare.textContent = 'Tentar novamente ↓';
  } finally {
    prepare.disabled = false;
    cancel.hidden = true;
  }
});
window.addEventListener('pagehide', () => { controller?.abort(); if (blobUrl) URL.revokeObjectURL(blobUrl); });
