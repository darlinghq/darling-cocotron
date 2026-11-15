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

/*****************************************************************************************
 * Note to programmers modifying or subclassing NSTextView: *
 *                                                                                       *
 * NSTextView uses undo coalescing to join adjacent keystrokes into one undo
 *operation.  * So you need to call breakUndoCoalescing before registering any
 *other undo operations. *
 *****************************************************************************************/

#import <AppKit/AppKitIvarLayout.h>
#import <AppKit/NSDragging.h>
#import <AppKit/NSParagraphStyle.h>
#import <AppKit/NSText.h>
#import <AppKit/NSTextInput.h>
#import <AppKit/NSTextInputClient.h>
#import <AppKit/NSLayoutManager.h>

#import <Foundation/NSTextCheckingResult.h>

NS_ASSUME_NONNULL_BEGIN

@class NSTextStorage, NSLayoutManager, NSTextContainer, NSUndoManager;
@class NSRulerView, NSRulerMarker, NSOrthography, NSSharingServicePicker, NSTextAttachment, NSMenu, NSEvent;
@protocol NSTextAttachmentCell;

typedef NS_ENUM(NSUInteger, NSTextViewSelectionGranularity) {
    NSSelectByCharacter = 0,
    NSSelectByWord = 1,
    NSSelectByParagraph = 2,
};
typedef NSTextViewSelectionGranularity NSSelectionGranularity;

typedef NS_ENUM(NSUInteger, NSTextViewSelectionAffinity) {
    NSTextViewSelectionAffinityUpstream = 0,
    NSTextViewSelectionAffinityDownstream = 1,
};

// Names used before the modern spellings; plain constants, so Swift does not see them.
enum {
    NSSelectionAffinityUpstream = NSTextViewSelectionAffinityUpstream,
    NSSelectionAffinityDownstream = NSTextViewSelectionAffinityDownstream,
};
typedef NSTextViewSelectionAffinity NSSelectionAffinity;

typedef enum {
    NSFindPanelActionShowFindPanel = 1,
    NSFindPanelActionNext,
    NSFindPanelActionPrevious,
    NSFindPanelActionReplaceAll,
    NSFindPanelActionReplace,
    NSFindPanelActionReplaceAndFind,
    NSFindPanelActionSetFindString,
    NSFindPanelActionReplaceAllInSelection,
    NSFindPanelActionSelectAll,
    NSFindPanelActionSelectAllInSelection
} NSFindPanelAction;

APPKIT_EXPORT NSString *const NSTextViewDidChangeSelectionNotification;
APPKIT_EXPORT NSString *const NSOldSelectedCharacterRange;
APPKIT_EXPORT NSString *const NSAllRomanInputSourcesLocaleIdentifier;

@class NSUndoTyping;

typedef NS_ENUM(NSUInteger, NSFindPanelSubstringMatchType) {
    NSFindPanelSubstringMatchTypeContains = 0,
    NSFindPanelSubstringMatchTypeStartsWith = 1,
    NSFindPanelSubstringMatchTypeFullWord = 2,
    NSFindPanelSubstringMatchTypeEndsWith = 3,
};

// Legacy ObjC ABI (i386): instance size must stay 0x54, Apple's; the ivars
// before the extras sit at Apple's offsets. Add new state to the extra
// struct, never as an ivar.
@interface NSTextView : NSText <NSTextInput, NSTextInputClient, NSTextLayoutOrientationProvider> {
    NS_EXTRA_IVARS_BEGIN(NSTextView)
        NSTextStorage *_textStorage;
        NSTextContainer *_textContainer;
        NSSize _textContainerInset;
        BOOL _ownsTextStorage;
        NSDictionary *_typingAttributes;

        id _delegate;
        BOOL _isEditable;
        BOOL _isSelectable;
        BOOL _isRichText;
        NSColor *_backgroundColor;
        BOOL _drawsBackground;
        NSFont *_font;
        NSColor *_textColor;
        NSTextAlignment _textAlignment;

