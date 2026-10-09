#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#include <stdio.h>
#include <stdlib.h>

static void expect(BOOL condition, const char *message)
{
    if (!condition)
    {
        fprintf(stderr, "FAIL: %s\n", message);
        exit(1);
    }
}

int main(void)
{
    @autoreleasepool
    {
        NSArray *formats = @[kCAContentsFormatRGBA8Uint, kCAContentsFormatRGBA16Float,
                             kCAContentsFormatGray8Uint, kCAContentsFormatAutomatic];
        expect(kCAContentsFormatAutomatic != nil, "automatic format is defined");
        expect([NSSet setWithArray: formats].count == formats.count, "contents formats are distinct");

        CALayer *layer = [CALayer layer];
        expect([layer.contentsFormat isEqualToString: kCAContentsFormatRGBA8Uint], "default contents format");
        layer.contentsFormat = kCAContentsFormatAutomatic;
        expect([layer.contentsFormat isEqualToString: kCAContentsFormatAutomatic], "automatic round trip");
    }
    puts("PASS");
    return 0;
}
