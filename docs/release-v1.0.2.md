# 風扇管理 Fan Control v1.0.2

日期：2026-10-24（Asia/Taipei）。App 版本 1.0.2，build 4。

## 此版本

- 正式更名為「風扇管理 Fan Control」：App bundle、視窗、選單列面板、授權提示、套件名稱與安裝文件同步更新。
- 頂端選單列顯示單色迷你轉速走勢；展開後提供最近一分鐘的曲線、轉速範圍及時間刻度。
- 保留即時 RPM、CPU／GPU 平均溫度、快速手動調速與恢復自動。設定可關閉頂端迷你圖。
- 選單列走勢獨立取樣，不受主視窗圖表暫停影響；缺值保留空缺，不填入模擬數據。

為延續既有偏好設定與輔助服務驗證，bundle identifier、helper identifier 與內部執行檔識別保持相容。GitHub 倉庫仍為使用者指定的 `eqwgeryfgbdf/MacminiContoral`。

## 驗證

- 17 項核心與圖表資料測試通過；建置紀錄為 `dist/build-v1.0.2.log`，測試紀錄為 `dist/tests-v1.0.2.log`。
- Universal App／helper 均包含 arm64、x86_64；兩種架構的最低 macOS 版本均為 15.0。
- DMG 本身的完整性與 SHA-256 驗證通過。
- 唯讀掛載後確認新版名稱、版本 1.0.2／build 4、Applications 捷徑、App 深度簽章、helper 安裝定位，以及全部 7 個一般檔案與建置內容一致。
- 詳細打包結果：[package-validation-v1.0.2.json](package-validation-v1.0.2.json)。
- 圖表與實際選單列調速功能已於同日 M4 Mac mini、macOS 26.7.1 的本地 build 3 驗證，包含 2,000 RPM、降至 1,500 RPM、恢復自動及 CPU／GPU 溫度更新；頂端迷你圖由使用者確認可見。詳見 [實機紀錄](menu-bar-chart-validation-2026-10-24.md)。本次 build 4 更名及版本更新未變更控制演算法。

此版本以 Apple Development 簽署，尚未經 Apple 公證。macOS 15、Intel 及其他硬體仍未完成實機驗證；不將 Universal 編譯成功視為這些裝置已通過實測。

## 安裝與更新

下載 [v1.0.2 Release](https://github.com/eqwgeryfgbdf/MacminiContoral/releases/tag/v1.0.2) 的 `Fan-Control-1.0.2-macos-universal.dmg`。私有倉庫需登入有權限的 GitHub 帳號。

1. 舊版先恢復自動調節並結束 App。
2. 因 v1.0.2 已更名，先移除 Applications 中舊的 `Macmini contoral.app`，再將 DMG 內的「風扇管理 Fan Control.app」拖至 Applications，避免保留兩份相同 App。
3. 從安裝位置開啟新版，在設定按「重新啟動控制服務」；尚未啟用時按「啟用風扇控制」。若 macOS 要求授權，請在登入項目與延伸功能完成。

## 安裝檔

- 檔案：`Fan-Control-1.0.2-macos-universal.dmg`
- 大小：3,711,089 bytes。
- SHA-256：`2d7579ef412b0cc12705e50bace6167f98b92498441e7e91f9740ac3392321a4`
- 另附 `.dmg.sha256` 校驗檔；v1.0.0、v1.0.1 的既有 Release 保留原內容。
