# Prototype 4 Result

## 這版要測什麼

Prototype 4 的唯一目標，是在 Intel Touch Bar 實機上判斷 DFR system-modal Touch Bar 內的 `NSButton`，是否真的會被 Finder drag session 選為 `NSDraggingDestination`。

Direct Touch Bar view 與螢幕底部 Overlay 都註冊 `NSPasteboard.PasteboardType.fileURL`，並各自記錄：

- `draggingEntered`
- `draggingUpdated`
- `prepareForDragOperation`
- `performDragOperation`
- `draggingExited`
- `draggingEnded`

Touch Bar 顯示最近事件、每個來源的總 callback 計數，以及 `CLEAR LOG`。App 視窗將 `touchBar.*` 和 `overlay.*` 放在不同 log 區域，Console 也會列印完整事件名稱。

## 建置與本機驗證

- arm64 type-check：通過。
- x86_64 type-check：通過。
- Universal Release：已建立，binary architectures 為 `x86_64 arm64`。
- App 版本：0.4 (4)。
- M5 smoke test：system-modal presentation、Debug 視窗建構、正常 dismissal 與退出均未 crash。
- Intel Touch Bar Finder drag：尚未實測，不能由 M5 結果推論。

## Intel 實測結果

尚未實測。以下欄位留給 Intel Touch Bar 實機填寫，不預先宣告結果。

- Intel 機型：待填
- macOS 版本：待填
- Touch Bar callback 是否增加：待填
- 出現的 Touch Bar callbacks：待填
- Overlay callback 是否增加：待填
- Console 摘要：待填

## 如果 Touch Bar callback 有增加

若停用 Overlay 後，左側 log 或 `TB` 計數出現 `touchBar.draggingEntered`，代表 Finder 的 desktop drag session 至少能找到 DFR-rendered Touch Bar view，並把它當作 drag destination 傳送 `NSDraggingInfo`。

若進一步出現 `prepareForDragOperation` 和 `performDragOperation`，代表該 Touch Bar view 不只收到 hover/route callback，也能完成 Finder file URL drop 並讀取 dragging pasteboard。這才足以證明 private system-modal Touch Bar 可以直接接收檔案 drop。

只有 `draggingEntered`/`draggingUpdated`、沒有 `performDragOperation`，只能證明 routing 部分成立；仍需依 callback 回傳值、pasteboard URL 和放開位置分析 drop 為何未完成。

## 如果 Touch Bar callback 完全沒有增加

若 Overlay 已停用，檔案拖到實體 `DROP HERE` 時 `TB` 仍為 0，左側 log 與 Console 也完全沒有 `touchBar.*`，代表 `registerForDraggedTypes` 雖可在該 `NSView` 呼叫，但 Finder/AppKit 沒有把 DFR Touch Bar surface 納入 desktop drag destination discovery。

此 negative result 指向 Finder `NSDraggingSession` 與 DFR-rendered Touch Bar surface 之間的 geometry、hit-testing 或 event-routing 邊界。它不是 pasteboard parser 失敗，因為程式連 `NSDraggingInfo` 都沒有收到；也不能在沒有額外證據時寫成「DFRFoundation 主動攔截事件」。

## Overlay 成功但 Touch Bar 失敗時的結論

若右側 `overlay.*` 正常出現，而且 `prepareForDragOperation`、`performDragOperation` 成功，但 `touchBar.*` 完全沒有事件，可排除共用 callback recorder、Finder file URL pasteboard 和基本 AppKit destination 實作問題。

結論會是：一般 desktop `NSWindow`/`NSView` 能成為 Finder drag destination；同一套 destination code 放進 DFR system-modal Touch Bar 後，該 remote surface 沒有取得 desktop drag routing。Overlay 只能作為 screen-edge proxy，不能證明 Touch Bar 本體支援 drag destination。

## 實測注意事項

1. Direct Touch Bar 測試前先按 `Disable Overlay`。
2. 按 `CLEAR LOG`，確認 `TB 0 | OV 0`。
3. 從 Finder 拖檔案到實體 Touch Bar `DROP HERE` 並放開。
4. 記錄左側 log、Touch Bar 計數與 Console。
5. 啟用 Overlay，清除 log，再以相同檔案測試螢幕底部中央 30 point 區域。

Prototype 4 沒有 File Shelf、動畫、拖出功能或檔案持久化。
