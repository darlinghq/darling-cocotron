#import <CoreText/CTFont.h>
#import <Foundation/NSObject.h>

@class NSData;

// Private on macOS, so not in the SDK headers (clients such as OpenSwiftUI declare it themselves).
// Carries the adaptive image payload; its metadata format is undocumented (VibeDarling/darling#845).
@interface CTAdaptiveImageGlyph : NSObject <CTAdaptiveImageProviding> {
    NSData *_imageContent;
}

- (instancetype)initWithImageContent:(NSData *)imageContent;

@property (readonly) NSData *imageContent;

@end
