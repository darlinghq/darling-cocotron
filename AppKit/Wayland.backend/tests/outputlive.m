#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>
@interface NSObject (OutputLive)
+ (id)currentDisplay;
- (NSArray *)screens;
- (id)platformWindow;
- (int)bufferScale;
@end
static NSWindow *window;
static NSString *previous;
@interface OutputLiveApplication : NSApplication @end
@implementation OutputLiveApplication
- (void)sample:(id)sender {
    NSArray *screens=[[NSClassFromString(@"NSDisplay") currentDisplay] screens];
    NSMutableString *line=[NSMutableString stringWithFormat:@"STATE %lu",(unsigned long)[screens count]];
    for(NSScreen *screen in screens) {
        NSRect r=[screen frame];
        [line appendFormat:@" %.3f,%.3f,%.3f",r.size.width,r.size.height,[screen backingScaleFactor]];
    }
    [line appendFormat:@" window=%d",[[window platformWindow] bufferScale]];
    if(![line isEqual:previous]) {printf("%s\n",[line UTF8String]);fflush(stdout);[previous release];previous=[line copy];}
}
- (void)finish:(id)sender { printf("LIVE_COMPLETE\n");fflush(stdout);exit(0); }
@end
int main(void) { @autoreleasepool {
    [OutputLiveApplication sharedApplication];
    window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,300,200) styleMask:NSTitledWindowMask backing:NSBackingStoreBuffered defer:NO];
    [window setTitle:@"Output state fixture"];[window orderFront:nil];
    [NSTimer scheduledTimerWithTimeInterval:.1 target:NSApp selector:@selector(sample:) userInfo:nil repeats:YES];
    [NSApp performSelector:@selector(finish:) withObject:nil afterDelay:24];[NSApp run];
} }
