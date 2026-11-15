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
APPKIT_EXPORT NSString *const NSTextViewDidChangeTypingAttributesNotification;
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
// TextKit 2 backing is not available; both values give the TextKit 1 network.
- (instancetype) initUsingTextLayoutManager: (BOOL) usingTextLayoutManager;

@property(nonatomic) BOOL acceptsGlyphInfo;

- (void) setNeedsDisplayInRect: (NSRect) rect avoidAdditionalLayout: (BOOL) avoidLayout;

- (void) _setTextStorage: (NSTextStorage *) storage;
- (void) replaceTextStorage: (NSTextStorage *) textStorage;

@property(nonatomic, retain) NSTextContainer *textContainer;
// Swaps the container, keeping the layout manager and text storage.
- (void) replaceTextContainer: (NSTextContainer *) newContainer;
- (void) invalidateTextContainerOrigin;

@property(nonatomic) NSSize textContainerInset;
@property(nonatomic, readonly) NSPoint textContainerOrigin;

@property(nonatomic, readonly) NSLayoutManager *layoutManager;
@property(nonatomic, readonly) NSTextStorage *textStorage;

- (void) insertText: (id) string;
- (void) insertText: (id) string replacementRange: (NSRange) replacementRange;

// Sets the frame size, limited by minSize and maxSize in the directions the
// view may resize in.
- (void) setConstrainedFrameSize: (NSSize) desiredSize;
- (void) setAlignment: (NSTextAlignment) alignment range: (NSRange) range;

// Font menu commands
- (void) turnOffKerning: (nullable id) sender;
- (void) tightenKerning: (nullable id) sender;
- (void) loosenKerning: (nullable id) sender;
- (void) useStandardKerning: (nullable id) sender;
- (void) turnOffLigatures: (nullable id) sender;
- (void) useStandardLigatures: (nullable id) sender;
- (void) useAllLigatures: (nullable id) sender;
- (void) raiseBaseline: (nullable id) sender;
- (void) lowerBaseline: (nullable id) sender;
- (void) outline: (nullable id) sender;
- (void) toggleTraditionalCharacterShape: (nullable id) sender;

// Text commands
- (void) changeColor: (nullable id) sender;
- (void) changeAttributes: (nullable id) sender;
- (void) changeDocumentBackgroundColor: (nullable id) sender;
// No spacing, list or table panels exist: these do nothing.
- (void) orderFrontSpacingPanel: (nullable id) sender;
- (void) orderFrontListPanel: (nullable id) sender;
- (void) orderFrontTablePanel: (nullable id) sender;

// Override points
- (void) drawViewBackgroundInRect: (NSRect) rect;
- (void) updateDragTypeRegistration;
- (void) clickedOnLink: (id) link atIndex: (NSUInteger) charIndex;
- (NSUInteger) characterIndexForInsertionAtPoint: (NSPoint) point;
+ (BOOL) stronglyReferencesTextStorage;
- (BOOL) performValidatedReplacementInRange: (NSRange) range
                       withAttributedString: (NSAttributedString *) attributedString;

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
- (void) toggleAutomaticQuoteSubstitution: (nullable id) sender;
- (void) toggleAutomaticLinkDetection: (nullable id) sender;
- (void) toggleAutomaticDataDetection: (nullable id) sender;
- (void) toggleAutomaticDashSubstitution: (nullable id) sender;
- (void) toggleAutomaticTextReplacement: (nullable id) sender;
- (void) toggleAutomaticTextCompletion: (nullable id) sender;
- (void) checkTextInRange: (NSRange) range
                    types: (NSTextCheckingTypes) checkingTypes
                  options: (NSDictionary *) options;
- (void) handleTextCheckingResults: (NSArray *) results
                          forRange: (NSRange) range
                             types: (NSTextCheckingTypes) checkingTypes
                           options: (NSDictionary *) options
                       orthography: (nullable NSOrthography *) orthography
                         wordCount: (NSInteger) wordCount;
// No substitutions panel exists: does nothing.
- (void) orderFrontSubstitutionsPanel: (nullable id) sender;
- (void) checkTextInSelection: (nullable id) sender;
- (void) checkTextInDocument: (nullable id) sender;
@property(nonatomic) BOOL usesFindPanel;

