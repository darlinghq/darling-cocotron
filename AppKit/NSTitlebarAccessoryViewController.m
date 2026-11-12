#import <AppKit/NSTitlebarAccessoryViewController.h>
#import <AppKit/NSScrollEdgeEffectStyle.h>

@implementation NSTitlebarAccessoryViewController

@synthesize preferredScrollEdgeEffectStyle = _preferredScrollEdgeEffectStyle;
@synthesize automaticallyAdjustsSize = _automaticallyAdjustsSize;
@synthesize hidden = _hidden;
@synthesize fullScreenMinHeight = _fullScreenMinHeight;
@synthesize layoutAttribute = _layoutAttribute;

- (void) dealloc {
    [_preferredScrollEdgeEffectStyle release];
    [super dealloc];
}

- (instancetype) initWithNibName: (NSString *) name bundle: (NSBundle *) bundle {
    if ((self = [super initWithNibName: name bundle: bundle])) {
        _automaticallyAdjustsSize = YES;
        _hidden = NO;
        _fullScreenMinHeight = 0;
        _layoutAttribute = NSLayoutAttributeBottom;
    }
    return self;
}

// The archived properties aren't decoded: the defaults apply.
- (instancetype) initWithCoder: (NSCoder *) coder {
    if ((self = [super initWithCoder: coder])) {
        _automaticallyAdjustsSize = YES;
        _hidden = NO;
        _fullScreenMinHeight = 0;
        _layoutAttribute = NSLayoutAttributeBottom;
    }
    return self;
}

@end
