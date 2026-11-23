/* Copyright (c) 2006-2007 Christopher J. W. Lloyd <cjwl@objc.net>

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

#import "NSViewLayoutInternal.h"
#import <AppKit/NSApplication.h>
#import <AppKit/NSButton.h>
#import <AppKit/NSButtonCell.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSController.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSFontManager.h>
#import <AppKit/NSRaise.h>
#import <AppKit/NSKeyEquivalentMatching.h>
#import <AppKit/NSTrackingArea.h>
#import <AppKit/NSWindow.h>

@interface NSButtonCell (NSButtonBorderTracking)
- (void) _setMouseInside: (BOOL) inside;
@end

@interface NSButtonCell (NSButtonAlignmentPrivate)
- (BOOL) _hasStockRoundedPushBezel;
- (NSEdgeInsets) _roundedPushAlignmentInsets;
- (int) _stockToggleKind;
- (NSEdgeInsets) _toggleAlignmentInsets;
@end

@interface NSButtonCell (NSButtonLayoutPriorities)
- (BOOL) _isStockToggleImage: (NSImage *) image;
@end

static NSString *const NSButtonBorderTrackingKey = @"NSButtonBorderTracking";

@implementation NSButton

// Operated at once: the click that activates the window is delivered to it
// (see -[NSWindow sendEvent:]).
- (BOOL) acceptsFirstMouse: (NSEvent *) event {
    return YES;
}

// A button's hugging follows its look until a priority is set: check boxes, radio buttons and
// borderless buttons hug like plain views; bezels drawn at a fixed height hug vertically, and
// those drawn at a fixed size hug in both directions.
// QUIRK: macOS changed the default for a few bezels. On macOS 10.14.4 a button without a bezel
// style (0) hugs at DefaultLow and textured square, small square and inline bezels at
// DefaultHigh; macOS 26.7.3 has it the other way round. We follow 10.14, which more applications
// were laid out against. Evidence: black-box observation, also of binaries linked against the
// 10.13 SDK on 26.7.3 (tier 2). Test: appkit-control-hugging-defaults.
- (NSLayoutPriority) _defaultContentHuggingPriorityForOrientation: (NSLayoutConstraintOrientation) orientation {
    NSButtonCell *cell = [self cell];

    if (![cell isKindOfClass: [NSButtonCell class]] || ![cell isBordered] ||
        [cell _isStockToggleImage: [cell image]])
        return NSLayoutPriorityDefaultLow;

    switch ([cell bezelStyle]) {
    case NSBezelStyleDisclosure:
    case NSBezelStyleCircular:
    case NSBezelStyleHelpButton:
    case NSBezelStyleRoundedDisclosure:
        return NSLayoutPriorityDefaultHigh;
    case NSBezelStyleRounded:
    case NSBezelStyleTexturedRounded:
    case NSBezelStyleRoundRect:
    case NSBezelStyleRecessed:
    case NSBezelStyleTexturedSquare:
    case NSBezelStyleSmallSquare:
    case NSBezelStyleInline:
        return orientation == NSLayoutConstraintOrientationVertical ? NSLayoutPriorityDefaultHigh : NSLayoutPriorityDefaultLow;
    default:
        return NSLayoutPriorityDefaultLow;
    }
}


+ (Class) cellClass {
    return [NSButtonCell class];
}

+ (instancetype) _buttonWithType: (NSButtonType) type
                           title: (NSString *) title
                           image: (NSImage *) image
                   imagePosition: (NSCellImagePosition) position
                          target: (id) target
                          action: (SEL) action
{
    NSButton *button = [[[self alloc] initWithFrame: NSZeroRect] autorelease];
    [button setButtonType: type];
    if (type == NSMomentaryPushInButton)
        [button setBezelStyle: NSRoundedBezelStyle];
    [button setTitle: title ? title : @""];
    if (image != nil) {
        [button setImage: image];
        [button setImagePosition: position];
    }
    [button setTarget: target];
    [button setAction: action];
    [button sizeToFit];
    return button;
}

+ (instancetype) buttonWithImage: (NSImage *) image target: (id) target action: (SEL) action {
    return [self _buttonWithType: NSMomentaryPushInButton title: nil image: image
                   imagePosition: NSImageOnly target: target action: action];
}

+ (instancetype) buttonWithTitle: (NSString *) title target: (id) target action: (SEL) action {
    return [self _buttonWithType: NSMomentaryPushInButton title: title image: nil
                   imagePosition: NSNoImage target: target action: action];
}

+ (instancetype) buttonWithTitle: (NSString *) title image: (NSImage *) image target: (id) target action: (SEL) action {
    return [self _buttonWithType: NSMomentaryPushInButton title: title image: image
                   imagePosition: NSImageLeft target: target action: action];
}

+ (instancetype) checkboxWithTitle: (NSString *) title target: (id) target action: (SEL) action {
    return [self _buttonWithType: NSSwitchButton title: title image: nil
                   imagePosition: NSNoImage target: target action: action];
}

+ (instancetype) radioButtonWithTitle: (NSString *) title target: (id) target action: (SEL) action {
    return [self _buttonWithType: NSRadioButton title: title image: nil
                   imagePosition: NSNoImage target: target action: action];
}

- initWithCoder: (NSCoder *) coder {
    [super initWithCoder: coder];

    if ([[self cell] controlSize] == NSMiniControlSize) {
        NSRect frame = [self frame];
        if (frame.size.height < 18) {
            frame.size.height = 18;
            frame.origin.y -= 1;
            [self setFrame: frame];
        }
    }

    return self;
}

- (void) dealloc {
    // The window may still hold a collected tracking area for a moment.
    [self _removeBorderTrackingAreas];
    if (NS_EXTRA_ALLOCATED(NSButton, self)) {
        [NS_EXTRA(NSButton, self)->_contentTintColor release];
    }
    [super dealloc];
}

- (BOOL) resignFirstResponder {
    [self setNeedsDisplay: YES];
    return [super resignFirstResponder];
}

- (BOOL) isFlipped {
    return YES;
}

// A rounded push button is laid out by its bezel, not by its frame, which also holds the room for the
// bezel's shadow (see -[NSButtonCell _roundedPushAlignmentInsets]).
- (NSEdgeInsets) alignmentRectInsets {
    NSButtonCell *cell = [self cell];

    if ([cell isKindOfClass: [NSButtonCell class]] && [cell _hasStockRoundedPushBezel])
        return [cell _roundedPushAlignmentInsets];
    if ([cell isKindOfClass: [NSButtonCell class]] && [cell _stockToggleKind] != 0 &&
        [cell imagePosition] == NSImageLeft)
        return [cell _toggleAlignmentInsets];
    return [super alignmentRectInsets];
}
- (BOOL) isOpaque {
    return [_cell isOpaque];
}

- (BOOL) isTransparent {
    return [_cell isTransparent];
}

- (NSString *) keyEquivalent {
    return [_cell keyEquivalent];
}

- (NSEventModifierFlags) keyEquivalentModifierMask {
    return [_cell keyEquivalentModifierMask];
}

- (NSImage *) image {
    return [_cell image];
}

- (NSCellImagePosition) imagePosition {
    return [_cell imagePosition];
}

- (NSImageScaling) imageScaling {
    return [_cell imageScaling];
}

- (void) setImageScaling: (NSImageScaling) value {
    [_cell setImageScaling: value];
}

- (NSString *) title {
    return [_cell title];
}

- (NSControlStateValue) state {
    return [_cell state];
}

- (BOOL) allowsMixedState {
    return [_cell allowsMixedState];
}

- (NSSound *) sound {
    return [_cell sound];
}

- (NSBezelStyle) bezelStyle {
    return [_cell bezelStyle];
}

- (NSString *) alternateTitle {
    return [_cell alternateTitle];
}

- (NSImage *) alternateImage {
    return [_cell alternateImage];
}

- (NSAttributedString *) attributedTitle {
    return [_cell attributedTitle];
}

- (NSAttributedString *) attributedAlternateTitle {
    return [_cell attributedAlternateTitle];
}

- (BOOL) showsBorderOnlyWhileMouseInside {
    return [_cell showsBorderOnlyWhileMouseInside];
}

- (void) getPeriodicDelay: (float *) delay interval: (float *) interval {
    NSUnimplementedMethod();
}

- (void) setTransparent: (BOOL) value {
    [_cell setTransparent: value];
    [self setNeedsDisplay: YES];
}

/* QUIRK: a button whose key equivalent is Return becomes the window's default button without a call to
   -setDefaultButtonCell:: when it is added to a window that has no default button yet (a second such button
   added later does not take over), and when its key equivalent is set to Return while it is in a window (this
   replaces an earlier default button). Not documented. Evidence: black-box observation on macOS 10.14.4 and
   26.7.3 (tier 2). Test: appkit-button-aqua.m */
