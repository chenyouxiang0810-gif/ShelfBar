# Prototype 10 — Finder Copy Drag 修正

## 目標

專攻 Shelf → Finder／Desktop／Folder，確認 Finder 是否會把原始 Shelf item 接受為真正 `.copy`，而不是 `.link` Alias。本 Prototype 不修改 AutoDrop，也不改 MouseBridge 的底邊座標、hover、click 或 drag 手感。

## NSDraggingSource

實作位置：`TouchBarPrivateResearch/MouseBridgeResearchController.swift`

- `MouseBridgeEdgeController.EdgeView.draggingSession(_:sourceOperationMaskFor:)`
- `DirectTouchBarFileButton.draggingSession(_:sourceOperationMaskFor:)`

兩個 route 對 `withinApplication` 與 `outsideApplication` 都只回傳 `.copy`。Debug 會列出：

- `context=withinApplication isLocal=true allowed=copy`
- `context=outsideApplication isLocal=false allowed=copy`

不再回傳 `.link`。Prototype 9 已證明 `.link` 會讓 Finder 建立 Alias，不是正常檔案。

Apple 的文件示例同樣對 outside-application context 回傳 `.copy`。[NSDraggingSource operation mask](https://developer.apple.com/documentation/appkit/nsdraggingsource/draggingsession%28_%3Asourceoperationmaskfor%3A%29)

## Pasteboard 格式研究

### URL drag mode

`ResearchFilePasteboardWriter` 以 `.fileURL` 建立 `NSDraggingItem`，`addURLRepresentations(to:url:)` 再加入 `.URL`。

實際 drag pasteboard 包含：

- `public.file-url`（`.fileURL`）
- `public.url`（`.URL`）
- `NSFilenamesPboardType`（AppKit 自動產生的舊格式）
- `Apple URL pasteboard type`
- CorePasteboard / dynamic UTI flavors

所有值都指向原始 Shelf URL。App 沒有 `copyItem`、`moveItem` 或暫存檔。

### `.fileContents`

沒有加入。Apple 已將 extension-based file-contents pasteboard API 標為舊路徑，建議改用 UTI；更重要的是 `.fileContents` 需要把完整檔案資料放入 pasteboard，對任意大小的 Shelf item 不適合，也不等同於把既有 file URL 交給 Finder。[Apple `.fileContents`](https://developer.apple.com/documentation/appkit/nspasteboard/pasteboardtype/filecontents)

### `NSFilenamesPboardType`

目前 SDK 將該 symbolic API 標為 unavailable／legacy；用 literal type 建立只有 legacy flavor 的 `NSDraggingItem` 時，AppKit 會輸出 invalid-UTI warning，甚至可能不建立有效 session。因此正式 writer 以 `.fileURL` 為主，讓 AppKit自行產生 compatibility flavor。

## NSFilePromiseProvider Probe

App 視窗新增獨立開關：

`Finder File Promise Probe (acceptance only; writes no file)`

預設 OFF。開啟後 FILE drag 改由 `FinderFilePromiseProbe` 建立 `NSFilePromiseProvider`：

- `fileType` 使用來源 URL 的 `UTType`；資料夾使用 `public.folder`。
- `fileNameForType` 回傳來源檔名。
- `operationQueue(for:)` 使用獨立 serial queue。
- Drag source 會強持有 probe delegate 到下一次 drag；`NSFilePromiseProvider.delegate` 是 weak，而 fulfillment 可能在 `endedAt` 之後才開始。
- `writePromiseTo` 若被呼叫，會記錄 Finder 提供的 destination URL，然後回傳刻意設計的 error。
- 不會在 destination 寫入、複製或建立空檔案。

Apple 明確規定 provider delegate 必須把 promised contents 寫到傳入的 destination URL；因此「Finder 接受 promise」可以先驗證，但「完成真正 copy」不可能在完全不寫檔的 Probe 中成立。[NSFilePromiseProvider](https://developer.apple.com/documentation/appkit/nsfilepromiseprovider)、[writePromiseTo](https://developer.apple.com/documentation/appkit/nsfilepromiseproviderdelegate/filepromiseprovider%28_%3Awritepromiseto%3Acompletionhandler%3A%29)

### Promise pasteboard types

實際 `NSDraggingSession` 列出：

- `com.apple.NSFilePromiseItemMetaData`
- `com.apple.pasteboard.promised-file-name`
- `com.apple.pasteboard.promised-suggested-file-name`
- `com.apple.pasteboard.promised-file-content-type`
- `Apple files promise pasteboard type`
- `com.apple.pasteboard.NSFilePromiseID`
- `NSPromiseContentsPboardType`
- `com.apple.pasteboard.promised-file-url`
- dynamic UTI flavors

這些類型全部由 public `NSFilePromiseProvider`／drag session 產生；程式沒有手動偽造 `com.apple.pasteboard.promised-file-url`。

`NSFilePromiseReceiver` 是 destination 端讀取 promise 的 API，不是 source 端修正 Finder 接受行為的工具。其 `readableDraggedTypes` 包含 promise metadata、dynamic promise type 與 promised content type。[NSFilePromiseReceiver](https://developer.apple.com/documentation/appkit/nsfilepromisereceiver)

## Debug

App 視窗與 Console 現在會記錄：

- URL mode / File Promise Probe mode
- 完整 pasteboard types
- promise UTI、來源與 filename request
- promise destination request（如果 Finder 接受並要求 fulfillment）
- operation mask
- `isLocal=true/false`
- final operation
- `FinderAccepted`／`FinderRejected`／`Cancelled`

注意：`FinderAccepted` 是由 source 的 final operation 推定。Finder process 內部的 `draggingEntered`／`performDragOperation` 不會跨 process 傳回本 App。

## M5 實測

環境：macOS 26.6 build 25G5052e，MouseBridge desktop edge route，70-byte plain-text fixture。

### Finder Folder

- Promise types：完整出現。
- outside operation mask：`.copy`。
- final operation：`.none`。
- `FinderAccepted=false`、`FinderRejected=true`。
- `writePromiseTo`：沒有被呼叫。
- destination：沒有建立檔案。

### Finder Desktop

- Promise types：完整出現。
- final operation：`.none`。
- `writePromiseTo`：沒有被呼叫。
- Desktop：沒有建立檔案。

這表示在本機 M5/macOS 26.6 測試中，Finder 連 promise 都沒有接受；不是因為 Probe 刻意在 fulfillment 階段回傳 error，因為 fulfillment callback 根本沒有開始。

## Intel 實測欄位

Prototype 1–7 的 Intel Touch Bar 結果不能代替本版 Finder promise 測試。請使用 3.5 (8)：

1. Shelf 放入一個可安全測試的小檔案。
2. 開啟 MouseBridge research。
3. 先關閉 Promise Probe，測 URL `.copy` 到 Finder folder／Desktop。
4. 再開啟 Promise Probe，重複測試。
5. 若 log 出現 `File Promise destination requested`，代表 Finder 已接受 promise 並要求寫入。
6. 本版會刻意回傳未寫檔 error，因此不應期待目的端留下檔案。

待填結果：

- Intel URL mode / Finder folder：**Pending**
- Intel URL mode / Desktop：**Pending**
- Intel Promise mode / Finder folder：**Pending**
- Intel Promise mode / Desktop：**Pending**
- Intel `writePromiseTo` callback：**Pending**

## 結論

**尚未修正 Finder copy；研究 Probe 完成。**

- `.copy` mask、local/non-local debug：完成。
- `.fileURL`／`.URL`／compatibility flavors：完成。
- `NSFilePromiseProvider` 最小 acceptance-only Probe：完成。
- M5 Finder folder／Desktop 接受 promise：失敗。
- 真正 file promise copy：本版刻意不實作，因為 Apple API 要求 source 寫入 destination，與本階段「不要真的複製內容」相衝突。
- 是否值得做下一版：只有在 Intel 顯示 Finder 會呼叫 `writePromiseTo` 時，才值得新增明確授權的實際 copy fulfillment。
