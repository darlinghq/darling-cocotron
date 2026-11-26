// Copyright (C) 2026 Lubos Dolezel
//
// Guest test: AppKit's NSTextPlaceholder and NSTextSelectionRect classes.
// Observed on macOS 26.7.3 (x86_64) with the same calls: both descend
// directly from NSObject; a placeholder made with -init has no rects; a
// subclass can provide them (as WebKit's WKTextPlaceholder does).
#import <AppKit/AppKit.h>
#import <objc/runtime.h>

@interface NSTextPlaceholder : NSObject
@property (nonatomic, readonly) NSArray *rects;
@end

@interface NSTextSelectionRect : NSObject
@property (nonatomic, readonly) NSRect rect;
@end

@interface TestPlaceholder : NSTextPlaceholder
@end

@implementation TestPlaceholder
- (NSArray *)rects
{
    return @[ @1 ];
}
@end

static int failures;

static void report(const char *name, BOOL ok)
{
    printf("%s: %s\n", ok ? "PASS" : "FAIL", name);
    if (!ok)
        failures++;
}

int main(void)
{
    @autoreleasepool {
        report("NSTextPlaceholder descends from NSObject", class_getSuperclass(objc_getClass("NSTextPlaceholder")) == [NSObject class]);
        report("NSTextSelectionRect descends from NSObject", class_getSuperclass(objc_getClass("NSTextSelectionRect")) == [NSObject class]);
        NSTextPlaceholder *placeholder = [[[NSTextPlaceholder alloc] init] autorelease];
        report("no rects by default", placeholder != nil && placeholder.rects == nil);
        report("subclass provides rects", [[[[TestPlaceholder alloc] init] autorelease].rects count] == 1);
    }
    return failures != 0;
}
