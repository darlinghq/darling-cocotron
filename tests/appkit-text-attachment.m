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

@interface ProviderProbe : NSObject
@property(retain) NSTextAttachment *attachment;
@end

@implementation ProviderProbe
- (instancetype)initWithTextAttachment:(NSTextAttachment *)attachment
                            parentView:(NSView *)parentView
                     textLayoutManager:(id)textLayoutManager
                              location:(id)location
{
    if ((self = [super init]))
        self.attachment = attachment;
    return self;
}
@end

static void testTextAttachment(void)
{
    id<NSTextLocation> location = nil;
    expect([NSTextAttachment conformsToProtocol:@protocol(NSTextAttachmentLayout)] &&
               [NSTextAttachment conformsToProtocol:@protocol(NSSecureCoding)],
           @"NSTextAttachment adopts NSTextAttachmentLayout and NSSecureCoding");

    NSData *bytes = [@"payload" dataUsingEncoding:NSUTF8StringEncoding];
    NSTextAttachment *attachment = [[NSTextAttachment alloc] initWithData:bytes ofType:@"public.plain-text"];
    expect([attachment.contents isEqual:bytes] && [attachment.fileType isEqual:@"public.plain-text"],
           @"contents and file type are stored");
    expect(attachment.allowsTextAttachmentView && !attachment.usesTextAttachmentView,
           @"view providers are allowed but none is registered");
    attachment.bounds = CGRectMake(1, 2, 30, 40);
    attachment.lineLayoutPadding = 3;
    CGRect bounds = [attachment attachmentBoundsForAttributes:@{} location:location textContainer:nil
                                         proposedLineFragment:CGRectZero position:CGPointZero];
    expect(CGRectEqualToRect(bounds, CGRectMake(1, 2, 30, 40)), @"explicit bounds are used for layout");

    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(16, 12)];
    NSTextAttachment *imageAttachment = [[NSTextAttachment alloc] initWithData:nil ofType:nil];
    imageAttachment.image = image;
    expect([imageAttachment imageForBounds:CGRectZero attributes:@{} location:location textContainer:nil] == image,
           @"imageForBounds returns the image");
    bounds = [imageAttachment attachmentBoundsForAttributes:@{} location:location textContainer:nil
                                       proposedLineFragment:CGRectZero position:CGPointZero];
    expect(CGRectEqualToRect(bounds, CGRectMake(0, 0, 16, 12)), @"empty bounds fall back to the image size");

    NSFileWrapper *wrapper = [[NSFileWrapper alloc] initRegularFileWithContents:bytes];
    NSTextAttachment *wrapped = [[NSTextAttachment alloc] initWithFileWrapper:wrapper];
    expect(wrapped.fileWrapper == wrapper && [wrapped.contents isEqual:bytes] && wrapped.attachmentCell != nil,
           @"file wrapper supplies contents and a cell");

    BOOL raised = NO;
    @try {
        [NSTextAttachment registerTextAttachmentViewProviderClass:[NSObject class] forFileType:@"public.data"];
    } @catch (NSException *exception) {
        raised = [[exception name] isEqual:NSInvalidArgumentException];
    }
    expect(raised && [NSTextAttachment textAttachmentViewProviderClassForFileType:@"public.data"] == Nil,
           @"a class without the provider initializer is rejected");
    [NSTextAttachment registerTextAttachmentViewProviderClass:[ProviderProbe class] forFileType:@"public.plain-text"];
    expect([NSTextAttachment textAttachmentViewProviderClassForFileType:@"public.plain-text"] == [ProviderProbe class],
           @"provider class registration");
    expect(attachment.usesTextAttachmentView, @"registered provider enables text attachment views");
    ProviderProbe *provider = (ProviderProbe *)[attachment viewProviderForParentView:nil location:location textContainer:nil];
    expect([provider isKindOfClass:[ProviderProbe class]] && provider.attachment == attachment,
           @"view provider is created from the registered class");
    attachment.allowsTextAttachmentView = NO;
    expect(!attachment.usesTextAttachmentView &&
               [attachment viewProviderForParentView:nil location:location textContainer:nil] == nil,
           @"disallowing text attachment views");

    NSTextAttachment *decoded = roundTrip(attachment, [NSTextAttachment class]);
    expect([decoded.contents isEqual:bytes] && [decoded.fileType isEqual:@"public.plain-text"] &&
               CGRectEqualToRect(decoded.bounds, attachment.bounds) && decoded.lineLayoutPadding == 3 &&
               !decoded.allowsTextAttachmentView,
           @"attachment survives a secure keyed archive");
}

int main(void)
{
    @autoreleasepool
    {
        testTextAttachment();
        NSLog(@"PASS: NSTextAttachment matches Apple's declaration and behavior");
    }
    return 0;
}
