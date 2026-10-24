# 驗證紀錄

最新補充：[2026-10-24 手動控制實機測試](manual-control-validation-2026-10-24.md)。已完成本機修正版的升速、降速與恢復自動驗證。以下保留 2026-10-23 原始版本的驗證紀錄。

日期：2026-10-23（Asia/Taipei）。版本：1.0.0。

## 已驗證

| 項目 | 結果與證據 |
| --- | --- |
| 本機環境 | Mac mini／Apple M4（Mac16,10），macOS 26.7.1，Xcode 27.1 |
| Universal 編譯 | App 與輔助程式含 arm64、x86_64；App 兩架構最低版本皆為 macOS 15.0，SDK 27.0。見 `build-final.log`。 |
| 簽署 | 使用本機 Apple Development 身分簽署；`codesign --verify --deep --strict` 通過。這是本機開發版本，尚未公證。 |
| 核心測試 | 11 項 XCTest 通過、0 失敗。見 `tests.log`。涵蓋數值解碼、無效目標拒絕、先記錄再寫入、外部手動模式保護、寫入失敗恢復、恢復重試及感測器缺值。 |
| 真實感測器 | 連續 5 筆唯讀 JSON：1 顆風扇，999–1,001 RPM，硬體範圍 1,000–4,900 RPM；CPU 12 個、GPU 8 個有效感測器。見 `live-samples.jsonl`。 |
| 主視窗 | 真實資料每秒更新、圖表與硬體資訊表正常顯示；1／5 分鐘切換與圖表暫停、繼續已操作驗證。暫停圖表時感測器仍更新。 |
| 快速控制面板 | 透過工具列開啟與 MenuBarExtra 共用的面板；CPU／GPU、RPM、自動／手動切換、2,000 RPM 未套用目標與 1,000–4,900 RPM 範圍皆可見。未授權時套用及恢復按鈕停用。見 `control-panel-manual.png`。 |
| 視覺 | 原生字體、SF Symbols、白色內容區與控制區 Liquid Glass 已於 macOS 26 實際截圖。見根目錄 `design-qa.md`。 |

## 授權狀態與未完成的實機測試

使用者選擇「稍後再授權」。SMAppService 已註冊，狀態為等待系統允許；系統設定內對應項目尚未開啟。本次未輸入管理員密碼、未啟動 root 控制服務、未實際寫入風扇設定。

調速、實際 RPM 收斂、恢復自動、輔助程式崩潰與睡眠後的硬體恢復，**尚未在實機驗證**。單元測試使用假硬體介面，只驗證控制邏輯，不能替代上述測試。

macOS 15、Intel、M1–M3 及其他機型未有實機可測；編譯成功不表示所有感測器與 SMC 寫入相容。未知溫度會顯示「—」。深色與「降低透明度」具有系統適配程式碼，但未變更使用者的全域外觀設定進行視覺測試。

MenuBarExtra 已編譯且使用相同的即時模型與控制面板；本次原生截圖工具只捕捉 App 視窗，因此沒有保存選單列錨點本身的截圖。

## 交付位置

- 已安裝：`/Users/server/Applications/Macmini contoral.app`
- 原始碼：`/Users/server/Project/MacminiContoral`
- App 壓縮包：`dist/Macmini-contoral-1.0.0-macos-universal.zip`
- 使用說明：`使用說明.md`