- (void) _adoptAsDefaultButtonIfReturn: (BOOL) replace {
    NSWindow *window = [self window];

    if (window != nil && (replace || [window defaultButtonCell] == nil) &&
        [_cell isKindOfClass: [NSButtonCell class]] && [[_cell keyEquivalent] isEqualToString: @"\r"] &&
        [_cell keyEquivalentModifierMask] == 0 && [window defaultButtonCell] != _cell)
        [window setDefaultButtonCell: _cell];
}

- (void) viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    [self _adoptAsDefaultButtonIfReturn: NO];
}

- (void) setKeyEquivalent: (NSString *) value {
    [_cell setKeyEquivalent: value];
    [self _adoptAsDefaultButtonIfReturn: YES];
    [self setNeedsDisplay: YES];
}

- (void) setKeyEquivalentModifierMask: (NSEventModifierFlags) value {
    [_cell setKeyEquivalentModifierMask: value];
}

- (void) setImage: (NSImage *) value {
    [_cell setImage: value];
    [self invalidateIntrinsicContentSize];
    [self setNeedsDisplay: YES];
}

- (void) setImagePosition: (NSCellImagePosition) value {
    [_cell setImagePosition: value];
    [self invalidateIntrinsicContentSize];
    [self setNeedsDisplay: YES];
}

