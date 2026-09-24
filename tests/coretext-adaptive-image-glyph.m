#import <Foundation/Foundation.h>
#import "../CoreText/CTAdaptiveImageGlyph.h"
#include <stdlib.h>

static void expect(BOOL condition, NSString *message)
{
    if (!condition)
    {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

static NSException *exceptionFrom(void (^block)(void))
{
    @try
    {
        block();
    }
    @catch (NSException *exception)
    {
        return exception;
    }
    return nil;
}

int main(void)
{
    @autoreleasepool
    {
        const char bytes[] = "\0\0\0\x18" "ftypheic";
        NSMutableData *source = [NSMutableData dataWithBytes:bytes length:sizeof(bytes) - 1];
        CTAdaptiveImageGlyph *glyph = [[CTAdaptiveImageGlyph alloc] initWithImageContent:source];
        expect([glyph conformsToProtocol:@protocol(CTAdaptiveImageProviding)], @"conforms to CTAdaptiveImageProviding");
        expect([glyph.imageContent isEqualToData:source], @"image content round trip");

        [source appendBytes:"x" length:1];
        expect(glyph.imageContent.length == sizeof(bytes) - 1, @"image content is copied");

        CTAdaptiveImageGlyph *same = [[CTAdaptiveImageGlyph alloc]
            initWithImageContent:[NSData dataWithBytes:bytes length:sizeof(bytes) - 1]];
        CTAdaptiveImageGlyph *other = [[CTAdaptiveImageGlyph alloc] initWithImageContent:source];
        expect([glyph isEqual:same] && glyph.hash == same.hash, @"equal content, equal glyphs and hashes");
        expect(![glyph isEqual:other], @"different content, different glyphs");
        expect(![glyph isEqual:glyph.imageContent], @"a glyph is not equal to its data");

        NSException *nilContent = exceptionFrom(^{ [[CTAdaptiveImageGlyph alloc] initWithImageContent:nil]; });
        expect([nilContent.name isEqualToString:NSInvalidArgumentException], @"nil content raises");
        expect(exceptionFrom(^{ [[CTAdaptiveImageGlyph alloc] init]; }) != nil, @"init without content raises");

        NSException *image = exceptionFrom(^{
            CGPoint offset;
            CGSize size;
            [glyph imageForProposedSize:CGSizeMake(20, 20) scaleFactor:2 imageOffset:&offset imageSize:&size];
        });
        expect([image.name isEqualToString:NSInternalInconsistencyException] &&
                   [image.reason rangeOfString:@"VibeDarling/darling#845"].location != NSNotFound,
               @"image lookup raises and names the issue");

        [glyph release];
        [same release];
        [other release];
    }
    NSLog(@"PASS");
    return 0;
}