        NSColor *_insertionPointColor;
        NSRect _insertionPointRect;
        BOOL _insertionPointOn;
        NSTimer *_insertionPointTimer;

        BOOL _isFieldEditor;
        NSSize _maxSize;
        NSSize _minSize;
        BOOL _isHorizontallyResizable;
        BOOL _isVerticallyResizable;
        BOOL _usesRuler;
        BOOL _rulerVisible;
        BOOL _usesFontPanel;
        BOOL _usesFindBar;
        BOOL _allowsUndo;

        NSMutableArray *_selectedRanges;
        NSArray *_initialRanges; // selected ranges at the start of a selection
                                 // change
        NSSelectionAffinity _selectionAffinity;
        NSSelectionGranularity _selectionGranularity;
        NSDictionary *_selectedTextAttributes;
        NSDictionary *_linkTextAttributes;
        NSDictionary *_markedTextAttributes;
        NSParagraphStyle *_defaultParagraphStyle;

        BOOL _didSendTextDidEndNotification;
        NSUInteger _selectionOrigin; // for keyboard selection sanity.
        id _killBuffer; // NSString for Emacs-style, NSMutableString for additive
        BOOL _killBufferIsAdditive; // .. additive == pine/pico style, but possible
                                    // memory hog

        NSRange _rangeForUserCompletion; // range of original user completion text.
        NSString *_userCompletionHint;   // original "hint" text which started
                                         // completion
        NSArray *_userCompletions; // current list of completions. shouldn't change
                                   // while modal
        NSInteger _userCompletionSelectedItem; // index within completion array

        NSUndoManager *_fieldEditorUndoManager;
        BOOL _processingKeyEvent;
        BOOL _firstResponderButNotEditingYet;

        NSInteger _spellCheckerDocumentTag;
        BOOL _isContinuousSpellCheckingEnabled;
        BOOL _isAutomaticSpellingCorrectionEnabled;
        NSTextCheckingTypes _enabledTextCheckingTypes;
        BOOL _smartInsertDeleteEnabled;

        BOOL _allowsDocumentBackgroundColorChange;

        NSUndoTyping *_undoTyping;
        NSTextLayoutOrientation _layoutOrientation;

        BOOL _incrementalSearchingEnabled;
        BOOL _grammarCheckingEnabled;
        BOOL _automaticQuoteSubstitutionEnabled;
        BOOL _automaticDashSubstitutionEnabled;
        BOOL _automaticLinkDetectionEnabled;
        BOOL _automaticDataDetectionEnabled;
        BOOL _automaticTextReplacementEnabled;

        BOOL _usesInspectorBar;
        BOOL _acceptsGlyphInfo;
        BOOL _usesAdaptiveColorMappingForDarkAppearance;
        BOOL _importsGraphics;

        // New state sits here, inverted where the documented default is YES, so that
        // zero-filled storage means the default.
        BOOL _displaysLinkToolTipsDisabled;
        BOOL _usesRolloverButtonDisabled;
        BOOL _allowsImageEditing;
        BOOL _usesFindPanel;
        BOOL _automaticTextCompletionDisabled;
        BOOL _allowsCharacterPickerDisabled;
        NSArray *_allowedInputSourceLocales;
        BOOL _hasMarkedText;
        NSRange _markedRange;
        BOOL _updatingMarkedText;
        BOOL _pendingTypedRangeValid;
        NSRange _pendingTypedRange;
        BOOL _applyAllTextCheckingResults;
    NS_EXTRA_IVARS_END(NSTextView)
}

- initWithFrame: (NSRect) frame textContainer: (NSTextContainer *) container;

- initWithFrame: (NSRect) frame;

@property(nonatomic) BOOL acceptsGlyphInfo;

- (void) setNeedsDisplayInRect: (NSRect) rect avoidAdditionalLayout: (BOOL) avoidLayout;

- (void) _setTextStorage: (NSTextStorage *) storage;
- (void) replaceTextStorage: (NSTextStorage *) textStorage;

