# Prototype 5 Result

## 本次測試目的

Prototype 4 的 Intel 結果是 Touch Bar `TB` 維持 0，而 Overlay 的 `updated` / `ended` 會增加。Prototype 5 只驗證 30 point Overlay 能否進一步收到 `prepareForDragOperation`、`performDragOperation`，並從 Finder dragging pasteboard 解析出真實檔案 URL。

本版在 `performDragOperation` 明確檢查：

- `pasteboard.types`
- `.fileURL`，透過 `readObjects(forClasses: [NSURL.self])`
- `NSURLPboardType`
- `NSFilenamesPboardType`

成功時顯示檔案數量、每個檔案名稱及完整路徑；失敗時列出各 reader 沒有產生 file URL 的原因。

## 建置狀態

- arm64 / x86_64 type-check：通過。
- Universal Release：已建立，版本 0.5 (5)，architectures 為 `x86_64 arm64`。
- M5 smoke test：啟動、DFR system-modal presentation、正常 dismissal 與退出均未 crash。
- M5 smoke test 沒有證明 Finder drop 成功；下列 Intel 實測欄位仍為空白。

## Overlay 成功收到檔案時代表什麼

若 `OV prepared`、`OV performed` 增加，`Received file count` 大於 0，而且完整路徑與 Finder 拖曳內容一致，代表透明 Overlay 是有效的 AppKit `NSDraggingDestination`：它可以接受 Finder drop、讀取 dragging pasteboard，並取得後續 Prototype 所需的 file URL。

這只證明 screen-edge Overlay proxy 可行，不會改變 Prototype 4 的結果，也不代表 DFR Touch Bar 本體能接收 drag callback。

## 只有 updated/ended、沒有 performed 時代表什麼

若 `OV updated` / `OV ended` 增加，但 `OV prepared` 和 `OV performed` 都是 0，代表 drag session 確實進入或經過 Overlay，但 AppKit 沒有接受該位置的 drop。應檢查實際放開時 cursor 是否仍在 30 point panel frame、dragging source 是否允許 `.copy`，以及 destination window 在放開前是否仍可見並參與 hit-testing。

若 `OV prepared` 增加但 `OV performed` 仍是 0，代表 destination 已通過 prepare，但 AppKit 沒有呼叫最終 perform；需以同一次測試的 callback 順序、放開位置與 Console 記錄判斷，不能宣稱已收到檔案。

## perform 有觸發但 pasteboard 沒有 file URL 的可能原因

- Finder 提供的 pasteboard type 與已註冊的三種 file type 不一致。
- 拖曳來源不是 Finder 檔案，或提供的是文字、promise file、虛擬項目等其他 representation。
- `.fileURL` object reader 回傳空陣列，而 legacy `NSURLPboardType` / `NSFilenamesPboardType` 也不存在或格式不符。
- pasteboard 內容在讀取時無法解析成有效的 local file URL。

Console 的 `pasteboard.types`、`fileURLs`、`URLReaders` 與 `noFileURLs reasons` 用來區分上述情況；不能只看 `draggingEnded` 推論 drop 成功。

## Intel 實測結果

尚未實測，保留給 Intel Touch Bar 機器填寫：

- Intel 機型：待填
- macOS 版本：待填
- 測試項目（PNG / PDF / Folder）：待填
- OV entered：待填
- OV updated：待填
- OV prepared：待填
- OV performed：待填
- OV exited：待填
- OV ended：待填
- Received file count：待填
- 完整路徑是否正確：待填
- pasteboard.types：待填
- URL reader：待填
- 結論：待填

Prototype 5 沒有 File Shelf、動畫、拖出功能或檔案持久化。
