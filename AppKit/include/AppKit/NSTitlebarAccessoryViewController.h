#import <AppKit/NSViewController.h>
#import <Foundation/Foundation.h>

@class NSScrollEdgeEffectStyle;

@interface NSTitlebarAccessoryViewController : NSViewController {
    NSScrollEdgeEffectStyle *_preferredScrollEdgeEffectStyle;
    BOOL _automaticallyAdjustsSize;
    BOOL _hidden;
    CGFloat _fullScreenMinHeight;
}

@property (retain) NSScrollEdgeEffectStyle *preferredScrollEdgeEffectStyle;
// Stored only: accessories aren't placed in the title bar.
@property BOOL automaticallyAdjustsSize;
@property (getter=isHidden) BOOL hidden;
@property CGFloat fullScreenMinHeight;

@end
