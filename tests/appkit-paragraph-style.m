#import <AppKit/AppKit.h>
#include <stdlib.h>

static void expect(BOOL condition, NSString *message)
{
    if (!condition)
    {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

static id roundTrip(id object, Class cls)
{
    NSError *error = nil;
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:object requiringSecureCoding:YES error:&error];
    expect(data != nil, [NSString stringWithFormat:@"archive %@: %@", cls, error]);
    id decoded = [NSKeyedUnarchiver unarchivedObjectOfClass:cls fromData:data error:&error];
    expect(decoded != nil, [NSString stringWithFormat:@"unarchive %@: %@", cls, error]);
    return decoded;
}

static void testParagraphStyle(void)
{
    expect([NSParagraphStyle conformsToProtocol:@protocol(NSSecureCoding)], @"NSParagraphStyle adopts NSSecureCoding");
    NSParagraphStyle *defaults = [NSParagraphStyle defaultParagraphStyle];
    expect(defaults.tabStops.count == 12 && !defaults.usesDefaultHyphenation &&
               !defaults.allowsDefaultTighteningForTruncation && defaults.lineBreakStrategy == NSLineBreakStrategyNone,
           @"default paragraph style values");

    NSMutableParagraphStyle *style = [defaults mutableCopy];
    style.usesDefaultHyphenation = YES;
    style.allowsDefaultTighteningForTruncation = YES;
    style.lineBreakStrategy = NSLineBreakStrategyPushOut;
    style.headerLevel = 2;
    style.alignment = NSCenterTextAlignment;
    style.tabStops = @[];
    expect(style.tabStops.count == 0, @"tab stops replaced on a mutable copy of the default style");
    NSTextTab *late = [[NSTextTab alloc] initWithType:NSLeftTabStopType location:80];
    NSTextTab *early = [[NSTextTab alloc] initWithType:NSLeftTabStopType location:20];
    NSTextTab *middle = [[NSTextTab alloc] initWithType:NSRightTabStopType location:50];
    [style addTabStop:late];
    [style addTabStop:early];
    [style addTabStop:middle];
    NSArray *tabs = style.tabStops;
    expect(tabs.count == 3 && tabs[0] == early && tabs[1] == middle && tabs[2] == late, @"addTabStop keeps location order");
    [style removeTabStop:middle];
    expect(style.tabStops.count == 3 - 1, @"removeTabStop");
    expect(tabs.count == 3, @"tabStops returns a copy");

    NSParagraphStyle *copy = [style copy];
    expect(copy != style && ![copy isKindOfClass:[NSMutableParagraphStyle class]],
           @"copying a mutable style gives an immutable one");
    expect(copy.usesDefaultHyphenation && copy.allowsDefaultTighteningForTruncation &&
               copy.lineBreakStrategy == NSLineBreakStrategyPushOut && copy.headerLevel == 2 &&
               copy.alignment == NSCenterTextAlignment && [copy isEqual:style],
           @"copy keeps every property");

    NSParagraphStyle *decoded = roundTrip(style, [NSParagraphStyle class]);
    expect([decoded isEqual:style] && decoded.lineBreakStrategy == NSLineBreakStrategyPushOut,
           @"paragraph style survives a secure keyed archive");

    style.tabStops = nil;
    expect(style.tabStops.count == 12, @"nil tab stops reset to the defaults");
}

int main(void)
{
    @autoreleasepool
    {
        testParagraphStyle();
        NSLog(@"PASS: NSParagraphStyle matches Apple's declaration and behavior");
    }
    return 0;
}
