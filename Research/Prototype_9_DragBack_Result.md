# Prototype 9 — Drag Back（Shelf → Finder）

## 目的

沿用已在 Intel 驗證可拖出的 MouseBridge，確認 Shelf 內的原始 file URL 能否由 `NSDraggingSession` 交給 Finder 與其他 App。App 不建立暫存檔、不複製來源，也不使用 `NSFilePromiseProvider`。

## 最終實作

檔案：`TouchBarPrivateResearch/MouseBridgeResearchController.swift`

- `ResearchFilePasteboardWriter` 先以 `.fileURL` 建立 `NSDraggingItem`。
- `addURLRepresentations(to:url:)` 再於同一個 public `NSDraggingSession.draggingPasteboard` 加入 `.URL`。
- 寫入值全部是 Shelf item 的原始 `URL.absoluteString`；沒有 `copyItem`、`moveItem` 或 file promise。
- AppKit 另外自動產生 `NSFilenamesPboardType`、Apple URL flavor 及 CorePasteboard flavors。
- source operation mask 最終只回傳 `.copy`。`.link` 未保留，原因見 Finder 實測。

Apple 的 `NSDraggingSource` 文件建議跨 App context 回傳 `.copy`；`NSDraggingItem` 接受任何 `NSPasteboardWriting` 物件。[Apple NSDraggingSource operation mask](https://developer.apple.com/documentation/appkit/nsdraggingsource/draggingsession%28_%3Asourceoperationmaskfor%3A%29)、[Apple NSDraggingItem](https://developer.apple.com/documentation/appkit/nsdraggingitem)

## Debug 記錄

App 視窗新增唯讀 `Prototype 9 Drag Session Debug` 區域及 `Clear Drag Log`。Console 同時以 `[Prototype9.DragBack]` 輸出相同事件。

實際記錄：

- `Drag Begin requested`：URL 與 route。
- `Pasteboard augmented`：最終 pasteboard type 列表。
- `Drag Begin`：`willBeginAt`、座標、pasteboard types。
- `Drag Update`：每次 `movedTo` 的 screen point。
- `Operation`：within/outside application context 與 allowed mask。
- `Drag End`：end point、final operation、`Accepted`、`Cancelled`。

判定規則：

- `Accepted=true`：`endedAt` 的 final operation 不為空。
- `Cancelled=true`：final operation 為 `.none`。

### 無法從 source 記錄的事件

`draggingEntered`、`draggingUpdated`、`prepareForDragOperation`、`performDragOperation` 是 `NSDraggingDestination` callback，只會送到 Finder／LINE／Mail 等目的 App 的 process。`NSDraggingSource` 公開 API 只有 begin、move、end 與 operation mask，因此來源 App 無法收到真正的 `Drag Enter Destination` 或 Finder 的內部 `Accepted` callback。

Prototype 會在 log 明確輸出：

`Drag Enter Destination | unavailable to NSDraggingSource; destination callbacks stay in target app`

最終接受狀態只能由 source 的 `endedAt(operation:)` 判斷。這個邊界可直接在 SDK 的 `NSDragging.h` 中確認。

## M5 實測環境

- macOS 26.6 build 25G5052e
- 測試來源：70-byte `Prototype9_Source.txt`
- destination：Finder 空白資料夾與 Desktop
- 測試使用 MouseBridge desktop edge route；不是實體 Touch Bar direct route。

## Finder 實測結果

### 實驗 1：允許 `.link`

- Finder folder 回傳 `Operation=link`、`Accepted=true`。
- Finder 建立 928-byte `MacOS Alias file`，不是原始內容的正常檔案。
- 因不符合需求，最終版本移除 `.link`。

### 實驗 2：最終 `.copy` 設定

- Finder 視窗：`Operation=none`、`Accepted=false`、`Cancelled=true`。
- Finder Desktop：沒有建立檔案。
- 原始來源仍存在，App 沒有自行複製或移動。

### 結論

在這台 M5/macOS 26.6 上，Finder 把 URL drag 接受為 link/alias，但不接受本 Prototype 的 copy-only 原始 URL session。公開 API 中可讓 Finder產生一般檔案的另一條路是 file promise，但 provider 必須在目的位置寫出檔案，違反「不要自行複製檔案」，所以沒有實作。

這個結果不能直接代替 Intel/macOS 15.7 實測。使用者已回報先前 Intel Drag Out 可啟動並拖出，但 Finder Window、Desktop、Sidebar、Downloads、Documents 和一般 Folder 必須用本版 3.4 (7) 分別重新測試。

## Destination 測試矩陣

| Destination | 本次結果 | 說明 |
|---|---|---|
| Finder window/folder | M5 copy-only 失敗 | final operation `.none`；link 實驗只產生 Alias。 |
| Finder Desktop | M5 copy-only 失敗 | 沒有建立檔案。 |
| Finder Downloads | Intel 待測 | 不把其他 Finder folder 的結果當成實測。 |
| Finder Documents | Intel 待測 | 不把其他 Finder folder 的結果當成實測。 |
| Finder Sidebar | Intel 待測 | Sidebar 通常只對 folder item 有意義；本次 fixture 是一般檔案。 |
| LINE 26.1.0 | 未執行 drop | 本機已安裝，但 drop 到真實聊天室可能立即上傳／傳送；未對第三方帳號產生副作用。 |
| Mail 16.0 | 未執行 drop | 未建立或同步測試草稿。 |
| Messages 26.0 | 未執行 drop | 未建立對話附件或傳送訊息。 |
| Discord | 無法測試 | 本機未安裝 Discord。 |

沒有實測的 App 不列為成功或失敗，也不猜測其 pasteboard 支援。

## Intel 實測步驟

1. 開啟 3.4 (7) Release App。
2. 讓 Shelf 第一個 item 指向一個可安全移動／複製的測試檔。
3. 開啟 `MouseBridge + DragOut Research`。
4. 從 FILE 區域拖到 Finder window、Desktop、Downloads、Documents、其他 folder。
5. 對 folder item 另外測 Finder Sidebar。
6. 在 App debug log 確認 final `Operation`、`Accepted`、`Cancelled`。
7. 確認目的端收到正常檔案，而不是 Alias 或 URL 文字。
8. LINE、Discord、Mail、Messages 只在安全測試帳號／草稿環境測試，並記錄實際 pasteboard 接受結果。

## Prototype 9 結論

**部分可行。**

- Drag session、原始 URL、完整 source lifecycle debug：成功。
- App 不自行複製檔案：成功。
- M5 Finder 正常 file copy：失敗；link 只產生 Alias。
- Intel Finder 與第三方 App：等待本版實機測試。
- 因 Finder 尚未在目標 Intel 環境確認接受，README 不宣稱已形成 Finder ↔ Shelf 完整雙向流程。

