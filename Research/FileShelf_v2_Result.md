# TouchBar File Shelf v2 Result

## 本次目標

將 v1 的常駐 30 point Overlay 改為短暫、可設定的 Finder drag target，並補上日常使用需要的單項移除、Recent Shelf、Reload 與完整 App 控制。

## 已完成

- App 啟動時 Overlay 為隱藏狀態，不再常駐攔截滑鼠。
- public `NSEvent` global monitor 觀察 mouse drag；只有 Finder 前景且 system drag pasteboard 含已註冊 file type 時才 order-front Overlay。
- mouse-up、成功／失敗 drop、destination drag end 後排程 0.3 秒 order-out。
- Overlay ON/OFF 與設定保存。
- 30、20、10、5、2 px 選項；依螢幕 backing scale 換算成 points。
- Touch Bar Shelf 繼續使用 free-mode `NSScrubber`，支援左右滑動。
- Finder-style item 保留 image thumbnail 優先、系統 icon fallback、下方截斷檔名。
- Touch Bar item 加入 `×` 單項移除；App 視窗加入 Remove Selected。
- Shelf 以 file URL 字串保存到 UserDefaults；Add、Remove、Clear 都立即持久化。
- App 啟動載入 Recent，並提供 Reload Shelf。
- App 視窗提供 Overlay ON/OFF、Overlay Height、Present、Dismiss、Clear、Reload、Remove Selected。

## Overlay 觸發條件與限制

本機驗證發現公開的 `NSPasteboard(name: .drag)` 在 Finder file drag 期間、Overlay 尚未出現時，已列出 `public.file-url` 與 `NSFilenamesPboardType`。v2 因此同時檢查 Finder bundle identifier 與這些 file types；不符合時不顯示 Overlay。

這項檢查只用 pasteboard type 判斷是否值得顯示 destination。真正 URL 仍只在 Overlay 的 `performDragOperation` 解析，解析成功才加入 Shelf。Intel/macOS 上 `.drag` pasteboard type 出現的時序仍需實測；若 type 沒有及時出現，v2 的選擇是維持隱藏，而不是退回所有 Finder mouse drag 都顯示。

## Recent 設計

- 保存 `URL.absoluteString`，不保存內容、不複製檔案。
- v2 未 sandbox，因此先採 URL；沒有建立 security-scoped bookmark。
- 重複 drop 會保留重複項目。
- 原始檔案移動或刪除後，舊 URL 不會自動跟隨。
- Reload 重新讀取已保存 URL 並重建 thumbnail/icon。

## 未包含

- 動畫。
- 從 Touch Bar 拖出。
- 新的 drag API 或 Accessibility hack。
- Pock 修改。
- 單項 Finder move tracking。

## Build 與本機驗證

- arm64 type-check：通過。
- x86_64 type-check：通過。
- Universal Release：已建立，版本 2.0 (2)，architectures 為 `x86_64 arm64`。
- M5 App UI：Overlay ON/OFF、30/20/10/5/2 px selector、Remove、Reload、Present、Dismiss、Clear layout 顯示正常。
- M5 startup hidden-state：on-screen window 清單只有 860×566 Shelf 視窗，沒有 Overlay。
- M5 Finder file drag：system drag pasteboard 出現 `public.file-url` / `NSFilenamesPboardType` 後，Overlay 自動出現；30 px 在 Retina 2× 實測 frame 為 15 points。
- M5 Finder 非檔案 drag：pasteboard changeCount/file type gate 未通過，Overlay 保持隱藏。
- M5 mouse-up：0.3 秒 hide work item 執行後，on-screen window 清單不再包含 Overlay。
- Model smoke：URL save、建立新 model reload、單項 remove、clear 通過。
- Intel Touch Bar、Finder global drag timing 與所有高度：待實測。

## Intel 高度實測

| Height | Overlay 自動出現 | Drop performed | URL 正確 | Mouse-up 後 ≤0.3s 隱藏 | 使用感受 |
|---:|---|---|---|---|---|
| 30 px | 待填 | 待填 | 待填 | 待填 | 待填 |
| 20 px | 待填 | 待填 | 待填 | 待填 | 待填 |
| 10 px | 待填 | 待填 | 待填 | 待填 | 待填 |
| 5 px | 待填 | 待填 | 待填 | 待填 | 待填 |
| 2 px | 待填 | 待填 | 待填 | 待填 | 待填 |

## Intel Shelf 實測

- Finder file drag 是否及時提供 system drag pasteboard file type：待填。
- Finder 非檔案 drag 是否保持 Overlay 隱藏：待填。
- 大量檔案左右滑動：待填。
- 圖片 thumbnail、PDF／Folder icon：待填。
- Touch Bar `×` 是否能可靠單項移除且不誤開檔案：待填。
- App 重開後 Recent 順序與重複項目：待填。
- CLOSE/Dismiss 後資料保留，CLEAR 後資料移除：待填。
