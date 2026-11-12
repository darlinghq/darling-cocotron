#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#include <assert.h>
#include <stdio.h>
@interface UnsupportedFocusRep : NSImageRep @end
@implementation UnsupportedFocusRep
- (NSString *)description { return @"unsupported-focus-sentinel"; }
@end
int main(void) {
    setbuf(stdout,NULL);
    NSAutoreleasePool *pool=[NSAutoreleasePool new];
    NSImage *image=[[NSImage alloc] initWithSize:NSMakeSize(8,8)];
    UnsupportedFocusRep *rep=[UnsupportedFocusRep new];
    unsigned char pixels[8*8*4]={0};
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGContextRef port=CGBitmapContextCreate(pixels,8,8,8,32,space,kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    assert(port);
    NSGraphicsContext *before=[NSGraphicsContext graphicsContextWithGraphicsPort:port flipped:NO];
    [NSGraphicsContext setCurrentContext:before];
    BOOL caught=NO;
    @try { [image lockFocusOnRepresentation:rep]; }
    @catch (NSException *error) {
        assert([[error name] isEqualToString:NSInvalidArgumentException]);
        assert([[error reason] isEqualToString:@"NSImageRep unsupported-focus-sentinel can not be lockFocus'd"]);
        caught=YES;
    }
    assert(caught && [NSGraphicsContext currentContext]==before);
    [NSGraphicsContext setCurrentContext:nil];
    CGContextRelease(port);
    [rep release]; [image release]; [pool drain];
    puts("PASS: unsupported focus representation raises a correctly formatted exception");
    return 0;
}
