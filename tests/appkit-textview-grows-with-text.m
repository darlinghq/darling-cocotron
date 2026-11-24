/*
 * A vertically resizable NSTextView that is the document view of an
 * NSScrollView grows to hold all of its text, so the scroll view can scroll
 * through it, and scrollRangeToVisible: brings the end of a long text into
 * view. Set up the way Apple's TextEdit sample sets up its plain (non paged)
 * view: a container of (scroll view width, CGFLOAT_MAX) whose width tracks the
 * text view, a vertically resizable text view with the scroll view's content
 * size as its minimum size. Expected behaviour is the documented one for
 * isVerticallyResizable, NSTextContainer and NSScrollView. The window is
 * resized before the text arrives, as a document window is laid out when it
 * opens, so a container that wrongly follows the view's height is caught.
 * Needs a window server.
 */
#import <AppKit/AppKit.h>
#include <float.h>
#include <stdio.h>

static int failures;

static void expect(BOOL ok, const char *what)
{
    if (!ok) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

static NSString *lines(int count)
{
    NSMutableString *text = [NSMutableString string];
    for (int i = 1; i <= count; i++)
        [text appendFormat: @"line number %d of the test\n", i];
    return text;
}

static void spin(void)
{
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.3]];
}

static NSScrollView *makeScrollView(NSWindow **windowOut)
{
    NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 400, 300)
                                                   styleMask: NSTitledWindowMask | NSResizableWindowMask
                                                     backing: NSBackingStoreBuffered
                                                       defer: NO];
    NSScrollView *scrollView = [[[NSScrollView alloc] initWithFrame: [[window contentView] bounds]] autorelease];
    [scrollView setHasVerticalScroller: YES];
    [scrollView setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
    [[window contentView] addSubview: scrollView];
    *windowOut = window;
    return scrollView;
}

static NSTextView *makeTextEditStyleView(NSScrollView *scrollView)
{
    NSSize size = [scrollView contentSize];
    NSTextStorage *storage = [[NSTextStorage alloc] init];
    NSLayoutManager *layoutManager = [[[NSLayoutManager alloc] init] autorelease];
    [storage addLayoutManager: layoutManager];
    NSTextContainer *container =
            [[[NSTextContainer alloc] initWithContainerSize: NSMakeSize(size.width, CGFLOAT_MAX)] autorelease];
    NSTextView *textView = [[[NSTextView alloc] initWithFrame: NSMakeRect(0, 0, size.width, size.height)
                                                textContainer: container] autorelease];
    [layoutManager insertTextContainer: container atIndex: 0];
    [container setWidthTracksTextView: YES];
    [container setHeightTracksTextView: NO];
    [textView setHorizontallyResizable: NO];
    [textView setVerticallyResizable: YES];
    [textView setAutoresizingMask: NSViewWidthSizable];
    [textView setMinSize: size];
    [textView setMaxSize: NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX)];
    [scrollView setDocumentView: textView];
    expect(![container heightTracksTextView] && [container widthTracksTextView],
           "making the view resizable leaves the container's tracking as it was set");
    return textView;
}

// A width change of the text view, as when its window is laid out or resized.
static void resizeWindow(NSWindow *window)
{
    NSRect frame = [window frame];
    frame.size.width += 40;
    [window setFrame: frame display: YES];
    spin();
}

