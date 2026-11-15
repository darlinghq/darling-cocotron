#import <AppKit/AppKit.h>
#include <stdio.h>

#define EXPECT(cond, msg) do { if (!(cond)) { printf("FAIL: %s\n", msg); return 1; } } while (0)

// +[NSTextField labelWithAttributedString:] (public SDK header, macOS 10.12): a non-editable, non-selectable
// field showing attributed text. The line break mode following the paragraph style is a QUIRK pinned below
// (observed on macOS 10.14.4).
@interface LabelSubclass : NSTextField
@end
@implementation LabelSubclass
@end

static NSAttributedString *styled(NSString *text, NSLineBreakMode mode, NSColor *color) {
    NSMutableParagraphStyle *style = [[[NSMutableParagraphStyle alloc] init] autorelease];
    [style setLineBreakMode: mode];
    NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys: style, NSParagraphStyleAttributeName,
                                                                           color, NSForegroundColorAttributeName, nil];
    return [[[NSAttributedString alloc] initWithString: text attributes: attributes] autorelease];
}

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    EXPECT([NSTextField respondsToSelector: @selector(labelWithAttributedString:)], "the class method exists");

    NSColor *red = [NSColor colorWithCalibratedRed: 1 green: 0 blue: 0 alpha: 1];
    NSAttributedString *text = styled(@"Hello label", NSLineBreakByCharWrapping, red);
    NSTextField *field = [NSTextField labelWithAttributedString: text];
    EXPECT([field isKindOfClass: [NSTextField class]], "it returns an NSTextField");
    EXPECT(![field isEditable], "not editable");
    EXPECT(![field isSelectable], "not selectable");
    EXPECT(![field isBezeled] && ![field isBordered], "no bezel or border");
    EXPECT(![field drawsBackground], "no background");
    EXPECT([[field stringValue] isEqualToString: @"Hello label"], "the string is the attributed string's text");
    EXPECT([[field attributedStringValue] isEqualToAttributedString: text], "it displays the attributed text with its attributes");
    EXPECT([field lineBreakMode] == NSLineBreakByCharWrapping, "line break mode comes from the paragraph style (char wrap)");

    NSTextField *truncating = [NSTextField labelWithAttributedString: styled(@"Another", NSLineBreakByTruncatingTail, red)];
    EXPECT([truncating lineBreakMode] == NSLineBreakByTruncatingTail, "line break mode follows the paragraph style (truncate tail)");
    NSTextField *clipping = [NSTextField labelWithAttributedString: styled(@"Third", NSLineBreakByClipping, red)];
    EXPECT([clipping lineBreakMode] == NSLineBreakByClipping, "line break mode follows the paragraph style (clip)");

    NSTextField *plain = [NSTextField labelWithAttributedString: [[[NSAttributedString alloc] initWithString: @"x"] autorelease]];
    EXPECT([plain isKindOfClass: [NSTextField class]] && [[plain stringValue] isEqualToString: @"x"], "a string without a paragraph style works");

    NSTextField *empty = [NSTextField labelWithAttributedString: [[[NSAttributedString alloc] initWithString: @""] autorelease]];
    EXPECT(empty != nil && ![empty isEditable], "an empty string works");

    EXPECT([[LabelSubclass labelWithAttributedString: text] isKindOfClass: [LabelSubclass class]], "a subclass gets its own class");

    [pool drain];
    printf("PASS: NSTextField labelWithAttributedString\n");
    return 0;
}
