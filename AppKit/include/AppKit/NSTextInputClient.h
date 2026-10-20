#import <Foundation/Foundation.h>

@protocol NSTextInputClient

- (BOOL) hasMarkedText;
- (NSRange) markedRange;
- (NSRange) selectedRange;
- (void) setMarkedText: (id) string selectedRange: (NSRange) selectedRange replacementRange: (NSRange) replacementRange;
- (void) unmarkText;
- (NSArray *) validAttributesForMarkedText;
- (NSAttributedString *) attributedSubstringForProposedRange: (NSRange) range actualRange: (NSRangePointer) actualRange;
- (void) insertText: (id) string replacementRange: (NSRange) replacementRange;
- (NSUInteger) characterIndexForPoint: (NSPoint) point;
- (NSRect) firstRectForCharacterRange: (NSRange) range actualRange: (NSRangePointer) actualRange;
- (void) doCommandBySelector: (SEL) selector;

@end
