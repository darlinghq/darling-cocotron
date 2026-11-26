#import <Foundation/NSObject.h>
#import <Foundation/NSRange.h>
#import <AppKit/NSText.h>

@class NSArray, NSAffineTransform;

// A rectangle of a text selection or placeholder, in the client's coordinates (macOS AppKit SPI).
// Subclasses provide the values; the base class has an empty rect.
@interface NSTextSelectionRect : NSObject
@property (nonatomic, readonly) NSRect rect;
@property (nonatomic, readonly) NSWritingDirection writingDirection;
@property (nonatomic, readonly) BOOL isVertical;
@property (nonatomic, readonly) NSAffineTransform *transform;
@end

// Stands for text an input method is about to insert, such as dictated text, while the text
// is not known yet (macOS AppKit SPI). A text input client makes one in
// -insertTextPlaceholderWithSize:completionHandler:.
@interface NSTextPlaceholder : NSObject {
    NSArray *_rects;
    NSRange _placeholderRange;
}
// The rectangles the placeholder covers, NSTextSelectionRects; nil until set.
@property (nonatomic, copy) NSArray *rects;
@property (nonatomic) NSRange placeholderRange;
@end
