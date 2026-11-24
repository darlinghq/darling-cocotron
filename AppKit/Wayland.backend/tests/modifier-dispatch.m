/*
 Copyright (C) 2026 Darling Developers

 Licensed under the MIT license, the same as the rest of this project.
*/
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>

// Actual-backend dispatch fixture, run only with an isolated native compositor.
// Drives the keyboard protocol callbacks of CoreGraphics' keyboard directly and reads the key events it
// posts to the event stream; no replacement modifier implementation or mocked XKB state is used.
union Argument { int32_t i; uint32_t u; const char *s; void *o; void *a; int h; };
struct Array { size_t size, alloc; void *data; };
@interface NSObject (ModifierFixture)
+ (id)currentDisplay;
- (id)platformWindow;
- (void *)surface;
- (void)keyboardEvent:(uint32_t)opcode arguments:(union Argument *)args;
- (void)processPendingEvents;
- (void)windowUnmapped:(id)window;
- (void)seatCapabilities:(uint32_t)capabilities;
@end
// The keyboard decoder is CoreGraphics': the fixture drives its protocol events directly and reads what it
// posts from the process' event stream (a program with no event tap gets the events there at once).
extern void _CGSEventStreamSetReadySource(CFRunLoopSourceRef source, CFRunLoopRef runLoop);
extern CGEventRef _CGSEventStreamCopyNextEvent(void);
@interface FixtureKeyEvent : NSObject {
@public
    NSEventType type;
    NSUInteger flags;
    unsigned short code;
    NSString *characters;
}
- (NSEventType)type;
- (NSUInteger)modifierFlags;
- (unsigned short)keyCode;
- (NSString *)characters;
@end
@implementation FixtureKeyEvent
- (NSEventType)type { return type; }
- (NSUInteger)modifierFlags { return flags; }
- (unsigned short)keyCode { return code; }
- (NSString *)characters { return characters; }
@end
static void ignoreSource(void *info) {}
static void startReading(void) {
    CFRunLoopSourceContext context = {0};
    context.perform = ignoreSource;
    CFRunLoopSourceRef source = CFRunLoopSourceCreate(NULL, 0, &context);
    CFRunLoopAddSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes);
    _CGSEventStreamSetReadySource(source, CFRunLoopGetMain());
}
// Moves what the decoder has posted into `events`
static void drain(NSMutableArray *events) {
    CGEventRef cg;
    while ((cg = _CGSEventStreamCopyNextEvent()) != NULL) {
        CGEventType t = CGEventGetType(cg);
        if (t == kCGEventKeyDown || t == kCGEventKeyUp || t == kCGEventFlagsChanged) {
            FixtureKeyEvent *e = [FixtureKeyEvent new];
            e->type = (NSEventType)t;
            e->flags = (NSUInteger)CGEventGetFlags(cg);
            e->code = (unsigned short)CGEventGetIntegerValueField(cg, kCGKeyboardEventKeycode);
            UniChar chars[8]; UniCharCount n = 0;
            if (t != kCGEventFlagsChanged) CGEventKeyboardGetUnicodeString(cg, 8, &n, chars);
            e->characters = [[NSString stringWithCharacters:chars length:n] retain];
            [events addObject:e];
            [e release];
        }
        CFRelease(cg);
    }
}
static id keyboardDecoder(void) {
    id connection = _CGSConnectionForID(CGSMainConnectionID());
    Ivar ivar = class_getInstanceVariable(object_getClass(connection), "_keyboardDecoder");
    return ivar ? object_getIvar(connection, ivar) : nil;
}
// The pointer decoder is CoreGraphics' too
static id pointerDecoder(void) {
    id connection = _CGSConnectionForID(CGSMainConnectionID());
    Ivar ivar = class_getInstanceVariable(object_getClass(connection), "_pointerDecoder");
    return ivar ? object_getIvar(connection, ivar) : nil;
}
static NSMutableArray *events;
static id display, decoder, connection;
static NSWindow *window;
static int failures,checks;
static void modifierCheck(BOOL ok,const char *what) {
    ++checks;if(!ok)++failures;printf("%s %s\n",ok?"PASS":"FAIL",what);fflush(stdout);
}
static void key(uint32_t code,BOOL down) {
    union Argument a[4]={{.u=1},{.u=0},{.u=code},{.u=down}};
    [decoder keyboardEvent:3 arguments:a];
}
static void mods(uint32_t depressed,uint32_t locked,uint32_t group) {
    union Argument a[5]={{.u=1},{.u=depressed},{.u=0},{.u=locked},{.u=group}};
    [decoder keyboardEvent:4 arguments:a];
}
static void enter(uint32_t *keys,size_t n) {
    struct Array array={n*sizeof(uint32_t),n*sizeof(uint32_t),keys};
    union Argument a[3]={{.u=1},{.o=[[window platformWindow] surface]},{.a=&array}};
    [decoder keyboardEvent:1 arguments:a];
}
static void leave(void) {
    union Argument a[2]={{.u=1},{.o=[[window platformWindow] surface]}};
    [decoder keyboardEvent:2 arguments:a];
}
static BOOL eventAt(NSUInteger index,NSEventType type,unsigned code,NSUInteger flags) {
    drain(events);
    if(index >= (drain(events),[events count]))return NO;
    NSEvent *e=[events objectAtIndex:index];
    return [e type]==type && [e modifierFlags]==flags && (type!=NSFlagsChanged || [e keyCode]==code);
}
static void idle(void) {
    for(int i=0;i<20;i++){[display processPendingEvents];usleep(10000);}
}
@interface ModifierApplication : NSApplication
@end
@implementation ModifierApplication
- (void)test:(id)sender {
    display=[NSClassFromString(@"NSDisplay") currentDisplay];
    connection=_CGSConnectionForID(CGSMainConnectionID());
    decoder=keyboardDecoder();
    modifierCheck(decoder!=nil,"the keyboard decoder exists");
    events=[NSMutableArray new];startReading();
    enter(NULL,0);mods(0,0,0);drain(events),[events removeAllObjects];
    key(42,YES);
    modifierCheck((drain(events),[events count])==0,"key waits for following authoritative mask");
    mods(1,0,0);
    modifierCheck(eventAt(0,NSFlagsChanged,56,NSShiftKeyMask|2),"following mask applied to left press");
    drain(events),[events removeAllObjects];key(54,YES);idle();
    modifierCheck((drain(events),[events count])==1 && eventAt(0,NSFlagsChanged,60,NSShiftKeyMask|6),"idle unchanged-mask right press delivered once");
    drain(events),[events removeAllObjects];key(42,NO);key(30,YES);
    modifierCheck(eventAt(0,NSFlagsChanged,56,NSShiftKeyMask|4) && eventAt(1,NSKeyDown,0,NSShiftKeyMask|4),"pending release precedes ordinary key");
    key(30,NO);key(42,YES);drain(events),[events removeAllObjects];
    // Pointer leave produces no mouse event itself but must flush pending key.
    union Argument p[2]={{.u=1},{.o=NULL}};[pointerDecoder() pointerEvent:1 arguments:p];
    modifierCheck((drain(events),[events count])==1 && eventAt(0,NSFlagsChanged,56,NSShiftKeyMask|6),"pointer dispatch flushes pending modifier first");
    drain(events),[events removeAllObjects];key(42,NO);leave();idle();
    modifierCheck((drain(events),[events count])==0,"leave cancels pending callback without stale event");
    uint32_t held[]={42,54};enter(held,2);mods(1,0,0);
    modifierCheck((drain(events),[events count])==1 && eventAt(0,NSFlagsChanged,65535,NSShiftKeyMask|6),"focus seeds both held sides without presses");
    drain(events),[events removeAllObjects];key(42,NO);idle();key(54,NO);mods(0,0,0);
    modifierCheck((drain(events),[events count])==2 && eventAt(0,NSFlagsChanged,56,NSShiftKeyMask|4) && eventAt(1,NSFlagsChanged,60,0),"focus-seeded releases retain identities");
    drain(events),[events removeAllObjects];key(58,YES);mods(0,2,0);key(58,NO);idle();
    modifierCheck((drain(events),[events count])==2 && eventAt(0,NSFlagsChanged,57,NSAlphaShiftKeyMask) && eventAt(1,NSFlagsChanged,57,NSAlphaShiftKeyMask),"Caps release preserves compositor lock");
    drain(events),[events removeAllObjects];key(58,YES);mods(0,0,0);key(58,NO);idle();
    modifierCheck((drain(events),[events count])==2 && eventAt(0,NSFlagsChanged,57,0) && eventAt(1,NSFlagsChanged,57,0),"Caps unlock remains compositor-owned");
    drain(events),[events removeAllObjects];key(100,YES);mods(8,0,0);mods(8,0,1);key(100,NO);mods(0,0,1);
    modifierCheck(eventAt((drain(events),[events count])-1,NSFlagsChanged,61,0),"group change retains right Option release identity");
    mods(0,0,0);drain(events),[events removeAllObjects];key(42,YES);
    const char *path=getenv("KEYMAP_FILE");int fd=path?open(path,O_RDONLY):-1;struct stat st;
    BOOL haveMap=fd>=0 && fstat(fd,&st)==0;
    modifierCheck(haveMap,"replacement keymap fixture available");
    if(haveMap){
        union Argument map[3]={{.u=1},{.h=fd},{.u=(uint32_t)st.st_size}};
        [decoder keyboardEvent:0 arguments:map];idle();
        modifierCheck((drain(events),[events count])==0,"keymap replacement cancels pending callback");
        mods(1,0,0);drain(events),[events removeAllObjects];key(42,NO);mods(0,0,0);
        modifierCheck(eventAt(0,NSFlagsChanged,56,0),"held identity survives keymap replacement");
    } else if(fd>=0) close(fd);
    drain(events),[events removeAllObjects];key(42,YES);[display windowUnmapped:[window platformWindow]];idle();
    modifierCheck((drain(events),[events count])==0,"window unmap cancels pending callback");
    enter(NULL,0);mods(0,0,0);drain(events),[events removeAllObjects];key(42,YES);[connection seatCapabilities:0];idle();
    modifierCheck((drain(events),[events count])==0,"device loss cancels pending callback");
    leave();[events release];
    printf("RESULT checks=%d failures=%d\n",checks,failures);fflush(stdout);exit(failures?1:0);
}
@end
int main(void) {
    [NSAutoreleasePool new];[ModifierApplication sharedApplication];
    window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,500,400)
            styleMask:NSTitledWindowMask backing:NSBackingStoreBuffered defer:NO];
    [window setTitle:@"Wayland input test"];[window makeKeyAndOrderFront:nil];
    [NSTimer scheduledTimerWithTimeInterval:4 target:NSApp selector:@selector(test:) userInfo:nil repeats:NO];
    puts("READY");fflush(stdout);[NSApp run];return 2;
}
