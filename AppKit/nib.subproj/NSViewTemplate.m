/*
 * Copyright (C) 2026 Lubos Dolezel
 */
#import "NSViewTemplate.h"
#import <AppKit/NSAttributedString.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSText.h>
#import <AppKit/NSTextContainer.h>
#import <AppKit/NSTextView.h>
#import <Foundation/NSKeyedArchiver.h>

// A size archived as two floats (the size members are doubles here).
static void decodeSize(NSCoder *coder, NSSize *size)
{
    float width = 0, height = 0;

    [coder decodeValuesOfObjCTypes: "ff", &width, &height];
    *size = NSMakeSize(width, height);
}

@implementation NSViewTemplate

- (NSString *) className {
    return _className;
}

- (void) setClassName: (NSString *) className {
    className = [className copy];
    [_className release];
    _className = className;
}

- (id) initWithCoder: (NSCoder *) coder {
    if ((self = [super initWithCoder: coder]) == nil)
        return nil;

    if ([coder allowsKeyedCoding]) {
        [self release];
        [NSException raise: NSInvalidArgumentException
                    format: @"-[%@ %s] is not implemented for coder %@", [self class], sel_getName(_cmd), coder];
    }

    // After the view: the name of the class of the real view.
    id className = [coder decodeObject];
    _className = [className isKindOfClass: [NSString class]] ? [className copy] : nil;
    return self;
}

- (void) encodeWithCoder: (NSCoder *) coder {
    [NSException raise: NSInvalidArchiveOperationException format: @"support for encoding %@ is not implemented", [self class]];
}

- (void) dealloc {
    [_className release];
    [super dealloc];
}

// The class of the real view; one that is not known gives a plain view.
- (Class) _realClass {
    Class cls = _className != nil ? NSClassFromString(_className) : Nil;

    return (cls != Nil && [cls isSubclassOfClass: [NSView class]]) ? cls : [NSView class];
}

// Makes the real view with the geometry of the template and takes over its subviews.
- (id) createRealObject {
    NSView *real = [[[self _realClass] alloc] initWithFrame: [self frame]];

    [real setAutoresizingMask: [self autoresizingMask]];
    [real setAutoresizesSubviews: [self autoresizesSubviews]];
    for (NSView *subview in [[[self subviews] copy] autorelease]) {
        [subview retain];
        [subview removeFromSuperview];
        [real addSubview: subview];
        [subview release];
    }
    return real;
}

- (id) awakeAfterUsingCoder: (NSCoder *) coder {
    return [[self createRealObject] autorelease];
}

@end

// Contents are archived as the RTFD form of the text.
static NSAttributedString *attributedStringFromTemplateContents(id contents) {
    if ([contents isKindOfClass: [NSAttributedString class]])
        return contents;
    if ([contents isKindOfClass: [NSString class]])
        return [[[NSAttributedString alloc] initWithString: contents] autorelease];
    if (![contents isKindOfClass: [NSData class]])
        return nil;

    // Plain RTF text starts with a brace; anything else is taken as RTFD data.
    NSAttributedString *text = nil;
    if ([contents length] >= 5 && memcmp([contents bytes], "{\\rtf", 5) == 0)
        text = [[[NSAttributedString alloc] initWithRTF: contents documentAttributes: NULL] autorelease];
    if (text == nil)
        text = [[[NSAttributedString alloc] initWithRTFD: contents documentAttributes: NULL] autorelease];
    return text;
}

@implementation NSTextViewTemplate

- (id) initWithCoder: (NSCoder *) coder {
    // The class version is asked before the superclass part is decoded.
    NSInteger version = [coder allowsKeyedCoding] ? 0 : [coder versionForClassName: @"NSTextViewTemplate"];

    if ((self = [super initWithCoder: coder]) == nil)
        return nil;

    // The contents, background colour, selected text attributes and insertion point colour
    // follow the class name, then three sizes (the container, the minimum and the maximum)
    // and the delegate; then one byte per flag (the last, allows undo, from version 454)
    // and, from version 105, the typing attributes.
    _contents = [[coder decodeObject] retain];
    _backgroundColor = [[coder decodeObject] retain];
    _selectedTextAttributes = [[coder decodeObject] retain];
    _insertionPointColor = [[coder decodeObject] retain];
    decodeSize(coder, &_containerSize);
    decodeSize(coder, &_minSize);
    decodeSize(coder, &_maxSize);
    _delegate = [coder decodeObject];

    char flags[14] = { 0 };
    int count = version >= 454 ? 14 : 13;
    for (int i = 0; i < count; i++)
        [coder decodeValuesOfObjCTypes: "c", &flags[i]];
    _flags.drawsBackground = flags[0] != 0;
    _flags.selectable = flags[1] != 0;
    _flags.editable = flags[2] != 0;
    _flags.richText = flags[3] != 0;
    _flags.importsGraphics = flags[4] != 0;
    _flags.horizontallyResizable = flags[5] != 0;
    _flags.verticallyResizable = flags[6] != 0;
    _flags.fieldEditor = flags[7] != 0;
    _flags.usesFontPanel = flags[8] != 0;
    _flags.rulerVisible = flags[9] != 0;
    _flags.containerTracksWidth = flags[10] != 0;
    _flags.containerTracksHeight = flags[11] != 0;
    _flags.usesRuler = flags[12] != 0;
    _flags.allowsUndo = flags[13] != 0;

    if (version >= 105)
        _typingAttributes = [[coder decodeObject] retain];
    return self;
}

