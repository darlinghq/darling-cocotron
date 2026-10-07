#import <AppKit/AppKit.h>
#import <QuartzCore/CADisplayLink.h>
#include <stdio.h>

@interface NSView (DisplayLinkTestDeclaration)
- (CADisplayLink *)displayLinkWithTarget:(id)target selector:(SEL)selector;
@end

static BOOL viewDeallocated, targetDeallocated;
@interface LinkView : NSView @end
@implementation LinkView
- (void)dealloc { viewDeallocated = YES; [super dealloc]; }
@end
@interface LinkTarget : NSObject { @public NSUInteger frames; CADisplayLink *sender; }
- (void)frame:(CADisplayLink *)link;
@end
@implementation LinkTarget
- (void)frame:(CADisplayLink *)link { ++frames; sender = link; }
- (void)dealloc { targetDeallocated = YES; [super dealloc]; }
@end
static void runFor(NSTimeInterval seconds) {
    @autoreleasepool {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
    }
}
static unsigned failures;
static void expectResult(BOOL pass, const char *name) {
    printf("%s %s\n", pass ? "PASS" : "FAIL", name); fflush(stdout);
    if (!pass) ++failures;
}
int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];
    LinkView *view = [[LinkView alloc] initWithFrame:NSMakeRect(0,0,80,80)];
    LinkTarget *target = [LinkTarget new];
    CADisplayLink *link = nil;
    @try { link = [[view displayLinkWithTarget:target selector:@selector(frame:)] retain]; }
    @catch (NSException *exception) {
        printf("FAIL factory: %s\n", [[exception reason] UTF8String]); return 1;
    }
    expectResult(link != nil, "factory returns a display link");
    if (!link) return 1;
    [link addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    runFor(.08); expectResult(target->frames == 0, "detached view suppresses callbacks");
    NSWindow *first = [[NSWindow alloc] initWithContentRect:NSMakeRect(30,30,80,80)
        styleMask:0 backing:NSBackingStoreBuffered defer:NO];
    NSView *parent = [[NSView alloc] initWithFrame:NSMakeRect(0,0,80,80)];
    [parent addSubview:view]; [parent setHidden:YES]; [first setContentView:parent];
    [first orderFront:nil]; runFor(.08);
    expectResult(target->frames == 0, "hidden ancestor suppresses callbacks");
    [parent setHidden:NO]; runFor(.12);
    expectResult(target->frames > 0 && target->sender == link, "visible view receives the actual link");
    NSUInteger previous = target->frames;
    [view setHidden:YES]; runFor(.08);
    expectResult(target->frames == previous, "hidden view suppresses callbacks");
    [view setHidden:NO]; runFor(.08);
    expectResult(target->frames > previous, "showing view resumes callbacks");
    previous = target->frames; link.paused = YES; runFor(.08);
    expectResult(target->frames == previous, "pause preserves callback suppression");
    link.paused = NO; [first orderOut:nil]; runFor(.08);
    expectResult(target->frames == previous, "ordered-out window suppresses callbacks");
    NSWindow *second = [[NSWindow alloc] initWithContentRect:NSMakeRect(150,30,80,80)
        styleMask:0 backing:NSBackingStoreBuffered defer:NO];
    [view removeFromSuperview]; [second setContentView:view]; [second orderFront:nil]; runFor(.12);
    expectResult(target->frames > previous, "reparenting to visible window resumes callbacks");
    [view removeFromSuperview]; [second setContentView:nil]; previous = target->frames; runFor(.08);
    expectResult(target->frames == previous, "detaching again suppresses callbacks");
    [view release]; expectResult(viewDeallocated, "link does not retain the view");
    runFor(.08); expectResult(target->frames == previous, "deallocated view suppresses callbacks");
    [link invalidate]; [target release];
    expectResult(targetDeallocated, "invalidation releases the callback target");
    [link release]; [first close]; [second close]; [parent release];
    printf("RESULT failures=%u\n", failures);
    return failures ? 1 : 0;
} }
