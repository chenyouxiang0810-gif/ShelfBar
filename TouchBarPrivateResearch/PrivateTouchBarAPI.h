#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

// Private DFRFoundation C API. Research prototype only.
extern void DFRSystemModalShowsCloseBoxWhenFrontMost(BOOL show);

// Private AppKit selectors. Research prototype only.
@interface NSTouchBar (TouchBarPrivateResearch)
+ (void)presentSystemModalTouchBar:(NSTouchBar *)touchBar
                         placement:(long long)placement
           systemTrayItemIdentifier:(nullable NSTouchBarItemIdentifier)identifier;
+ (void)dismissSystemModalTouchBar:(NSTouchBar *)touchBar;
@end

// Private AppKit class used only by the opt-in MouseBridge research mode.
@interface NSFunctionRow : NSObject
+ (NSArray<NSView *> *)_topLevelFunctionRowViews;
@end

NS_ASSUME_NONNULL_END
