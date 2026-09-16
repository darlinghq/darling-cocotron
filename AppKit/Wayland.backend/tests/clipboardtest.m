#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>

static NSString *path(const char *name) { const char *s = getenv(name); return s ? [NSString stringWithUTF8String:s] : nil; }
static void report(const char *text) { puts(text); fflush(stdout); }

@interface ClipboardView : NSView <NSPasteboardTypeOwner>
@end
@implementation ClipboardView
- (BOOL)acceptsFirstResponder { return YES; }
- (void)drawRect:(NSRect)rect { [[NSColor whiteColor] set]; NSRectFill([self bounds]); }
- (void)pasteboard:(NSPasteboard *)board provideDataForType:(NSString *)type {
    report("lazy provider");
    [board setData:[NSData dataWithContentsOfFile:path("CLIPBOARD_INPUT")] forType:type];
}
- (void)pasteboardChangedOwner:(NSPasteboard *)board { report("owner changed"); }
- (void)keyDown:(NSEvent *)event {
    NSString *key = [event characters];
    NSPasteboard *board = [NSPasteboard generalPasteboard];
    if ([key isEqual:@"c"]) {
        [board declareTypes:@[NSStringPboardType] owner:nil];
        BOOL ok = [board setData:[NSData dataWithContentsOfFile:path("CLIPBOARD_INPUT")] forType:NSStringPboardType];
        printf("copy %d change=%ld\n", ok, (long)[board changeCount]);
    } else if ([key isEqual:@"l"]) {
        [board declareTypes:@[NSStringPboardType] owner:self];
        report("lazy declared");
    } else if ([key isEqual:@"p"]) {
        NSData *data = [board dataForType:NSStringPboardType];
        BOOL ok = data && [data writeToFile:path("CLIPBOARD_RESULT") atomically:YES];
        printf("paste %d bytes=%lu change=%ld\n",ok,(unsigned long)[data length],(long)[board changeCount]);
    } else if ([key isEqual:@"u"]) {
        printf("unsupported nil=%d\n",[board dataForType:@"application/x-not-offered"] == nil);
    } else if ([key isEqual:@"e"]) {
        [board clearContents]; report("cleared");
    } else if ([key isEqual:@"r"]) {
        NSTimeInterval start = [NSDate timeIntervalSinceReferenceDate];
        BOOL nilData = [board dataForType:NSStringPboardType] == nil;
        printf("bounded nil=%d seconds=%.2f\n",nilData,[NSDate timeIntervalSinceReferenceDate]-start);
    } else if ([key isEqual:@"q"]) {
        report("exiting"); exit(0);
    }
    fflush(stdout);
}
@end

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSPasteboard *named=[NSPasteboard pasteboardWithName:@"Wayland local test"];
        [named declareTypes:@[NSStringPboardType] owner:nil];
        [named setString:@"local ăîșț" forType:NSStringPboardType];
        if (![[named stringForType:NSStringPboardType] isEqual:@"local ăîșț"]) return 2;
        if ([NSPasteboard pasteboardWithName:NSPasteboardNameGeneral] != [NSPasteboard generalPasteboard]) return 3;
        report("local pasteboard PASS");
        NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(100,100,400,200)
            styleMask:NSTitledWindowMask|NSClosableWindowMask|NSResizableWindowMask backing:NSBackingStoreBuffered defer:NO];
        [window setTitle:@"Wayland clipboard test"];
        ClipboardView *view=[[ClipboardView alloc] initWithFrame:NSMakeRect(0,0,400,200)];
        [window setContentView:view];
        [window makeKeyAndOrderFront:nil]; [window makeFirstResponder:view];
        report("clipboard ready");
        [NSApp run];
    }
    return 0;
}
