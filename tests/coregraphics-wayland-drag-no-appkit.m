// CFLAGS: -framework Foundation -framework CoreGraphics -framework CoreFoundation
/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// The drag and drop SPI of CoreGraphics (CGSDrag.h) on Wayland without AppKit (the program links only CoreGraphics and
// Foundation): a process with two toplevel windows of its own drags from one to the other through the data device, and
// the second window's destination hears the drag (entered, updated, exited or perform, with the point, the operations and
// the types), reads the data the source gives through the data device, and the source gets the operation the
// destination performed. Driven by coregraphics-wayland-drag-no-appkit.sh (a virtual pointer on a headless sway): the
// program prints "READY", then for each of three drags "ARMED <n>" (a drag from the source window starts when the left
// button goes down in it) and "DONE <n>" when the drag is over:
//   1. dropped on the destination window: copy, move and link allowed (link cannot be said, so copy and move are what is
//      offered), the destination takes copy
//   2. released away from any window: the compositor cancels the drag, the destination hears an exit and no drop
//   3. a drag that allows nothing to other applications and a move within this one: local, dropped on the destination
// and "ALL PASSED" or "FAILED n". Usage: coregraphics-wayland-drag-no-appkit
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreGraphics/CGSConnection.h>
#import <CoreGraphics/CGSWindow.h>
#import <CoreGraphics/CGSServerSPI.h>
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

// The layout of CGSDragDescription (CGSDrag.h): the header is private, so the program declares what it uses.
typedef struct {
    uint32_t window;
    NSArray *types;
    id source;
    NSUInteger operations;
    NSUInteger localOperations;
    CGImageRef image;
    CGPoint imageOffset;
    CGFloat imageScale;
} Description;

enum { Copy = 1, Link = 2, Move = 16 };

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

static NSMutableArray *heard;
static NSData *dataRead, *missingRead;
static NSArray *typesSeen;
static NSUInteger sourceOperationsSeen;
static BOOL fromThisProcessSeen;
static NSUInteger destinationReturns;

@interface Destination : NSObject
@end

@implementation Destination
- (NSUInteger) dropSession: (id<DropSession>) session enteredAtPoint: (CGPoint) point {
    [heard addObject: [NSString stringWithFormat: @"entered %@", point.x >= 0 && point.y >= 0 && point.x < 320 && point.y < 240 ? @"inside" : @"outside"]];
    typesSeen = [[session types] copy];
    sourceOperationsSeen = [session sourceOperations];
    fromThisProcessSeen = [session fromThisProcess];
    return destinationReturns;
}
- (NSUInteger) dropSession: (id<DropSession>) session updatedAtPoint: (CGPoint) point {
    return destinationReturns;
}
- (void) dropSessionExited: (id<DropSession>) session {
    [heard addObject: @"exited"];
}
- (NSUInteger) dropSession: (id<DropSession>) session performWithOperation: (NSUInteger) operation {
    [heard addObject: [NSString stringWithFormat: @"perform %lu", (unsigned long) operation]];
    dataRead = [[session dataForType: @"public.utf8-plain-text"] retain];
    missingRead = [[session dataForType: @"public.rtf"] retain];
    return operation;
}
@end

static NSUInteger sourceNarrowCalls, sourceTextCalls;

@interface Source : NSObject
@end

@implementation Source
- (NSData *) selectionDataForType: (NSString *) type {
    if (![type isEqual: @"public.utf8-plain-text"])
        return nil;
    sourceTextCalls++;
    return [@"drag payload" dataUsingEncoding: NSUTF8StringEncoding];
}
- (void) selectionLost {
}
- (NSUInteger) dragOperationsNarrowing: (NSUInteger) offered {
    sourceNarrowCalls++;
    return offered;
}
@end

static BOOL buttonDown;
static uint32_t pressedIn;

static CGEventRef tapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *info) {
    if (type == kCGEventLeftMouseDown) {
        buttonDown = YES;
        pressedIn = (uint32_t) CGEventGetIntegerValueField(event, kCGMouseEventWindowUnderMousePointer);
    }
    return event;
}

static void spin(NSTimeInterval seconds) {
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, seconds, false);
}

