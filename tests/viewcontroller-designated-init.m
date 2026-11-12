#import <AppKit/AppKit.h>
#include <stdio.h>
@interface StoredControlsController : NSViewController {
    NSPopUpButton *_popup;
    NSUInteger _initializations;
}
@property(readonly) NSPopUpButton *popup;
@property(readonly) NSUInteger initializations;
@end
@implementation StoredControlsController
- (instancetype)initWithNibName:(NSString *)name bundle:(NSBundle *)bundle {
    self=[super initWithNibName:name bundle:bundle];
    if(self) { _popup=[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO]; _initializations++; }
    return self;
}
- (void)dealloc { [_popup release]; [super dealloc]; }
- (NSPopUpButton *)popup { return _popup; }
- (NSUInteger)initializations { return _initializations; }
- (void)loadView {
    NSView *view=[[[NSView alloc] initWithFrame:NSMakeRect(0,0,280,300)] autorelease];
    [view addSubview:_popup]; [self setView:view];
}
@end
int main(void) {
    NSAutoreleasePool *pool=[NSAutoreleasePool new];
    StoredControlsController *controller=[[[StoredControlsController alloc] init] autorelease];
    BOOL initialized=[controller popup]!=nil && [controller initializations]==1;
    NSView *view=[controller view];
    BOOL child=[controller popup]!=nil && [[view subviews] containsObject:[controller popup]];
    fprintf(stderr,"%s default initializer dispatches once to designated initializer\n",initialized?"PASS":"FAIL");
    fprintf(stderr,"%s stored control survives into loadView\n",child?"PASS":"FAIL");
    [pool drain]; return initialized&&child?0:1;
}
