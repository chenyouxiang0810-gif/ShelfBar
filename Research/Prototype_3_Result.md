# Prototype 3 Result — Touch Bar Drag Destination

## Scope

本階段只驗證 Finder 檔案 drag 的 event routing：

1. Touch Bar 上的 `NSButton` 是否能直接收到 `NSDraggingDestination` callbacks。
2. 若 direct route 不成立，以透明螢幕底邊 `NSPanel` 接收 drag，再更新 system-modal Touch Bar。

沒有 File Shelf、動畫、拖出、開啟檔案或持久化。

## Implemented probes

### Direct Touch Bar probe

`TouchBarPrivateResearch/TouchBarDropButton.swift`：

- 繼承 `NSButton`。
- `registerForDraggedTypes([.fileURL])`。
- override `draggingEntered`、`draggingUpdated`、`prepareForDragOperation`、`performDragOperation`。
- 每個 callback forward 給 `PrivateTouchBarController`，log prefix 是 `touchBar.*`。

Touch Bar 只顯示這個 button，初始 title 是 `📥 Drop Here`。

### Transparent Overlay fallback

`TouchBarPrivateResearch/ScreenEdgeDropOverlayController.swift`：

- borderless、nonactivating、透明 `NSPanel`。
- 位於主螢幕底部中央，寬度最多 1085 points，高度 30 points。
- level 是 `.mainMenu`，可跨 Spaces，App deactivate 後仍顯示。
- content view 註冊 `.fileURL` 並實作相同四個 callbacks。
- callback prefix 是 `overlay.*`。

Overlay `draggingEntered` 後 Touch Bar 改為 `📥 Drop your file here`。`performDragOperation` 從該次 `NSDraggingInfo.draggingPasteboard` 讀 URL，只顯示檔名：

- image：`🖼 filename`
- PDF：`📄 filename`
- folder：`📁 filename`
- movie：`🎬 filename`
- other：`📎 filename`

程式不保存 URL 陣列；callback 結束後只有 button title 留下。

## Callback verification status

| Callback | Direct Touch Bar | Overlay |
|---|---|---|
| `draggingEntered` | Probe implemented; Intel result pending | Implemented; Intel Finder test pending |
| `draggingUpdated` | Probe implemented; Intel result pending | Implemented with location logging; Intel test pending |
| `prepareForDragOperation` | Probe implemented; Intel result pending | Implemented; returns true only for file URLs |
| `performDragOperation` | Probe implemented; Intel result pending | Implemented; reads URLs and updates Touch Bar title |

M5 沒有 Touch Bar，無法從本機觀察 direct callback。M5 也不應被用來推論 Intel 的 DFR event forwarding 行為。

## Why direct Touch Bar drag is expected to fail

### Event Routing

Apple 的 `NSDraggingDestination` 文件明確限定：已註冊 destination 只有在 dragged image 進入其 view bounds 或 window frame 時才收到 callbacks。`NSDraggingInfo.draggingLocation` 也是「destination window base coordinates」中的 mouse pointer 位置：

