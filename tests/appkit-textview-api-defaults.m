/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * NSTextView defaults, stored settings, the text checking types and the
 * factory methods. Expected values are those of a fresh NSTextView on macOS
 * 10.14.4 and 26.7.3 (where the two differ, the setting is not checked or
 * checked only after being set). No window server needed.
 */
#import <AppKit/AppKit.h>
#include <stdio.h>

// The methods under test, declared here so that the test also builds against
// an SDK that predates them.
@interface NSTextView (V613Test)
- (NSSelectionAffinity) selectionAffinity;
- (NSSelectionGranularity) selectionGranularity;
- (void) setSelectionGranularity: (NSSelectionGranularity) granularity;
- (BOOL) displaysLinkToolTips;
- (void) setDisplaysLinkToolTips: (BOOL) flag;
- (BOOL) allowsImageEditing;
- (void) setAllowsImageEditing: (BOOL) flag;
- (BOOL) usesRolloverButtonForSelection;
- (void) setUsesRolloverButtonForSelection: (BOOL) flag;
- (BOOL) usesFindPanel;
- (void) setUsesFindPanel: (BOOL) flag;
- (BOOL) isAutomaticTextCompletionEnabled;
- (void) setAutomaticTextCompletionEnabled: (BOOL) flag;
- (BOOL) allowsCharacterPickerTouchBarItem;
- (void) setAllowsCharacterPickerTouchBarItem: (BOOL) flag;
- (NSArray *) allowedInputSourceLocales;
- (void) setAllowedInputSourceLocales: (NSArray *) locales;
- (BOOL) isCoalescingUndo;
- (NSArray *) acceptableDragTypes;
- (NSArray *) readablePasteboardTypes;
+ (id) fieldEditor;
+ (NSScrollView *) scrollableDocumentContentTextView;
+ (NSScrollView *) scrollablePlainDocumentContentTextView;
- (void) updateDragTypeRegistration;
@end

static int failures;

static void expect(BOOL ok, const char *what)
{
    if (!ok) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

static void testFreshDefaults(void)
{
    NSTextView *view = [[NSTextView alloc] initWithFrame: NSMakeRect(0, 0, 100, 100)];
    expect([view smartInsertDeleteEnabled], "smart insert and delete is on");
    expect([view isAutomaticTextReplacementEnabled], "text replacement is on");
    expect([view isAutomaticSpellingCorrectionEnabled], "spelling correction is on");
    expect(![view isAutomaticLinkDetectionEnabled], "link detection is off");
    expect(![view isAutomaticDataDetectionEnabled], "data detection is off");
    expect(![view isContinuousSpellCheckingEnabled], "continuous spell checking is off");
    expect([view displaysLinkToolTips], "link tool tips are on");
    expect(![view allowsImageEditing], "image editing is off");
    expect([view usesRolloverButtonForSelection], "the rollover button is on");
    expect(![view usesFindPanel], "uses find panel is off");
    expect(![view usesFindBar], "uses find bar is off");
    expect(![view isIncrementalSearchingEnabled], "incremental searching is off");
    expect(![view usesInspectorBar], "uses inspector bar is off");
    expect([view isAutomaticTextCompletionEnabled], "text completion is on");
    expect([view allowsCharacterPickerTouchBarItem], "the character picker item is on");
    expect([[view allowedInputSourceLocales] count] == 0, "no input source restriction");
    expect([view selectionGranularity] == NSSelectByCharacter, "selection granularity starts at character");
    expect([view selectionAffinity] == NSSelectionAffinityUpstream, "selection affinity starts upstream");
    expect([view isRichText] && [view isEditable] && [view isSelectable], "rich, editable and selectable");
    expect(![view importsGraphics] && ![view allowsUndo] && ![view isFieldEditor], "graphics, undo and field editor are off");
    expect(![view allowsDocumentBackgroundColorChange], "document background changes are off");
    expect(![view isCoalescingUndo], "no undo is being coalesced");
    expect([view usesFontPanel], "uses font panel is on");
    [view release];
}

static void testRulers(void)
{
    NSTextView *view = [[NSTextView alloc] initWithFrame: NSMakeRect(0, 0, 100, 100)];
    expect([view usesRuler] && ![view isRulerVisible], "rulers are allowed but not visible");
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame: NSMakeRect(0, 0, 300, 100)];
    [scroll setDocumentView: view];
    NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 400, 300)
                                                   styleMask: NSTitledWindowMask
                                                     backing: NSBackingStoreBuffered
                                                       defer: NO];
    [[window contentView] addSubview: scroll];
    [window makeFirstResponder: view];
    expect([view usesRuler] && ![view isRulerVisible] && ![scroll rulersVisible] && ![scroll hasHorizontalRuler],
           "becoming first responder neither shows a ruler nor changes usesRuler");
    [window release];
    [scroll release];
    [view release];
}