- (void) setTitle: (NSString *) value {
    NSString *before = [[_cell title] retain];

    [_cell setTitle: value];
    if (!(before == [_cell title] || [before isEqual: [_cell title]]))
        [self invalidateIntrinsicContentSize];
    [before release];
    [self setNeedsDisplay: YES];
}

- (void) setState: (NSControlStateValue) value {
    [_cell setState: value];
    [self setNeedsDisplay: YES];
}

- (void) setNextState {
    [_cell setNextState];
    [self setNeedsDisplay: YES];
}

- (void) setAllowsMixedState: (BOOL) flag {
    [_cell setAllowsMixedState: flag];
}

- (void) setSound: (NSSound *) sound {
    [_cell setSound: sound];
}

- (void) setBezelStyle: (NSBezelStyle) value {
    [_cell setBezelStyle: value];
    [self invalidateIntrinsicContentSize];
    [self setNeedsDisplay: YES];
}

- (void) setAlternateTitle: (NSString *) value {
    [_cell setAlternateTitle: value];
    [self invalidateIntrinsicContentSize];
    [self setNeedsDisplay: YES];
}

- (void) setAlternateImage: (NSImage *) value {
    [_cell setAlternateImage: value];
    [self invalidateIntrinsicContentSize];
    [self setNeedsDisplay: YES];
}

- (void) setAttributedTitle: (NSAttributedString *) value {
    [_cell setAttributedTitle: value];
    [self invalidateIntrinsicContentSize];
    [self setNeedsDisplay: YES];
}

- (void) setAttributedAlternateTitle: (NSAttributedString *) value {
    [_cell setAttributedAlternateTitle: value];
    [self invalidateIntrinsicContentSize];
    [self setNeedsDisplay: YES];
}

- (void) setCell: (id) cell {
    [super setCell: cell];
    [self updateTrackingAreas];
}

- (void) setShowsBorderOnlyWhileMouseInside: (BOOL) value {
    [_cell setShowsBorderOnlyWhileMouseInside: value];
    [self updateTrackingAreas];
    [self setNeedsDisplay: YES];
}

// A button whose border shows only while the pointer is over it watches the pointer and tells its cell
// (see -updateTrackingAreas).
- (void) _removeBorderTrackingAreas {
    for (NSTrackingArea *area in [self trackingAreas]) {
        if ([[area userInfo] objectForKey: NSButtonBorderTrackingKey] != nil)
            [self removeTrackingArea: area];
    }
}

- (void) setBordered: (BOOL) flag {
    [super setBordered: flag];
    [self updateTrackingAreas];
}

