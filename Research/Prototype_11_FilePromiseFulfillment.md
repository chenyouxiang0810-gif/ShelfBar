# Prototype 11 — File Promise Fulfillment

## Intel 回報與判讀

Prototype 10 在 Intel 的結果：拖到 Finder Documents／Desktop 時游標顯示 `+`，但放開後沒有檔案。

`+` 只能證明 Finder 在 drag validation 階段認得 `.copy` 與 file-promise pasteboard types；它不保證 drop 已完成，也不保證 `NSFilePromiseProviderDelegate.writePromiseTo` 已被呼叫。Prototype 10 的 provider 即使收到 fulfillment request，也刻意回傳 error、不寫內容，因此本來就不可能留下檔案。

## 真正 fulfillment 實作

檔案：`TouchBarPrivateResearch/MouseBridgeResearchController.swift`

類別：`FinderFilePromiseWriter`

方法：

- `filePromiseProvider(_:fileNameForType:)`
- `filePromiseProvider(_:writePromiseTo:completionHandler:)`
- `operationQueue(for:)`

Finder File Promise Copy 開啟時：

1. `NSFilePromiseProvider` 使用來源的實際 UTI；資料夾使用 `public.folder`。
2. promised filename 是 `sourceURL.lastPathComponent`。
3. Finder 接受 drop 後提供完整 destination URL。
4. Writer 確認來源仍存在。
5. 執行 `FileManager.default.copyItem(at: sourceURL, to: destinationURL)`。
6. 成功呼叫 `completionHandler(nil)`；失敗傳回原始 error。

沒有重新編碼或重新產生檔案內容。一般檔案由 `copyItem` 直接複製；資料夾由同一 API 遞迴複製。程式不先刪除或覆寫已存在的 destination，避免破壞 Finder 的名稱衝突處理。

Apple 規定 provider delegate 必須將 promised file 寫到傳入的 URL，並在完成後呼叫 completion handler。[NSFilePromiseProviderDelegate](https://developer.apple.com/documentation/appkit/nsfilepromiseproviderdelegate)、[writePromiseTo](https://developer.apple.com/documentation/appkit/nsfilepromiseproviderdelegate/filepromiseprovider%28_%3Awritepromiseto%3Acompletionhandler%3A%29)

## Delegate 生命週期修正

`NSFilePromiseProvider.delegate` 是 weak，而 `writePromiseTo` 會在 drag 完成後才呼叫。

Drag source 現在強持有 `FinderFilePromiseWriter`，不再於 `draggingSession(_:endedAt:operation:)` 立即釋放。Writer 保留到下一次 drag 或 source view 銷毀，確保 Finder 在 drop 後仍能呼叫 fulfillment delegate。

這是「validation 成功但沒有 fulfillment callback」最需要排除的 source-side 原因。

## 完整 log

Promise fulfillment 會輸出到 App 視窗與 Console：

- `writePromiseTo called`
- `destinationURL=<absolute URL>`
- `filename=<source filename>`
- `source=<full source path>`
- `File Promise success`
- `success=true`
- `File Promise failure`
- `success=false`
- `error=<domain>(<code>): <localized description>`

Drag lifecycle 仍會記錄：

- pasteboard types
- local／non-local operation mask
- final operation
- `FinderAccepted`／`FinderRejected`／`Cancelled`

## 如果 writePromiseTo 仍未呼叫

依 log 分三種情況：

1. `final Operation=none`
   - Finder validation 曾顯示 `+`，但 drop 最終被拒絕或取消。
   - 目的端不會要求 promise fulfillment。

2. `final Operation=copy`，但沒有 `writePromiseTo called`
   - Finder 已回報接受 drag，但未向 provider 要求 fulfillment。
   - 先確認本版為 3.6 (9)、Promise Copy 開關為 ON、pasteboard 包含 promise metadata。
   - 本版已排除 weak delegate 過早釋放；若仍發生，限制在 Finder／AppKit promise dispatch 層，需保存完整 Console log 再分析。

3. 有 `writePromiseTo called`，但沒有檔案
   - 查看 `File Promise failure` 的 NSError domain、code 與 destination URL。
   - 常見可驗證因素包括來源已不存在、destination 已存在或檔案系統權限錯誤；不在沒有 error log 時猜測原因。

## Intel 實測步驟

1. 開啟 3.6 (9) Release App。
2. Shelf 放入可安全複製的小檔案。
3. 開啟 `MouseBridge + DragOut Research`。
4. 開啟 `Finder File Promise Copy (writes to destination)`。
5. 拖到 Finder Documents folder，放開。
6. 確認 log 有 `writePromiseTo called` 與完整 destination URL。
7. 確認 `File Promise success` 且 Finder 出現內容相同的檔案。
8. 再測 Desktop。
9. 以資料夾來源重複測試，確認遞迴 copy。

待填結果：

- Documents final operation：**Pending**
- Documents `writePromiseTo called`：**Pending**
- Documents copy success：**Pending**
- Desktop final operation：**Pending**
- Desktop `writePromiseTo called`：**Pending**
- Desktop copy success：**Pending**
- Folder recursive copy：**Pending**

## 結論

真正的 public `NSFilePromiseProvider` fulfillment 已完成，不再是 acceptance-only probe。程式已具備把原始實體檔案／資料夾複製到 Finder 指定 URL 的完整路徑；實際 Intel Finder 結果需用本版 3.6 (9) 填寫，未假裝已完成實機驗證。