@property(nonatomic, retain) NSTextContainer *textContainer;

@property(nonatomic) NSSize textContainerInset;
@property(nonatomic, readonly) NSPoint textContainerOrigin;

@property(nonatomic, readonly) NSLayoutManager *layoutManager;
@property(nonatomic, readonly) NSTextStorage *textStorage;

- (void) insertText: (id) string;
- (void) insertText: (id) string replacementRange: (NSRange) replacementRange;

@property(nonatomic) BOOL usesRuler;
@property(nonatomic, getter=isRulerVisible) BOOL rulerVisible;
@property(nonatomic) BOOL allowsUndo;
@property(nonatomic, retain) NSColor *insertionPointColor;
@property(nonatomic, copy) NSDictionary *typingAttributes;
@property(nonatomic, copy) NSDictionary *selectedTextAttributes;
@property(nonatomic, copy) NSDictionary *linkTextAttributes;
@property(nonatomic, copy) NSDictionary *markedTextAttributes;
@property(nonatomic, copy) NSArray *selectedRanges;
@property(nonatomic, retain) NSParagraphStyle *defaultParagraphStyle;



- (NSRange) selectionRangeForProposedRange: (NSRange) range
                               granularity:
                                       (NSSelectionGranularity) granularity;

- (void) setSelectedRange: (NSRange) range
                 affinity: (NSSelectionAffinity) affinity
           stillSelecting: (BOOL) stillSelecting;
- (void) setSelectedRanges: (NSArray *) ranges
                  affinity: (NSSelectionAffinity) affinity
            stillSelecting: (BOOL) stillSelecting;


@property(nonatomic, readonly) NSRange rangeForUserCompletion;
- (NSArray *) completionsForPartialWordRange: (NSRange) range
                         indexOfSelectedItem: (NSInteger *) index;
- (void) insertCompletion: (NSString *) string
        forPartialWordRange: (NSRange) range
                   movement: (NSInteger) movement
                    isFinal: (BOOL) isFinal;

@property(nonatomic, readonly) NSArray *writablePasteboardTypes;
- (BOOL) writeSelectionToPasteboard: (NSPasteboard *) pasteboard
                               type: (NSString *) type;
- (BOOL) writeSelectionToPasteboard: (NSPasteboard *) pasteboard
                              types: (NSArray *) types;

@property(nonatomic, readonly) NSRange rangeForUserTextChange;
@property(nonatomic, readonly) NSRange rangeForUserCharacterAttributeChange;
@property(nonatomic, readonly) NSRange rangeForUserParagraphAttributeChange;

- (BOOL) shouldChangeTextInRange: (NSRange) changeInRange
               replacementString: (NSString *) replacementString;
- (void) didChangeText;

- (BOOL) shouldDrawInsertionPoint;
- (void) drawInsertionPointInRect: (NSRect) rect
                            color: (NSColor *) color
                         turnedOn: (BOOL) turnedOn;
- (void) updateInsertionPointStateAndRestartTimer: (BOOL) restart;

- (void) updateRuler;

- (void) alignJustified: sender;

- (void) cut: sender;
- (void) copy: sender;
- (void) paste: sender;
- (void) selectAll: sender;

- (void) moveLeft: sender;
- (void) moveRight: sender;
- (void) moveForward: sender;
- (void) moveBackward: sender;
- (void) moveToBeginningOfLine: sender;
- (void) moveToEndOfLine: sender;

- (void) deleteForward: sender;
- (void) deleteBackward: sender;

- (void) pageUp: sender;
- (void) pageDown: sender;

- (NSDragOperation) dragOperationForDraggingInfo: (id<NSDraggingInfo>) info
                                            type: (NSString *) type;
- (void) cleanUpAfterDragOperation;

- (void) _setFieldEditorUndoManager: (NSUndoManager *) undoManager;
- (void) breakUndoCoalescing;

@property(nonatomic, readonly) NSInteger spellCheckerDocumentTag;

