// CFLAGS: -framework Foundation -framework CoreGraphics -framework CoreFoundation
/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// The drag and drop SPI of CoreGraphics (CGSDrag.h) without AppKit (the program links only CoreGraphics and
// Foundation): a process with two windows of its own drags from one to the other through XDND, and the second
// window's destination hears the drag (entered, updated, exited or perform, with the point, the operations and the
// types), reads the data the source gives lazily through the selection layer, and the source gets the operation
// the destination performed. Driven by coregraphics-x11-drag-no-appkit.sh (XTest): the program prints "READY",
// then for each of three drags "ARMED <n>" (a drag from the source window starts when the left button goes down
// in it) and "DONE <n>" when the drag is over:
//   1. dropped on the destination window: copy, move and link allowed, the destination takes copy
//   2. the pointer passes over the destination window and is released outside it: no drop, an exit
//   3. a drag that allows nothing to other applications and a move within this one: local, dropped on the destination
// and "ALL PASSED" or "FAILED n". With the argument "unavailable" (a window system whose backend has no drag and
// drop of its own) it checks that the SPI says so and refuses to start a drag.
// Usage: coregraphics-x11-drag-no-appkit [unavailable]
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

typedef uint32_t CGSConnectionID;
typedef uint32_t CGSWindowID;
typedef CFTypeRef RegionRef;
extern CGSConnectionID CGSMainConnectionID(void);
extern CGError CGSNewRegionWithRect(const CGRect *rect, RegionRef *newRegion);
extern CGError CGSNewWindow(CGSConnectionID cid, CFIndex flags, float x, float y, const RegionRef region, CGSWindowID *windowID);
extern OSStatus CGSOrderWindow(CGSConnectionID cid, CGSWindowID wid, int place, CGSWindowID relativeTo);

// The layout of CGSDragDescription (CGSDrag.h): the header is private, so the program declares what it uses.
typedef struct {
    uint32_t window;
    NSArray *types;
    id source;
    NSUInteger operations;
    NSUInteger localOperations;
    CGImageRef image;
    CGPoint imageOffset;
} Description;

enum { Copy = 1, Link = 2, Move = 16 };

// The sessions' methods (CGSDrag.h), typed for the compiler.
@protocol DropSession <NSObject>
@property (readonly) NSArray *types;
@property (readonly) NSUInteger sourceOperations;
@property (readonly) BOOL fromThisProcess;
- (NSData *) dataForType: (NSString *) type;
@end

@protocol DragSession <NSObject>
@property (readonly) BOOL finished;
- (BOOL) update;
- (NSUInteger) concludePumping: (void (^)(NSDate *until)) pump;
- (void) close;
@end

static BOOL (*dragAvailable)(void);
static id (*dragBegin)(const Description *);
static void (*setDestination)(uint32_t, id);

static int failures;
static void expect(BOOL ok, NSString *what) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", [what UTF8String]);
    if (!ok)
        failures++;
}

// What the destination heard, in order.
static NSMutableArray *heard;
static NSData *dataRead, *missingRead;
static NSArray *typesSeen;
static NSUInteger sourceOperationsSeen;
static BOOL fromThisProcessSeen;
static NSUInteger performedWith;
static NSUInteger destinationReturns;

@interface Destination : NSObject
@end

@implementation Destination
- (NSUInteger) dropSession: (id<DropSession>) session enteredAtPoint: (CGPoint) point {
    [heard addObject: [NSString stringWithFormat: @"entered %@", point.x >= 0 && point.y >= 0 ? @"inside" : @"outside"]];
    typesSeen = [[session types] copy];
    sourceOperationsSeen = [session sourceOperations];
    fromThisProcessSeen = [session fromThisProcess];
    return destinationReturns;
}
- (NSUInteger) dropSession: (id<DropSession>) session updatedAtPoint: (CGPoint) point {
    [heard addObject: @"updated"];
    return destinationReturns;
}
- (void) dropSessionExited: (id<DropSession>) session {
    [heard addObject: @"exited"];
}
- (NSUInteger) dropSession: (id<DropSession>) session performWithOperation: (NSUInteger) operation {
    performedWith = operation;
    [heard addObject: [NSString stringWithFormat: @"perform %lu", (unsigned long) operation]];
    dataRead = [[session dataForType: @"public.utf8-plain-text"] retain];
    missingRead = [[session dataForType: @"public.rtf"] retain];
    return operation;
}
@end

