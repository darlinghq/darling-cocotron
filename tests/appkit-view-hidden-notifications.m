/*
 * This file is part of Darling.
 *
 * Copyright (C) 2026 Lubos Dolezel
 *
 * Darling is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * Darling is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with Darling.  If not, see <http://www.gnu.org/licenses/>.
 */

/*
 * -viewDidHide and -viewDidUnhide are sent to a view when it is hidden or
 * shown, directly or because an ancestor was hidden or shown. The expected
 * traces were observed on macOS 26.7.3 (x86_64) with this program:
 * - hiding or showing a view tells the view and its subviews, superviews
 *   first, except subviews that are hidden themselves;
 * - nothing is sent when the effective state does not change (hiding a view
 *   under a hidden ancestor, showing it while the ancestor stays hidden);
 * - moving a view into or out of a hidden superview tells it and its
 *   subviews, between -viewWillMoveToSuperview: and -viewDidMoveToSuperview.
 *
 * Needs no display (the window is never shown). No ARC.
 */
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <string.h>

static NSMutableString *trace;
static int failures;

@interface TraceView : NSView {
@public
	const char *name;
}
@end

@implementation TraceView
- (void)viewDidHide { [trace appendFormat: @"%s:hide ", name]; }
- (void)viewDidUnhide { [trace appendFormat: @"%s:unhide ", name]; }
- (void)viewWillMoveToSuperview:(NSView *)superview { [trace appendFormat: @"%s:willMove ", name]; }
- (void)viewDidMoveToSuperview { [trace appendFormat: @"%s:didMove ", name]; }
@end

static TraceView *makeView(const char *name)
{
	TraceView *view = [[TraceView alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)];
	view->name = name;
	return view;
}

static void checkTrace(const char *step, const char *expected)
{
	const char *got = [[trace stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]] UTF8String];
	if (strcmp(got, expected) == 0) {
		printf("PASS: %s\n", step);
	} else {
		printf("FAIL: %s: got \"%s\", expected \"%s\"\n", step, got, expected);
		failures++;
	}
	[trace setString: @""];
}

static void run(BOOL inWindow)
{
	printf("-- %s\n", inWindow ? "in a window" : "without a window");
	TraceView *a = makeView("A"), *b = makeView("B"), *c = makeView("C"), *d = makeView("D"), *e = makeView("E");
	NSWindow *window = nil;
	[a addSubview: b];
	[b addSubview: c];
	[a addSubview: d];
	[d addSubview: e];
	if (inWindow) {
		window = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 100, 100)
		                                     styleMask: NSWindowStyleMaskBorderless
		                                       backing: NSBackingStoreBuffered
		                                         defer: YES];
		[[window contentView] addSubview: a];
	}
	[trace setString: @""];

	[d setHidden: YES];
	checkTrace("hide a view with a subview", "D:hide E:hide");
	[a setHidden: YES];
	checkTrace("hide the ancestor: a hidden subview is not told", "A:hide B:hide C:hide");
	[a setHidden: YES];
	checkTrace("hide it again", "");
	[a setHidden: NO];
	checkTrace("show the ancestor", "A:unhide B:unhide C:unhide");
	[b setHidden: YES];
	checkTrace("hide a middle view", "B:hide C:hide");
	[a setHidden: YES];
	checkTrace("hide the ancestor of a hidden view", "A:hide");
	[b setHidden: NO];
	checkTrace("show a view under a hidden ancestor", "");
	[a setHidden: NO];
	checkTrace("show the ancestor again", "A:unhide B:unhide C:unhide");
	[d setHidden: NO];
	checkTrace("show the view with a subview", "D:unhide E:unhide");

	TraceView *f = makeView("F"), *g = makeView("G"), *h = makeView("H");
	[f addSubview: g];
	[h setHidden: YES];
	[f addSubview: h];
	[a setHidden: YES];
	[trace setString: @""];
	[a addSubview: f];
	checkTrace("add a view to a hidden superview", "F:willMove F:hide G:hide F:didMove");
	[inWindow ? [window contentView] : [[NSView alloc] initWithFrame: NSZeroRect] addSubview: f];
	checkTrace("move it to a shown superview", "F:willMove F:unhide G:unhide F:didMove");
	TraceView *x = makeView("X");
	[a addSubview: x];
	checkTrace("add another view to the hidden superview", "X:willMove X:hide X:didMove");
	[a replaceSubview: x with: f];
	checkTrace("replace it with the view", "F:willMove F:hide G:hide F:didMove X:willMove X:unhide X:didMove");
	[f removeFromSuperview];
	checkTrace("remove the view from the hidden superview", "F:willMove F:unhide G:unhide F:didMove");
	[h removeFromSuperview];
	[trace setString: @""];
	[a addSubview: h];
	checkTrace("add a hidden view to the hidden superview", "H:willMove H:didMove");
	[a setHidden: NO];
	[trace setString: @""];
}

int main(void)
{
	@autoreleasepool {
		trace = [[NSMutableString alloc] init];
		[NSApplication sharedApplication];
		run(NO);
		run(YES);
	}
	printf("%s\n", failures ? "FAIL" : "PASS");
	return failures ? 1 : 0;
}
