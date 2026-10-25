const destination = 'https://container.emo-lab.com/';
const link = `<a href="${destination}">Container Desk ↗</a>`;
const project = `<section id="container-desk" aria-labelledby="container-desk-title"><p class="eyebrow">OPEN SOURCE · MAC APP</p><h2 id="container-desk-title">Container Desk — 原生 Mac 容器管理工具</h2><p>以 SwiftUI 打造的 Apple Container 圖形介面，整合容器、映像檔、網路、儲存卷與專案管理。支援 macOS 26 以上與 Apple Silicon，採 Apache-2.0 開源授權。</p><p><a class="inline-link" href="${destination}">探索 Container Desk 與下載 Mac 版 →</a></p></section>`;
const fanDestination = 'https://fancontrol.emo-lab.com/';
const fanLink = `<a href="${fanDestination}">Fan Control ↗</a>`;
const fanProject = `<section id="fan-control" aria-labelledby="fan-control-title"><p class="eyebrow">MAC APP</p><h2 id="fan-control-title">Fan Control</h2><p>在選單列掌握即時 RPM、CPU 與 GPU 溫度，查看轉速走勢、快速調速與恢復自動。支援 macOS 15 以上。</p><p><a class="inline-link" href="${fanDestination}">探索 Fan Control 與下載 Mac 版 →</a></p></section>`;
export default {
  async fetch(request, env) {
    const incoming = new URL(request.url);
    const originURL = new URL(incoming.pathname + incoming.search, 'https://emo-lab.com');
    const target = ['/', '/projects', '/projects/'].includes(incoming.pathname) && request.method === 'GET';
    const forwarded = new Request(originURL, request);
    // HTML is modified below, so conditional origin validators cannot be reused.
    if (target) { forwarded.headers.delete('If-None-Match'); forwarded.headers.delete('If-Modified-Since'); }
    const response = await env.EMOLAB_ORIGIN.fetch(forwarded);
    if (!target || response.status !== 200 || !response.headers.get('content-type')?.includes('text/html')) return response;
    let rewriter = new HTMLRewriter();
    if (incoming.pathname === '/') {
      rewriter = rewriter.on('section[aria-labelledby="more-title"] .home-list', {
        element(el) { el.prepend(`<li data-fan-control-entry>${fanLink}：即時查看 Mac 風扇轉速、CPU 與 GPU 溫度，快速調整與恢復自動。</li><li data-container-desk-entry>${link}：以原生 Mac 介面管理 Apple Container，查看功能與下載安裝檔。</li>`, { html: true }); }
      }).on('nav[aria-label="網站資訊"]', {element(el) {el.prepend(fanLink + link, {html:true});}});
    } else {
      rewriter = rewriter.on('main.content-page > .lead', {element(el) {el.after(fanProject + project, {html:true});}})
        .on('nav.footer-links', {element(el) {el.append(fanLink + link, {html:true});}});
    }
    const headers = new Headers(response.headers);
    for (const name of ['content-length', 'etag', 'last-modified', 'content-md5']) headers.delete(name);
    headers.set('Cache-Control', 'public, max-age=0, must-revalidate');
    headers.set('X-Container-Desk-Entry', '1');
    headers.set('X-Fan-Control-Entry', '1');
    return rewriter.transform(new Response(response.body, {status:response.status, headers}));
  }
};
