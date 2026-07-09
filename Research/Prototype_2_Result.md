# Prototype 2 Result — Dynamic Touch Bar Interaction

## Scope

Prototype 2 只研究 system-modal Touch Bar 的按鈕事件與動態 UI 更新：

- `HELLO` / `Pressed: N`
- `TEST`
- `CLEAR`
- 每秒更新的右側時間

沒有 Finder drag、`NSDraggingDestination`、pasteboard 或 File Shelf。

## Implementation

實作位於 `TouchBarPrivateResearch/PrivateTouchBarController.swift`：

1. `TEST` action 增加 `testPressCount`，直接修改既有 `helloLabel.stringValue` 為 `Pressed: N`。
2. 同一 action 透過 `onStatusChange` 更新 Debug 視窗，並印出 `TEST pressed (N)`。
3. `CLEAR` action 將 counter 設為 0，恢復 `HELLO`，視窗顯示並印出 `Cleared`。
4. `Timer` 加入 main run loop 的 common mode，每秒只更新獨立的 `clockLabel`。

時間和 counter 使用不同 `NSTouchBarItem` 與不同 label，因此計時器不會覆蓋 `Pressed: N`。

## 是否能更新 Touch Bar

程式已經以持有的 `NSTextField` reference 原地更新 Touch Bar item view。arm64/x86_64 編譯可以驗證 API 與型別路徑，但 M5 沒有實體 Touch Bar，無法在本機宣稱畫面更新已通過。

Intel 實機應確認：

- 初始顯示 `HELLO`。
- TEST 依序顯示 `Pressed: 1`、`Pressed: 2`。
- 時鐘每秒更新，但左側 `Pressed: N` 保持不變。
- CLEAR 後立即恢復 `HELLO`。

## 是否能接收按鈕事件

`TEST` 與 `CLEAR` 都使用標準 `NSButton` target/action。事件處理與 private presentation 分離；private API 只負責讓整個 `NSTouchBar` 成為 system-modal。

M5 無法產生實體 Touch Bar touch event，因此 Intel 實機仍需確認：

- TEST 每次觸控只增加一次。
- App 視窗顯示 `TEST pressed (N)`。
- Console 同步印出 `[TouchBarPrivateResearch] TEST pressed (N)`。
- CLEAR 將 counter 歸零，視窗與 Console 都顯示 `Cleared`。

## Intel 實機測試清單

1. 啟動 Release App，確認 system-modal bar 有 counter、TEST、CLEAR 與右側時間。
2. 連按 TEST 至至少 3，核對 Touch Bar、App 視窗、Console 三者一致。
3. 等待至少 5 秒，確認時間持續走、counter 不被時間覆寫。
4. 按 CLEAR，確認 counter 歸零且回到 `HELLO`。
5. 再按 TEST，確認從 `Pressed: 1` 重新開始。
6. 切換前景 App，觀察 system-modal bar 與 timer 是否持續；若被系統 dismiss，記錄 macOS 版本與操作順序。
7. 結束 App，確認 dismissal 不 crash。

## Current result

- Source implementation: complete.
- arm64 and x86_64 type check: passed.
- Universal Release v0.2 build and DFRFoundation linkage: passed.
- M5 launch, timer setup, system-modal present, normal quit, and dismiss smoke test: passed without crash.
- Intel dynamic UI and touch verification: pending.

完成後停止；下一個 Finder drag Prototype 尚未開始。
