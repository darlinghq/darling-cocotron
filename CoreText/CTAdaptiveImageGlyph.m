#import "CTAdaptiveImageGlyph.h"
#import <Foundation/NSData.h>
#import <Foundation/NSException.h>
#import <Foundation/NSString.h>

@implementation CTAdaptiveImageGlyph

- (instancetype)init
{
    return [self initWithImageContent:nil];
}

- (instancetype)initWithImageContent:(NSData *)imageContent
{
    if (imageContent == nil)
    {
        [self release];
        [NSException raise:NSInvalidArgumentException format:@"-[CTAdaptiveImageGlyph initWithImageContent:]: nil image content"];
    }
    self = [super init];
    if (self != nil)
        _imageContent = [imageContent copy];
    return self;
}

- (void)dealloc
{
    [_imageContent release];
    [super dealloc];
}

- (NSData *)imageContent
{
    return _imageContent;
}

- (BOOL)isEqual:(id)other
{
    if (other == self)
        return YES;
    return [other isKindOfClass:[CTAdaptiveImageGlyph class]] &&
           [_imageContent isEqualToData:((CTAdaptiveImageGlyph *)other)->_imageContent];
}

- (NSUInteger)hash
{
    return [_imageContent hash];
}

- (CGImageRef)imageForProposedSize:(CGSize)proposedSize
                       scaleFactor:(CGFloat)scaleFactor
                       imageOffset:(CGPoint *)outImageOffset
                         imageSize:(CGSize *)outImageSize
{
    [NSException raise:NSInternalInconsistencyException
                format:@"-[CTAdaptiveImageGlyph %@]: Darling cannot read adaptive image glyph content, "
                       @"whose format Apple does not document (VibeDarling/darling#845)",
                       NSStringFromSelector(_cmd)];
    return NULL;
}

@end
