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
#import "NSKeyValueBinding/NSObject+BindingSupport.h"
#import "NSKeyValueBinding/NSTextFieldBinder.h"
#import <AppKit/NSApplication.h>
#import <AppKit/NSCursor.h>
#import <AppKit/NSAttributedString.h>
#import <AppKit/NSParagraphStyle.h>
#import <AppKit/NSDragging.h>
#import <AppKit/NSPasteboard.h>
#import <AppKit/NSStringDrawer.h>
#import <AppKit/NSTextField.h>
#import <AppKit/NSTextFieldCell.h>
#import <AppKit/NSTextStorage.h>
#import <AppKit/NSTextView.h>
#import <AppKit/NSWindow.h>
#import "NSViewLayoutInternal.h"
#import <AppKit/NSLinkedOnOrAfter.h>

@interface NSTextFieldCell (Private)

- (CGFloat) _fontSize;
- (void) _setFontSize: (CGFloat) fontSize;
- (NSString *) _fontFamilyName;
- (void) _setFontFamilyName: (NSString *) familyName;

@end

@interface NSTextFieldCell (NSTextFieldInset)
- (NSSize) _textInsetSize;
- (NSInteger) _maximumNumberOfLines;
- (void) _setMaximumNumberOfLines: (NSInteger) value;
@end

@implementation NSTextField

// Operated at once: the click that activates the window is delivered to it
// (see -[NSWindow sendEvent:]).
- (BOOL) acceptsFirstMouse: (NSEvent *) event {
    return YES;
}

- (CGFloat) preferredMaxLayoutWidth {
    return NS_EXTRA(NSTextField, self)->_preferredMaxLayoutWidth;
}

// The width wrapped text is laid out in is part of the intrinsic size, so a change invalidates it.
- (void) setPreferredMaxLayoutWidth: (CGFloat) width {
    if (NS_EXTRA(NSTextField, self)->_preferredMaxLayoutWidth == width)
        return;
    NS_EXTRA(NSTextField, self)->_preferredMaxLayoutWidth = width;
    [self invalidateIntrinsicContentSize];
}

NS_EXTRA_DEALLOC(NSTextField)

// A non-editable, non-selectable, borderless field without background that shows
// the attributed text, sized to fit it. The line break mode comes from the
// string's paragraph style; without one the cell's default (word wrapping)
// stays, as observed on macOS.
+ (instancetype) labelWithAttributedString: (NSAttributedString *) attributedStringValue {
    NSTextField *label = [[[self alloc] initWithFrame: NSZeroRect] autorelease];
    [label setAttributedStringValue: attributedStringValue];
    [label setBezeled: NO];
    [label setBordered: NO];
    [label setDrawsBackground: NO];
    [label setEditable: NO];
    [label setSelectable: NO];
    if ([attributedStringValue length] > 0) {
        NSParagraphStyle *style = [attributedStringValue attribute: NSParagraphStyleAttributeName
                                                           atIndex: 0
                                                    effectiveRange: NULL];
        // QUIRK: the field's lineBreakMode follows the paragraph style of the text. Not
        // documented beyond the header saying the mode is "determined by" the style.
        // Evidence: black-box observation on macOS 10.14.4 (tier 2; macOS 26.7.3 reports
        // word wrapping for every style, the wider older behaviour is followed).
        // Test: tests/appkit-text-field-label-attributed.m
        if (style != nil)
            [label setLineBreakMode: [style lineBreakMode]];
    }
    [label sizeToFit];
    return label;
}

+ (Class) cellClass {
    return [NSTextFieldCell class];
}

+ (instancetype) labelWithString: (NSString *) stringValue {
    NSTextField *label = [[[self alloc] initWithFrame: NSZeroRect] autorelease];
    [label setStringValue: (stringValue != nil) ? stringValue : @""];
    [label setBezeled: NO];
    [label setDrawsBackground: NO];
    [label setEditable: NO];
    [label setSelectable: NO];
    [label setFont: [NSFont systemFontOfSize: [NSFont systemFontSize]]];
    // A label stays on one line: it clips rather than wraps.
    [label setLineBreakMode: NSLineBreakByClipping];
    [label sizeToFit];
    return label;
}

