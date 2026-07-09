# Shelf Fix: Y Axis, Remove on Success, Aspect Fit

## 目的

本版只修正式 Shelf 的三個既有問題：MouseBridge Y 軸、成功 DragOut 後的 Shelf 狀態，以及超寬圖片 thumbnail 比例。AutoDrop、操作選單與 Research controller 流程未修改。

## 1. MouseBridge 2D 座標

檔案：`TouchBarPrivateResearch/ShelfMouseBridgeController.swift`

正式 bridge 現在維護 `virtualTouchBarRect`，預設參數為：

- `virtualTouchBarHeight = 40`
- `enterThreshold = 5`
- `exitThreshold = 12`
- `dragThreshold = 6` physical pixels

游標第一次進入底邊 enter 區域時，透明 bridge panel 會暫時擴展到虛擬 Touch Bar 高度加 exit margin。Panel point 以 X、Y 各自正規化到實體 Touch Bar view bounds：

- `virtualX → parent.bounds.width`
- `virtualY → parent.bounds.height`

`showCursor`、hover、click、mouse-down item selection 與 drag 起點都使用同一個 2D point。`PrivateTouchBarController.shelfMouseBridgeHit` 先使用 `NSView.hitTest(_:)`，再以每個 `ShelfScrubberItemView` 的完整 `CGRect.contains(_:)` fallback；不再把 Y 固定在 `midY`。

退出判定使用 `virtualTouchBarRect` 外擴 12pt 的 rectangle。Y 稍微越界不會立刻取消 hover；真正超出 exit rectangle 才收回 cursor、highlight 並把 panel 恢復成底邊 enter 高度。

DragOut 仍要求向上移動，並以完整 2D 距離判斷 6 physical-pixel threshold。這保留 click／drag 分流，也避免只有 X 軸的舊行為。

## 2. FilePromise 成功後移除

檔案：

- `TouchBarPrivateResearch/ShelfMouseBridgeController.swift`
- `TouchBarPrivateResearch/PrivateTouchBarController.swift`
- `TouchBarPrivateResearch/FileShelfModel.swift`

移除條件不是 Finder 顯示 `+`，也不是 `NSDraggingSession` 回傳非空 operation；唯一成功條件是 `ShelfFilePromiseWriter.writePromiseTo` 完成 `FileManager.copyItem` 並呼叫 completion success。

流程：

1. 每個 promise writer 以 UUID 保留，並記錄對應 Shelf item ID。
2. Drag operation 為 `.none` 時釋放 writer，記錄 `DragOut cancelled keep item`，不修改 Shelf。
3. `copyItem` 失敗時記錄 error 與 `DragOut failed keep item`，不修改 Shelf。
4. `copyItem` 成功時記錄 `FilePromise copy success`。
5. `PrivateTouchBarController` 收到成功 item ID 後呼叫 `FileShelfModel.remove(id:)`。
6. Model 的單次 `commitChange()` 同步更新 Touch Bar、App 視窗 callback 與 Recent URL persistence。
7. 最後記錄 `DragOut success remove item`。

這只移除 Shelf item；來源 URL 指向的原始檔案完全不會刪除。

## 3. Thumbnail aspect-fit

檔案：

- `TouchBarPrivateResearch/FileShelfModel.swift`
- `TouchBarPrivateResearch/ShelfScrubberItemView.swift`

舊版將任何 CG thumbnail 的 `NSImage.size` 強制設成 24×24，超寬 Touch Bar 截圖因此失去原始寬高比。

新版限制：

- `maxThumbnailWidth = 48`
- `maxThumbnailHeight = 28`
- scale 使用 `min(1, maxWidth / width, maxHeight / height)`
- 小圖不放大
- `NSImageView.imageScaling = .scaleProportionallyDown`
- image view 置中，Shelf item 寬度仍固定，不因寬圖擴張

因此超寬、超高與一般圖片都只會等比例縮小。PDF、資料夾與其他非圖片仍使用原本的 `NSWorkspace` icon。

## Logs

正式 Console 與 Developer Mode drag log 包含：

- `DragOut accepted; awaiting FilePromise copy`
- `DragOut cancelled keep item`
- `Shelf FilePromise success ...`
- `Shelf FilePromise failure ...`
- `FilePromise copy success`
- `DragOut success remove item`
- `DragOut failed keep item`

## 驗證狀態

M5 已完成：

- arm64 typecheck／Release compile
- x86_64 typecheck／Release compile
- Universal binary、ad-hoc codesign 與啟動 smoke test
- source-level 確認成功移除走既有 `FileShelfModel.remove`，因此 UI 與 persistence 共用原本通知路徑

M5 沒有實體 Touch Bar，不能宣稱已實測 2D 游標手感或 Finder fulfillment 的 Intel 行為。Intel 回歸測試應確認：

1. 底邊進入後可在 Touch Bar 上下左右移動，item hit 不再只看 X。
2. 小幅 Y 越界不退出，超過 exit margin 才退出。
3. click 不拖仍進入原操作選單。
4. 成功拖到 Finder／Desktop／Documents 後，目的檔存在且 Shelf item 消失。
5. 按 Escape 取消或製造 copy failure 時，Shelf item 保留。
6. 以超寬 Touch Bar 截圖確認 thumbnail 等比例、置中且 item 不爆版。

## 結論

程式已將正式 MouseBridge 改為完整 2D 座標，將 Shelf 移除綁定到真正 FilePromise copy success，並修正 thumbnail 的比例來源與 aspect-fit 顯示。Intel 實機結果保留給實體 Touch Bar 回歸測試，不在 M5 假裝通過。
