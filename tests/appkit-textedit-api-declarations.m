// Copyright (C) 2026 Lubos Dolezel
//
// Declarations of public AppKit API that were missing or typed differently from the SDK's headers:
//  - NSOnState, NSOffState and NSMixedState are NSControlStateValue constants (so comparing them with
//    -[NSCell state], or passing them to -setState:, needs no enum cast);
//  - -[NSView rectForPage:] takes an NSInteger page number;
//  - -[NSBundle loadNibNamed:owner:topLevelObjects:] and the NSDocument and NSDocumentController methods
//    that document-based applications override (beginOpenPanel:forTypes:completionHandler:,
//    checkAutosavingSafetyAndReturnError:, duplicateAndReturnError:, fileNameExtensionForType:saveOperation:,
//    performSynchronousFileAccessUsingBlock:) are declared;
//  - -[NSDrawer state] returns an NSInteger, like the other state accessors, so [object state] on an id is
//    not ambiguous.
// Build (any mismatch is an error, which is the failure before the headers were fixed):
//   clang -framework AppKit -Werror=objc-method-access -Werror=enum-compare -Werror=implicit-enum-enum-cast \
//         -Werror=mismatched-parameter-types -Werror=objc-multiple-method-names -Werror=incompatible-property-type \
//         -Werror=nullability appkit-textedit-api-declarations.m
#import <AppKit/AppKit.h>
#include <stdlib.h>

static void expect(BOOL condition, NSString *message) {
    if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}

// An override with the SDK's signature compiles without a mismatch warning.
@interface PageView : NSView
@end
@implementation PageView
- (NSRect)rectForPage:(NSInteger)page { return NSMakeRect(0, 0, (CGFloat)page, 1); }
@end

@interface Doc : NSDocument
@end
@implementation Doc
- (BOOL)checkAutosavingSafetyAndReturnError:(NSError **)outError { return [super checkAutosavingSafetyAndReturnError:outError]; }
- (NSDocument *)duplicateAndReturnError:(NSError **)outError { return [super duplicateAndReturnError:outError]; }
- (NSString *)fileNameExtensionForType:(NSString *)type saveOperation:(NSSaveOperationType)op { return [super fileNameExtensionForType:type saveOperation:op]; }
@end

@interface Controller : NSDocumentController
@end
@implementation Controller
- (void)beginOpenPanel:(NSOpenPanel *)panel forTypes:(NSArray *)types completionHandler:(void (^)(NSInteger))handler {
    [super beginOpenPanel:panel forTypes:types completionHandler:handler];
}
@end

static int onState(id sender) { return [sender state] == NSOnState; } // ambiguity check: an id receiver

int main(void) {
    @autoreleasepool {
        NSControlStateValue on = NSOnState, off = NSOffState, mixed = NSMixedState;
        expect(on == NSControlStateValueOn && off == NSControlStateValueOff && mixed == NSControlStateValueMixed, @"the old names have the new values");
        expect(on == 1 && off == 0 && mixed == -1, @"the values are 1, 0, -1");

        NSButton *button = [[[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)] autorelease];
        [button setState:NSOnState];
        expect(onState(button), @"the state constants work with -setState: and -state");
        NSCell *cell = [[[NSCell alloc] init] autorelease];
        [cell setAllowsMixedState:YES];
        [cell setState:NSMixedState];
        expect([cell state] == NSMixedState, @"a cell holds the mixed state");

        // The page number is an NSInteger in the method signature (an int would show as 'i' on 64-bit).
        NSMethodSignature *signature = [NSView instanceMethodSignatureForSelector:@selector(rectForPage:)];
        expect(strcmp([signature getArgumentTypeAtIndex:2], @encode(NSInteger)) == 0, [NSString stringWithFormat:@"rectForPage: takes an NSInteger (got %s)", [signature getArgumentTypeAtIndex:2]]);
        PageView *view = [[[PageView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)] autorelease];
        expect([view rectForPage:7].size.width == 7, @"the override is called with the page number");

        // The nib loading method of NSBundle is declared and answers NO for a missing nib.
        NSArray *objects = nil;
        BOOL loaded = [[NSBundle mainBundle] loadNibNamed:@"NoSuchNibInThisBundle" owner:nil topLevelObjects:&objects];
        expect(!loaded, @"a missing nib is not loaded");

        // The state accessor of drawers returns an NSInteger.
        NSMethodSignature *drawer = [NSDrawer instanceMethodSignatureForSelector:@selector(state)];
        expect(strcmp([drawer methodReturnType], @encode(NSInteger)) == 0, @"-[NSDrawer state] returns an NSInteger");

        // The file access method of NSDocument takes a block and runs it.
        __block BOOL ran = NO;
        [[[[Doc alloc] init] autorelease] performSynchronousFileAccessUsingBlock:^{ ran = YES; }];
        expect(ran, @"performSynchronousFileAccessUsingBlock: runs the block");
        printf("PASS\n");
    }
    return 0;
}