+ (instancetype) wrappingLabelWithString: (NSString *) stringValue {
    NSTextField *label = [[[self alloc] initWithFrame: NSZeroRect] autorelease];
    [label setStringValue: (stringValue != nil) ? stringValue : @""];
    [label setBezeled: NO];
    [label setDrawsBackground: NO];
    [label setEditable: NO];
    [label setSelectable: YES];
    [label setFont: [NSFont systemFontOfSize: [NSFont systemFontSize]]];
    [label setLineBreakMode: NSLineBreakByWordWrapping];
    return label;
}

+ (instancetype) textFieldWithString: (NSString *) stringValue {
    NSTextField *field = [[[self alloc] initWithFrame: NSZeroRect] autorelease];
    [field setStringValue: (stringValue != nil) ? stringValue : @""];
    [field setBezeled: YES];
    [field setDrawsBackground: YES];
    [field setEditable: YES];
    [field setSelectable: YES];
    [field setFont: [NSFont systemFontOfSize: [NSFont systemFontSize]]];
    [field sizeToFit];
    return field;
}

+ (Class) _binderClassForBinding: (id) binding {
    if ([binding isEqual: @"value"])
        return [_NSTextFieldBinder class];
    else
        return [super _binderClassForBinding: binding];
}

- initWithCoder: (NSCoder *) coder {
    [super initWithCoder: coder];
    [self registerForDraggedTypes:
                    [NSArray arrayWithObject: NSStringPboardType]];
    NS_EXTRA(NSTextField, self)->_automaticTextCompletionEnabled = YES;

    if ([coder allowsKeyedCoding]) {
        NSKeyedUnarchiver *keyed = (NSKeyedUnarchiver *) coder;

        [self setDelegate: [keyed decodeObjectForKey: @"NSDelegate"]];
        NS_EXTRA(NSTextField, self)->_errorAction = NSSelectorFromString(
                [keyed decodeObjectForKey: @"NSErrorAction"]);

        NS_EXTRA(NSTextField, self)->_preferredMaxLayoutWidth =
                [keyed decodeDoubleForKey: @"NSPreferredMaxLayoutWidth"];
        // TODO
    } else {
        NSInteger version = [coder versionForClassName: @"NSTextField"];

        if (version < 25) {
            [self setNextKeyView: [coder decodeObject]];
            [[coder decodeObject] setNextKeyView: self];
        }

        [self setDelegate: [coder decodeObject]];
        [coder decodeValuesOfObjCTypes: ":", &NS_EXTRA(NSTextField, self)->_errorAction];
    }
    return self;
}

- (void) encodeWithCoder: (NSCoder *) coder {
    [super encodeWithCoder: coder];

    if (coder.allowsKeyedCoding) {
        [coder encodeObject: _delegate forKey: @"NSDelegate"];
        [coder encodeObject: NSStringFromSelector(NS_EXTRA(NSTextField, self)->_errorAction)
                     forKey: @"NSErrorAction"];
        [coder encodeDouble: NS_EXTRA(NSTextField, self)->_preferredMaxLayoutWidth
                     forKey: @"NSPreferredMaxLayoutWidth"];
        // TODO
    } else {
        [NSException raise: NSInvalidArchiveOperationException
                    format: @"TODO: support unkeyed encoding in NSTextField"];
    }
}

// With a preferred maximum width, the cell's text wraps at that width: the intrinsic height is
// that of the wrapped lines and the width that of the widest of them.
- (NSSize) intrinsicContentSize {
    CGFloat maxWidth = NS_EXTRA(NSTextField, self)->_preferredMaxLayoutWidth;
    NSCell *cell = [self cell];

    if (maxWidth > 0 && [cell wraps]) {
        NSSize size = [cell cellSizeForBounds: NSMakeRect(0, 0, maxWidth, NSStringDrawerLargeDimension)];

        NSSize inset = [(NSTextFieldCell *) cell _textInsetSize];

        return NSMakeSize(ceil(size.width - inset.width), size.height);
    }
    return [super intrinsicContentSize];
}

// QUIRK: a wrapping text field without a preferredMaxLayoutWidth that is laid out with constraints,
// in a program built against the 10.11 SDK or later, has the height of its text wrapped at the width
// layout gave it, while -intrinsicContentSize keeps answering the unwrapped single-paragraph size.
// With older SDKs the height stays that of the unwrapped text. Not documented. Evidence: black-box
// observation on macOS 10.14.4 and 26.7.3 (tier 2): a label of two paragraphs, 356 points wide by
// constraints, ends up 119 points high when the program records SDK 10.11 or later and 34 points
// (two lines) when it records 10.10 or earlier, with intrinsicContentSize {1602, 34} either way.
// Test: tests/appkit-wrapping-label-automatic-width.m
- (BOOL) _wrapsAtLayoutWidth {
    return NS_EXTRA(NSTextField, self)->_preferredMaxLayoutWidth <= 0 && [[self cell] wraps] &&
           NSProgramLinkedOnOrAfterSDK(NS_SDK_VERSION_MACOSX_10_11);
}

