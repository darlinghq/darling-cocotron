#import <Foundation/Foundation.h>
#import <QuartzCore/CALayerContext.h>
#include <stdio.h>
int main(void) {
    @autoreleasepool {
        // Do not register an EGL display: context creation must fail.
        CALayerContext *context=[[CALayerContext alloc] initWithFrame:CGRectMake(0,0,20,20)];
        BOOL failed=context==nil;
        [context release];
        printf("layer failed-init check=%s\n",failed?"PASS":"FAIL");
        return !failed;
    }
}