static void checkGrown(NSTextView *textView, NSScrollView *scrollView, const char *how)
{
    char what[256];
    NSLayoutManager *layoutManager = [textView layoutManager];
    NSTextContainer *container = [textView textContainer];
    NSUInteger glyphs = [layoutManager numberOfGlyphs];
    NSRange laidOut = [layoutManager glyphRangeForTextContainer: container];
    NSRect used = [layoutManager usedRectForTextContainer: container];
    CGFloat height = [textView frame].size.height;
    CGFloat clipHeight = [[scrollView contentView] bounds].size.height;

    snprintf(what, sizeof what, "%s: all %lu glyphs are laid out in the container (got %lu)", how,
             (unsigned long) glyphs, (unsigned long) NSMaxRange(laidOut));
    expect(NSMaxRange(laidOut) == glyphs, what);
    snprintf(what, sizeof what, "%s: the text view (%.0f high) is as high as its text (%.0f)", how, height,
             NSMaxY(used));
    expect(height >= NSMaxY(used), what);
    snprintf(what, sizeof what, "%s: the document (%.0f high) is taller than the clip view (%.0f)", how,
             [[scrollView documentView] frame].size.height, clipHeight);
    expect([[scrollView documentView] frame].size.height > clipHeight * 2, what);

    [textView scrollRangeToVisible: NSMakeRange([[textView string] length], 0)];
    NSRect visible = [[scrollView contentView] documentVisibleRect];
    NSRect caret = [layoutManager boundingRectForGlyphRange: NSMakeRange(glyphs - 1, 1)
                                            inTextContainer: container];
    snprintf(what, sizeof what, "%s: scrolling to the end shows the last line (visible y %.0f..%.0f, line at %.0f)",
             how, NSMinY(visible), NSMaxY(visible), NSMinY(caret));
    expect(NSMinY(visible) > 0 && NSMaxY(visible) >= NSMaxY(caret) - 1, what);
}

// Inserted through the text view as typing or pasting does.
static void testInsertText(void)
{
    NSWindow *window;
    NSScrollView *scrollView = makeScrollView(&window);
    NSTextView *textView = makeTextEditStyleView(scrollView);
    [window makeFirstResponder: textView];
    [window orderFront: nil];
    resizeWindow(window);

    [textView insertText: lines(200)];
    spin();
    checkGrown(textView, scrollView, "insertText:");

    // Typing at the end of the long text keeps the insertion point in view.
    [[scrollView contentView] scrollToPoint: NSZeroPoint];
    [textView insertText: @"end"];
    spin();
    NSRect visible = [[scrollView contentView] documentVisibleRect];
    expect(NSMinY(visible) > 0, "typing at the end scrolls the insertion point into view");
    [window orderOut: nil];
    [window release];
}

// Changed through the text storage, as a document's text is loaded.
static void testTextStorageEdit(void)
{
    NSWindow *window;
    NSScrollView *scrollView = makeScrollView(&window);
    NSTextView *textView = makeTextEditStyleView(scrollView);
    [window orderFront: nil];
    resizeWindow(window);

    [[textView textStorage] replaceCharactersInRange: NSMakeRange(0, 0) withString: lines(200)];
    spin();
    checkGrown(textView, scrollView, "text storage edit");
    [window orderOut: nil];
    [window release];
}

// A text view made with -initWithFrame: (its own text system) in a scroll view.
static void testDefaultTextView(void)
{
    NSWindow *window;
    NSScrollView *scrollView = makeScrollView(&window);
    NSSize size = [scrollView contentSize];
    NSTextView *textView = [[[NSTextView alloc] initWithFrame: NSMakeRect(0, 0, size.width, size.height)] autorelease];
    [textView setMinSize: size];
    [textView setMaxSize: NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX)];
    [[textView textContainer] setContainerSize: NSMakeSize(size.width, CGFLOAT_MAX)];
    [[textView textContainer] setWidthTracksTextView: YES];
    [[textView textContainer] setHeightTracksTextView: NO];
    [textView setVerticallyResizable: YES];
    [textView setAutoresizingMask: NSViewWidthSizable];
    [scrollView setDocumentView: textView];
    [window orderFront: nil];
    resizeWindow(window);

    [textView setString: lines(200)];
    spin();
    checkGrown(textView, scrollView, "initWithFrame: text view");
    [window orderOut: nil];
    [window release];
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        testInsertText();
        testTextStorageEdit();
        testDefaultTextView();
    }
    if (failures)
        return 1;
    puts("textview grows with text: PASS");
    return 0;
}