// Called when the flag, the cell or the border changes, and by the view whenever it moved or resized (itself or
// an ancestor) or went to another window: the area is then replaced by a new one that never saw the pointer come
// in, so the cell is told where the pointer is now.
//
// Observed on macOS 26.7.3: the area belongs to a button that shows its border only while the pointer is over it
// and is bordered (none for a button without a border), its owner is the cell, its rectangle the button's bounds,
// and its options mouse-entered-and-exited and active-always (not in-visible-rect), so it works while the
// application is inactive; the button itself does not react to entered and exited events, the cell does. A pointer
// that is over the button when the area is made counts as inside, also when the application is inactive.
// Not reproduced: macOS makes the area only at the next tracking area update, so right after the flag is set the
// border stays hidden there even with the pointer over the button.
// Test: appkit-button-border-only-while-mouse-inside.
- (void) updateTrackingAreas {
    [super updateTrackingAreas];
    [self _removeBorderTrackingAreas];
    if (![_cell isKindOfClass: [NSButtonCell class]] || ![_cell showsBorderOnlyWhileMouseInside] || ![_cell isBordered])
        return;

    NSTrackingArea *area = [[NSTrackingArea alloc]
            initWithRect: [self bounds]
                 options: NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways
                   owner: _cell
                userInfo: [NSDictionary dictionaryWithObject: [NSNumber numberWithBool: YES]
                                                      forKey: NSButtonBorderTrackingKey]];
    [self addTrackingArea: area];
    [area release];

    BOOL inside = NO;
    if ([self window] != nil) {
        NSPoint point = [self convertPoint: [[self window] mouseLocationOutsideOfEventStream] fromView: nil];
        inside = NSMouseInRect(point, [self bounds], [self isFlipped]);
    }
    [_cell _setMouseInside: inside];
}

- (void) setButtonType: (NSButtonType) value {
    [_cell setButtonType: value];
    [self invalidateIntrinsicContentSize];
    [self setNeedsDisplay: YES];
}

- (void) setTitleWithMnemonic: (NSString *) value {
    NSUnimplementedMethod();
}

- (void) setPeriodicDelay: (float) delay interval: (float) interval {
    NSUnimplementedMethod();
}

- (void) highlight: (BOOL) value {
    [self lockFocus];
    [_cell highlight: value withFrame: [self bounds] inView: self];
    [self unlockFocus];
    [[self window] flushWindow];
}

- (BOOL) performKeyEquivalent: (NSEvent *) event {
    if (![self isEnabled])
        return NO;

    if (NSKeyEquivalentMatchesEvent([self keyEquivalent],
                                    [self keyEquivalentModifierMask], event)) {
        [self performClick: nil];
        return YES;
    }

    return NO;
}

- (void) performClick: sender {
    [self highlight: YES];

    [[self cell] setState: [[self cell] nextState]];

    [self sendAction: [self action] to: [self target]];

    [self highlight: NO];
}

- (void) keyDown: (NSEvent *) event {
    // " " is a key equivalent to clicking
    if ([[event charactersIgnoringModifiers] isEqualToString: @" "]) {
        [self performClick: nil];
    } else {
        [self interpretKeyEvents: [NSArray arrayWithObject: event]];
    }
}

- (NSColor *) _borderColorForNSShowAllViews {
    return [NSColor cyanColor];
}

@end

@implementation NSButton (BindingSupport)

- (void) _setFontFamilyName: (NSString *) familyName {
    // Bail if it's any of the objects we don't grok
    if (familyName == nil || familyName == NSNoSelectionMarker ||
        familyName == NSMultipleValuesMarker ||
        familyName == NSNotApplicableMarker) {
        return;
    }

    NSFont *currentFont = [self font];
    CGFloat size = [currentFont pointSize];

    NSFont *newFont =
            [[NSFontManager sharedFontManager] fontWithFamily: familyName
                                                       traits: 0
                                                       weight: 5
                                                         size: size];
    if (newFont != nil) {
        [self setFont: newFont];
    }
}

@end

@implementation NSButton (NSButtonContentTint)

- (NSColor *) contentTintColor {
    return NS_EXTRA(NSButton, self)->_contentTintColor;
}

- (void) setContentTintColor: (NSColor *) color {
    color = [color copy];
    [NS_EXTRA(NSButton, self)->_contentTintColor release];
    NS_EXTRA(NSButton, self)->_contentTintColor = color;
}

@end

@implementation NSButton (NSDestructiveAction)

- (BOOL) hasDestructiveAction {
    return NS_EXTRA(NSButton, self)->_hasDestructiveAction;
}

- (void) setHasDestructiveAction: (BOOL) value {
    NS_EXTRA(NSButton, self)->_hasDestructiveAction = value;
}

@end
