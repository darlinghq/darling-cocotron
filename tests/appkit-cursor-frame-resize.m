#import <AppKit/AppKit.h>
#include <stdlib.h>

static void expect(BOOL condition, NSString *message)
{
    if (!condition)
    {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

// GUESS (not in the public documentation, not observed): which cursor answers each position and direction set (the
// documentation's table is pictures of arrows; this follows their compass directions), and that an empty set
// raises. Every EXPECT below pins that guess.
int main(void)
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    expect([NSCursor respondsToSelector:@selector(frameResizeCursorFromPosition:inDirections:)],
           @"+[NSCursor frameResizeCursorFromPosition:inDirections:] exists");
    NSCursorFrameResizeDirections in = NSCursorFrameResizeDirectionsInward;
    NSCursorFrameResizeDirections out = NSCursorFrameResizeDirectionsOutward;
    NSCursorFrameResizeDirections all = NSCursorFrameResizeDirectionsAll;
    Class c = [NSCursor class];

    expect([c frameResizeCursorFromPosition:NSCursorFrameResizePositionTop inDirections:out] == [NSCursor resizeUpCursor],
           @"GUESS: top outward is the up cursor");
    expect([c frameResizeCursorFromPosition:NSCursorFrameResizePositionTop inDirections:in] == [NSCursor resizeDownCursor],
           @"GUESS: top inward is the down cursor");
    expect([c frameResizeCursorFromPosition:NSCursorFrameResizePositionBottom inDirections:out] == [NSCursor resizeDownCursor],
           @"GUESS: bottom outward is the down cursor");
    expect([c frameResizeCursorFromPosition:NSCursorFrameResizePositionBottom inDirections:in] == [NSCursor resizeUpCursor],
           @"GUESS: bottom inward is the up cursor");
    expect([c frameResizeCursorFromPosition:NSCursorFrameResizePositionLeft inDirections:out] == [NSCursor resizeLeftCursor],
           @"GUESS: left outward is the left cursor");
    expect([c frameResizeCursorFromPosition:NSCursorFrameResizePositionLeft inDirections:in] == [NSCursor resizeRightCursor],
           @"GUESS: left inward is the right cursor");
    expect([c frameResizeCursorFromPosition:NSCursorFrameResizePositionRight inDirections:out] == [NSCursor resizeRightCursor],
           @"GUESS: right outward is the right cursor");
    expect([c frameResizeCursorFromPosition:NSCursorFrameResizePositionRight inDirections:in] == [NSCursor resizeLeftCursor],
           @"GUESS: right inward is the left cursor");
    expect([c frameResizeCursorFromPosition:NSCursorFrameResizePositionTop inDirections:all] == [NSCursor resizeUpDownCursor] &&
               [c frameResizeCursorFromPosition:NSCursorFrameResizePositionBottom inDirections:all] == [NSCursor resizeUpDownCursor],
           @"GUESS: both directions on a horizontal edge is the up-down cursor");
    expect([c frameResizeCursorFromPosition:NSCursorFrameResizePositionLeft inDirections:all] == [NSCursor resizeLeftRightCursor] &&
               [c frameResizeCursorFromPosition:NSCursorFrameResizePositionRight inDirections:all] == [NSCursor resizeLeftRightCursor],
           @"GUESS: both directions on a vertical edge is the left-right cursor");
    NSCursorFrameResizePosition TL = NSCursorFrameResizePositionTopLeft, TR = NSCursorFrameResizePositionTopRight;
    NSCursorFrameResizePosition BL = NSCursorFrameResizePositionBottomLeft, BR = NSCursorFrameResizePositionBottomRight;
    NSCursor *nwse = [c frameResizeCursorFromPosition:TL inDirections:all];
    NSCursor *nesw = [c frameResizeCursorFromPosition:TR inDirections:all];
    expect(nwse != nil && nesw != nil && nwse != nesw, @"GUESS: the two diagonals are different cursors");
    expect(nwse == [c frameResizeCursorFromPosition:BR inDirections:all] && nesw == [c frameResizeCursorFromPosition:BL inDirections:all],
           @"GUESS: opposite corners with both directions share the diagonal cursor (north-west to south-east, north-east to south-west)");
    expect(nwse == [c frameResizeCursorFromPosition:TL inDirections:all], @"GUESS: a corner cursor is shared, not made per call");
    NSCursor *northWest = [c frameResizeCursorFromPosition:TL inDirections:out];
    expect(northWest == [c frameResizeCursorFromPosition:BR inDirections:in] && northWest != nwse,
           @"GUESS: top-left outward and bottom-right inward are the north-west arrow");
    NSCursor *southEast = [c frameResizeCursorFromPosition:TL inDirections:in];
    expect(southEast == [c frameResizeCursorFromPosition:BR inDirections:out] && southEast != northWest,
           @"GUESS: top-left inward and bottom-right outward are the south-east arrow");
    NSCursor *northEast = [c frameResizeCursorFromPosition:TR inDirections:out];
    expect(northEast == [c frameResizeCursorFromPosition:BL inDirections:in] && northEast != nesw && northEast != northWest,
           @"GUESS: top-right outward and bottom-left inward are the north-east arrow");
    NSCursor *southWest = [c frameResizeCursorFromPosition:TR inDirections:in];
    expect(southWest == [c frameResizeCursorFromPosition:BL inDirections:out] && southWest != northEast && southWest != southEast,
           @"GUESS: top-right inward and bottom-left outward are the south-west arrow");
    expect(nwse != [NSCursor crosshairCursor] && nwse != [NSCursor arrowCursor] && nwse != [NSCursor resizeUpDownCursor],
           @"GUESS: a corner is none of the existing cursors");

    BOOL raised = NO;
    @try {
        [c frameResizeCursorFromPosition:NSCursorFrameResizePositionTop inDirections:0];
    } @catch (NSException *exception) {
        raised = [[exception name] isEqual:NSInvalidArgumentException];
    }
    expect(raised, @"GUESS: an empty direction set raises NSInvalidArgumentException (documented as not allowed)");

    [pool drain];
    printf("PASS: +[NSCursor frameResizeCursorFromPosition:inDirections:]\n");
    return 0;
}