static void testStoredSettings(void)
{
    NSTextView *view = [[NSTextView alloc] initWithFrame: NSMakeRect(0, 0, 100, 100)];
    [view setDisplaysLinkToolTips: NO];
    expect(![view displaysLinkToolTips], "displaysLinkToolTips is stored");
    [view setAllowsImageEditing: YES];
    expect([view allowsImageEditing], "allowsImageEditing is stored");
    [view setUsesRolloverButtonForSelection: NO];
    expect(![view usesRolloverButtonForSelection], "usesRolloverButtonForSelection is stored");
    [view setUsesFindPanel: YES];
    expect([view usesFindPanel], "usesFindPanel is stored");
    [view setUsesFindBar: YES];
    expect([view usesFindBar], "usesFindBar is stored");
    [view setAutomaticTextCompletionEnabled: NO];
    expect(![view isAutomaticTextCompletionEnabled], "automaticTextCompletionEnabled is stored");
    [view setAllowsCharacterPickerTouchBarItem: NO];
    expect(![view allowsCharacterPickerTouchBarItem], "allowsCharacterPickerTouchBarItem is stored");
    NSArray *locales = @[@"en", @"de"];
    [view setAllowedInputSourceLocales: locales];
    expect([[view allowedInputSourceLocales] isEqualToArray: locales], "allowedInputSourceLocales is stored");

    [view setString: @"hello world"];
    [view setSelectedRange: NSMakeRange(2, 0) affinity: NSSelectionAffinityDownstream stillSelecting: NO];
    expect([view selectionAffinity] == NSSelectionAffinityDownstream, "selection affinity follows setSelectedRange:affinity:...");
    [view setSelectionGranularity: NSSelectByWord];
    expect([view selectionGranularity] == NSSelectByWord, "selection granularity is settable");
    [view setSelectedRange: NSMakeRange(0, 2)];
    expect([view selectionGranularity] == NSSelectByCharacter, "setting the selection resets the granularity");
    expect([view selectionAffinity] == NSSelectionAffinityUpstream, "and the affinity");
    [view release];
}

// The checking types are made of the switches plus bits no switch covers
// (default 0x2001); setting the types sets the switches.
static void testTextCheckingTypes(void)
{
    NSTextView *view = [[NSTextView alloc] initWithFrame: NSMakeRect(0, 0, 100, 100)];
    expect(([view enabledTextCheckingTypes] & 0x2001) == 0x2001, "the default types include the bits no switch covers");
    expect(([view enabledTextCheckingTypes] & 0x300) == 0x300, "default types include replacement and correction");

    [view setEnabledTextCheckingTypes: 0];
    expect([view enabledTextCheckingTypes] == 0, "types 0 read back as 0");
    expect(![view isAutomaticTextReplacementEnabled] && ![view isAutomaticSpellingCorrectionEnabled] &&
                   ![view isAutomaticQuoteSubstitutionEnabled] && ![view isAutomaticDashSubstitutionEnabled] &&
                   ![view isAutomaticLinkDetectionEnabled] && ![view isAutomaticDataDetectionEnabled] &&
                   ![view isContinuousSpellCheckingEnabled] && ![view isGrammarCheckingEnabled],
           "types 0 switch everything off");

    [view setAutomaticQuoteSubstitutionEnabled: YES];
    expect([view enabledTextCheckingTypes] == 0x40, "quote substitution is 0x40");
    [view setAutomaticQuoteSubstitutionEnabled: NO];
    [view setAutomaticDashSubstitutionEnabled: YES];
    expect([view enabledTextCheckingTypes] == 0x80, "dash substitution is 0x80");
    [view setAutomaticDashSubstitutionEnabled: NO];
    [view setAutomaticLinkDetectionEnabled: YES];
    expect([view enabledTextCheckingTypes] == 0x20, "link detection is 0x20");
    [view setAutomaticLinkDetectionEnabled: NO];
    [view setAutomaticTextReplacementEnabled: YES];
    expect([view enabledTextCheckingTypes] == 0x100, "text replacement is 0x100");
    [view setAutomaticTextReplacementEnabled: NO];
    [view setAutomaticSpellingCorrectionEnabled: YES];
    expect([view enabledTextCheckingTypes] == 0x200, "spelling correction is 0x200");
    [view setAutomaticSpellingCorrectionEnabled: NO];
    [view setContinuousSpellCheckingEnabled: YES];
    expect([view enabledTextCheckingTypes] == 0x2, "continuous spell checking is 0x2");
    [view setContinuousSpellCheckingEnabled: NO];
    [view setGrammarCheckingEnabled: YES];
    expect([view enabledTextCheckingTypes] == 0, "grammar checking shows only together with spelling");
    [view setContinuousSpellCheckingEnabled: YES];
    expect([view enabledTextCheckingTypes] == 0x6, "grammar checking with spelling is 0x6");
    [view setContinuousSpellCheckingEnabled: NO];
    [view setGrammarCheckingEnabled: NO];
    [view setAutomaticDataDetectionEnabled: YES];
    expect([view enabledTextCheckingTypes] == 0x1818, "data detection is 0x1818");
    [view setAutomaticDataDetectionEnabled: NO];
    expect([view enabledTextCheckingTypes] == 0, "and off again");

    [view setEnabledTextCheckingTypes: 1ULL << 6];
    expect([view isAutomaticQuoteSubstitutionEnabled] && [view enabledTextCheckingTypes] == 0x40,
           "types with the quote bit switch quote substitution on");
    [view setEnabledTextCheckingTypes: 1ULL << 3];
    expect([view isAutomaticDataDetectionEnabled] && [view enabledTextCheckingTypes] == 0x1808,
           "a date type switches data detection on and reads back with the extra bits");
    [view setEnabledTextCheckingTypes: 1ULL << 13];
    expect([view enabledTextCheckingTypes] == 0x2000 && ![view isAutomaticDataDetectionEnabled],
           "bits without a switch are kept");
    [view setEnabledTextCheckingTypes: 0xffffffffULL];
    expect([view isAutomaticQuoteSubstitutionEnabled] && [view isAutomaticDashSubstitutionEnabled] &&
                   [view isAutomaticLinkDetectionEnabled] && [view isContinuousSpellCheckingEnabled] &&
                   [view isGrammarCheckingEnabled] && [view enabledTextCheckingTypes] == 0xffffffffULL,
           "all system types switch everything on");
    [view release];
}

