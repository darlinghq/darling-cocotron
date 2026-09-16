#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

// Exercise the real backend's readers and event handler, not a duplicate model.
union OutputArgument { int32_t i; uint32_t u; const char *s; void *o; };
@interface NSObject (OutputFixture)
+ (id)currentDisplay;
- (NSArray *)screens;
- (NSArray *)outputsWithModes;
- (NSArray *)modesForScreen:(int)index;
- (NSDictionary *)currentModeForScreen:(int)index;
- (int32_t)scaleForOutput:(void *)proxy;
- (void)outputEvent:(uint32_t)opcode output:(id)output arguments:(union OutputArgument *)args;
- (void)invalidateScreens;
- (void)logicalOutputEvent:(uint32_t)opcode output:(id)output arguments:(union OutputArgument *)args;
@end
static int failures,checks;
static void outputCheck(BOOL ok,const char *name) {
    checks++;if(!ok)failures++;printf("%s %s\n",ok?"PASS":"FAIL",name);fflush(stdout);
}
static void *slot(id obj,const char *name) {
    Ivar iv=class_getInstanceVariable(object_getClass(obj),name);
    if(!iv){fprintf(stderr,"missing ivar %s\n",name);exit(2);}
    return (char *)obj+ivar_getOffset(iv);
}
static void event(id display,id output,uint32_t opcode,int a,int b,int c,int d) {
    union OutputArgument args[8]={{.i=a},{.i=b},{.i=c},{.i=d}};
    if(opcode==0)args[7].i=a;
    [display outputEvent:opcode output:output arguments:args];
}
static BOOL frame(id display,double w,double h,double scale) {
    NSArray *screens=[display screens];if([screens count]!=1)return NO;
    NSScreen *s=[screens objectAtIndex:0];NSRect r=[s frame];
    return r.size.width==w && r.size.height==h && [s backingScaleFactor]==scale;
}
static void logical(id d,id o,uint32_t op,int a,int b) {
    union OutputArgument args[2]={{.i=a},{.i=b}};
    [d logicalOutputEvent:op output:o arguments:args];
}
static id makeOutput(int version,int logicalVersion,int w,int h,id d) {
    id o=[NSClassFromString(@"WaylandOutput") new];
    *(uint32_t *)slot(o,"_version")=version;
    *(uint32_t *)slot(o,"_logicalVersion")=logicalVersion;
    *(id *)slot(o,"_pendingModes")=[NSMutableArray new];*(id *)slot(o,"_modes")=[NSArray new];
    ((int32_t *)slot(o,"_current"))[3]=1;((int32_t *)slot(o,"_pending"))[3]=1;
    event(d,o,1,1,w,h,60000);event(d,o,2,0,0,0,0);return o;
}
static BOOL rectAt(id d,int i,CGFloat x,CGFloat y,CGFloat w,CGFloat h) {
    NSArray *screens=[d screens];if(i>=[screens count])return NO;
    return NSEqualRects([[screens objectAtIndex:i] frame],NSMakeRect(x,y,w,h));
}
static void synthetic(void) {
    id d=class_createInstance(NSClassFromString(@"WaylandDisplay"),0);
    NSMutableArray *outputs=[NSMutableArray new];*(id *)slot(d,"_outputs")=outputs;
    CFMutableArrayRef windows=CFArrayCreateMutable(NULL,0,NULL);*(CFMutableArrayRef *)slot(d,"_windows")=windows;
    id a=makeOutput(2,3,1200,800,d),b=makeOutput(2,3,900,600,d);
    [outputs addObject:a];[outputs addObject:b];[d invalidateScreens];
    outputCheck(rectAt(d,0,0,0,1200,800)&&rectAt(d,1,1200,0,900,600),"no logical metadata uses horizontal core fallback");
    logical(d,a,0,300,400);logical(d,a,1,800,500);logical(d,a,2,0,0);
    [d invalidateScreens];outputCheck(rectAt(d,0,0,0,1200,800),"v3 ignores deprecated logical done");
    event(d,a,2,0,0,0,0);
    outputCheck(rectAt(d,0,0,0,1200,800),"partial output set stays entirely in fallback");
    logical(d,b,0,-200,-100);logical(d,b,1,450,300);event(d,b,2,0,0,0,0);
    outputCheck(rectAt(d,0,0,0,800,500)&&rectAt(d,1,-500,700,450,300),"nonzero anchor and negative position convert to Cocoa topology");
    outputCheck([d scaleForOutput:NULL]==1,"logical size does not change integer buffer scale");
    logical(d,b,0,500,600);[d invalidateScreens];
    outputCheck(rectAt(d,1,-500,700,450,300),"v3 position pending until core done even after cache rebuild");
    event(d,b,2,0,0,0,0);
    outputCheck(rectAt(d,1,200,0,450,300),"position-only update preserves logical size and overlap");
    logical(d,b,1,300,700);event(d,b,2,0,0,0,0);
    outputCheck(rectAt(d,1,200,-400,300,700),"logical size is already transformed and scaled");
    logical(d,b,1,0,-1);event(d,b,2,0,0,0,0);
    outputCheck(rectAt(d,1,200,-400,300,700),"invalid logical size preserves last usable geometry");
    *(uint32_t *)slot(b,"_logicalVersion")=2;
    event(d,b,1,1,1000,700,60000);event(d,b,3,2,0,0,0);
    logical(d,b,0,50,100);logical(d,b,2,0,0);
    outputCheck(rectAt(d,1,-250,100,300,700)&&[[[d currentModeForScreen:1] objectForKey:@"Width"] intValue]==900,
                "v2 logical done does not publish pending core mode");
    outputCheck([[[d screens] objectAtIndex:0] backingScaleFactor]==1 && [[[d screens] objectAtIndex:1] backingScaleFactor]==1,"legacy logical done preserves both committed backing scales");
    event(d,b,2,0,0,0,0);
    outputCheck([[[d screens] objectAtIndex:0] backingScaleFactor]==1 && [[[d screens] objectAtIndex:1] backingScaleFactor]==2,"core done publishes second output backing scale independently");
    logical(d,b,0,200,100);event(d,b,2,0,0,0,0);[d invalidateScreens];
    outputCheck(rectAt(d,1,-250,100,300,700),"core done does not publish pending v2 logical state");
    logical(d,b,2,0,0);outputCheck(rectAt(d,1,-100,100,300,700),"v2 logical done publishes its independent batch");
    logical(d,a,0,INT32_MAX,INT32_MAX);event(d,a,2,0,0,0,0);
    logical(d,b,0,INT32_MIN,INT32_MIN);logical(d,b,2,0,0);
    outputCheck(rectAt(d,1,-4294967295.0,4294967095.0,300,700),"coordinate arithmetic avoids signed int overflow");
    [outputs removeObject:a];[d invalidateScreens];
    outputCheck(rectAt(d,0,0,0,300,700),"remaining first screen becomes coordinate anchor");
    [outputs removeAllObjects];[d invalidateScreens];[a release];[b release];[outputs release];CFRelease(windows);object_dispose(d);
}
int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];[NSClassFromString(@"NSDisplay") currentDisplay];
    synthetic();printf("RESULT checks=%d failures=%d\n",checks,failures);return failures?1:0;
} }