@property(nonatomic, getter=isContinuousSpellCheckingEnabled) BOOL continuousSpellCheckingEnabled;
- (void) toggleContinuousSpellChecking: sender;

@property(nonatomic, getter=isAutomaticSpellingCorrectionEnabled) BOOL automaticSpellingCorrectionEnabled;
- (void) toggleAutomaticSpellingCorrection: sender;

@property(nonatomic) NSTextCheckingTypes enabledTextCheckingTypes;

@property(nonatomic) BOOL smartInsertDeleteEnabled;

@property(nonatomic) BOOL allowsDocumentBackgroundColorChange;

- (void) setSpellingState: (NSInteger) value range: (NSRange) characterRange;

@property(nonatomic, getter=isIncrementalSearchingEnabled) BOOL incrementalSearchingEnabled;
@property(nonatomic) BOOL usesFindBar;
@property(nonatomic) BOOL usesInspectorBar;
- (void) performFindPanelAction: (id) sender;

- (void) setLayoutOrientation:(NSTextLayoutOrientation)orientation;

@property(nonatomic, getter=isGrammarCheckingEnabled) BOOL grammarCheckingEnabled;
@property(nonatomic, getter=isAutomaticQuoteSubstitutionEnabled) BOOL automaticQuoteSubstitutionEnabled;
@property(nonatomic, getter=isAutomaticDashSubstitutionEnabled) BOOL automaticDashSubstitutionEnabled;
@property(nonatomic, getter=isAutomaticLinkDetectionEnabled) BOOL automaticLinkDetectionEnabled;
@property(nonatomic, getter=isAutomaticDataDetectionEnabled) BOOL automaticDataDetectionEnabled;
@property(nonatomic, getter=isAutomaticTextReplacementEnabled) BOOL automaticTextReplacementEnabled;

// An NSTextView wrapped in a configured, vertically-scrolling NSScrollView (10.14)
+ (NSScrollView *) scrollableTextView;

@end

@interface NSObject (NSTextView_undoManager)
- (NSUndoManager *) undoManagerForTextView: (NSTextView *) textView;
@end

@interface NSObject (NSTextView_delegate)

- (BOOL) textView: (NSTextView *) textView doCommandBySelector: (SEL) selector;
- (NSArray *) textView: (NSTextView *) textView
                completions: (NSArray *) words
        forPartialWordRange: (NSRange) range
        indexOfSelectedItem: (NSInteger *) index;

- (void) textViewDidChangeSelection: (NSNotification *) note;

- (NSRange) textView: (NSTextView *) textView
        willChangeSelectionFromCharacterRange: (NSRange) oldSelectedCharRange
                             toCharacterRange: (NSRange) newSelectedCharRange;
- (NSArray *) textView: (NSTextView *) textView
        willChangeSelectionFromCharacterRanges:
                (NSArray *) oldSelectedCharRanges
                             toCharacterRanges:
                                     (NSArray *) newSelectedCharRanges;

- (BOOL) textView: (NSTextView *) textView
        shouldChangeTextInRange: (NSRange) affectedCharRange
              replacementString: (NSString *) replacementString;

@end

@protocol NSTextViewDelegate <NSTextDelegate>
@end

NS_ASSUME_NONNULL_END

@interface NSTextView (NSTextViewLayoutOrientationAndHighlights)
// Private AppKit: the Highlight menu items AppKit adds to text menus. None here.
+ (NSArray *) _textHighlightMenuItems;
// Stored only: there's no dark appearance.
@property BOOL usesAdaptiveColorMappingForDarkAppearance;
// Switches between horizontal and vertical layout.
- (void) changeLayoutOrientation: (id) sender;
@end

@class NSPasteboard;

@interface NSTextView (NSFindIndicatorAndPasteboard)
- (void) showFindIndicatorForRange: (NSRange) range;
- (void) orderFrontLinkPanel: (id) sender;
- (BOOL) readSelectionFromPasteboard: (NSPasteboard *) pasteboard type: (NSString *) type;
@end