- [NSDraggingDestination](https://developer.apple.com/documentation/appkit/nsdraggingdestination)
- [draggingEntered](https://developer.apple.com/documentation/appkit/nsdraggingdestination/draggingentered(_:))
- [NSDraggingInfo.draggingLocation](https://developer.apple.com/documentation/appkit/nsdragginginfo/dragginglocation)

實體 Touch Bar 並不是桌面 mouse pointer 可以進入的 `NSWindow` screen rectangle。把 `NSButton` 放進 `NSCustomTouchBarItem` 可以接收 Touch Bar touch/control action，不會自動建立桌面 drag hit-test rectangle。

### NSResponder Chain

一般 responder chain 不會把一個未命中 destination window 的 Finder drag 轉送給任意 responder。Drag destination routing 先依 registered pasteboard type 與 destination geometry 決定 receiver；只有被選中的 destination 才取得 `NSDraggingInfo`。

因此，把 controller、button 或 App delegate 放進 responder chain，不會補上缺少的桌面 destination geometry。

### NSDraggingSession

Finder 是這次 drag 的 source 與 `NSDraggingSession` owner。Source-side movement callback 只屬於 Finder 的 source。另一個 App 必須讓 cursor 進入它的 registered `NSView`/`NSWindow`，才會成為 destination。

Apple 的 drag-and-drop programming guide 也寫明 source/destination 必須代表一塊 screen real estate：[Introduction to Drag and Drop](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/DragandDrop/DragandDrop.html)。

### DFRFoundation

目前找到的 DFRFoundation symbols 與 Pock/MTMR call sites 證明它可以 present system-modal elements、處理 Touch Bar/HID events，但沒有證據顯示它會把 desktop `NSDraggingSession`、Finder pasteboard 與 mouse coordinates bridge 到 `NSCustomTouchBarItem` view。

不能根據現有證據說「DFRFoundation 攔截並丟棄 drag」。較精確的結論是：AppKit desktop drag destination routing 和 DFR Touch Bar rendering/input surface 之間沒有已知 bridge。

### Does Touch Bar have a drag destination?

`NSView` API 層面可以呼叫 `registerForDraggedTypes`，本 Prototype 正是在驗證這件事。但是「method 可呼叫」不代表該 view 所在的 remote Touch Bar surface 具有 desktop drag geometry。若 Intel log 完全沒有 `touchBar.draggingEntered`，限制就在 destination discovery/hit-testing 層，而不是 button override 或 pasteboard parsing。

`prepareForDragOperation` 只有在最近一次 `draggingEntered`/`draggingUpdated` 回傳可接受 operation 後才會被呼叫。Direct route 若連 `draggingEntered` 都沒有，後兩個 callback 必然不會出現。

## True limiting layer

目前證據指向：**真正限制是 AppKit desktop drag session 的 destination discovery、window geometry 與 event routing，位置在 Finder `NSDraggingSession` 和 DFR-rendered Touch Bar surface 之間。**

不是：

- Shelf model 問題（本 Prototype 沒有 Shelf）。
- pasteboard parser 問題（direct route 若未被選為 destination，根本拿不到 `NSDraggingInfo`）。
- standard `NSButton` target/action 問題（Touch Bar touch 與 desktop drag 是不同 input route）。
- 已證實的 DFR「攔截」問題（沒有這項證據）。

Overlay 能工作的原因是它提供真正的 desktop `NSWindow` frame。它不是讓 Touch Bar 成為 `NSDraggingDestination`；它是 screen-edge proxy，接到檔案後再更新 Touch Bar view。

## Intel test procedure

### A. Isolate direct Touch Bar destination

1. 啟動 Prototype 3，確認 Touch Bar 顯示 `📥 Drop Here`。
2. 在 Debug 視窗按 `Disable Overlay`。
3. 從 Finder 拖一個檔案到螢幕底邊，並嘗試移向實體 Touch Bar。
4. 檢查 Debug log 與 Console 是否出現任何 `touchBar.draggingEntered` / `updated`。
5. 若有，放開並檢查 `prepare`、`perform` 與 filename title。
6. 若完全沒有 `touchBar.*`，記錄 macOS version；這是 direct route negative result。

### B. Test Overlay fallback

1. 按 `Enable Overlay`。
2. 從 Finder 把 image、PDF 或兩者一起拖到螢幕底部中央約 30 points。
3. 應依序看到 `overlay.draggingEntered`、一或多個 `overlay.draggingUpdated`。
4. 放開後應看到 `overlay.prepareForDragOperation` 與 `overlay.performDragOperation`。
5. Touch Bar 應顯示例如 `🖼 image.png   📄 report.pdf`。

## Current status

- Direct callback instrumentation: complete.
- Transparent Overlay fallback: complete.
- arm64/x86_64 type check: passed.
- Universal Release v0.3 build: passed; binary contains `x86_64 arm64` and links DFRFoundation.
- M5 smoke test: passed for app launch, system-modal presentation call, Overlay creation, normal quit, and system-modal dismissal; no crash observed.
- M5 cannot verify physical Touch Bar destination callbacks or a Finder drop onto that surface.
- Intel direct/fallback empirical result: pending.

完成後停止；沒有進入 File Shelf。