static void testFactories(void)
{
    NSScrollView *scroll = [NSTextView scrollableTextView];
    NSTextView *plain = [scroll documentView];
    expect([plain isKindOfClass: [NSTextView class]], "scrollableTextView holds a text view");
    expect([scroll hasVerticalScroller] && ![scroll hasHorizontalScroller], "vertical scroller only");
    expect([scroll borderType] == NSNoBorder, "no border");
    expect(![plain isRichText] && ![plain usesFindBar] && ![plain usesFontPanel] && ![plain importsGraphics],
           "scrollableTextView: plain text, no find bar, font panel or graphics");
    expect([plain isVerticallyResizable] && ![plain isHorizontallyResizable], "resizes vertically");
    expect([plain autoresizingMask] == (NSViewWidthSizable | NSViewHeightSizable), "autoresizes both ways");
    expect([[plain textContainer] widthTracksTextView] && ![[plain textContainer] heightTracksTextView],
           "the container follows the width");

    NSTextView *document = [[NSTextView scrollableDocumentContentTextView] documentView];
    expect([document isRichText] && [document usesFindBar] && [document usesFontPanel] && [document importsGraphics],
           "document view: rich, find bar, font panel, graphics");

    NSTextView *plainDocument = [[NSTextView scrollablePlainDocumentContentTextView] documentView];
    expect(![plainDocument isRichText] && [plainDocument usesFindBar] && ![plainDocument importsGraphics],
           "plain document view: plain text with a find bar");

    NSTextView *editor = [NSTextView fieldEditor];
    expect([editor isFieldEditor] && [editor isRichText] && [editor isEditable] && [editor isSelectable],
           "field editor");
    expect(![[editor textContainer] widthTracksTextView], "the field editor's container does not follow the width");
}

static void testDragTypes(void)
{
    NSTextView *view = [[NSTextView alloc] initWithFrame: NSMakeRect(0, 0, 100, 100)];
    NSArray *types = [view acceptableDragTypes];
    expect([types containsObject: NSStringPboardType], "plain text is an acceptable drag type");
    [view setEditable: NO];
    [view updateDragTypeRegistration];
    expect([view isEditable] == NO, "still not editable");
    [view release];
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        testFreshDefaults();
        testRulers();
        testStoredSettings();
        testTextCheckingTypes();
        testFactories();
        testDragTypes();
    }
    if (failures)
        return 1;
    puts("textview api defaults: PASS");
    return 0;
}
