'use strict';
// Run only against the local synthetic demo described in docs/DEMO.md.
const { chromium } = require('playwright');
const path = require('node:path');
const fs = require('node:fs');
(async () => {
  const password = process.env.NINHO_DEMO_PASSWORD;
  if (!password) throw new Error('Defina NINHO_DEMO_PASSWORD com a senha fictícia da demonstração local.');
  const browser = await chromium.launch({ headless: true, ...(process.env.BROWSER_BIN ? { executablePath: process.env.BROWSER_BIN } : {}) });
  try {
    const page = await browser.newPage({ viewport: { width: 1280, height: 980 }, locale: 'pt-BR' });
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.goto('http://127.0.0.1:9096');
    await page.fill('#password', password);
    await page.click('#enter');
    await page.waitForSelector('#viewer:not([hidden])');
    await page.click('[data-home-mode="dormir"]');
    await page.waitForFunction(() => document.querySelector('#mode-summary').textContent.includes('Dormir'));
    await page.click('#play');
    await page.waitForTimeout(12000);
    if (await page.locator('#watch').isVisible()) await page.click('#watch');
    await page.waitForFunction(() => document.querySelector('video').currentTime > 1, null, { timeout: 30000 });
    await page.waitForFunction(() => document.querySelector('#event-list').textContent.includes('Movimento na câmera'), null, { timeout: 30000 });
    if (await page.title() !== 'Ninho Monitor — Remoto') throw new Error('A captura espera a identidade pública Ninho Monitor.');
    const output = path.join(__dirname, '..', 'docs', 'media');
    fs.mkdirSync(output, { recursive: true });
    await page.evaluate(() => scrollTo(0, 0));
    await page.locator('#viewer-stage').screenshot({ path: path.join(output, 'viewer-desktop-scene.webp'), type: 'webp', quality: 88 });
    await page.setViewportSize({ width: 390, height: 1000 });
    await page.evaluate(() => scrollTo(0, 0));
    await page.locator('#viewer-stage').screenshot({ path: path.join(output, 'viewer-mobile-scene.webp'), type: 'webp', quality: 88 });
    const historyClip = await page.locator('.event-card').evaluate(element => {
      const rect = element.getBoundingClientRect();
      return { x: rect.x + scrollX, y: rect.y + scrollY, width: rect.width, height: Math.min(rect.height, 440) };
    });
    await page.screenshot({ path: path.join(output, 'events-detail.webp'), type: 'webp', quality: 88, fullPage: true, clip: historyClip });
    if (errors.length) throw new Error('Erros JS durante a demonstração: ' + errors.join('; '));
    await page.click('#logout');
    console.log('Três capturas com vídeo sintético e sem erros JS.');
  } finally { await browser.close(); }
})().catch(error => { console.error(error.message); process.exitCode = 1; });
