# TouchBar File Shelf v3 Result

## Intel v2 實測輸入

- 5 px Overlay 好用。
- Touch Bar Shelf 基本成功。
- `NSScrubber` 左右箭頭用途不清楚。
- 每張檔案卡片的小型 `×` 太難按。
- 從 Touch Bar 往桌面拖出目前不可用。

## v3 修改

### Shelf 瀏覽

- `NSScrubber` 維持 `.free` mode，可用手勢左右滑動。
- `showsArrowButtons` 設為 `false`，完全移除左右箭頭。
- 檔案卡只保留 thumbnail/icon 與下方截斷檔名。
- 移除卡片上的小型 `×` 與其 action。

### 長按刪除

每個 `ShelfScrubberItemView` 安裝 `NSPressGestureRecognizer`：

- `minimumPressDuration = 3.0`
- `allowableMovement = 8`
- 只在 recognizer `.began` 時進入確認狀態。
- 手指移動超出範圍時 recognizer 失敗，讓左右滑動保持可用。

確認狀態的 Touch Bar 顯示：

```text
Delete this file?
[filename]
DELETE    BACK
```

- DELETE：依 Shelf item UUID 移除單一 model item，更新 Recent URL；不呼叫 FileManager，不刪除磁碟檔案。
- BACK：清除 pending delete 狀態並回到 Shelf，不修改 model。
- 確認狀態期間阻止 `NSScrubber` tap selection 開啟檔案，避免長按放開後誤觸 open。
- Dismiss 時會取消 pending confirmation，下一次 Present 回到 Shelf。

### Overlay

- 保留 30、20、10、5、2 px 選項。
- 既有設定繼續由 UserDefaults 載入。
- 新安裝或尚無設定時預設為 Intel 已確認好用的 5 px。

## 保留功能

- Finder file drag 才短暫顯示 Overlay。
- mouse-up / drop 後 0.3 秒隱藏。
- CLEAR、CLOSE、點擊開啟、左右滑動。
- Recent URL 保存與 Reload Shelf。
- App 視窗 Remove Selected。

## 尚未支援拖出

v3 不支援從 Touch Bar 拖到 Finder 或其他 App。現有 `ShelfScrubberItemView` 是 Touch Bar 點擊／手勢 view，不是 desktop `NSDraggingSource`，也沒有建立 source dragging pasteboard 或 desktop drag image/session。

這需要後續獨立研究 `NSDraggingSource`、pasteboard payload、screen coordinates，以及 DFR Touch Bar input surface 是否能啟動 desktop dragging session；本版沒有加入猜測性實作。

## Build 與驗證

- arm64 type-check：通過。
- x86_64 type-check：通過。
- Universal Release：已建立，版本 3.0 (3)，architectures 為 `x86_64 arm64`。
- M5 structure smoke：scrubber `showsArrowButtons == false`；item 沒有任何 `NSButton`；唯一 `NSPressGestureRecognizer.minimumPressDuration == 3.0`。
- M5 default smoke：清除既有高度設定後，新 Overlay 預設為 5 px。
- M5 delete-model smoke：單項 remove 後 Shelf 為空，測試用硬碟檔案仍存在。
- M5 App launch / normal quit：通過，無 crash。
- Intel Touch Bar 3 秒長按、確認畫面與 DELETE / BACK：待實測。

## Intel v3 實測欄位

- 左右箭頭是否完全消失：待填。
- 小型 `×` 是否完全消失：待填。
- 左右滑動是否維持正常：待填。
- 長按約 3 秒是否進入確認：待填。
- 長按後是否避免誤開檔案：待填。
- DELETE 是否只移除指定 Shelf item：待填。
- 硬碟原始檔案是否保持存在：待填。
- BACK 是否不刪除並返回 Shelf：待填。