- (NSSize) _intrinsicContentSizeForLayout {
    NSSize size = [self intrinsicContentSize];

    if (![self _wrapsAtLayoutWidth] || size.height == NSViewNoIntrinsicMetric)
        return size;

    CGFloat width = [self frame].size.width;
    NS_EXTRA(NSTextField, self)->_layoutWidth = width;
    if (width <= 0)
        return size;

    NSSize wrapped = [[self cell] cellSizeForBounds: NSMakeRect(0, 0, width, NSStringDrawerLargeDimension)];
    size.height = wrapped.height;
    return size;
}

// The wrapped height depends on the width the solver produced, so a new width asks for another pass.
- (void) layout {
    [super layout];
    if ([self _wrapsAtLayoutWidth] && [self frame].size.width != NS_EXTRA(NSTextField, self)->_layoutWidth)
        [self invalidateIntrinsicContentSize];
}

- initWithFrame: (NSRect) frame {
    [super initWithFrame: frame];
    // Default for a NSTextFieldCell is NOT the same as NSTextField
    [_cell setEditable: YES];
    [_cell setSelectable: YES];
    [_cell setBezeled: YES];
    // QUIRK: a new text field draws its background, in textBackgroundColor,
    // and has controlTextColor as its text colour. Not documented. Evidence:
    // black-box observation on macOS 10.14.4 and 26.7.3 (tier 2), probe
    // mac-probes/aqua-metric-followups.m of the research notes.
    // Test: appkit-text-field-defaults.m (test_quirk_field_defaults)
    [self _setDefaultBackground];
    [_cell setTextColor: [NSColor controlTextColor]];
    NS_EXTRA(NSTextField, self)->_automaticTextCompletionEnabled = YES;
    [self registerForDraggedTypes:
                    [NSArray arrayWithObject: NSStringPboardType]];
    return self;
}

// The background a new field of this class draws; see -initWithFrame:.
- (void) _setDefaultBackground {
    [_cell setDrawsBackground: YES];
    [_cell setBackgroundColor: [NSColor textBackgroundColor]];
}

- (BOOL) isFlipped {
    return YES;
}

// Stored only: field editing offers no completions yet.
- (BOOL) isAutomaticTextCompletionEnabled {
    return NS_EXTRA(NSTextField, self)->_automaticTextCompletionEnabled;
}

- (void) setAutomaticTextCompletionEnabled: (BOOL) value {
    NS_EXTRA(NSTextField, self)->_automaticTextCompletionEnabled = value;
}

- (BOOL) isOpaque {
    return [_cell drawsBackground] || [_cell isBezeled];
}

// See the QUIRK in NSControl: a text field follows the view rule, so a
// label lets clicks through and a bezeled, editable field does not.
- (BOOL) mouseDownCanMoveWindow {
    return ![self isOpaque];
}

- (void) resetCursorRects {
    [_cell resetCursorRect: [self bounds] inView: self];
}

- delegate {
    return _delegate;
}

- (void) setDelegate: delegate {
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    struct {
        SEL selector;
        NSString *name;
    } notes[] = {{@selector(controlTextDidBeginEditing:),
                  NSControlTextDidBeginEditingNotification},
                 {@selector(controlTextDidChange:),
                  NSControlTextDidChangeNotification},
                 {@selector(controlTextDidEndEditing:),
                  NSControlTextDidEndEditingNotification},
                 {NULL, nil}};
    int i;

    if (_delegate != nil)
        for (i = 0; notes[i].selector != NULL; i++)
            [center removeObserver: _delegate name: notes[i].name object: self];

    _delegate = delegate;

    for (i = 0; notes[i].selector != NULL; i++)
        if ([_delegate respondsToSelector: notes[i].selector])
            [center addObserver: _delegate
                       selector: notes[i].selector
                           name: notes[i].name
                         object: self];
}

- (NSColor *) backgroundColor {
    return [_cell backgroundColor];
}

- (NSColor *) textColor {
    return [_cell textColor];
}

- (BOOL) drawsBackground {
    return [_cell drawsBackground];
}