static NSUInteger sourceNarrowCalls, sourceDataCalls, sourceTextCalls;

@interface Source : NSObject
@end

@implementation Source
- (NSData *) selectionDataForType: (NSString *) type {
    sourceDataCalls++;
    if ([type isEqual: @"public.utf8-plain-text"])
        sourceTextCalls++;
    return [type isEqual: @"public.utf8-plain-text"] ? [@"drag payload" dataUsingEncoding: NSUTF8StringEncoding] : nil;
}
- (void) selectionLost {
}
- (NSUInteger) dragOperationsNarrowing: (NSUInteger) offered {
    sourceNarrowCalls++;
    return offered;
}
@end

static BOOL buttonDown, buttonUp;
static uint32_t pressedIn;

static CGEventRef tapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *info) {
    if (type == kCGEventLeftMouseDown) {
        buttonDown = YES;
        pressedIn = (uint32_t) CGEventGetIntegerValueField(event, kCGMouseEventWindowUnderMousePointer);
    } else if (type == kCGEventLeftMouseUp) {
        buttonUp = YES;
    }
    return event;
}

static void spin(NSTimeInterval seconds) {
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, seconds, false);
}

int main(int argc, char **argv) {
    @autoreleasepool {
        BOOL expectUnavailable = argc > 1 && strcmp(argv[1], "unavailable") == 0;
        dragAvailable = dlsym(RTLD_DEFAULT, "_CGSDragAvailable");
        dragBegin = dlsym(RTLD_DEFAULT, "_CGSDragBegin");
        setDestination = dlsym(RTLD_DEFAULT, "_CGSDragSetDestination");
        if (dragAvailable == NULL || dragBegin == NULL || setDestination == NULL) {
            printf("FAIL CoreGraphics has no drag and drop SPI\n");
            return 1;
        }

        CGSConnectionID cid = CGSMainConnectionID();
        if (cid == 0) {
            printf("FAIL no connection to the window system\n");
            return 1;
        }
        if (expectUnavailable) {
            Description description = { .window = 1, .types = @[ @"public.utf8-plain-text" ], .source = [Source new],
                                        .operations = Copy, .localOperations = Copy };
            expect(!dragAvailable(), @"the backend has no drag and drop of its own");
            expect(dragBegin(&description) == nil, @"a drag does not start");
            setDestination(1, [Destination new]);
            expect(YES, @"setting a destination of a window is harmless");
            printf(failures == 0 ? "ALL PASSED\n" : "FAILED %d\n", failures);
            return failures != 0;
        }
        expect(dragAvailable(), @"the backend has drag and drop");

        CGRect sourceFrame = CGRectMake(100, 100, 300, 200), destinationFrame = CGRectMake(500, 100, 300, 200);
        RegionRef region = NULL;
        CGSWindowID sourceWindow = 0, destinationWindow = 0;
        if (CGSNewRegionWithRect(&sourceFrame, &region) != kCGErrorSuccess ||
            CGSNewWindow(cid, 0, 0, 0, region, &sourceWindow) != kCGErrorSuccess ||
            CGSNewRegionWithRect(&destinationFrame, &region) != kCGErrorSuccess ||
            CGSNewWindow(cid, 0, 0, 0, region, &destinationWindow) != kCGErrorSuccess ||
            CGSOrderWindow(cid, sourceWindow, 1, 0) != kCGErrorSuccess ||
            CGSOrderWindow(cid, destinationWindow, 1, 0) != kCGErrorSuccess) {
            printf("FAIL no windows\n");
            return 1;
        }
        heard = [NSMutableArray array];
        Destination *destination = [Destination new];
        setDestination(destinationWindow, destination);

        CFMachPortRef tap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionListenOnly,
                                             CGEventMaskBit(kCGEventLeftMouseDown) | CGEventMaskBit(kCGEventLeftMouseUp),
                                             tapCallback, NULL);
        if (tap == NULL) {
            printf("FAIL no event tap\n");
            return 1;
        }
        CFRunLoopSourceRef source = CFMachPortCreateRunLoopSource(NULL, tap, 0);
        CFRunLoopAddSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes);
        CGEventTapEnable(tap, true);

        // Nothing to drag: no operation at all, or no type.
        Description nothing = { .window = sourceWindow, .types = @[ @"public.utf8-plain-text" ], .source = [Source new] };
        expect(dragBegin(&nothing) == nil, @"a drag that allows no operation does not start");
        nothing.operations = Copy;
        nothing.types = @[];
        expect(dragBegin(&nothing) == nil, @"a drag of no type does not start");

        printf("READY\n");
        fflush(stdout);

        for (int n = 1; n <= 3; n++) {
            [heard removeAllObjects];
            dataRead = missingRead = nil;
            typesSeen = nil;
            performedWith = 0;
            sourceNarrowCalls = sourceDataCalls = sourceTextCalls = 0;
            buttonDown = buttonUp = NO;
            destinationReturns = n == 3 ? Move : (Move | Copy);
            printf("ARMED %d\n", n);
            fflush(stdout);
            NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow: 40];
            while (!buttonDown && [deadline timeIntervalSinceNow] > 0)
                spin(0.05);
            if (!buttonDown || pressedIn != sourceWindow) {
                expect(NO, [NSString stringWithFormat: @"drag %d: the button went down in the source window", n]);
                break;
            }

            Description description = {
                .window = sourceWindow,
                .types = @[ @"public.utf8-plain-text", @"public.html" ],
                .source = [Source new],
                .operations = n == 3 ? 0 : (Copy | Move | Link),
                .localOperations = n == 3 ? Move : Copy,
            };
            id<DragSession> session = dragBegin(&description);
            if (session == nil) {
                expect(NO, [NSString stringWithFormat: @"drag %d starts", n]);
                break;
            }
            BOOL moved = NO;
            deadline = [NSDate dateWithTimeIntervalSinceNow: 40];
            while (!buttonUp && ![session finished] && [deadline timeIntervalSinceNow] > 0) {
                spin(0.01);
                if ([session update])
                    moved = YES;
            }
            NSUInteger result = [session concludePumping: ^(NSDate *until) {
                spin(MIN(0.02, MAX(0.001, [until timeIntervalSinceNow])));
            }];
            [session close];
            [session release];
            spin(0.2);

            NSString *log = [heard componentsJoinedByString: @","];
            if (n == 1) {
                expect(moved, @"drag 1: the session saw the pointer move");
                expect([log hasPrefix: @"entered inside"] && [log hasSuffix: @"perform 1"], [NSString stringWithFormat: @"drag 1: the destination heard entered, updates and perform with copy (%@)", log]);
                expect([typesSeen containsObject: @"public.utf8-plain-text"] && [typesSeen containsObject: @"public.html"], @"drag 1: the destination sees the types of the source");
                expect(sourceOperationsSeen == (Copy | Move | Link), @"drag 1: the destination sees the operations of the source");
                expect(fromThisProcessSeen, @"drag 1: a drag of this process is marked as such");
                expect([dataRead isEqual: [@"drag payload" dataUsingEncoding: NSUTF8StringEncoding]], @"drag 1: the destination reads the data from the source");
                expect(missingRead == nil, @"drag 1: a type the source has no data for is refused");
                expect(sourceTextCalls == 1 && sourceDataCalls >= 2, [NSString stringWithFormat: @"drag 1: the source's data is asked for only when read (%lu requests for the text, %lu in all)", (unsigned long) sourceTextCalls, (unsigned long) sourceDataCalls]);
                expect(sourceNarrowCalls > 0, @"drag 1: the source narrows the operations it announces");
                expect(result == Copy, @"drag 1: the source gets the performed operation");
            } else if (n == 2) {
                expect([log hasPrefix: @"entered inside"] && [log hasSuffix: @"exited"] && ![log containsString: @"perform"], [NSString stringWithFormat: @"drag 2: the destination heard entered and exited, no perform (%@)", log]);
                expect(result == 0, @"drag 2: nothing was performed");
                expect(sourceDataCalls == 0, @"drag 2: the source's data was never asked for");
            } else {
                expect([log hasPrefix: @"entered inside"] && [log hasSuffix: @"perform 16"], [NSString stringWithFormat: @"drag 3: the destination heard entered and perform with move (%@)", log]);
                expect(fromThisProcessSeen, @"drag 3: a drag of this process is marked as such");
                expect(sourceOperationsSeen == Move, @"drag 3: a local drag offers the local operations");
                expect(result == Move, @"drag 3: the source gets the performed operation");
            }
            printf("DONE %d\n", n);
            fflush(stdout);
        }
        setDestination(destinationWindow, nil);
        printf(failures == 0 ? "ALL PASSED\n" : "FAILED %d\n", failures);
        return failures != 0;
    }
}