@property(nonatomic) BOOL smartInsertDeleteEnabled;
- (NSRange) smartDeleteRangeForProposedRange: (NSRange) proposedCharRange;
- (void) toggleSmartInsertDelete: (nullable id) sender;
- (void) smartInsertForString: (NSString *) pasteString
               replacingRange: (NSRange) charRangeToReplace
                 beforeString: (NSString *_Nullable *_Nullable) beforeString
                  afterString: (NSString *_Nullable *_Nullable) afterString;
- (nullable NSString *) smartInsertBeforeStringForString: (NSString *) pasteString
                                          replacingRange: (NSRange) charRangeToReplace;
- (nullable NSString *) smartInsertAfterStringForString: (NSString *) pasteString
                                         replacingRange: (NSRange) charRangeToReplace;

@property(nonatomic) BOOL allowsDocumentBackgroundColorChange;

- (void) setSpellingState: (NSInteger) value range: (NSRange) characterRange;
- (void) toggleGrammarChecking: (nullable id) sender;

@property(nonatomic, readonly) NSSelectionAffinity selectionAffinity;
@property(nonatomic) NSSelectionGranularity selectionGranularity;
// If set, link attributes act as implicit tool tips. Default YES.
@property(nonatomic) BOOL displaysLinkToolTips;
@property(nonatomic) BOOL allowsImageEditing;
@property(nonatomic) BOOL usesRolloverButtonForSelection;
@property(nonatomic, getter=isAutomaticTextCompletionEnabled) BOOL automaticTextCompletionEnabled;
@property(nonatomic) BOOL allowsCharacterPickerTouchBarItem;
@property(nonatomic, copy, nullable) NSArray<NSString *> *allowedInputSourceLocales;
@property(nonatomic, readonly, getter=isCoalescingUndo) BOOL coalescingUndo;
// The multiple-range forms; nil when the change is not permitted.
- (BOOL) shouldChangeTextInRanges: (NSArray *) affectedRanges
                replacementStrings: (nullable NSArray *) replacementStrings;
@property(nonatomic, readonly, copy, nullable) NSArray *rangesForUserTextChange;
@property(nonatomic, readonly, copy, nullable) NSArray *rangesForUserCharacterAttributeChange;
@property(nonatomic, readonly, copy, nullable) NSArray *rangesForUserParagraphAttributeChange;

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
// A text view configured as a field editor (10.14)
+ (instancetype) fieldEditor;
// Text views for document contents, rich and plain, in a scroll view (10.14)
+ (NSScrollView *) scrollableDocumentContentTextView;
+ (NSScrollView *) scrollablePlainDocumentContentTextView;

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
@optional
- (BOOL) textView: (NSTextView *) textView clickedOnLink: (id) link atIndex: (NSUInteger) charIndex;
- (void) textView: (NSTextView *) textView
        clickedOnCell: (id<NSTextAttachmentCell>) cell
               inRect: (NSRect) cellFrame
              atIndex: (NSUInteger) charIndex;
- (void) textView: (NSTextView *) textView
        doubleClickedOnCell: (id<NSTextAttachmentCell>) cell
                     inRect: (NSRect) cellFrame
                    atIndex: (NSUInteger) charIndex;
- (void) textView: (NSTextView *) view
        draggedCell: (id<NSTextAttachmentCell>) cell
             inRect: (NSRect) rect
              event: (NSEvent *) event
            atIndex: (NSUInteger) charIndex;
- (NSArray *) textView: (NSTextView *) view
        writablePasteboardTypesForCell: (id<NSTextAttachmentCell>) cell
                               atIndex: (NSUInteger) charIndex;
- (BOOL) textView: (NSTextView *) view
          writeCell: (id<NSTextAttachmentCell>) cell
            atIndex: (NSUInteger) charIndex
       toPasteboard: (NSPasteboard *) pboard
               type: (NSString *) type;
- (NSRange) textView: (NSTextView *) textView
        willChangeSelectionFromCharacterRange: (NSRange) oldSelectedCharRange
                             toCharacterRange: (NSRange) newSelectedCharRange;
- (NSArray *) textView: (NSTextView *) textView
        willChangeSelectionFromCharacterRanges: (NSArray *) oldSelectedCharRanges
                             toCharacterRanges: (NSArray *) newSelectedCharRanges;
- (BOOL) textView: (NSTextView *) textView
        shouldChangeTextInRanges: (NSArray *) affectedRanges
               replacementStrings: (nullable NSArray *) replacementStrings;