- (void) setBackgroundColor: (NSColor *) color {
    [_cell setBackgroundColor: color];
    [self setNeedsDisplay: YES];
}

- (void) setTextColor: (NSColor *) color {
    [_cell setTextColor: color];
    [self setNeedsDisplay: YES];
}

- (void) setDrawsBackground: (BOOL) flag {
    [_cell setDrawsBackground: flag];
    [self setNeedsDisplay: YES];
}

- (NSTextFieldBezelStyle) bezelStyle {
    return [_cell bezelStyle];
}

- (void) setBezelStyle: (NSTextFieldBezelStyle) style {
    [_cell setBezelStyle: style];
    [self setNeedsDisplay: YES];
}

- (BOOL) allowsEditingTextAttributes {
    return [_cell allowsEditingTextAttributes];
}

- (void) setAllowsEditingTextAttributes: (BOOL) flag {
    [_cell setAllowsEditingTextAttributes: flag];
}

- (NSString *) placeholderString {
    return [_cell placeholderString];
}

- (void) setPlaceholderString: (NSString *) placeholderString {
    [_cell setPlaceholderString: placeholderString];
    [self setNeedsDisplay: YES];
}

- (NSAttributedString *) placeholderAttributedString {
    return [_cell placeholderAttributedString];
}

- (void) setPlaceholderAttributedString:
        (NSAttributedString *) placeholderAttributedString
{
    [_cell setPlaceholderAttributedString: placeholderAttributedString];
    [self setNeedsDisplay: YES];
}

- (NSInteger) maximumNumberOfLines {
    return [_cell respondsToSelector: @selector(_maximumNumberOfLines)]
            ? [(NSTextFieldCell *) _cell _maximumNumberOfLines]
            : 0;
}

// The cap changes how many lines the cell draws and measures, so the size and the drawing are stale.
- (void) setMaximumNumberOfLines: (NSInteger) maximumNumberOfLines {
    if (![_cell respondsToSelector: @selector(_setMaximumNumberOfLines:)])
        return;
    // A negative cap is kept as given and lays the text out without a limit (the cell only limits for a cap
    // above zero). Observed by black-box test on macOS 26.7.3 and 10.14.4: the getter returns what was set.
    // Test: appkit-text-field-maximum-number-of-lines.m
    [(NSTextFieldCell *) _cell _setMaximumNumberOfLines: maximumNumberOfLines];
    [self invalidateIntrinsicContentSize];
    [self setNeedsDisplay: YES];
}

// Only an editable field accepts the keys; a selectable one takes them when pressed (macOS 10.14.4 and 26.7.3; test:
// appkit-textfield-label-mouse-down.m)
- (BOOL) acceptsFirstResponder {
    return [self isEditable];
}

- (BOOL) canBecomeKeyView {
    if (![self isEditable])
        return NO;

    return [super canBecomeKeyView];
}

- (BOOL) needsPanelToBecomeKey {
    return YES;
}

// The ring of a text field is drawn around its bounds while it is being edited (its field editor has the focus).
- (NSRect) focusRingMaskBounds {
    return [self currentEditor] != nil ? [self bounds] : NSZeroRect;
}

- (void) drawFocusRingMask {
    NSRectFill([self bounds]);
}

- (BOOL) becomeFirstResponder {
    [self selectText: nil];
    return YES;
}

- (void) _selectTextWithRange: (NSRange) range {
    NSTextFieldCell *cell = [self selectedCell];

    if (![cell isEnabled])
        return;

    if ([cell isEditable] || [cell isSelectable]) {
        if (NS_EXTRA(NSControl, self)->_currentEditor == nil) {
            NSText *editor = [[self window] fieldEditor: YES forObject: self];
            NS_EXTRA(NSControl, self)->_currentEditor = [[cell setUpFieldEditorAttributes: editor] retain];
            [NS_EXTRA(NSControl, self)->_currentEditor setDelegate: self];
            [NS_EXTRA(NSControl, self)->_currentEditor registerForDraggedTypes: [self _draggedTypes]];
            [NS_EXTRA(NSControl, self)->_currentEditor becomeFirstResponder];
        }

        [cell selectWithFrame: [self bounds]
                       inView: self
                       editor: NS_EXTRA(NSControl, self)->_currentEditor
                     delegate: self
                        start: range.location
                       length: range.length];
    }
}

- (void) selectText: sender {
    [self _selectTextWithRange: NSMakeRange(0, [[self stringValue] length])];
}

