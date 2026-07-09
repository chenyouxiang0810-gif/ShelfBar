# AutoDrop from All Apps

## 原本限制

`TouchBarPrivateResearch/FinderDragMonitor.swift` 的 `.leftMouseDragged` 分支原本要求：

```swift
NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder"
```

即使 drag pasteboard 已有 file URL，只要 Finder 不是 frontmost App，就不會顯示 Overlay。限制發生在 Overlay 出現之前，不是 `performDragOperation` 或 URL parser 的限制。

## 修改

已移除 frontmost application 與 Finder bundle identifier 判斷。Global mouse-drag monitor 現在只在下列條件成立時顯示既有 Overlay：

1. Overlay 設定為 ON。
2. `NSPasteboard(name: .drag)` 的 change count 表示目前 drag payload 已更新。
3. `FileDropReader.inspect` 能解析至少一個實際 file URL。

來源 App 不參與判斷。

## Pasteboard formats

`FileDropReader.registeredTypes` 與 parser 支援：

- `NSPasteboard.PasteboardType.fileURL`，其 UTI 是 `public.file-url`
- `NSPasteboard.PasteboardType.URL`（`public.url`），但值必須是 `file://`
- `NSURLPboardType`，但值必須是 file URL
- `NSFilenamesPboardType`

`.fileURL`／NSURL object reader仍使用 `.urlReadingFileURLsOnly: true`。所有來源最後以 standardized path 去重。

## 為什麼不只檢查 type 名稱

`public.url` 與 `NSURLPboardType` 也可能表示 `https://` 網頁。只用 `availableType` 會讓拖曳一般網頁連結也出現 Drop Here。現在 monitor 直接使用與正式 drop 相同的 `FileDropReader.inspect`，只有能解析為 file URL 才啟用 Overlay。

## 預期來源

Finder、Desktop、Safari、Chrome、Discord、LINE、VS Code、Xcode、Terminal 或其他 App，只要拖曳 pasteboard 提供上述任一可解析 file URL，就走相同流程：

`file drag → Overlay → DROP YOUR FILE HERE → performDragOperation → Shelf`

這不是按 App 白名單保證。若某個 App 只提供純文字、網頁 URL、影像 bytes 或 `NSFilePromiseProvider`，但沒有任何 file URL／filename path，本版會誠實地不視為 file-URL drag；需求明確限制在 file URL，未新增 file-promise receiver。

## 未修改

- Overlay 視覺與高度
- `draggingEntered`／`draggingUpdated`／`performDragOperation`
- Drop Here Touch Bar UI
- 多檔 URL 累加
- MouseBridge、DragOut 與 FilePromise source

## 驗證狀態

M5 已完成：

- source check：`FinderDragMonitor.swift` 不再含 `frontmostApplication` 或 `com.apple.finder`
- `.fileURL`／`.URL`／`NSURLPboardType`／`NSFilenamesPboardType` parser 編譯
- arm64／x86_64 typecheck 與 Release compile

實際 drag pasteboard 內容由來源 App 決定。Safari、Discord、LINE、VS Code、Xcode、Chrome、Terminal 與 Finder 的逐項 Intel／實機結果尚未假裝完成。
