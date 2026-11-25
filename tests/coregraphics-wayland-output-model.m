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

// The output model of CoreGraphics' Wayland connection: how wl_output events become displays, with their
// bounds (in CoreGraphics' global space), backing scale, modes and current mode. It exercises the real
// connection's readers and event handler, not a duplicate model: a connection object without a compositor
// is made and fed the events. Run with the Wayland backend selected (DARLING_APPKIT_BACKEND=wayland) so that
// CoreGraphics loads its Wayland backend.
extern CGSConnectionID CGSMainConnectionID(void);
union OutputArgument { int32_t i; uint32_t u; const char *s; void *o; };
@interface NSObject (OutputFixture)
- (NSArray *)createScreens;
- (NSArray *)_outputsWithModes;
- (void)outputEvent:(uint32_t)opcode output:(id)output arguments:(union OutputArgument *)args;
- (void)invalidateScreens;
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
static BOOL frame(id display,double w,double h,double scale) {
    NSArray *screens=screensOf(display);if([screens count]!=1)return NO;
    CGSScreen *s=[screens objectAtIndex:0];CGRect r=[s bounds];
    return r.size.width==w && r.size.height==h && [s backingScale]==scale;
}
static NSArray *modesOf(id display,int index) {return [[screensOf(display) objectAtIndex:index] modes];}
static NSDictionary *currentModeOf(id display,int index) {return [[screensOf(display) objectAtIndex:index] currentModeDictionary];}
static BOOL noScreens(id display) {return [screensOf(display) count]==0;}
static void synthetic(void) {
    // Allocate a disconnected backend instance. Only output-state readers/events
    // run here; its window list is empty and no native proxy is created/destroyed.
    id d=class_createInstance(NSClassFromString(@"CGSConnectionWayland"),0);
    id o=[NSClassFromString(@"CGSWaylandOutput") new];
    outputCheck(d && o,"backend runtime classes available");if(!d||!o)exit(2);
    NSMutableArray *outputs=[[NSMutableArray alloc] initWithObjects:o,nil];
    *(id *)slot(d,"_outputs")=outputs;
    *(uint32_t *)slot(o,"_version")=2;
    *(id *)slot(o,"_pendingModes")=[NSMutableArray new];
    *(id *)slot(o,"_modes")=[NSArray new];
    // Match registry binding defaults without dispatching an event that could
    // invalidate the cache under test (scale is the fourth int32 state field).
    ((int32_t *)slot(o,"_current"))[3]=1;
    ((int32_t *)slot(o,"_pending"))[3]=1;
    outputCheck(noScreens(d),"no display before any output has a current mode");
    event(d,o,1,1,801,603,59940);
    outputCheck([[d _outputsWithModes] count]==0 && noScreens(d),"initial pending mode invisible to every mode reader");
    event(d,o,2,0,0,0,0);
    outputCheck(frame(d,801,603,1) && [[d _outputsWithModes] count]==1,"done publishes initial mode");
    NSArray *oldModes=[modesOf(d,0) retain];
    event(d,o,1,1,1001,701,60000);event(d,o,3,2,0,0,0);event(d,o,0,1,0,0,0);
    outputCheck(frame(d,801,603,1),"screen cache unchanged inside v2 batch");
    [d invalidateScreens];
    outputCheck(frame(d,801,603,1),"rebuilt screen cache uses committed state inside v2 batch");
    outputCheck([modesOf(d,0) count]==1 && [oldModes count]==1 &&
                [[currentModeOf(d,0) objectForKey:@"PixelWidth"] intValue]==801 &&
                [[screensOf(d)[0] modes] count]==1 && [[d _outputsWithModes] count]==1,
                "all committed readers unchanged inside v2 batch");
    event(d,o,2,0,0,0,0);
    outputCheck(frame(d,350.5,500.5,2),"rotated odd dimensions use floating point division");
    outputCheck([modesOf(d,0) count]==2 && [oldModes count]==1 &&
                [[currentModeOf(d,0) objectForKey:@"PixelWidth"] intValue]==1001 &&
                [[currentModeOf(d,0) objectForKey:@"PixelHeight"] intValue]==701 &&
                [[currentModeOf(d,0) objectForKey:@"Width"] intValue]==501 &&
                [screensOf(d)[0] backingScale]==2,"done publishes raw mode and copied mode list atomically");
    for(int t=0;t<8;t++) {
        event(d,o,0,t,0,0,0);event(d,o,2,0,0,0,0);
        char label[80];snprintf(label,sizeof(label),"transform-only batch %d preserves mode/scale",t);
        outputCheck(frame(d,(t&1)?350.5:500.5,(t&1)?500.5:350.5,2),label);
    }
    event(d,o,3,1,0,0,0);event(d,o,2,0,0,0,0);
    outputCheck(frame(d,701,1001,1),"scale-only batch preserves rotated mode");
    event(d,o,1,1,-1,0,-1);event(d,o,0,99,0,0,0);event(d,o,2,0,0,0,0);
    outputCheck(frame(d,701,1001,1),"invalid mode and transform preserve last usable state");
    [oldModes release];
    // Reuse output for legacy v1; clear published mode through a new instance.
    [outputs removeAllObjects];[o release];o=[NSClassFromString(@"CGSWaylandOutput") new];[outputs addObject:o];
    *(uint32_t *)slot(o,"_version")=1;*(id *)slot(o,"_pendingModes")=[NSMutableArray new];*(id *)slot(o,"_modes")=[NSArray new];
    ((int32_t *)slot(o,"_current"))[3]=1;
    ((int32_t *)slot(o,"_pending"))[3]=1;
    [d invalidateScreens];outputCheck(noScreens(d),"no display cached before v1 mode");
    event(d,o,1,1,900,600,60000);
    outputCheck(frame(d,900,600,1),"v1 mode replaces the cached empty list without done");
    event(d,o,0,3,0,0,0);outputCheck(frame(d,600,900,1),"v1 geometry immediately updates dimensions");
    [outputs removeAllObjects];[d invalidateScreens];outputCheck(noScreens(d),"empty output model has no display");
    [o release];[d invalidateScreens];[outputs release];object_dispose(d);
}
int main(void) {
    @autoreleasepool {
        // Makes CoreGraphics load its backends.
        CGSMainConnectionID();
        synthetic();printf("RESULT checks=%d failures=%d\n",checks,failures);fflush(stdout);
        return failures?1:0;
    }
}
