# Fan Control v1.0.4

2026-10-26（Asia/Taipei）。版本 1.0.4，build 7；Universal 支援 Apple Silicon 與 Intel，最低 macOS 15。

## 新增與改善

- 軟體名稱統一為 **Fan Control**：App 套件、主視窗、選單列面板及授權提示同步更新，介面說明保留繁體中文。
- 主畫面直接並排顯示所有實際偵測到的風扇，每顆具備獨立 RPM、走勢、目標輸入與快捷調速，不需切換。
- 單風扇使用完整寬度；多顆風扇依視窗寬度換行，工具列提供「全部恢復自動」。
- 保留選單列即時 RPM、CPU／GPU 溫度、小走勢圖與快速調速。

## 下載與更新

1. 先將舊版恢復自動控制並結束 App。
2. 開啟 DMG，將 **Fan Control.app** 拖至 Applications。新版名稱不同，安裝後移除舊的「風扇管理 Fan Control.app」或「Macmini contoral.app」副本。
3. 從安裝位置開啟新版，在設定按「重新啟動控制服務」，確認服務版本為 `1.0.4（7）`。若 macOS 要求允許，於登入項目與延伸功能完成授權。

[官網](https://fancontrol.emo-lab.com/) · [完整專案](https://github.com/eqwgeryfgbdf/Fan-Control)

## 驗證範圍

- 本次重新建置與執行 29 項測試，全部通過；App／helper 均含 arm64、x86_64，最低 macOS 15.0。
- DMG 完整性、唯讀掛載、App 深度簽章與 helper 安裝定位驗證通過；7 個檔案與建置結果逐一一致。
- 多風扇版面曾以實際 MonitorView 配合 0／1／2／4 顆模擬風扇驗證，包含非連續 ID、獨立目標輸入與歷史走勢。詳見 [多風扇版面紀錄](https://github.com/eqwgeryfgbdf/Fan-Control/blob/v1.0.4/docs/multi-fan-dashboard.md) 與 [打包驗證](https://github.com/eqwgeryfgbdf/Fan-Control/blob/v1.0.4/docs/package-validation-v1.0.4.json)。
- 此輪僅建置與發布，未更換已安裝的 App 或操作實機風扇。v1.0.4 實機調速、實體多風扇、macOS 15 與 Intel 執行仍待驗證。

此版本使用 Apple Development 簽署，尚未經 Apple 公證。

## 安裝檔

- `Fan-Control-1.0.4-macos-universal.dmg`：3,775,385 bytes。
- SHA-256：`a966d8cbf08b88111bf34a5ffe13df582f97899658172c8fc91c3b27fcc5ad45`。
- 另附 `.dmg.sha256` 校驗檔。完整原始碼包含 Sources、Resources、Tests、建置／打包腳本、官網與驗證文件，排除機密及暫存建置產物。
