#import <AppKit/NSPathCell.h>

#import <AppKit/AppKit.h>
#import <AppKit/NSPathComponentCell.h>

#import "AppKit/NSRaise.h"

@implementation NSPathCell

- initWithCoder: (NSCoder *) coder {
    self = [super initWithCoder: coder];
    if (self) {
        if (![coder allowsKeyedCoding]) {
            [NSException raise: NSInvalidArgumentException
                        format: @"%@ can not initWithCoder:%@", [self class],
                                [coder class]];
        }

        // The one key holds either a plain string or an attributed string, whichever the cell had.
        id placeholder = [coder decodeObjectForKey: @"NSPlaceholderString"];

        if ([placeholder isKindOfClass: [NSAttributedString class]])
            [self setPlaceholderAttributedString: placeholder];
        else
            [self setPlaceholderString: placeholder];
        [self setBackgroundColor:
                        [coder decodeObjectForKey: @"NSBackgroundColor"]];
        [self setPathComponentCells:
                        [coder decodeObjectForKey: @"NSPathComponentCells"]];
        [self setPathStyle: [coder decodeIntForKey: @"NSPathStyle"]];
        _delegate = [coder decodeObjectForKey: @"NSDelegate"];
        [self setAllowedTypes: [coder decodeObjectForKey: @"NSAllowedTypes"]];
    }

    return self;
}

- (void) dealloc {
    [_URL release];
    [_pathComponentCells release];
    [_backgroundColor release];
    [_allowedTypes release];
    [_placeholder release];
    [super dealloc];
}

- (void) mouseEntered: (NSEvent *) event
            withFrame: (NSRect) frame
               inView: (NSView *) view
{
    NSUnimplementedMethod();
}

- (void) mouseExited: (NSEvent *) event
           withFrame: (NSRect) frame
              inView: (NSView *) view
{
    NSUnimplementedMethod();
}

- (NSArray *) allowedTypes {
    return _allowedTypes;
}

- (void) setAllowedTypes: (NSArray *) value {
    value = [value copy];
    [_allowedTypes release];
    _allowedTypes = value;
}

- (NSPathStyle) pathStyle {
    return _pathStyle;
}

- (void) setPathStyle: (NSPathStyle) style {
    _pathStyle = style;
    [[self controlView] setNeedsDisplay: YES];
}

- objectValue {
    return [self URL];
}

- (void) setObjectValue: (id<NSCopying>) valueX {
    id value = (id) valueX;

    if ([(id) value isKindOfClass: [NSURL class]])
        [self setURL: (id) value];
    else if ([(id) value isKindOfClass: [NSString class]])
        [self setURL: [NSURL fileURLWithPath: (id) value]];

    [NSException raise: NSInvalidArgumentException
                format: @"-[%@ %s] only accepts URL's and strings, class=%@",
                        [self class], _cmd, [(id) value class]];
}

// A cell has one placeholder, a plain string or an attributed string: setting either replaces what was there (a
// nil clears it whichever kind it was), and each getter answers nil while the placeholder is of the other kind.
// Not documented (the documentation only says the attributed string is drawn when it is not nil and the plain one
// with default attributes otherwise). Evidence: black-box observation on macOS 26.7.3 and 10.14.4 (x86_64 and
// i386) (tier 2), probes p765.m and p765b.m of batch 12a in mac-probes/cristim; the archive holds the one object
// under the key NSPlaceholderString.
// Test: appkit-pathcell-nil-placeholder (test_quirk_pathcell_has_one_placeholder)
- (NSAttributedString *) placeholderAttributedString {
    return [_placeholder isKindOfClass: [NSAttributedString class]] ? _placeholder : nil;
}

- (void) setPlaceholderAttributedString: (NSAttributedString *) value {
    value = [value copy];
    [_placeholder release];
    _placeholder = value;
}

- (NSString *) placeholderString {
    return [_placeholder isKindOfClass: [NSString class]] ? _placeholder : nil;
}

// The documented property is optional: nil clears the placeholder, and it is the
// normal value of a cell decoded from an archive that has none.
- (void) setPlaceholderString: (NSString *) string {
    string = [string copy];
    [_placeholder release];
    _placeholder = string;
}

- (NSColor *) backgroundColor {
    return _backgroundColor;
}

- (void) setBackgroundColor: (NSColor *) color {
    color = [color copy];
    [_backgroundColor release];
    _backgroundColor = color;
}

+ (Class) pathComponentCellClass {
    return [NSPathComponentCell class];
}

