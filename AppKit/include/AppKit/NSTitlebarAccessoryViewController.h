#import <AppKit/NSViewController.h>
#import <Foundation/Foundation.h>

@class NSScrollEdgeEffectStyle;

@interface NSTitlebarAccessoryViewController : NSViewController {
    NSScrollEdgeEffectStyle *_preferredScrollEdgeEffectStyle;
}

@property (retain) NSScrollEdgeEffectStyle *preferredScrollEdgeEffectStyle;

@end
