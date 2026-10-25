import assert from 'node:assert/strict';
import { Miniflare, convertV4MiniflareOptions } from 'miniflare';
import { fileURLToPath } from 'node:url';
const home = '<html><body><h1>EMO-Lab</h1><section aria-labelledby="more-title"><ul class="home-list"><li>Existing research</li></ul></section><nav aria-label="網站資訊"><a href="/privacy/">Privacy</a></nav></body></html>';
const projects = '<html><body><main class="content-page"><p class="lead">Existing projects</p><section id="existing">Research</section></main><nav class="footer-links"><a href="/privacy/">Privacy</a></nav></body></html>';
const mf = new Miniflare(convertV4MiniflareOptions({ workers: [
  { name: 'entry', modules: true, scriptPath: fileURLToPath(new URL('../integration/worker.js', import.meta.url)), compatibilityDate: '2026-10-12', serviceBindings: { EMOLAB_ORIGIN: 'origin' } },
  { name: 'origin', modules: true, compatibilityDate: '2026-10-12', script: `export default {async fetch(request) { const url=new URL(request.url); if(request.headers.has('If-None-Match'))return new Response(null,{status:304}); const text=url.pathname==='/'?${JSON.stringify(home)}:${JSON.stringify(projects)};return new Response(text,{headers:{'Content-Type':'text/html; charset=utf-8','ETag':'origin-v1'}});}}` }
] }));
try {
  for (const path of ['/', '/projects', '/projects/']) {
    const res = await mf.dispatchFetch('https://emo-lab.com' + path, { headers: { 'If-None-Match': 'origin-v1' } });
    assert.equal(res.status, 200); assert.equal(res.headers.get('etag'), null);
    const html = await res.text();
    assert.equal((html.match(/https:\/\/fancontrol\.emo-lab\.com\//g) || []).length, 2);
    assert.equal((html.match(/https:\/\/container\.emo-lab\.com\//g) || []).length, 2);
    assert.ok(html.includes('Privacy')); assert.ok(html.includes(path === '/' ? 'Existing research' : 'id="existing"'));
  }
  const pass = await mf.dispatchFetch('https://emo-lab.com/about/');
  assert.equal(pass.headers.get('etag'), 'origin-v1');
  assert.equal(await pass.text(), projects);
  const conditional = await mf.dispatchFetch('https://emo-lab.com/about/', { headers: { 'If-None-Match': 'origin-v1' } });
  assert.equal(conditional.status, 304);
  console.log('PASS: homepage/projects additions, existing links, validator handling and non-target passthrough');
} finally { await mf.dispose(); }
