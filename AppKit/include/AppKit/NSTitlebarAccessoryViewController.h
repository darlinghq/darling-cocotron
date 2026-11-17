#import <AppKit/NSViewController.h>
#import <AppKit/NSLayoutConstraint.h>
#import <AppKit/AppKitIvarLayout.h>
#import <Foundation/Foundation.h>

@class NSScrollEdgeEffectStyle;

@interface NSTitlebarAccessoryViewController : NSViewController {
    NSScrollEdgeEffectStyle *_preferredScrollEdgeEffectStyle;
    BOOL _automaticallyAdjustsSize;
    BOOL _hidden;
    CGFloat _fullScreenMinHeight;
    NSLayoutAttribute _layoutAttribute;
    NS_LEGACY_IVAR_PAD(_NSTitlebarAccessoryViewControllerReserved, 20)
}

@property (retain) NSScrollEdgeEffectStyle *preferredScrollEdgeEffectStyle;
// Stored only: accessories aren't placed in the title bar.
@property BOOL automaticallyAdjustsSize;
@property (getter=isHidden) BOOL hidden;
@property CGFloat fullScreenMinHeight;
@property NSLayoutAttribute layoutAttribute;

@end
