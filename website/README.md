# Fan Control 官網

- 官網：<https://fancontrol.emo-lab.com/>
- 主站入口：EMO-Lab 首頁「繼續探索」、專案頁與頁尾。
- 下載：所有下載按鈕直接連結 `https://github.com/eqwgeryfgbdf/Fan-Control/releases/latest`。
- 官網目前介紹已發布的 v1.0.3。v1.0.4 原始碼中的並排主畫面尚未製作 Release，不把它當作目前安裝檔已有的功能。

使用原創風扇 SVG Logo、系統字體、大字級標題、輕量捲動進場與按鈕過場。無追蹤碼、第三方字體、彈出提示或假下載按鈕。動畫遵循 `prefers-reduced-motion`；JavaScript 未執行時內容與連結仍完整可用。主視窗為標示清楚的介面示意；選單列面板使用 v1.0.3 的實際截圖。

依使用者要求，既有 GitHub 倉庫已改為公開；原始碼與 Release 安裝檔皆可直接存取。下載連結導向 GitHub 最新正式 Release，網站不包含 GitHub 憑證。

## 開發與部署

需要 Node.js 及 npm，使用已授權的 Cloudflare 帳號。

```sh
cd website
npm ci
npm run dev
npm run check
node scripts/check-entry.mjs
npm run deploy
npx wrangler deploy --config integration/wrangler.jsonc
```

`wrangler.jsonc` 只發布 `public/`，使用 `fan-control-site` Worker 的 Static Assets 與 `fancontrol.emo-lab.com` Custom Domain。Cloudflare 管理 DNS 與 TLS。

## EMO-Lab 共用入口

`integration/worker.js` 延續既有 `emo-lab-container-entry` Worker。透過 `EMOLAB_ORIGIN` Service Binding 讀取 `emo-lab-website`，僅在首頁與 `/projects`、`/projects/` 的 HTML 加入產品入口。既有 Container Desk 入口、原始主站資產及其他路徑保持原有行為；不覆蓋 EMO-Lab 原始網站。

此 Worker 是共用資源。後續若從 Container Desk 專案的舊 integration 副本重新部署，應先同步本檔中的 Fan Control 入口，以免遺失。本次整合前的 Cloudflare Worker 版本為 `7b02e395-4a98-4f26-b6ff-bb4e2c0fbf3d`，必要時可在部署紀錄回復。

驗證採用 Miniflare 執行真實 HTMLRewriter，測試首頁／專案入口、Container Desk 連結保留、條件快取標頭及非目標路徑轉送。瀏覽器另檢查桌面與 390／320 px 手機版、下載跳轉及正式域名。
