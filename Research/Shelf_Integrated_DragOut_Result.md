# Shelf Integrated DragOut Result

## 目標

將已分別驗證的 AutoDrop、MouseBridge、NSDraggingSession 與 NSFilePromiseProvider fulfillment 整合進正式 Touch Bar Shelf。正常使用者不需要啟用 Research 或 FilePromise prototype 開關。

## 正式架構

### AutoDrop → Shelf

既有流程保持不變：

1. `FinderDragMonitor` 偵測 Finder file drag。
2. `ScreenEdgeDropOverlayController` 暫時顯示 bottom overlay。
3. `PrivateTouchBarController` 顯示 Drop Here system-modal Touch Bar。
4. `performDragOperation` 解析 file URLs。
5. `FileShelfModel` 累加 item，正式 Shelf 顯示縮圖／icon 與檔名。

### Shelf → MouseBridge

新增 `TouchBarPrivateResearch/ShelfMouseBridgeController.swift`。

`PrivateTouchBarController` 現在直接持有正式 `ShelfMouseBridgeController`：

- Shelf 有檔案且 system-modal Touch Bar 正在顯示時，自動啟用。
- Drop Here、操作選單或 Shelf dismiss 時，自動停用。
- 透過 private `NSFunctionRow._topLevelViews()` 取得實體 Touch Bar view。
- 建立透明、nonactivating bottom-edge `NSPanel` 接收桌面滑鼠。
- Panel 高度跟隨 Overlay Height；預設 5 physical pixels。
- 將 bottom-edge x 座標映射到 Touch Bar x 座標。
- 對目前可見的 `ShelfScrubberItemView` 做 hit testing。
- 在實體 Touch Bar view 顯示 cursor，並高亮命中的 item。

Research A/B/C/FILE controller 仍保留，但正式流程不依賴它。

## Click 與 Drag 分流

`ShelfMouseBridgeController.BridgeView` 在 `mouseDown` 保存：

- 起點
- 命中的 `FileShelfItem`

判定方式：

- 未啟動 drag 就 `mouseUp`：呼叫 `shelfMouseBridgeDidClick`，進入原本 `[檔名] / OPEN / REMOVE / BACK` 選單。
- 向上移動達 6 physical pixels：建立正式 FilePromise drag session。
- 純水平移動不會觸發 drag threshold，避免左右瀏覽時過早開始拖出。

Threshold 會除以 `NSScreen.backingScaleFactor`，所以 Retina 與非 Retina 都維持 6 個實體 pixel。

## 正式 FilePromise Copy

類別：`ShelfFilePromiseWriter`

實作：

- UTI 取自來源 URL；資料夾使用 `public.folder`。
- promised filename 使用原始 filename。
- source operation mask 對 local／external 都回傳 `.copy`。
- Finder 呼叫 `writePromiseTo(destinationURL:)` 後，執行：

  `FileManager.default.copyItem(at: sourceURL, to: destinationURL)`

- 成功呼叫 `completionHandler(nil)`。
- 失敗回傳原始 NSError。
- 不先刪除或覆寫 destination。
- 支援一般檔案及資料夾遞迴 copy。

`NSFilePromiseProvider.delegate` 是 weak，而且 fulfillment 可能在 drag end 之後發生。正式 `ShelfMouseBridgeController` 以 UUID dictionary 保留每個 writer，直到 success／failure completion，再釋放；即使使用者拖出後立即關閉 Shelf，promise delegate 仍然存在。

## Developer Logs

正式流程會輸出：

- hit／MouseBridge active 狀態
- drag threshold 與 filename
- promise pasteboard types
- local／external operation mask
- drag begin/update/end
- `writePromiseTo` destination URL
- filename 與 source path
- copy success／failure
- NSError domain、code、localized description

App 視窗只有在 Developer Mode 開啟後才顯示這些 logs。Console log 仍保留。

## App Window

### Normal Mode（預設）

只顯示：

- Clear
- Close Shelf
- Overlay ON/OFF
- Overlay Height
- Developer Mode

已在 M5 UI 實際確認進階 controls、table 與 logs 不可見。

### Developer Mode

展開後顯示：

- item count 與完整 Shelf table
- Remove Selected、Reload、Present、Dismiss
- 正式 MouseBridge／Promise logs
- Research MouseBridge switch
- Prototype FilePromise override

關閉 Developer Mode 時會關閉 Research controller 與 prototype override，但不關閉正式 Shelf drag-out。

## Defaults

- Overlay ON：`ScreenEdgeDropOverlayController` 新安裝預設 true。
- Overlay Height：無有效保存值時預設 5px。
- AutoDrop ON：App 啟動時 `FinderDragMonitor.start()`。
- 正式 MouseBridge DragOut ON：Shelf present 時自動啟用，沒有一般使用者開關。
- 正式 FilePromise Copy ON：所有正式 Shelf drag-out 使用 provider fulfillment。
- Developer Mode OFF：UI switch 每次啟動預設 off。

## 驗證狀態

### 已有 Intel 實測證據

使用者已回報：

- AutoDrop 正式流程成功。
- MouseBridge／Drag Out 成功。
- FilePromise fulfillment 成功將 Touch Bar Shelf item 真正複製回 Finder。

### 本次 M5 驗證

- arm64 與 x86_64 typecheck。
- Normal Mode UI 只顯示指定簡單 controls。
- Developer Mode 展開／收合及預設 OFF。
- `FileManager.copyItem` byte-for-byte file copy 測試。
- Universal Release、codesign 與啟動 smoke test。

M5 沒有實體 Touch Bar，因此本次不能假裝已在 M5 驗證正式 item hit testing 或 physical cursor。整合後的 Intel end-to-end 操作仍應依下列步驟做 regression test。

## Intel Regression Checklist

1. 從 Finder 拖檔案到 5px Overlay。
2. 確認 Shelf 自動顯示且無需開 Developer Mode。
3. 滑鼠進入底邊，確認 cursor／item highlight。
4. 點 item 不拖，確認進入操作選單而不是立即 open。
5. 小於 6px 移動後放開，確認不開始 drag。
6. 向上超過 6px，拖到 Desktop／Documents／Finder folder。
7. 確認 destination 出現內容一致的真正檔案，不是 Alias。
8. 測試資料夾遞迴 copy。
9. 測試拖出後立即按 CLOSE，確認 promise 仍完成。
10. 開啟 Developer Mode，確認 success／failure logs。

## 結論

正式 Shelf 已完成 MouseBridge + DragOut + FilePromise copy 整合。Research controller 只保留作為 Developer Mode debug 工具；正常使用流程不再依賴任何 prototype switch。

