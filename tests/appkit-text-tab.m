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

static void testTextTab(void)
{
    expect([NSTextTab conformsToProtocol:@protocol(NSSecureCoding)], @"NSTextTab adopts NSSecureCoding");
    NSCharacterSet *terminators = [NSTextTab columnTerminatorsForLocale:[NSLocale localeWithLocaleIdentifier:@"de_DE"]];
    expect([terminators characterIsMember:','], @"German column terminators contain the decimal comma");

    NSDictionary *options = @{NSTabColumnTerminatorsAttributeName : terminators};
    NSTextTab *tab = [[NSTextTab alloc] initWithTextAlignment:NSTextAlignmentRight location:40 options:options];
    expect(tab.alignment == NSTextAlignmentRight && tab.location == 40, @"alignment and location are stored");
    expect([tab.options isEqual:options], @"options are stored");
    expect(tab.tabStopType == NSDecimalTabStopType, @"right tab with terminators is a decimal tab");

    NSTextTab *center = [[NSTextTab alloc] initWithType:NSCenterTabStopType location:10];
    expect(center.alignment == NSTextAlignmentCenter && center.options.count == 0, @"legacy center tab");
    NSTextTab *decimal = [[NSTextTab alloc] initWithType:NSDecimalTabStopType location:10];
    expect(decimal.alignment == NSTextAlignmentRight && decimal.tabStopType == NSDecimalTabStopType &&
               decimal.options[NSTabColumnTerminatorsAttributeName] != nil,
           @"legacy decimal tab is right-aligned with terminators");
    expect([center compare:tab] == NSOrderedAscending, @"tabs order by location");

    // A decimal tab's character set is not archived here: Darling's Foundation
    // cannot decode NSCharacterSet yet.
    NSTextTab *decoded = roundTrip(center, [NSTextTab class]);
    expect([decoded isEqual:center] && decoded.tabStopType == NSCenterTabStopType,
           @"tab survives a secure keyed archive");
}

int main(void)
{
    @autoreleasepool
    {
        testTextTab();
        NSLog(@"PASS: NSTextTab matches Apple's declaration and behavior");
    }
    return 0;
}
