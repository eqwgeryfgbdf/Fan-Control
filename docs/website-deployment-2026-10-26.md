# Fan Control 官網與公開下載

日期：2026-10-26（Asia/Taipei）。

- 官網：https://fancontrol.emo-lab.com/，使用 Cloudflare Workers Static Assets、Custom Domain 與 HTTPS。
- EMO-Lab 首頁與專案頁已加入 Fan Control，既有 Container Desk 入口保留。
- 原創風扇 SVG Logo、大字級、系統字體、輕量進場／按鈕動畫；遵循降低動態效果設定，無彈出提示。
- 產品名稱為 **Fan Control**，說明仍為繁體中文。
- 使用者最終選擇直接公開既有 `eqwgeryfgbdf/Fan-Control` 倉庫；未另建下載倉庫。官網按鈕導向最新 GitHub Release。

## 驗證

- 桌面、390 px 與 320 px 版面已目視檢查；修正窄螢幕水平溢出與導覽換行。瀏覽器尺寸已恢復。
- 正式網域 5 個主要資產與本地檔案逐位元一致，HTTPS 200 與安全標頭正常。
- 真實 HTMLRewriter 測試通過：首頁／專案頁新增入口、保留原內容、條件快取處理及非目標路徑原樣轉送。
- 未登入 Chrome 點擊官網下載可開啟 v1.0.3 Release；無憑證下載 DMG 成功，2,968,417 bytes，SHA-256 與已發布紀錄一致。
- Git 歷史 116 個 blob 與新網站檔案的常見金鑰／私鑰／憑證 URL 檢查未出現可疑命中；未將本機 OAuth、快取或建置產物納入版本控制。此為針對性檢查，非完整安全稽核。

已發布安裝檔維持 v1.0.3，名稱更新及多風扇主畫面在 v1.0.4 開發版；本次未建立新 Release、重新上傳舊版 DMG 或取代已安裝 App。v1.0.3 的實際截圖仍保留其原始名稱，並標示版本。

部署版本與下載校驗見 [機器可讀紀錄](website-deployment-2026-10-26.json)。
