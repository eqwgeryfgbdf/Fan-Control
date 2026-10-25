# Fan Control 名稱統一

2026-10-26，依使用者要求移除軟體名稱中的中文，介面功能與說明維持繁體中文。

- 開發版 v1.0.4（build 7）使用 `Fan Control.app`；CFBundleName、CFBundleDisplayName、主視窗、選單列面板與授權提示皆統一為 Fan Control。
- 打包腳本、磁碟名稱與安裝說明同步；升級文件仍列出舊名稱供辨識。
- Bundle ID 與控制服務識別維持原值，未更動既有授權識別或風扇控制邏輯。
- Universal 建置成功；App 與 helper 簽章驗證通過，arm64／x86_64 最低 macOS 15.0。Info.plist 的英文名稱及 build 7 驗證通過。
- 建置位於 `dist/Fan Control.app`，尚未安裝或製作新 Release。既有 v1.0.3 DMG 與歷史測試紀錄保留原始名稱；Release 顯示標題與公開下載說明已更新。

## v1.0.4 發布更新

本頁上方保留功能完成當時的驗證狀態。2026-10-26 已以英文名稱 Fan Control、build 7 完成打包發布；最新驗證與安裝說明見 [v1.0.4 Release 紀錄](release-v1.0.4.md)。本次發布未取代本機已安裝 App。
