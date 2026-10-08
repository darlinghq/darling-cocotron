#import <AppKit/AppKit.h>
#import <Foundation/NSLayoutAnchor.h>
#include <stdio.h>
static int failures;
static void expect(BOOL value, const char *label) {
    fprintf(stderr,"%s %s\n",value?"PASS":"FAIL",label);
    failures+=!value;
}
int main(void) {
    NSAutoreleasePool *pool=[NSAutoreleasePool new];
    NSView *root=[[[NSView alloc] initWithFrame:NSZeroRect] autorelease];
    NSView *a=[[[NSView alloc] initWithFrame:NSZeroRect] autorelease];
    NSView *b=[[[NSView alloc] initWithFrame:NSZeroRect] autorelease];
    [root addSubview:a]; [root addSubview:b];
    NSLayoutConstraint *c=[[a leftAnchor] constraintEqualToAnchor:[b leftAnchor]];
    expect(![c isActive],"new constraint inactive");
    [c setActive:YES];
    expect([c isActive] && [[root constraints] containsObject:c] && ![[a constraints] containsObject:c],
           "install on closest common ancestor");
    [c setActive:YES];
    expect([[root constraints] count]==1,"repeated activation is idempotent");
    [c setActive:NO];
    expect(![c isActive] && [[root constraints] count]==0,"deactivation unregisters equation");
    NSLayoutConstraint *size=[[a widthAnchor] constraintEqualToConstant:10];
    [size setActive:YES];
    expect([[a constraints] containsObject:size],"single-item equation owned by item");
    [size setActive:NO];
    NSView *other=[[[NSView alloc] initWithFrame:NSZeroRect] autorelease];
    NSLayoutConstraint *invalid=[[a leftAnchor] constraintEqualToAnchor:[other leftAnchor]];
    BOOL caught=NO;
    @try { [invalid setActive:YES]; } @catch(NSException *e) { caught=YES; }
    expect(caught && ![invalid isActive],"reject disconnected items without activation");
    fprintf(stderr,"RESULT failures=%d\n",failures);
    [pool drain]; return failures?1:0;
}