- (void) dealloc {
    [_contents release];
    [_backgroundColor release];
    [_selectedTextAttributes release];
    [_insertionPointColor release];
    [_typingAttributes release];
    [super dealloc];
}

- (id) createRealObject {
    NSTextView *tv = [[NSTextView alloc] initWithFrame: [self frame]];
    NSTextContainer *container = [tv textContainer];

    [tv setAutoresizingMask: [self autoresizingMask]];
    [tv setAutoresizesSubviews: [self autoresizesSubviews]];

    [tv setRichText: _flags.richText];
    [tv setImportsGraphics: _flags.importsGraphics];
    [tv setEditable: _flags.editable];
    [tv setSelectable: _flags.selectable || _flags.editable];
    [tv setFieldEditor: _flags.fieldEditor];
    [tv setUsesFontPanel: _flags.usesFontPanel];
    [tv setUsesRuler: _flags.usesRuler];
    [tv setRulerVisible: _flags.rulerVisible];
    [tv setAllowsUndo: _flags.allowsUndo];
    [tv setDrawsBackground: _flags.drawsBackground];
    if (_backgroundColor != nil)
        [tv setBackgroundColor: _backgroundColor];
    if (_insertionPointColor != nil)
        [tv setInsertionPointColor: _insertionPointColor];
    if (_selectedTextAttributes != nil)
        [tv setSelectedTextAttributes: _selectedTextAttributes];
    if (_typingAttributes != nil)
        [tv setTypingAttributes: _typingAttributes];

    [tv setMinSize: _minSize];
    [tv setMaxSize: _maxSize];
    [tv setHorizontallyResizable: _flags.horizontallyResizable];
    [tv setVerticallyResizable: _flags.verticallyResizable];
    [container setContainerSize: _containerSize];
    [container setWidthTracksTextView: _flags.containerTracksWidth];
    [container setHeightTracksTextView: _flags.containerTracksHeight];

    NSAttributedString *text = attributedStringFromTemplateContents(_contents);
    if (text != nil)
        [[tv textStorage] setAttributedString: text];

    if (_delegate != nil)
        [tv setDelegate: _delegate];

    for (NSView *subview in [[[self subviews] copy] autorelease]) {
        [subview retain];
        [subview removeFromSuperview];
        [tv addSubview: subview];
        [subview release];
    }
    return tv;
}

@end

@implementation NSTextTemplate

- (id) initWithCoder: (NSCoder *) coder {
    NSInteger version = [coder allowsKeyedCoding] ? 0 : [coder versionForClassName: @"NSTextTemplate"];

    if ((self = [super initWithCoder: coder]) == nil)
        return nil;

    // Contents, text colour and font follow the class name, then the alignment as an
    // int, the background colour, two sizes and the delegate; then one byte per flag
    // (the last, allows undo, from version 454).
    _contents = [[coder decodeObject] retain];
    _textColor = [[coder decodeObject] retain];
    _font = [[coder decodeObject] retain];
    int alignment;
    [coder decodeValueOfObjCType: "i" at: &alignment];
    _alignment = alignment;
    _backgroundColor = [[coder decodeObject] retain];
    decodeSize(coder, &_minSize);
    decodeSize(coder, &_maxSize);
    _delegate = [coder decodeObject];

    char flags[11] = { 0 };
    int count = version >= 454 ? 11 : 10;
    for (int i = 0; i < count; i++)
        [coder decodeValuesOfObjCTypes: "c", &flags[i]];
    _flags.drawsBackground = flags[0] != 0;
    _flags.selectable = flags[1] != 0;
    _flags.editable = flags[2] != 0;
    _flags.richText = flags[3] != 0;
    _flags.importsGraphics = flags[4] != 0;
    _flags.horizontallyResizable = flags[5] != 0;
    _flags.verticallyResizable = flags[6] != 0;
    _flags.fieldEditor = flags[7] != 0;
    _flags.usesFontPanel = flags[8] != 0;
    _flags.rulerVisible = flags[9] != 0;
    _flags.allowsUndo = flags[10] != 0;
    return self;
}

- (void) dealloc {
    [_contents release];
    [_textColor release];
    [_font release];
    [_backgroundColor release];
    [super dealloc];
}

// The real object is a text view in either case.
- (id) createRealObject {
    NSTextView *tv = [[NSTextView alloc] initWithFrame: [self frame]];

    [tv setAutoresizingMask: [self autoresizingMask]];
    [tv setRichText: _flags.richText];
    [tv setImportsGraphics: _flags.importsGraphics];
    [tv setEditable: _flags.editable];
    [tv setSelectable: _flags.selectable || _flags.editable];
    [tv setFieldEditor: _flags.fieldEditor];
    [tv setUsesFontPanel: _flags.usesFontPanel];
    [tv setRulerVisible: _flags.rulerVisible];
    [tv setAllowsUndo: _flags.allowsUndo];
    [tv setDrawsBackground: _flags.drawsBackground];
    if (_backgroundColor != nil)
        [tv setBackgroundColor: _backgroundColor];
    [tv setMinSize: _minSize];
    [tv setMaxSize: _maxSize];
    [tv setHorizontallyResizable: _flags.horizontallyResizable];
    [tv setVerticallyResizable: _flags.verticallyResizable];

    NSAttributedString *text = attributedStringFromTemplateContents(_contents);
    if (text != nil)
        [[tv textStorage] setAttributedString: text];
    if (_textColor != nil)
        [tv setTextColor: _textColor];
    if (_font != nil)
        [tv setFont: _font];
    [tv setAlignment: (NSTextAlignment) _alignment];
    if (_delegate != nil)
        [tv setDelegate: _delegate];
    return tv;
}

@end
