#import <AppKit/NSViewController.h>
#import <Foundation/Foundation.h>

@interface NSTitlebarAccessoryViewController : NSViewController {
    BOOL _automaticallyAdjustsSize;
    BOOL _hidden;
    CGFloat _fullScreenMinHeight;
}

// Stored only: accessories aren't placed in the title bar.
@property BOOL automaticallyAdjustsSize;
@property (getter=isHidden) BOOL hidden;
@property CGFloat fullScreenMinHeight;

@end
