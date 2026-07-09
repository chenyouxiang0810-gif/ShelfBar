# MouseBridge Subscreen Retry

## 基準版本

本次先回退到最後正常的 4.1 (11) 基準。回退後 Universal executable SHA-256 為：

`ae2fbfe09ba2ad0cb39855a9a1b6bb9ecef3958142e83da28bec5b6f0f834a03`

此值與 4.1 初次成功建置時記錄的 SHA-256 完全一致。基準保留：

- 主 Shelf MouseBridge
- 40pt 2D virtual Touch Bar 與 Y 軸
- 6 physical-pixel drag threshold
- DragOut／FilePromise copy
- copy success 後移除 Shelf item
- AutoDrop
- thumbnail aspect-fit

先前失敗的 `ShelfBridgeHitRegion` 通用 cache、`currentTouchBarMode`、跨畫面 rebuild 與 `.floating` panel 修改均未留在 `ShelfMouseBridgeController.swift`。

## 重試策略

不修改主畫面 `ShelfMouseBridgeController`。新增獨立檔案：

`TouchBarPrivateResearch/ActionMenuMouseBridgeController.swift`

`PrivateTouchBarController.updateMouseBridgeState()` 保留原本主畫面判定；只有 `selectedOperationItemID != nil` 的 action menu 狀態才停用主 bridge 並啟用 action-menu bridge。

這使兩條路徑分離：

- Shelf 主畫面：原 4.1 `ShelfMouseBridgeController`
- OPEN／REMOVE／BACK 子畫面：`ActionMenuMouseBridgeController`

## 子畫面 hit regions

Action menu 顯示後，獨立 controller：

1. 等待 system-modal Touch Bar hierarchy 建立。
2. 取得 `NSFunctionRow._topLevelViews().last`。
3. 只掃描 action title：OPEN、DRAG、DRAG OUT、REMOVE、BACK、DELETE。
4. 將目前可見按鈕 frame 轉成 top-level Touch Bar 座標。
5. 建立子畫面自己的 hit regions。
6. 若第一次 hierarchy 尚未就緒，短延遲後重試；dismiss 時取消。

Hover 使用 `NSButton.isHighlighted`，click 僅呼叫現有 `performClick(nil)`。這不改 OPEN／REMOVE／BACK 原 action，也不接觸 Shelf DragOut session。

子畫面 bridge 沿用 40pt virtual height、5pt enter threshold 與 12pt exit margin，支援完整 X/Y cursor。

## 沒有修改的部分

- `ShelfMouseBridgeController.swift` 主畫面 hit-test／panel／drag 流程
- AutoDrop UI
- `NSDraggingSession`
- `ShelfFilePromiseWriter`
- FilePromise copy completion 與 remove-on-success
- Shelf UI 與 thumbnail

## 驗證狀態

M5 已完成 arm64／x86_64 typecheck、Release compile、Universal merge、codesign 與啟動 smoke。M5 沒有 Touch Bar，不能宣稱 Intel 子畫面 hover/click 已實測。

Intel 回歸項目：

1. 先確認主 Shelf cursor、hover、click、DragOut 與 Y 軸維持正常。
2. Click card 進 OPEN／REMOVE／BACK。
3. 移到螢幕底邊，確認子畫面 cursor 出現。
4. Hover 與 click 三個按鈕。
5. BACK 後再次確認原主 Shelf bridge 正常。

## 結論

本次沒有在主 MouseBridge 上繼續修補，而是以隔離 controller 處理子畫面。這降低再次破壞已驗證主畫面事件流程的風險；Intel 實體結果仍需實測填寫。
