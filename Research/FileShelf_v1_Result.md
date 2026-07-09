# TouchBar File Shelf v1 Result

## 目標

把已證實可行的兩條技術路徑組合為可用 v1：

1. 透明 30 point desktop Overlay 接收 Finder file URL。
2. private DFRFoundation system-modal Touch Bar 顯示並操作 Shelf。

本版停止 Touch Bar drag callback 研究，不嘗試讓 Touch Bar 本體成為 `NSDraggingDestination`。

## 已完成

- `FileShelfModel` 保存 URL、檔名及顯示圖像。
- 同一次 drop 支援多個檔案；不同 drop 會持續 append，不覆蓋先前項目。
- 圖片由 ImageIO 建立縮圖；PDF、資料夾和其他類型使用 `NSWorkspace` icon。
- Touch Bar 使用 free-mode `NSScrubber` 建立可水平瀏覽的檔案列表。
- Touch Bar item 同時顯示圖像與使用 middle truncation 的單行檔名。
- 點擊項目呼叫 `NSWorkspace.shared.open(_:)`。
- `CLEAR` 清空 model 並 dismiss system-modal Touch Bar。
- `CLOSE` 只 dismiss，Shelf 資料保留。
- 新 drop 自動 present Touch Bar。
- AppKit 視窗顯示檔案數量、icon、檔名與完整路徑，並提供 Clear、Present、Dismiss。
- Overlay 維持 1085×30 point，沒有改為 1px。

## 狀態流程

- App 啟動且 Shelf 為空：Overlay 與 App 視窗啟用，不主動佔用 Touch Bar。
- Finder drop 成功：URL 加入 Shelf，Touch Bar 自動 present。
- 手動 Dismiss/CLOSE：Touch Bar 隱藏，Shelf 保留。
- 再次 drop 或按 Present Touch Bar：顯示現有 Shelf。
- Clear：Shelf 清空並 dismiss，原本的 Touch Bar UI 可以返回。

## v1 未包含

- 從 Touch Bar 拖出檔案。
- 動畫。
- 1px Overlay。
- Finder-to-Touch-Bar direct drag callback 研究。
- 長按 Reveal in Finder。v1 先保留可靠的單擊開啟操作。
- Shelf 持久化、檔案移除單項、排序或去重。
- Pock 修改或 App Store 上架設定。

## 技術限制

DFRFoundation system-modal API 與使用的 `NSTouchBar` presentation selectors 都是 private API。它們已由使用者在 Intel Touch Bar 實機驗證可顯示，但沒有相容性承諾。

Prototype 4 已確認 Touch Bar direct callback 維持 0；Prototype 5 已由使用者確認 Overlay 的 `performDragOperation` 能取得 Finder file URL。因此 v1 的輸入層仍是 desktop Overlay，Touch Bar 只作為顯示與點擊介面。

## 建置與驗證

- arm64 type-check：通過。
- x86_64 type-check：通過。
- Universal Release：已建立，版本 1.0 (1)，architectures 為 `x86_64 arm64`。
- Model smoke test：兩個 pasteboard file URLs 解析成功；多次 add 累加與 clear 通過。
- M5 smoke test：App 啟動、Shelf 視窗 layout、正常退出通過；空 Shelf 啟動時未呼叫 system-modal presentation。
- Intel Touch Bar v1 UI 與點擊開啟：需要實機驗證。

## Intel v1 實測項目

- 多檔案一次 drop 是否全部顯示。
- 多次 drop 是否累加。
- 圖片縮圖、PDF icon、資料夾 icon 是否正確。
- 長檔名是否截斷且沒有破版。
- 點擊是否以預設 App 開啟。
- CLOSE 後 Shelf 是否保留，Present 是否能恢復。
- CLEAR 是否清空並讓原本 Touch Bar UI 返回。
