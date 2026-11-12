#import <AppKit/NSTitlebarAccessoryViewController.h>

@implementation NSTitlebarAccessoryViewController

@synthesize automaticallyAdjustsSize = _automaticallyAdjustsSize;
@synthesize hidden = _hidden;
@synthesize fullScreenMinHeight = _fullScreenMinHeight;
@synthesize layoutAttribute = _layoutAttribute;

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