- (NSDictionary *) textView: (NSTextView *) textView
        shouldChangeTypingAttributes: (NSDictionary *) oldTypingAttributes
                        toAttributes: (NSDictionary *) newTypingAttributes;
- (void) textViewDidChangeSelection: (NSNotification *) notification;
- (void) textViewDidChangeTypingAttributes: (NSNotification *) notification;
- (nullable NSString *) textView: (NSTextView *) textView
                willDisplayToolTip: (NSString *) tooltip
              forCharacterAtIndex: (NSUInteger) characterIndex;
- (NSArray *) textView: (NSTextView *) textView
                completions: (NSArray *) words
        forPartialWordRange: (NSRange) charRange
        indexOfSelectedItem: (nullable NSInteger *) index;
- (BOOL) textView: (NSTextView *) textView
        shouldChangeTextInRange: (NSRange) affectedCharRange
              replacementString: (nullable NSString *) replacementString;
- (BOOL) textView: (NSTextView *) textView doCommandBySelector: (SEL) commandSelector;
- (NSInteger) textView: (NSTextView *) textView
        shouldSetSpellingState: (NSInteger) value
                         range: (NSRange) affectedCharRange;
- (nullable NSMenu *) textView: (NSTextView *) view
                          menu: (NSMenu *) menu
                      forEvent: (NSEvent *) event
                       atIndex: (NSUInteger) charIndex;
- (NSDictionary *) textView: (NSTextView *) view
        willCheckTextInRange: (NSRange) range
                     options: (NSDictionary *) options
                       types: (NSTextCheckingTypes *) checkingTypes;
- (NSArray *) textView: (NSTextView *) view
        didCheckTextInRange: (NSRange) range
                      types: (NSTextCheckingTypes) checkingTypes
                    options: (NSDictionary *) options
                    results: (NSArray *) results
                orthography: (NSOrthography *) orthography
                  wordCount: (NSInteger) wordCount;
- (nullable NSURL *) textView: (NSTextView *) textView
        URLForContentsOfTextAttachment: (NSTextAttachment *) textAttachment
                               atIndex: (NSUInteger) charIndex;
- (nullable NSSharingServicePicker *) textView: (NSTextView *) textView
                  willShowSharingServicePicker: (NSSharingServicePicker *) servicePicker
                                      forItems: (NSArray *) items;
- (nullable NSUndoManager *) undoManagerForTextView: (NSTextView *) view;
// Not sent: there is no Touch Bar, candidate list or Writing Tools here.
- (NSArray *) textView: (NSTextView *) textView
        shouldUpdateTouchBarItemIdentifiers: (NSArray *) identifiers;
- (nullable NSArray *) textView: (NSTextView *) textView
                candidatesForSelectedRange: (NSRange) selectedRange;
- (NSArray *) textView: (NSTextView *) textView
                candidates: (NSArray *) candidates
          forSelectedRange: (NSRange) selectedRange;
- (BOOL) textView: (NSTextView *) textView shouldSelectCandidateAtIndex: (NSUInteger) index;
// The forms that predate the character index.
- (BOOL) textView: (NSTextView *) textView clickedOnLink: (id) link;
- (void) textView: (NSTextView *) textView clickedOnCell: (id<NSTextAttachmentCell>) cell inRect: (NSRect) cellFrame;
- (void) textView: (NSTextView *) textView doubleClickedOnCell: (id<NSTextAttachmentCell>) cell inRect: (NSRect) cellFrame;
- (void) textView: (NSTextView *) view draggedCell: (id<NSTextAttachmentCell>) cell inRect: (NSRect) rect event: (NSEvent *) event;
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


@interface NSTextView (NSPasteboard)
@property(nonatomic, readonly, copy) NSArray *readablePasteboardTypes;
- (NSString *) preferredPasteboardTypeFromArray: (NSArray *) availableTypes
                     restrictedToTypesFromArray: (NSArray *) allowedTypes;
- (BOOL) readSelectionFromPasteboard: (NSPasteboard *) pasteboard;
+ (void) registerForServices;
- (id) validRequestorForSendType: (NSString *) sendType returnType: (NSString *) returnType;
- (void) pasteAsPlainText: (id) sender;
- (void) pasteAsRichText: (id) sender;
@end

@interface NSTextView (NSDragging)
@property(nonatomic, readonly, copy) NSArray *acceptableDragTypes;
@end
