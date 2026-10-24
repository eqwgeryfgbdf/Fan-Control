# 手動控制實機測試

日期：2026-10-24，Asia/Taipei。裝置：Mac mini、Apple M4、Mac16,10。這份紀錄適用於本機修正版，不適用於已發布的 v1.0.0 DMG。

## 結果

實際透過 App 工具列的風扇控制面板操作，另以 MacminiProbe 每秒唯讀取樣交叉確認模式、目標和實際 RPM。

| 步驟 | 連續樣本 | 實際 RPM | 硬體模式 | 回讀目標 |
| --- | ---: | --- | --- | ---: |
| 自動控制基準 | 3 | 1,000 | 自動（0） | 1,000 |
| 手動 1,500 RPM | 20 | 1,498–1,501 | 手動（1） | 1,500 |
| 最終修正版手動 2,000 RPM | 20 | 1,997–2,002 | 手動（1） | 2,000 |
| 從 2,000 調低至 1,500 RPM | 10 | 1,498–1,502 | 手動（1） | 1,500 |
| 恢復自動控制 | 15 | 999–1,001 | 自動（0） | 1,000 |

所有取樣的系統熱狀態均為 nominal（0）。最後畫面顯示「已恢復自動調節」，CPU 約 53°C、GPU 約 47°C；App 保持執行，風扇由 macOS 自動控制。

升速和降速過程會有短暫超調，上表為指令完成後記錄的取樣範圍，不是機械瞬間到達目標的保證。

## 發現與修正

1. 輔助服務無法啟動：launchd 實際以 `Contents/MacOS/MacminiHelper` 作為 argv[0]。原實作將此相對路徑用於定位 App，導致簽署團隊資訊讀取失敗並以 exit 1 結束。改用 dyld 提供的實際執行檔路徑定位 App。修正後 launchd 顯示服務持續 running。
2. 韌體回讀延遲：寫入成功後立即回讀，會誤判為設定未成功。手動設定與恢復自動現在最多等待 1 秒、每 50 ms 重新讀取；仍無法確認時保留原本失敗回復與持續恢復機制。
3. 設定新增「重新啟動控制服務」，使用 SMAppService 解除註冊、等待移除完成後重新註冊；手動控制期間停用此按鈕。本機已操作確認重啟成功。

這台機器目前使用 `F0Md`，`F0md` 與 `Ftst` 不存在。測試未停用或變更系統散熱服務。

## 驗證

- 14 項核心測試通過：新增延遲目標回讀、延遲自動模式回讀，以及回讀逾時後恢復自動的回歸案例。
- Universal App／helper 編譯完成，最低版本仍為 macOS 15。
- 安裝後 `codesign --verify --deep --strict` 通過。
- 輔助程式以絕對路徑、相對 BundleProgram 和僅檔名作為 argv[0]，在 `/` 工作目錄下的唯讀 `--validate-installation` 檢查皆通過。
- 本機安裝：`/Users/server/Applications/Macmini contoral.app`。
- 本機證據：`dist/manual-control-test-2026-10-24/`，含逐秒 JSON、摘要、手動／自動畫面與最終可及性狀態；測試與建置輸出為 `dist/tests-manual-control.log`、`dist/build-manual-test.log`。

最終安裝的執行檔 SHA-256：

```text
MacminiContoral 28900eb1af36e6caeb418fa3bd587e7911a4fe46af8987db0273d619aa581629
MacminiHelper   99d62902cbc66757e9eed442abfe211518ff02eb32f0d47a45df6e8ed5dd1188
```

## 範圍

本次驗證的是此 M4 Mac mini 的一般手動升速、降速及恢復自動。沒有進行最高轉速、系統過熱、強制終止服務、睡眠／喚醒或其他 Mac／macOS 版本的實機測試。選單列面板與工具列共用控制實作；本次操作來自工具列面板。

原 v1.0.0 DMG 及 GitHub Release 保留原內容。上述測試先於版本標示更新完成，修正內容納入 v1.0.1（build 2）；測試摘要另存於 [JSON 紀錄](manual-control-test-results.json)。原安裝備份保留於 `dist/backup-v1.0.0-before-manual-test.app`。修正版仍使用 Apple Development 簽署，尚未經 Apple 公證。
