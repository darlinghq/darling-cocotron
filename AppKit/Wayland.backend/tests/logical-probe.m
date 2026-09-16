#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
@interface NSObject (LogicalProbe)
+ (id)currentDisplay;
- (NSArray *)screens;
- (void)processPendingEvents;
@end
int main(void){@autoreleasepool{
    [NSApplication sharedApplication];id display=[NSClassFromString(@"NSDisplay") currentDisplay];
    NSArray *screens=[display screens];int failures=0;
    if([screens count]!=1)failures++;
    else {
        NSScreen *s=[screens objectAtIndex:0];NSRect r=[s frame];int scale=atoi(getenv("EXPECTED_SCALE"));
        printf("FRAME %.0f %.0f %.0f %.0f scale=%.0f\n",r.origin.x,r.origin.y,r.size.width,r.size.height,[s backingScaleFactor]);
        if(!NSEqualRects(r,NSMakeRect(0,0,333,222))||[s backingScaleFactor]!=scale)failures++;
    }
    if(getenv("PROBE_LIFECYCLE")) {
        BOOL updated=NO,added=NO;
        for(int i=0;i<400;i++) {
            [display processPendingEvents];screens=[display screens];
            if([screens count]==1 && NSEqualRects([[screens objectAtIndex:0] frame],NSMakeRect(0,0,444,222)))updated=YES;
            if([screens count]==2 && NSEqualRects([[screens objectAtIndex:0] frame],NSMakeRect(0,0,444,222)) &&
                NSEqualRects([[screens objectAtIndex:1] frame],NSMakeRect(300,0,333,222))){added=YES;break;}
            usleep(10000);
        }
        printf("LIFECYCLE updated=%d added=%d\n",updated,added);if(!updated||!added)failures++;
    }
    [display processPendingEvents];printf("PROBE failures=%d\n",failures);return failures?1:0;
}}