- (void) setPreviousText: text {
    // FIX, not sure how to implement this
    //   [self setPreviousKeyView:text];
}

- (void) setNextText: text {
    [self setNextKeyView: text];
}

- previousText {
    return [self previousKeyView];
}

- nextText {
    return [self nextKeyView];
}

- (void) validateEditing {
    if (NS_EXTRA(NSControl, self)->_currentEditor) {
        NSString *string = [NS_EXTRA(NSControl, self)->_currentEditor string];
        BOOL acceptsString = YES;
        NSFormatter *formatter = [self formatter];
        if (formatter) {
            acceptsString = NO;

            id objectValue = nil;
            NSString *error = nil;
            if ([formatter getObjectValue: &objectValue
                                forString: string
                         errorDescription: &error] == YES) {
                [[self selectedCell] setObjectValue: objectValue];
            } else {
                // Ask the delegate what to do
                SEL sel = @selector(control:
                        didFailToFormatString:errorDescription:);
                if ([_delegate respondsToSelector: sel]) {
                    acceptsString = [_delegate control: self
                                 didFailToFormatString: string
                                      errorDescription: error];
                }
            }
        }
        if (acceptsString) {
            if ([NS_EXTRA(NSControl, self)->_currentEditor isRichText]) {
                if ([NS_EXTRA(NSControl, self)->_currentEditor isKindOfClass: [NSTextView class]]) {
                    NSTextView *textview = (NSTextView *) NS_EXTRA(NSControl, self)->_currentEditor;
                    NSAttributedString *text = [textview textStorage];
                    NSAttributedString *string = [[[NSAttributedString alloc]
                            initWithAttributedString: text] autorelease];
                    [[self selectedCell] setAttributedStringValue: string];
                } else {
                    [[self selectedCell] setStringValue: string];
                }
            } else {
                [[self selectedCell] setStringValue: string];
            }
        }
    }
}

- (void) textDidEndEditing: (NSNotification *) note {

    int movement = [[[note userInfo] objectForKey: @"NSTextMovement"] intValue];

    [super textDidEndEditing: note];

    if (movement == NSReturnTextMovement ||
        [[self selectedCell] sendsActionOnEndEditing])
        [self sendAction: [self action] to: [self target]];

    if (movement == NSTabTextMovement)
        [[self window] selectKeyViewFollowingView: self];

    if (movement == NSBacktabTextMovement)
        [[self window] selectKeyViewPrecedingView: self];
}

- (void) mouseDown: (NSEvent *) event {
    NSTextFieldCell *cell = [self selectedCell];

    // A label takes no press: it goes up the responder chain, as on macOS (10.14.4 and 26.7.3; test:
    // appkit-textfield-label-mouse-down.m), so a click on a label in a table's cell reaches the table
    if (![self isEditable] && ![self isSelectable]) {
        [[self nextResponder] mouseDown: event];
        return;
    }

    if (![cell isEnabled])
        return;

    if ([[self window] firstResponder] != self) {
        // This will create our editor if needed
        [[self window] makeFirstResponder: self];
    }

    NSPoint point = [self convertPoint: [event locationInWindow] fromView: nil];
    NSRect editingFrame = [cell titleRectForBounds: [self bounds]];

    // In case we get the mouse down because we hadn't an editor yet, propagate
    // the mouse event to the editor
    if (NS_EXTRA(NSControl, self)->_currentEditor &&
        NSMouseInRect(point, editingFrame, [self isFlipped])) {
        [NS_EXTRA(NSControl, self)->_currentEditor mouseDown: event];
    } else {
        [super mouseDown: event];
    }
}

- (BOOL) textShouldBeginEditing: (NSText *) text {
    if ([_delegate respondsToSelector: @selector(control:
                                               textShouldBeginEditing:)])
        if ([_delegate control: self textShouldBeginEditing: text] == NO) {
            NSBeep();
            return NO;
        }
    return YES;
}

