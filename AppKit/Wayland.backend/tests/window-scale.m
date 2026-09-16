#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <math.h>
#include <stdio.h>
static int creates,checks,failures;
@interface ScaleObject : NSObject { @public CGFloat scale; } @end
@implementation ScaleObject
- (CGFloat)backingScaleFactor{return scale;}
@end
@interface ScaleWindow : NSWindow { @public id fakeScreen; } @end
@implementation ScaleWindow
- (NSScreen *)screen{return fakeScreen;}
- (id)platformWindow{creates++;return nil;}
@end
static void checkScale(ScaleWindow *window,CGFloat expected){checks++;CGFloat actual=[window backingScaleFactor];if(actual!=expected||creates){failures++;printf("FAIL scale=%g expected=%g creates=%d\n",(double)actual,(double)expected,creates);}}
int main(void){@autoreleasepool{
    // Do not initialize/map a window; this isolates the real scale accessor.
    ScaleWindow *window=[ScaleWindow alloc];ScaleObject *screen=[ScaleObject new];screen->scale=1.75;window->fakeScreen=screen;
    Ivar iv=class_getInstanceVariable([NSWindow class],"_platformWindow");if(!iv)return 2;
    checkScale(window,1.75);
    NSObject *legacy=[NSObject new];object_setIvar(window,iv,legacy);checkScale(window,1.75);
    ScaleObject *native=[ScaleObject new];object_setIvar(window,iv,native);
    const CGFloat values[]={1,1.25,1.5,2,0,-1,NAN,INFINITY};
    for(unsigned i=0;i<sizeof(values)/sizeof(values[0]);i++){native->scale=values[i];checkScale(window,i<4?values[i]:1.75);}
    object_setIvar(window,iv,nil);window->fakeScreen=nil;checkScale(window,1);
    // Deliberately leave the uninitialized fixture alive until process exit.
    printf("RESULT checks=%d failures=%d\n",checks,failures);return failures?1:0;
}}
