/* Copyright (c) 2006-2007 Christopher J. W. Lloyd

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import <AppKit/NSTextAttachmentCell.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

NS_HEADER_AUDIT_BEGIN(nullability, sendability)

@class NSTextContainer;
@class NSLayoutManager;
@class NSFileWrapper;
@class NSTextAttachmentViewProvider;
@class NSTextLayoutManager;
@protocol NSTextLocation;

@class NSImage;
@class NSView;
@class NSTextAttachmentCell;
@protocol NSTextAttachmentCell;

enum { NSAttachmentCharacter = 0xFFFC };

// This protocol and the class's primary interface match Apple's declarations
// member for member: Clang rejects a definition that two modules spell differently.
@protocol NSTextAttachmentLayout <NSObject>

- (nullable NSImage *)imageForBounds:(CGRect)bounds attributes:(NSDictionary<NSAttributedStringKey, id> *)attributes location:(id <NSTextLocation>)location textContainer:(nullable NSTextContainer *)textContainer;

- (CGRect)attachmentBoundsForAttributes:(NSDictionary<NSAttributedStringKey, id> *)attributes location:(id <NSTextLocation>)location textContainer:(nullable NSTextContainer *)textContainer proposedLineFragment:(CGRect)proposedLineFragment position:(CGPoint)position;

- (nullable NSTextAttachmentViewProvider *)viewProviderForParentView:(nullable NSView *)parentView location:(id <NSTextLocation>)location textContainer:(nullable NSTextContainer *)textContainer;

@end

// i386's fragile runtime needs these in the @interface; elsewhere the
// implementation declares them, keeping the interface identical to Apple's.
#define _NSTEXTATTACHMENT_IVARS \
    NSData *_contents; \
    NSString *_fileType; \
    NSImage *_image; \
    CGRect _bounds; \
    NSFileWrapper *_fileWrapper; \
    id<NSTextAttachmentCell> _cell; \
    CGFloat _lineLayoutPadding; \
    BOOL _allowsTextAttachmentView;

@interface NSTextAttachment : NSObject <NSTextAttachmentLayout, NSSecureCoding>
#if !__OBJC2__
{
    _NSTEXTATTACHMENT_IVARS
}
#endif

- (instancetype)initWithData:(nullable NSData *)contentData ofType:(nullable NSString *)uti NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithFileWrapper:(nullable NSFileWrapper *)fileWrapper;

@property (nullable, copy, NS_NONATOMIC_IOSONLY) NSData *contents;
@property (nullable, copy, NS_NONATOMIC_IOSONLY) NSString *fileType;

@property (nullable, strong) NSImage *image;

@property (NS_NONATOMIC_IOSONLY) CGRect bounds;
@property (nullable, strong, NS_NONATOMIC_IOSONLY) NSFileWrapper *fileWrapper;

@property (nullable, strong) id <NSTextAttachmentCell> attachmentCell API_AVAILABLE(macos(10.0));

@property CGFloat lineLayoutPadding;

+ (nullable Class)textAttachmentViewProviderClassForFileType:(NSString *)fileType;
+ (void)registerTextAttachmentViewProviderClass:(Class)textAttachmentViewProviderClass forFileType:(NSString *)fileType;

@property BOOL allowsTextAttachmentView;
@property (readonly) BOOL usesTextAttachmentView;

@end

NS_HEADER_AUDIT_END(nullability, sendability)