- (BOOL) textShouldEndEditing: (NSText *) text {
    if ([_delegate respondsToSelector: @selector(control:
                                               textShouldEndEditing:)])
        if ([_delegate control: self textShouldEndEditing: text] == NO) {
            NSBeep();
            return NO;
        }

    NSFormatter *formatter = [[self selectedCell] formatter];
    BOOL acceptsString = YES;
    if (formatter) {
        // Ask the formatter if the string is valid
        // If it's not, then we'll present an error and refuse the end of the
        // editing

        NSString *string = [text string];
        id objectValue;
        NSError *error = nil;
        if ([formatter isKindOfClass: [NSNumberFormatter class]]) {
            NSNumberFormatter *numberFormatter =
                    (NSNumberFormatter *) formatter;
            acceptsString = [numberFormatter getObjectValue: &objectValue
                                                  forString: string
                                                      range: NULL
                                                      error: &error];
        } else {
            NSString *errorString;
            if ([formatter getObjectValue: &objectValue
                                forString: string
                         errorDescription: &errorString] == NO) {

                acceptsString = NO;
                NSDictionary *info = nil;
                if (errorString == nil) {
                    // Just in case we get no error from the formatter
                    errorString = NSLocalizedStringFromTableInBundle(
                            @"Invalid number", nil,
                            [NSBundle bundleForClass: [NSTextField class]],
                            @"");
                }
                info = [NSDictionary
                        dictionaryWithObject: errorString
                                      forKey: NSLocalizedDescriptionKey];
                error = [NSError errorWithDomain: NSCocoaErrorDomain
                                            code: 2048
                                        userInfo: info];
            }
        }
        if (error) {
            [self presentError: error];
        }
    }
    return acceptsString;
}

- (void) setEditable: (BOOL) flag {
    [super setEditable: flag];
    [NS_EXTRA(NSControl, self)->_currentEditor setEditable: [self isEditable]];
}

- (void) setSelectable: (BOOL) flag {
    [super setSelectable: flag];
    [NS_EXTRA(NSControl, self)->_currentEditor setSelectable: [self isSelectable]];
}

- (void) setStringValue: (NSString *) value {
    if (!NS_EXTRA(NSControl, self)->_currentEditor)
        [super setStringValue: value];
    else {
        NSRange selectedRange = [NS_EXTRA(NSControl, self)->_currentEditor selectedRange];
        BOOL isEntireString =
                NSEqualRanges(selectedRange,
                              NSMakeRange(0, [[NS_EXTRA(NSControl, self)->_currentEditor string] length]));

        [super setStringValue: value];
        [NS_EXTRA(NSControl, self)->_currentEditor setString: [self stringValue]];
        NSRange entireString = NSMakeRange(0, [[NS_EXTRA(NSControl, self)->_currentEditor string] length]);

        if (isEntireString) {
            // NSTextField will re-select entire string on a setString: if the
            // previous value is completely selected
            [NS_EXTRA(NSControl, self)->_currentEditor setSelectedRange: entireString];
        } else {
            // otherwise it will re-select what it can
            selectedRange = NSIntersectionRange(selectedRange, entireString);

            if (selectedRange.length == 0) // 0 on intersection is undefined
                                           // location, so we have to set it
                selectedRange.location = 0;
            [NS_EXTRA(NSControl, self)->_currentEditor setSelectedRange: entireString];
        }
    }
}

- (void) setFont: (NSFont *) font {
    // Don't do extra work if we don't need to...
    if (font != [self font]) {
        [super setFont: font];
        [NS_EXTRA(NSControl, self)->_currentEditor setFont: [self font]];
    }
}

- (void) setAlignment: (NSTextAlignment) alignment {
    [super setAlignment: alignment];
    [NS_EXTRA(NSControl, self)->_currentEditor setAlignment: [self alignment]];
}

- (void) setRefusesFirstResponder: (BOOL) flag {
    [_cell setRefusesFirstResponder: flag];
}

- (void) doCommandBySelector: (SEL) selector {
    BOOL didSelector = NO;

    if ([_delegate respondsToSelector: @selector(control:
                                                textView:doCommandBySelector:)])
        didSelector = [_delegate control: self
                                textView: (NSTextView *) NS_EXTRA(NSControl, self)->_currentEditor
                     doCommandBySelector: selector];

    if (!didSelector)
        [super doCommandBySelector: selector];
}

- (void) setTitleWithMnemonic: (NSString *) value {
    [self setStringValue: value];
}

@end

@implementation NSTextField (Bindings)

- (CGFloat) _fontSize {
    return [(NSTextFieldCell *) _cell _fontSize];
}
- (void) _setFontSize: (CGFloat) fontSize {
    [(NSTextFieldCell *) _cell _setFontSize: fontSize];
}
- (NSString *) _fontFamilyName {
    return [(NSTextFieldCell *) _cell _fontFamilyName];
}
- (void) _setFontFamilyName: (NSString *) familyName {
    [(NSTextFieldCell *) _cell _setFontFamilyName: familyName];
}

@end
