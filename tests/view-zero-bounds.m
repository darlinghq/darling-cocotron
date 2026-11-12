// Run against a rebuilt AppKit. No window server or shared application needed.
#import <AppKit/AppKit.h>
#include <math.h>
#include <stdio.h>

static BOOL closeEnough(CGFloat a, CGFloat b) {
    return isfinite(a) && fabs(a-b)<0.00001;
}
static BOOL sameRect(NSRect a, NSRect b) {
    return closeEnough(a.origin.x,b.origin.x) && closeEnough(a.origin.y,b.origin.y) &&
        closeEnough(a.size.width,b.size.width) && closeEnough(a.size.height,b.size.height);
}
int main(void) {
    @autoreleasepool {
        for (unsigned mask=0; mask<4; mask++) {
            NSView *parent=[[NSView alloc] initWithFrame:NSMakeRect(0,0,100,100)];
            CGFloat width=(mask&1)?40:0, height=(mask&2)?60:0;
            NSView *child=[[NSView alloc] initWithFrame:NSMakeRect(10,20,width,height)];
            [child setBounds:NSMakeRect(0,0,width/2,height/3)];
            [parent addSubview:child];
            NSRect input=NSMakeRect(2,3,5,7);
            CGFloat sx=width?2:1, sy=height?3:1;
            NSRect expected=NSMakeRect(10+2*sx,20+3*sy,5*sx,7*sy);
            NSRect converted=[child convertRect:input toView:parent];
            NSRect restored=[child convertRect:converted fromView:parent];
            BOOL pass=sameRect(converted,expected) && sameRect(restored,input);
            printf("mask=%u converted=%g,%g,%g,%g pass=%d\n",mask,
                converted.origin.x,converted.origin.y,converted.size.width,converted.size.height,pass);
            [child release];[parent release];
            if (!pass) return 1;
        }
        puts("zero bounds conversion PASS");
    }
    return 0;
}
