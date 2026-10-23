# 主機管理-Macmini contoral

Native SwiftUI fan and temperature monitor for macOS 15 or newer. The selected visual reference is `docs/selected-design.png`.

原生 macOS 選單列風扇與溫度監測工具。可即時查看風扇轉速、CPU／GPU 感測器平均溫度及最近 15 分鐘趨勢，並在管理員授權後使用快速調速控制。支援 macOS 15 以上，macOS 26 以上適量採用 Liquid Glass。

[繁體中文使用說明](docs/使用說明.md) · [實機驗證紀錄](docs/validation.md)

![主視窗實機截圖](docs/main-window.png)

目前已驗證 M4 的即時監測。使用者選擇稍後授權，因此實機調速與恢復自動仍待驗證；macOS 15、Intel 與其他機型尚未完成實機測試。

## Features

- A chart-focused main window with 1, 5, and 15 minute history, per-fan actual RPM, firmware limits, and current mode.
- A persistent menu bar item showing actual RPM and CPU temperature. The panel also shows GPU temperature, manual target selection, Apply, and Restore Automatic.
- Real readings sampled once per second off the main thread. Pausing the chart does not pause sensor readings or control heartbeats. History stays in memory and is not uploaded.
- macOS 26+ uses the native toolbar appearance and one regular Liquid Glass surface for the interactive fan controls. macOS 15 uses standard material. Reduce Transparency uses an opaque control surface. Data and charts never use custom glass.
- Standard system fonts and SF Symbols. Light and dark appearance follow the system.

## Build and launch

Requires Xcode 26 or newer and a valid Apple Development or Developer ID signing identity in Keychain.

```sh
./scripts/build-app.sh
open 'dist/Macmini contoral.app'
```

The script builds arm64 and x86_64, combines both into universal app/helper executables, embeds the launch daemon, and signs the bundle. Override `SIGNING_IDENTITY` to select a different signing certificate. The minimum OS is encoded as 15.0 in both binary architectures and Info.plist.

Install the app in `/Applications` or your `~/Applications` folder before enabling the control service. The local deliverable uses development signing; it is not a notarized public release.

## Fan control authorization

Monitoring needs no administrator permission. Choose **啟用風扇控制** in the menu panel or Settings to register the bundled helper with Apple's `SMAppService`. macOS may request administrator authentication and approval under System Settings → General → Login Items & Extensions. The application does not collect or save an administrator password.

After approval, choose Manual, select a target within the firmware-reported range, and Apply. The target setting and actual fan speed are displayed separately. A successful write is reported only after mode and target readback; physical RPM can take time to settle.

The helper accepts only this app's bundle identifier signed by the same Apple signing team. The app also validates the helper's signature. IPC exposes set-target, restore, ping, and heartbeat; it exposes no arbitrary key writes, shell commands, or filesystem paths.

The service records owned fan IDs before changing hardware in `/var/run/local.macmini.contoral.control.json` (root-owned, mode 0600). It restores owned fans on connection loss, expired 12-second heartbeat lease, serious/critical system thermal state, graceful service termination, and recovery after a service restart. The lease clock includes sleep. The app requests automatic mode before sleep and normal quit. Recovery errors retain journal ownership and are retried. A different program's manual session is not silently taken over.

## Compatibility and limits

OS compatibility and hardware sensor compatibility are separate. Temperature maps cover M1–M4 and common Intel keys; unknown or unavailable temperatures show `—`. A model's sensor average means the mean of readable, valid mapped sensors, not case temperature or ambient temperature. SMC keys and fan writes are hardware-specific and are not a stable public Apple API.

Only the local M4 machine has been available for physical verification. macOS 15 and Intel runtime testing require additional machines. An Intel build is not an Intel hardware test. Do not describe a new model as validated until live reading and restoration tests pass on it.

## Checks

```sh
swift test
swift run MacminiProbe 5
```

Core tests cover decoding, range/non-finite validation before any hardware write, persistence before mutation, external manual ownership, write failure restoration, recovery journals, absent temperatures, and the heartbeat boundary. `MacminiProbe` performs read-only JSON sampling.

See `docs/validation.md` and `design-qa.md` for the actual verification record. See `THIRD_PARTY_NOTICES.md` for Stats attribution and the MIT license.

## Apple references

- [Materials and Liquid Glass guidance](https://developer.apple.com/design/human-interface-guidelines/materials)
- [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)
- [MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra)
- [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
