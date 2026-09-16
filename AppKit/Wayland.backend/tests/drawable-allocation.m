#import <AppKit/AppKit.h>
#import <CoreGraphics/CGSubWindow.h>
#include <stdio.h>
@interface NSWindow (AllocationFixture)
- (CGSubWindow *)_createSubWindowWithFrame:(CGRect)frame;
@end
static NSWindow *window;static CGSubWindow *child;static unsigned failures,checks;
static void expectSize(CGFloat w,CGFloat h,const char *label){
    CGSize actual=[child drawablePixelSize];checks++;
    BOOL pass=actual.width==w&&actual.height==h;
    printf("CHECK %s %s %.0fx%.0f\n",pass?"PASS":"FAIL",label,actual.width,actual.height);fflush(stdout);
    if(!pass)failures++;
}
@interface AllocationDriver:NSObject @end
@implementation AllocationDriver
- (void)start:(id)sender{
    child=[[window _createSubWindowWithFrame:CGRectMake(2000,2000,101.2,51.2)]retain];
    if(!child){printf("NO_CHILD\n");fflush(stdout);exit(2);}
    expectSize(1,1,"initial-clipped-allocation");
    [child setFrame:CGRectMake(20,20,101.2,51.2)];expectSize(102,52,"visible-allocation");
    [child setFrame:CGRectMake(2000,2000,199,99)];expectSize(102,52,"clipped-retains-allocation");
    [child setFrame:CGRectMake(20,20,103,53)];expectSize(103,53,"resized-allocation");
    [child hide];expectSize(103,53,"hidden-retains-allocation");[child show];
    printf("SCALE_READY\n");fflush(stdout);
    [self performSelector:@selector(finish:) withObject:nil afterDelay:2];
}
- (void)finish:(id)sender{
    expectSize(206,106,"output-scale-allocation");
    checks++;if([window backingScaleFactor]!=2)failures++;
    [child setFrame:CGRectMake(2000,2000,99,99)];expectSize(206,106,"scaled-clipped-retains-allocation");
    [child release];printf("RESULT checks=%u failures=%u\n",checks,failures);fflush(stdout);exit(failures?1:0);
}
@end
int main(void){@autoreleasepool{
    [NSApplication sharedApplication];window=[[NSWindow alloc]initWithContentRect:NSMakeRect(100,100,500,350) styleMask:NSTitledWindowMask backing:NSBackingStoreBuffered defer:NO];[window setTitle:@"Drawable allocation fixture"];[window makeKeyAndOrderFront:nil];
    AllocationDriver *driver=[AllocationDriver new];[driver performSelector:@selector(start:) withObject:nil afterDelay:.5];[NSApp run];
}}
