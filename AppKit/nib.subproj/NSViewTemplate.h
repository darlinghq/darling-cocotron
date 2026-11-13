/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * Placeholders for views in NSArchiver nibs: the archive holds the class name of the
 * real view and the geometry; unarchiving a template yields the real object.
 */
#import <AppKit/NSView.h>

@class NSColor, NSFont;

@interface NSViewTemplate : NSView {
    NSString *_className;
}

- (NSString *) className;
- (void) setClassName: (NSString *) className;
- (id) createRealObject;

@end

// A text view as nibs of the NSArchiver era hold it.
@interface NSTextViewTemplate : NSViewTemplate {
    id _contents;
    NSColor *_backgroundColor;
    NSDictionary *_selectedTextAttributes;
    NSColor *_insertionPointColor;
    NSSize _containerSize;
    NSSize _minSize;
    NSSize _maxSize;
    id _delegate;
    struct {
        unsigned drawsBackground : 1;
        unsigned selectable : 1;
        unsigned editable : 1;
        unsigned richText : 1;
        unsigned importsGraphics : 1;
        unsigned horizontallyResizable : 1;
        unsigned verticallyResizable : 1;
        unsigned fieldEditor : 1;
        unsigned usesFontPanel : 1;
        unsigned rulerVisible : 1;
        unsigned containerTracksWidth : 1;
        unsigned containerTracksHeight : 1;
        unsigned usesRuler : 1;
        unsigned allowsUndo : 1;
    } _flags;
    NSDictionary *_typingAttributes;
}
@end

// The earlier text placeholder; it too gives a text view.
@interface NSTextTemplate : NSViewTemplate {
    id _contents;
    NSColor *_textColor;
    NSFont *_font;
    NSInteger _alignment;
    NSColor *_backgroundColor;
    NSSize _minSize;
    NSSize _maxSize;
    id _delegate;
    struct {
        unsigned drawsBackground : 1;
        unsigned selectable : 1;
        unsigned editable : 1;
        unsigned richText : 1;
        unsigned importsGraphics : 1;
        unsigned horizontallyResizable : 1;
        unsigned verticallyResizable : 1;
        unsigned fieldEditor : 1;
        unsigned usesFontPanel : 1;
        unsigned rulerVisible : 1;
        unsigned allowsUndo : 1;
    } _flags;
}
@end
