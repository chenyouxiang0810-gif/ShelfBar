# Phase 1–2 Findings

## 固定研究版本

| Source | Commit / system |
|---|---|
| Pock | `127aac1986e2dc5a3d6995ddbd35e19bf2f0c85a` |
| PockKit | `335bc4c0edb4c9ad1beabe294f70cd39300dc577` |
| Pock Dock widget | `fd5250e6291e886abdeaf018406dd2d4b6d2160a` |
| MTMR | `94fc98cceff94cf69a2e7c28f726cf35ab93c461` |
| touch-baer | `419a5cb828048fee8cd634de8ea0d1c51b49e99a` |
| bttopn | `40ef89b6034bfa775ba4a835b8ccef591e8f4216` |
| Local system | 2026-07-04 本機 macOS/Command Line Tools snapshot |

## 第一階段：跨來源研究

### Apple 公開資料的邊界

Apple 的公開 `NSTouchBar` 文件描述 front-most App 與 responder-chain discovery，沒有公開 system-modal presentation API：

- [NSTouchBar documentation](https://developer.apple.com/documentation/appkit/nstouchbar)
- [Apple Touch Bar sample code index](https://developer.apple.com/documentation/samplecode)
- [WWDC19: SwiftUI On All Devices](https://developer.apple.com/videos/play/wwdc2019/240/)

Apple 的舊 WWDC/官方 sample 資料仍只描述 contextual `NSTouchBar`、delegate、items 與 responder/focus 關係；本次沒有在 Apple 官方資料找到 system-modal selector 的公開說明。

Apple OSS Distributions 搜尋沒有找到 DFRFoundation source repository。這只代表本次在 Apple 公開 OSS 入口沒有找到來源，不能據此證明 Apple 從未發布過任何相關片段：

- [Apple OSS Distributions](https://github.com/apple-oss-distributions/)

### 本機 SDK 中的 DFRFoundation

目前 SDK 的 private TBD：

`$SDK/System/Library/PrivateFrameworks/DFRFoundation.framework/Versions/A/DFRFoundation.tbd`

- targets 同時列出 `x86_64-macos`、`arm64-macos`、`arm64e-macos`（TBD 第 3、7 行）。
- install name 明確位於 `/System/Library/PrivateFrameworks`（第 4 行）。
- exported symbols 包含 `DFRElementPresentSystemModal`、`DFRElementDismissSystemModal`、`DFRElementSetControlStripPresenceForIdentifier`（第 15-22 行）。
- 也包含 `DFRSystemModalShowsCloseBoxWhenFrontMost`、Touch Bar simulator、`_DFRGetServerPID` 與 `_DFRGetTouchBarAgentPID`（第 51-68 行）。

在本機用 `dlopen`/`dlsym` 做只讀 symbol presence check，以上四個 Pock 常用 symbols 均存在；AppKit runtime 也回報 `NSTouchBar` class responds to `presentSystemModalTouchBar:placement:systemTrayItemIdentifier:`、dismiss 與 minimize selectors。這證明 symbols 在本機存在，不代表沒有 Touch Bar 的 M5 已顯示 UI。

### NSFunctionRow

Pock 自行宣告 private `NSFunctionRow`：`Pock/Pock/Private/ApplePrivate.h:54-61`。

實際用途：

- `Pock/Pock/Private/TouchBarHelper.swift:98-109` 取得 top-level function-row views 並隱藏 close button。
- `TouchBarHelper.swift:184-224` swizzle `markActiveFunctionRowsAsDimmed:` 和 private `_NSFunctionRow.escapeKeyPaddingForCloseButton:`。
- `PockTouchBarController.swift:33-47` 用 `_topLevelViews()` 取得 Touch Bar internal view，供 mouse/drag visual mapping。

本機 runtime presence check 找到 `NSFunctionRow`、`_NSFunctionRow` 與 `NSFunctionRowBackgroundColorView`。它們不在公開 AppKit headers。

### Touch Bar daemon / agents

本機系統檔案證據：

- `/System/Library/LaunchDaemons/com.apple.touchbarserver.plist` 的 Program 是 `/usr/libexec/TouchBarServer`，Mach services 包含 `com.apple.touchbarserver`、`.mig`、`.plugin`、`.render`。
- `/System/Library/LaunchAgents/com.apple.controlstrip.plist` 啟動 `ControlStrip.app`，使用 `com.apple.touchbar.matching` launch event。
- `/usr/libexec/TouchBarServer` 同時有 x86_64 與 arm64e slices，連結 private `DFRBrightness`、`DFRDisplay`、`DFRFoundation`、`SkyLight`、`TCC` 等 frameworks。
- `TouchBarServer` entitlement 包含 `com.apple.appledfr.client`、`com.apple.private.SkyLight.touchbar` 與 private HID/TCC capabilities。
- `ControlStrip.app` 連結 `DFRFoundation`，並有 `com.apple.private.controlstrip`、`com.apple.private.touchbar.user-device` entitlements。

這台 M5 上沒有 Touch Bar，因此 `TouchBarServer`/`ControlStrip` 沒有 active process；launch configuration 與 binaries 仍存在。

### system-modal Touch Bar 的交叉證據

- Pock：`PockTouchBarController.swift:62-86` 直接呼叫 private system-modal selectors。
- MTMR：`ResearchSources/MTMR/MTMR/CBridge/TouchBarPrivateApi.h:18-30` 宣告 10.13/10.14 variants；`TouchBarController.swift:288-307` 建立 Control Strip item 並 present。
- touch-baer：`ResearchSources/touch-baer/TouchBarTest/AppDelegate.m:25-49,71-80` 是最小 Objective-C 範例。
- bttopn：`ResearchSources/bttopn/Sources/TouchBarManager.swift:117-140,175-210` 在較新 macOS 反覆 re-present cached bar；其註解顯示 focus change 仍會使 modal 被系統 dismiss。

共同模式是：公開 `NSTouchBar` 負責內容，private `NSTouchBar` class selector 負責 system-modal presentation；可選的 DFR functions 與 `NSTouchBarItem.addSystemTrayItem` 負責 Control Strip trigger。

## 第二階段：Pock 全量稽核

### 1. Private Framework imports / links

Pock main target 直接連結的 private framework 只有一個：

- `DFRFoundation.framework`：`Pock/Pock.xcodeproj/project.pbxproj:56,171,205-211`。
- build settings 額外搜尋 `$(SYSTEM_LIBRARY_DIR)/PrivateFrameworks`：同檔 `1137-1140,1171-1174`。

PockKit 沒有直接連結 private framework；它在 `PKTouchBarController.swift:112-128` 以 Objective-C runtime 找 host App 的 `TouchBarHelper`。

獨立 Dock widget 沒直接連結 DFRFoundation，但 `PockDockHelper.h:12-15` 宣告未文件化 `CoreDockGetAutoHideEnabled`、`CoreDockSetAutoHideEnabled`、`_AXUIElementGetWindow` symbols。這些不是 Pock main target 的 private framework imports。

### 2. Objective-C Runtime 呼叫

Touch Bar 相關：

- `object_getClass`：`Pock/Private/TouchBarHelper.swift:104`。
- `class_getClassMethod`：`TouchBarHelper.swift:199`。
- `class_getInstanceMethod`：`TouchBarHelper.swift:221`。
- `method_exchangeImplementations`：`TouchBarHelper.swift:200,222`。
- `NSSelectorFromString`：`TouchBarHelper.swift:219`。
- `NSClassFromString`：列於下一節。

PockKit host bridge：

- `objc_getClass`、`Selector`、`perform`：`PockKit/.../PKTouchBarController.swift:112-128`。
- `object_getClass` 另在 `PKScreenEdgeController.swift:55,76` 用於 debug class name，與 private API 無關。

其他一般 dynamic dispatch：`HotKey.swift:39,42` 以 `perform` 呼叫設定的 target selector；`PKView.swift:64,71` 用 delayed perform。它們不是 private Touch Bar access。

### 3. 所有 NSClassFromString()

- `Pock/Widgets/Models/PKWidgetInfo.swift:76-79`：從 widget metadata 載入 preference class；不是 private Touch Bar class。
- `Pock/Private/TouchBarHelper.swift:103-105`：`NSFunctionRowBackgroundColorView`。
- `TouchBarHelper.swift:219-222`：`_NSFunctionRow`。

### 4. 所有 dlopen()

Pock、PockKit、Dock widget source 在固定 commits 中沒有 `dlopen()` call。

### 5. 所有 dlsym()

只有一處：`Pock/Utilities/STPrivilegedTask/STPrivilegedTask.m:29-64`，從 `RTLD_DEFAULT` 解析已 deprecated 的 `AuthorizationExecuteWithPrivileges`。用途是 privileged task，不是建立 Touch Bar。

### 6. Private selectors

`Pock/Pock/Private/ApplePrivate.h:10-68` 的宣告：

- `NSApplication.toggleTouchBarControlStripCustomizationPalette:`：有使用，`AppController.swift:310-312`。
- `NSMenuItem._setViewHandlesEvents:`：有使用，兩個 custom menu view files。
- `NSTouchBarItem.addSystemTrayItem:`：有宣告；Pock main commit 未找到 call site。
- `NSCustomTouchBarItem.viewForCustomizationPalette` / `viewForCustomizationPreview` / `preferredSizeForCustomizationPalette`：前兩個由 `PKWidgetTouchBarItem` override 並用於 customization snapshot；第三個未找到 call site。
- `NSTouchBar.presentSystemModalFunctionBar...` / dismiss / minimize：10.13 fallback。
- `NSTouchBar.presentSystemModalTouchBar...` / dismiss / minimize：10.14+ 主路徑。
- `NSTouchBar._purgeCacheIfNecessary`、`items`：有宣告；未找到 call site。
- `NSFunctionRow.markActiveFunctionRowsAsDimmed:`、`_topLevelFunctionRowViews`、`activeFunctionRows`：有使用。
- `NSFunctionRow.removeActiveFunctionRow:`、`addActiveFunctionRow:`：有宣告；未找到 call site。
- `_NSFunctionRow.escapeKeyPaddingForCloseButton:`：以 `NSSelectorFromString` 取得並 swizzle。

Private C symbols：

- `_DFRGetServerPID`：`TouchBarHelper.swift:117-136` 使用。
- `_DFRGetTouchBarAgentPID`：只有宣告，未找到 call site。
- `DFRSystemModalShowsCloseBoxWhenFrontMost`、`DFRElementSetControlStripPresenceForIdentifier`：ApplePrivate 宣告；Pock main 固定 commit 未找到 call site。

### 7. Touch Bar 建立流程

1. `AppDelegate.applicationDidFinishLaunching` 載入 widgets，callback 內呼叫 `AppController.shared.prepareTouchBar()`：`Pock/AppDelegate.swift:23-58`。
2. `prepareTouchBar()` 建立 `PockTouchBarController.load()`，再建立 `PKTouchBarNavigationController(rootController:)`：`Pock/AppController.swift:131-135`。
3. navigation controller initializer `push(rootController)`，而 `push` 呼叫 `controller.present()`：`PockKit/.../PKTouchBarNavigationController.swift:27-47`。
4. `PockTouchBarController.present()` 收集 widgets、選 placement、呼叫 private system-modal selector：`PockTouchBarController.swift:62-86`。
5. `makeTouchBar()` 建立公開 `NSTouchBar`；delegate 依 identifier 建立 `PKWidgetTouchBarItem`：同檔 `108-134`。
6. `PKWidgetTouchBarItem` 建立 widget instance，透過 `PKWidgetViewController` 把 widget view 放進 `NSCustomTouchBarItem`。

### 8. 如何取得 Touch Bar Controller

Pock 並不是向 daemon 查詢 controller。它自行持有：

- `AppController.pockTouchBarController`：`Pock/AppController.swift:74-80`。
- `prepareTouchBar()` 建立 controller：同檔 `131-135`。
- `PKTouchBarNavigationController.visibleController` 是 stack 最上層 controller：`PockKit/.../PKTouchBarNavigationController.swift:16-25`。
- PockKit widget 需要 main navigation controller 時，`PKTouchBarController.executeTouchBarHelperMethod("mainNavigationController")` 透過 `objc_getClass` 找 host `TouchBarHelper`：`PockKit/.../PKTouchBarController.swift:31-45,112-128`。

`NSFunctionRow._topLevelViews()` 取得的是 internal Touch Bar view，不是 Pock controller 本身。

## Prototype 1 研究判準

- 編譯成功：只能證明 private declarations 與 linker symbols 在 SDK 可解析。
- M5 啟動不 crash：只能證明呼叫在無 Touch Bar hardware 的環境可執行到 return。
- 真正成功：必須在 Intel Touch Bar Mac 看到 system-modal bar 顯示 `HELLO` 與可按的 `TEST`，並在 log 看到 press count。

本階段不執行 Finder drag Prototype。