static CGSWindow *makeWindow(NSString *title, CGRect frame) {
    CGSToplevelAttributes attributes = {.frame = frame, .unmanaged = false, .translucent = false};
    CGSWindow *window = _CGSNewToplevelWindow(&attributes);
    [window setProperty: CFSTR("WindowTitle") value: title];
    CGSToplevelHints hints = {.kind = kCGSToplevelKindNormal, .acceptsKeyboardInput = true, .takesFocusWhenShown = true};
    [window setToplevelHints: &hints];
    [window orderWindow: kCGSOrderIn relativeTo: nil];
    spin(1.0);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, frame.size.width, frame.size.height, 8, 0, space,
                                                 kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    CGColorSpaceRelease(space);
    CGContextSetRGBFillColor(context, 0.2, 0.5, 0.8, 1);
    CGContextFillRect(context, CGRectMake(0, 0, frame.size.width, frame.size.height));
    CGImageRef image = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    [window drawImage: image atPoint: CGPointZero];
    CGImageRelease(image);
    spin(0.5);
    return window;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        dragAvailable = dlsym(RTLD_DEFAULT, "_CGSDragAvailable");
        dragBegin = dlsym(RTLD_DEFAULT, "_CGSDragBegin");
        setDestination = dlsym(RTLD_DEFAULT, "_CGSDragSetDestination");
        if (dragAvailable == NULL || dragBegin == NULL || setDestination == NULL) {
            printf("FAIL CoreGraphics has no drag and drop SPI\n");
            return 1;
        }
        if (CGSMainConnectionID() == 0) {
            printf("FAIL no connection to the window system\n");
            return 1;
        }
        expect(dragAvailable(), @"the backend has drag and drop");

        CGSWindow *sourceWindow = makeWindow(@"cg-wl-drag-source", CGRectMake(100, 100, 320, 240));
        CGSWindow *destinationWindow = makeWindow(@"cg-wl-drag-destination", CGRectMake(500, 100, 320, 240));
        if (sourceWindow == nil || destinationWindow == nil) {
            printf("FAIL no windows\n");
            return 1;
        }
        heard = [NSMutableArray array];
        Destination *destination = [Destination new];
        setDestination([destinationWindow windowId], destination);

        CFMachPortRef tap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionListenOnly,
                                             CGEventMaskBit(kCGEventLeftMouseDown), tapCallback, NULL);
        if (tap == NULL) {
            printf("FAIL no event tap\n");
            return 1;
        }
        CFRunLoopSourceRef source = CFMachPortCreateRunLoopSource(NULL, tap, 0);
        CFRunLoopAddSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes);
        CGEventTapEnable(tap, true);

        // Nothing to drag: no operation at all, or no type.
        Description nothing = { .window = [sourceWindow windowId], .types = @[ @"public.utf8-plain-text" ], .source = [Source new] };
        expect(dragBegin(&nothing) == nil, @"a drag that allows no operation does not start");
        nothing.operations = Copy;
        nothing.types = @[];
        expect(dragBegin(&nothing) == nil, @"a drag of no type does not start");
        // No button is down: the compositor takes a drag only for a press.
        nothing.types = @[ @"public.utf8-plain-text" ];
        expect(dragBegin(&nothing) == nil, @"a drag without a button press does not start");

        printf("READY\n");
        fflush(stdout);

        for (int n = 1; n <= 3; n++) {
            [heard removeAllObjects];
            dataRead = missingRead = nil;
            typesSeen = nil;
            sourceNarrowCalls = sourceTextCalls = 0;
            buttonDown = NO;
            destinationReturns = n == 3 ? Move : (Move | Copy);
            printf("ARMED %d\n", n);
            fflush(stdout);
            NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow: 40];
            while (!buttonDown && [deadline timeIntervalSinceNow] > 0)
                spin(0.05);
            if (!buttonDown || pressedIn != [sourceWindow windowId]) {
                expect(NO, [NSString stringWithFormat: @"drag %d: the button went down in the source window", n]);
                break;
            }

            Description description = {
                .window = [sourceWindow windowId],
                .types = @[ @"public.utf8-plain-text", @"public.html" ],
                .source = [Source new],
                .operations = n == 3 ? 0 : (Copy | Move | Link),
                .localOperations = n == 3 ? Move : (Copy | Move),
            };
            id<DragSession> session = dragBegin(&description);
            if (session == nil) {
                expect(NO, [NSString stringWithFormat: @"drag %d starts", n]);
                break;
            }
            deadline = [NSDate dateWithTimeIntervalSinceNow: 40];
            while (![session finished] && [deadline timeIntervalSinceNow] > 0) {
                spin(0.01);
                [session update];
            }
            NSUInteger result = [session concludePumping: ^(NSDate *until) {
                spin(MIN(0.02, MAX(0.001, [until timeIntervalSinceNow])));
            }];
            [session close];
            [session release];
            spin(0.2);

            NSString *log = [heard componentsJoinedByString: @","];
            if (n == 1) {
                expect([log hasPrefix: @"entered inside"] && [log hasSuffix: @"perform 1"], [NSString stringWithFormat: @"drag 1: the destination heard entered and perform with copy (%@)", log]);
                expect([typesSeen containsObject: @"public.utf8-plain-text"], @"drag 1: the destination sees the type of the source");
                expect(sourceOperationsSeen == (Copy | Move), [NSString stringWithFormat: @"drag 1: the destination sees the operations the data device can say (%lu)", (unsigned long) sourceOperationsSeen]);
                expect(fromThisProcessSeen, @"drag 1: a drag of this process is marked as such");
                expect([dataRead isEqual: [@"drag payload" dataUsingEncoding: NSUTF8StringEncoding]], @"drag 1: the destination reads the data from the source");
                expect(missingRead == nil, @"drag 1: a type the source has no data for is refused");
                expect(result == Copy, [NSString stringWithFormat: @"drag 1: the source gets the performed operation (%lu)", (unsigned long) result]);
            } else if (n == 2) {
                expect(![log containsString: @"perform"], [NSString stringWithFormat: @"drag 2: no drop (%@)", log]);
                expect(result == 0, @"drag 2: nothing was performed");
            } else {
                expect([log hasPrefix: @"entered inside"] && [log hasSuffix: @"perform 16"], [NSString stringWithFormat: @"drag 3: the destination heard entered and perform with move (%@)", log]);
                expect(fromThisProcessSeen, @"drag 3: a drag of this process is marked as such");
                expect(sourceOperationsSeen == Move, @"drag 3: a local drag offers the local operations");
                expect([dataRead isEqual: [@"drag payload" dataUsingEncoding: NSUTF8StringEncoding]], @"drag 3: the destination reads the data from the source");
                expect(result == Move, [NSString stringWithFormat: @"drag 3: the source gets the performed operation (%lu)", (unsigned long) result]);
            }
            printf("DONE %d\n", n);
            fflush(stdout);
        }
        setDestination([destinationWindow windowId], nil);
        printf(failures == 0 ? "ALL PASSED\n" : "FAILED %d\n", failures);
        return failures != 0;
    }
}