- (NSRect) rectOfPathComponentCell: (NSPathComponentCell *) cell
                         withFrame: (NSRect) frame
                            inView: (NSView *) view
{
    NSRect rect = frame;

    for (NSPathComponentCell *check in _pathComponentCells) {
        rect.size.width = [check cellSize].width;

        if (cell == check)
            return rect;

        switch ([self pathStyle]) {
        case NSPathStyleStandard:
            rect.origin.x += rect.size.width;
            break;

        case NSPathStyleNavigationBar:
            // Navigation style components butt up against each other
            rect.origin.x += rect.size.width;
            break;

        case NSPathStylePopUp:
            break;
        }
    }

    return NSZeroRect;
}

- (NSPathComponentCell *) pathComponentCellAtPoint: (NSPoint) point
                                         withFrame: (NSRect) frame
                                            inView: (NSView *) view
{

    for (NSPathComponentCell *cell in _pathComponentCells) {
        NSRect checkFrame = [self rectOfPathComponentCell: cell
                                                withFrame: frame
                                                   inView: view];

        if (NSMouseInRect(point, checkFrame, [view isFlipped]))
            return cell;
    }

    return nil;
}

- (BOOL) trackMouse: (NSEvent *) event
              inRect: (NSRect) cellFrame
              ofView: (NSView *) controlView
        untilMouseUp: (BOOL) untilMouseUp
{

    do {
        NSPoint point = [controlView convertPoint: [event locationInWindow]
                                         fromView: nil];

        [_clickPathComponentCell release];
        _clickPathComponentCell =
                [[self pathComponentCellAtPoint: point
                                      withFrame: cellFrame
                                         inView: controlView] retain];

        [controlView setNeedsDisplay: YES];

        event = [[controlView window]
                nextEventMatchingMask: NSLeftMouseUpMask |
                                       NSLeftMouseDraggedMask];

    } while ([event type] != NSLeftMouseUp);

    return (_clickPathComponentCell != nil);
}

- (NSPathComponentCell *) clickedPathComponentCell {
    return _clickPathComponentCell;
}

- (NSArray *) pathComponentCells {
    return _pathComponentCells;
}

- (void) setPathComponentCells: (NSArray *) cells {
    cells = [cells retain];
    [_pathComponentCells release];
    _pathComponentCells = cells;

    [_clickPathComponentCell release];
    _clickPathComponentCell = nil;

    [[self controlView] setNeedsDisplay: YES];
}

- (SEL) doubleAction {
    return _doubleAction;
}

- (void) setDoubleAction: (SEL) action {
    _doubleAction = action;
}

- (NSURL *) URL {
    return _URL;
}

- (void) setURL: (NSURL *) url {
    url = [url copy];
    [_URL release];
    _URL = url;

    NSMutableArray *cells = [NSMutableArray array];

    if (url != nil) {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSWorkspace *ws = [NSWorkspace sharedWorkspace];
        BOOL isFileURL = [url isFileURL];
        NSString *host = [url host];
        NSString *path = [url path];
        NSString *scheme = [url scheme];
        Class pcClass = [[self class] pathComponentCellClass];

        NSArray *pathComponents = [path pathComponents];
        NSMutableString *currentPath = [NSMutableString string];

        for (NSString *path in pathComponents) {
            [currentPath appendString: @"/"];
            [currentPath appendString: path];

            NSURL *currentURL =
                    [[[NSURL alloc] initWithScheme: scheme
                                              host: host
                                              path: currentPath] autorelease];
            NSString *title;
            NSImage *image;

            if (isFileURL) {
                title = [fm displayNameAtPath: currentPath];
                image = [ws iconForFile: currentPath];
            } else {
                title = [path stringByReplacingPercentEscapesUsingEncoding:
                                      NSUTF8StringEncoding];
                image = nil;
            }

            NSPathComponentCell *cell =
                    [[[pcClass alloc] initTextCell: @""] autorelease];
            [cell setURL: currentURL];
            [cell setImage: image];
            [cell setStringValue: title];

            [cells addObject: cell];
        }
    }

    [self setPathComponentCells: cells];
}

- delegate {
    return _delegate;
}

- (void) setDelegate: (id) delegate {
    _delegate = delegate;
}

- (void) drawWithFrame: (NSRect) frame inView: (NSView *) view {
    if (_backgroundColor != nil) {
        [_backgroundColor set];
        [NSBezierPath fillRect: frame];
    }

    // Draw them last to first to get the proper overlapping arrows drawing

    NSInteger count = [_pathComponentCells count];

    while (--count >= 0) {
        NSPathComponentCell *cell = [_pathComponentCells objectAtIndex: count];
        NSRect cellFrame = [self rectOfPathComponentCell: cell
                                               withFrame: frame
                                                  inView: view];
        [cell drawWithFrame: cellFrame inView: view];
    }
}

@end