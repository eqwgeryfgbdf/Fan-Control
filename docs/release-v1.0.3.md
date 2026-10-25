# Fan Control v1.0.3

日期：2026-10-26（Asia/Taipei）。App 版本 1.0.3，build 5。Universal 支援 Apple Silicon 與 Intel，最低 macOS 15。

## 新增與改善

- 選單列可分別顯示 RPM、CPU、GPU 數字及迷你走勢圖，保留展開面板的完整即時讀值與最近一分鐘圖表。
- 手動面板新增 1,500／2,000／2,500 RPM 快速套用及整數轉速輸入，可按 Enter 或「套用轉速」確認。快捷選項依硬體範圍顯示，無效或超出範圍的數字不能套用。
- 調速前確認控制服務連線、協定、版本與 build。舊服務會提示更新；成功恢復自動後才切換顯示狀態。
- 控制服務獨立監測正在控制的風扇；讀值或原本可用的 CPU／GPU 溫度持續失效三秒時恢復自動控制，並保留失敗後重試機制。

## 驗證範圍

- 29 項自動測試已通過；本次打包未修改程式，DMG 內 App／helper 與已安裝實測的 build 5 SHA-256 完全相同。
- M4 Mac mini、macOS 26.7.1 已驗證展開面板即時讀值、圖表、快捷 1500／2000 RPM、輸入 1800 RPM 後按 Enter，以及非法輸入拒絕。
- 實際穩定轉速：1500 目標為 1498–1501 RPM；2000 目標為 1999–2002 RPM；1800 目標為 1798–1801 RPM。測試後恢復自動模式，最後五筆為 999–1000 RPM。
- 使用者已確認頂端選單列 RPM、CPU、GPU 與小走勢圖四項均有顯示。詳見 [安裝實測](v1.0.3-install-validation-2026-10-26.md)。
- DMG 完整性、唯讀掛載、App 深度簽章、helper 安裝定位、7 個檔案一致性、兩種架構最低 macOS 15.0 均已驗證，詳見 [打包驗證](package-validation-v1.0.3.json)。

此版使用 Apple Development 簽署，尚未經 Apple 公證。macOS 15、Intel、其他機型與睡眠／喚醒仍未完成實機驗證；感測器失效保護以模擬硬體測試，未進行實體故障注入。

## 下載與更新

[v1.0.3 Release](https://github.com/eqwgeryfgbdf/Fan-Control/releases/tag/v1.0.3)。原 MacminiContoral 倉庫目前已更名為 `eqwgeryfgbdf/Fan-Control`，現已公開，可直接下載，無須登入 GitHub。

1. 舊版先恢復自動調節並結束 App。
2. 開啟 DMG，將「風扇管理 Fan Control.app」拖至 Applications，取代舊版。
3. 從安裝位置開啟新版，在設定按「重新啟動控制服務」，確認顯示 `1.0.3（5）` 與「可調速」。首次啟用時依 macOS 提示完成授權。

本機目前已安裝相同 build 5，無須為本次打包重新安裝。

## 安裝檔

- `Fan-Control-1.0.3-macos-universal.dmg`：2,968,417 bytes。
- SHA-256：`dd7147ce04569f8ae489e96acb6cb20ed52230f61ed802389f4df63883ca39f1`。
- 另附 `Fan-Control-1.0.3-macos-universal.dmg.sha256` 校驗檔。

原始碼包含完整 Sources、Resources、Tests、建置／打包腳本及驗證文件，排除機密、快取與暫存建置產物。先前透過 API 同步產生的遠端歷史，已在確認 v1.0.2 檔案樹完全相同後與本地歷史連接；保留兩邊既有提交，無須強制推送。
