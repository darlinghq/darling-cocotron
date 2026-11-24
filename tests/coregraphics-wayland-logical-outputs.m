/*
 Copyright (C) 2026 Darling Developers

 Licensed under the MIT license, the same as the rest of this project.
*/
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreGraphics/CGSScreen.h>
#import <CoreGraphics/CGSConnection.h>
#import <objc/runtime.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

// The compositor's logical output layout (xdg-output) in CoreGraphics' Wayland connection: how the events become
// the displays' bounds in CoreGraphics' global space (origin at the main display's top-left corner, y down) and
// their backing scale. It exercises the real connection's readers and event handlers: a connection object without
// a compositor is made and fed the events. Run with the Wayland backend selected (DARLING_APPKIT_BACKEND=wayland).
// (The check that a logical size leaves the integer buffer scale of a window's output alone belonged to AppKit's
// own output list, which keeps only what windows need; it is not part of the displays.)
extern CGSConnectionID CGSMainConnectionID(void);
union OutputArgument { int32_t i; uint32_t u; const char *s; void *o; };
@interface NSObject (OutputFixture)
- (NSArray *)createScreens;
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
static NSArray *screensOf(id connection) {
    return [[connection createScreens] autorelease];
}
static void logical(id d,id o,uint32_t op,int a,int b) {
    union OutputArgument args[2]={{.i=a},{.i=b}};
    [d logicalOutputEvent:op output:o arguments:args];
}
static id makeOutput(int version,int logicalVersion,int w,int h,id d) {
    id o=[NSClassFromString(@"CGSWaylandOutput") new];
    *(uint32_t *)slot(o,"_version")=version;
    *(uint32_t *)slot(o,"_logicalVersion")=logicalVersion;
    *(id *)slot(o,"_pendingModes")=[NSMutableArray new];*(id *)slot(o,"_modes")=[NSArray new];
    ((int32_t *)slot(o,"_current"))[3]=1;((int32_t *)slot(o,"_pending"))[3]=1;
    event(d,o,1,1,w,h,60000);event(d,o,2,0,0,0,0);return o;
}
static BOOL rectAt(id d,int i,CGFloat x,CGFloat y,CGFloat w,CGFloat h) {
    // The expected rectangles are in Cocoa's global space (y up from the main display's bottom edge), as the
    // layout is described by NSScreen frames; the displays are in CoreGraphics' space.
    NSArray *screens=screensOf(d);if(i>=[screens count])return NO;
    CGFloat mainHeight=[[screens objectAtIndex:0] bounds].size.height;
    CGRect b=[[screens objectAtIndex:i] bounds];
    return b.origin.x==x && mainHeight-b.origin.y-b.size.height==y && b.size.width==w && b.size.height==h;
}
static void synthetic(void) {
    id d=class_createInstance(NSClassFromString(@"CGSConnectionWayland"),0);
    NSMutableArray *outputs=[NSMutableArray new];*(id *)slot(d,"_outputs")=outputs;
        id a=makeOutput(2,3,1200,800,d),b=makeOutput(2,3,900,600,d);
    [outputs addObject:a];[outputs addObject:b];[d invalidateScreens];
    outputCheck(rectAt(d,0,0,0,1200,800)&&rectAt(d,1,1200,0,900,600),"no logical metadata uses horizontal core fallback");
    logical(d,a,0,300,400);logical(d,a,1,800,500);logical(d,a,2,0,0);
    [d invalidateScreens];outputCheck(rectAt(d,0,0,0,1200,800),"v3 ignores deprecated logical done");
    event(d,a,2,0,0,0,0);
    outputCheck(rectAt(d,0,0,0,1200,800),"partial output set stays entirely in fallback");
    logical(d,b,0,-200,-100);logical(d,b,1,450,300);event(d,b,2,0,0,0,0);
    outputCheck(rectAt(d,0,0,0,800,500)&&rectAt(d,1,-500,700,450,300),"nonzero anchor and negative position convert to Cocoa topology");
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
    outputCheck(rectAt(d,1,-250,100,300,700)&&[[[[screensOf(d) objectAtIndex:1] currentModeDictionary] objectForKey:@"PixelWidth"] intValue]==900,
                "v2 logical done does not publish pending core mode");
    outputCheck([[screensOf(d) objectAtIndex:0] backingScale]==1 && [[screensOf(d) objectAtIndex:1] backingScale]==1,"legacy logical done preserves both committed backing scales");
    event(d,b,2,0,0,0,0);
    outputCheck([[screensOf(d) objectAtIndex:0] backingScale]==1 && [[screensOf(d) objectAtIndex:1] backingScale]==2,"core done publishes second output backing scale independently");
    logical(d,b,0,200,100);event(d,b,2,0,0,0,0);[d invalidateScreens];
    outputCheck(rectAt(d,1,-250,100,300,700),"core done does not publish pending v2 logical state");
    logical(d,b,2,0,0);outputCheck(rectAt(d,1,-100,100,300,700),"v2 logical done publishes its independent batch");
    logical(d,a,0,INT32_MAX,INT32_MAX);event(d,a,2,0,0,0,0);
    logical(d,b,0,INT32_MIN,INT32_MIN);logical(d,b,2,0,0);
    outputCheck(rectAt(d,1,-4294967295.0,4294967095.0,300,700),"coordinate arithmetic avoids signed int overflow");
    [outputs removeObject:a];[d invalidateScreens];
    outputCheck(rectAt(d,0,0,0,300,700),"remaining first screen becomes coordinate anchor");
    [outputs removeAllObjects];[d invalidateScreens];[a release];[b release];[outputs release];object_dispose(d);
}
int main(void) { @autoreleasepool {
    CGSMainConnectionID(); // makes CoreGraphics load its backends
    synthetic();printf("RESULT checks=%d failures=%d\n",checks,failures);return failures?1:0;
} }
