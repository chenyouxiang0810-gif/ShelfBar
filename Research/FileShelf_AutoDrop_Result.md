# File Shelf AutoDrop Result

## 目的

平常完全釋放 system-modal Touch Bar；只有 Finder file drag 真正進入底部 Overlay 時顯示 `DROP YOUR FILE HERE`。成功 drop 立即切成 Shelf，取消則讓 Pock／原本 Touch Bar UI 回來。

## 狀態機

| Event | App status | Overlay | Touch Bar |
|---|---|---|---|
| App idle | Idle | Hidden | Dismissed |
| Finder file drag detected | Drag detected | Visible at bottom | Still dismissed |
| `draggingEntered` | Drop ready | Visible | `DROP YOUR FILE HERE` |
| `draggingUpdated` | Drop ready | Visible | Keep Drop Here |
| successful `performDragOperation` | Drop success → Shelf active | Hide after drag | Shelf UI |
| exited/ended without success | Idle after 0.3s | Hidden | Dismissed |
| CLOSE | Idle | unchanged/hidden | Dismissed, Shelf retained |
| CLEAR | Idle | unchanged/hidden | Dismissed, Shelf cleared |

`currentDragDidDrop` 防止成功 drop 後的 `draggingEnded` 或 global mouse-up 誤排程 dismissal。取消路徑使用可取消的 0.3 秒 `DispatchWorkItem`；若期間收到 successful perform，work item 會取消。

## Touch Bar 切換

- Drop target 狀態只使用一個 custom item，文字為 `DROP YOUR FILE HERE`。
- 成功解析 URL 前不加入 Shelf。
- 成功後清除 drop-target flag，reload `NSScrubber` 並保持同一個 system-modal Touch Bar presentation。
- Shelf item 顯示 thumbnail/icon 與截斷檔名。

## App 狀態顯示

`PrivateTouchBarController.AutoDropStatus` 定義：

- Idle
- Drag detected
- Drop ready
- Drop success
- Shelf active

App 視窗的 status label 只顯示狀態機值；Overlay 設定、Reload 等操作不再覆蓋狀態文字。

## M5 狀態機 smoke test

實際呼叫 lifecycle 並驗證：

1. Initial `Idle`，Touch Bar 未 present。
2. Finder detection → `Drag detected`，仍未 present。
3. Overlay enter → `Drop ready`，system-modal presentation 被呼叫。
4. Overlay exit without drop → 0.3 秒後 `Idle` 並 dismissal。
5. 第二次 enter + successful URL → `Drop success` → `Shelf active`。
6. Successful drag 的 ended callback 後等待 0.4 秒，Shelf 仍保持 presented。
7. Clear → Shelf empty、dismiss、`Idle`。

arm64 與 x86_64 type-check 均通過。Universal Release 已建立，版本 3.2 (5)，binary architectures 為 `x86_64 arm64`。

## M5 Finder 整合 smoke test

以 Finder 真實 local file 拖入 5 px Overlay：

- 偵測到 file drag 後狀態為 `Drag detected`。
- 游標進入 Overlay 後呼叫 system-modal presentation，狀態為 `Drop ready`。
- `draggingUpdated` 維持 Drop Here；相同狀態通知已去重，不重複洗 Console。
- `performDragOperation` 收到 `public.file-url` / `NSFilenamesPboardType`。
- 成功解析 `/private/tmp/AutoDropIntegration/file.txt`。
- 狀態依序切為 `Drop success`、`Shelf active`。
- Shelf 保持 presented，沒有被後續 ended callback dismiss。

此測試驗證 M5 的 Finder → Overlay → model 狀態流程；實體 Touch Bar 畫面仍需 Intel 驗證。

## Intel 待測

- Finder file drag 尚未進入底部時，Touch Bar 是否保持 Pock：待填。
- 進入 5 px Overlay 時是否立即顯示 Drop Here：待填。
- 在 Overlay 內移動是否持續顯示 Drop Here：待填。
- 放開後是否立即切到 Shelf thumbnail／filename：待填。
- 成功 drop 後 Shelf 是否保持到 CLOSE／CLEAR：待填。
- 拖離或取消後是否約 0.3 秒讓 Pock 回來：待填。
- App 狀態順序是否正確：待填。

## 排除項目

- 沒有長按或 `NSPressGestureRecognizer`。
- 沒有 drag-out、`NSDraggingSource` 或 desktop drag handle。
- 沒有動畫。
- 沒有修改 Pock。

## 結論

AutoDrop 狀態機與取消／成功 race protection 已在 M5 通過；Finder-to-Overlay 實際 drop 與實體 Touch Bar 畫面切換仍需 Intel 驗證。
