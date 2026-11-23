// CFLAGS: -framework Foundation -framework AppKit
// Copyright (C) 2026 Lubos Dolezel
//
// NSCollectionViewItem's imageView and textField outlets: nil in a new item, kept per item, and retained, so an outlet
// outlives its other owners until it is cleared or the item goes (as observed on macOS 26.7.3 and 10.14.4; the program
// passes unchanged on both).
//
// Prints PASS or FAIL lines, then ALL PASSED or FAILED n.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
static int imagesGone, labelsGone;

static void expect(BOOL ok, const char *what)
{
    printf("%s %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        failures++;
}

@interface CountedImageView : NSImageView
@end
@implementation CountedImageView
- (void) dealloc {
    imagesGone++;
    [super dealloc];
}
@end

@interface CountedTextField : NSTextField
@end
@implementation CountedTextField
- (void) dealloc {
    labelsGone++;
    [super dealloc];
}
@end

int main(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [NSApplication sharedApplication];

    NSCollectionViewItem *item = [[NSCollectionViewItem alloc] init];
    NSCollectionViewItem *other = [[NSCollectionViewItem alloc] init];
    expect(item.imageView == nil && item.textField == nil, "a new item has no image view or text field");

    NSImageView *image;
    NSTextField *label;
    NSAutoreleasePool *inner = [[NSAutoreleasePool alloc] init];
    image = [[CountedImageView alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)];
    label = [[CountedTextField alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)];
    item.imageView = image;
    item.textField = label;
    expect(item.imageView == image, "imageView is what was set");
    expect(item.textField == label, "textField is what was set");
    expect(other.imageView == nil && other.textField == nil, "another item's outlets are its own");
    [image release];
    [label release];
    [inner release];
    expect(imagesGone == 0 && labelsGone == 0, "the outlets keep their views");

    inner = [[NSAutoreleasePool alloc] init];
    expect(item.imageView == image && item.textField == label, "the outlets still hold them");
    [other setImageView: image];
    [other setTextField: label];
    expect([other imageView] == image && [other textField] == label, "the accessor methods");
    item.imageView = nil;
    item.textField = nil;
    expect(item.imageView == nil && item.textField == nil, "outlets can be cleared");
    [inner release];
    expect(imagesGone == 0 && labelsGone == 0, "clearing one item's outlets leaves the other's views");

    inner = [[NSAutoreleasePool alloc] init];
    other.imageView = nil;
    [inner release];
    expect(imagesGone == 1, "clearing the last outlet holding a view releases it");

    [other release];
    [item release];
    expect(labelsGone == 1, "an item releases its outlets when it goes");

    printf(failures ? "FAILED %d\n" : "ALL PASSED\n", failures);
    [pool release];
    return failures != 0;
}
