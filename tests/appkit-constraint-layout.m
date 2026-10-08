#import <AppKit/AppKit.h>
#import <Foundation/NSLayoutAnchor.h>
#include <math.h>
#include <stdio.h>
#include <stdint.h>
@interface SizedView : NSView
@end
@implementation SizedView
- (NSSize)intrinsicContentSize { return NSMakeSize(80, 20); }
@end
@interface FlippedView : NSView
@end
@implementation FlippedView
- (BOOL)isFlipped { return YES; }
@end
static int failures;
static void layoutAssert(BOOL pass, const char *name) {
    fprintf(stderr, "%s %s\n", pass ? "PASS" : "FAIL", name);
    if (!pass) failures++;
}
static BOOL near(CGFloat a, CGFloat b) { return fabs(a-b) < .01; }
int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    NSView *root = [[[NSView alloc] initWithFrame:NSMakeRect(0,0,400,300)] autorelease];
    SizedView *child = [[[SizedView alloc] initWithFrame:NSZeroRect] autorelease];
    [child setTranslatesAutoresizingMaskIntoConstraints:NO]; [root addSubview:child];
    NSLayoutConstraint *left = [[child leftAnchor] constraintEqualToAnchor:[root leftAnchor] constant:10];
    NSLayoutConstraint *top = [[child topAnchor] constraintEqualToAnchor:[root topAnchor] constant:-15];
    [NSLayoutConstraint activateConstraints:@[left,top]];
    [root layoutSubtreeIfNeeded];
    NSRect r=[child frame];
    layoutAssert(near(r.origin.x,10) && near(r.origin.y,265) && near(r.size.width,80) && near(r.size.height,20), "anchors and intrinsic dimensions");
    layoutAssert([[root constraints] count]==2 && [left isActive], "common ancestor registration");
    [left setConstant:25]; [root layoutSubtreeIfNeeded];
    layoutAssert(near([child frame].origin.x,25), "constant mutation");
    [root setFrameSize:NSMakeSize(500,400)]; [root layoutSubtreeIfNeeded];
    layoutAssert(near([child frame].origin.y,365), "parent resize");
    NSLayoutConstraint *width=[[child widthAnchor] constraintEqualToAnchor:[root widthAnchor] multiplier:.5];
    [width setActive:YES]; [root layoutSubtreeIfNeeded];
    layoutAssert(near([child frame].size.width,250), "multiplier and required size over intrinsic");
    [width setActive:NO]; [root layoutSubtreeIfNeeded];
    layoutAssert(near([child frame].size.width,80) && [[root constraints] count]==2, "deactivation removes equation");
    NSLayoutConstraint *minimum=[[child widthAnchor] constraintGreaterThanOrEqualToConstant:100];
    [minimum setActive:YES]; [root layoutSubtreeIfNeeded];
    layoutAssert(near([child frame].size.width,100), "inequality");
    [minimum setActive:NO];
    NSView *detached=[[[NSView alloc] initWithFrame:NSZeroRect] autorelease];
    NSLayoutConstraint *invalid=[[child leftAnchor] constraintEqualToAnchor:[detached leftAnchor]];
    BOOL caught=NO;
    @try { [invalid setActive:YES]; } @catch(NSException *e) { caught=YES; }
    layoutAssert(caught && ![invalid isActive], "reject disconnected items");
    FlippedView *flipped=[[[FlippedView alloc] initWithFrame:NSMakeRect(0,0,200,100)] autorelease];
    SizedView *nested=[[[SizedView alloc] initWithFrame:NSZeroRect] autorelease];
    [nested setTranslatesAutoresizingMaskIntoConstraints:NO]; [flipped addSubview:nested];
    [NSLayoutConstraint activateConstraints:@[
        [[nested topAnchor] constraintEqualToAnchor:[flipped topAnchor] constant:12],
        [[nested leftAnchor] constraintEqualToAnchor:[flipped leftAnchor] constant:7]]];
    [flipped layoutSubtreeIfNeeded];
    layoutAssert(near([nested frame].origin.y,12) && near([nested frame].origin.x,7), "flipped root coordinates");
    NSLayoutConstraint *strong = [[child widthAnchor] constraintEqualToConstant:100];
    [strong setPriority:900]; [strong setActive:YES];
    NSMutableArray *weak = [NSMutableArray array];
    for (int i=0;i<4;i++) {
        NSLayoutConstraint *c=[[child widthAnchor] constraintEqualToConstant:10+i];
        [c setPriority:800]; [c setActive:YES]; [weak addObject:c];
    }
    [root layoutSubtreeIfNeeded];
    layoutAssert(near([child frame].size.width,100), "higher priority survives multiple weaker constraints");
    [NSLayoutConstraint deactivateConstraints:weak]; [strong setActive:NO];
    NSView *a=[[[NSView alloc] initWithFrame:NSMakeRect(0,0,20,20)] autorelease];
    NSView *b=[[[NSView alloc] initWithFrame:NSMakeRect(0,0,20,20)] autorelease];
    NSView *container=(uintptr_t)a > (uintptr_t)b ? a : b;
    NSView *leaf=container==a ? b : a;
    [container setTranslatesAutoresizingMaskIntoConstraints:NO];
    [leaf setTranslatesAutoresizingMaskIntoConstraints:NO];
    [leaf setAutoresizingMask:NSViewWidthSizable];
    [root addSubview:container]; [container addSubview:leaf];
    NSArray *nestedConstraints=@[
        [[container leftAnchor] constraintEqualToAnchor:[root leftAnchor]],
        [[container bottomAnchor] constraintEqualToAnchor:[root bottomAnchor]],
        [[container widthAnchor] constraintEqualToConstant:100],
        [[container heightAnchor] constraintEqualToConstant:50],
        [[leaf leftAnchor] constraintEqualToAnchor:[container leftAnchor]],
        [[leaf bottomAnchor] constraintEqualToAnchor:[container bottomAnchor]],
        [[leaf widthAnchor] constraintEqualToConstant:40],
        [[leaf heightAnchor] constraintEqualToConstant:10]];
    [NSLayoutConstraint activateConstraints:nestedConstraints];
    [root layoutSubtreeIfNeeded];
    layoutAssert(near([leaf frame].size.width,40) && near([container frame].size.width,100),
                 "parent frame update preserves solved child size");
    [NSLayoutConstraint deactivateConstraints:nestedConstraints];
    [container removeFromSuperview];
    [child removeFromSuperview];
    layoutAssert(![left isActive] && ![top isActive] && [[root constraints] count]==0,
                 "removal deactivates ancestor-owned constraints");
    BOOL removalLayout=YES;
    @try { [root layoutSubtreeIfNeeded]; } @catch(NSException *e) { removalLayout=NO; }
    layoutAssert(removalLayout, "layout after subtree removal");
    NSView *temporary=[[NSView alloc] initWithFrame:NSZeroRect];
    NSLayoutConstraint *owned=[[[temporary widthAnchor] constraintEqualToConstant:10] retain];
    [owned setActive:YES]; [temporary release];
    layoutAssert(![owned isActive], "destroying the owner deactivates its constraints");
    [owned release];
    fprintf(stderr,"RESULT failures=%d\n",failures);
    [pool drain]; return failures ? 1 : 0;
}
