#import <AppKit/AppKit.h>

// The nib loader's connector class is not in the public headers; reach it by name.
@interface NSObject (NibHelpConnector)
- (void)setFile:(NSString *)file;
- (void)setMarker:(NSString *)marker;
- (void)setDestination:(id)destination;
- (void)establishConnection;
@end
#include <stdlib.h>

static void expect(BOOL condition, NSString *message)
{
    if (!condition)
    {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

// Interface Builder attaches a control's tool tip to its cell. NSCell has no -setToolTip:, so the nib help
// connector must not send it there; it goes to the control the cell belongs to, which a cell knows as soon as
// the control has installed it (before any drawing, as at nib load). A tip for a destination that is neither
// a cell nor a view is ignored.
int main(void)
{
    @autoreleasepool
    {
        // A control's cell knows its control after -setCell:, after -initWithFrame: and after a keyed round trip.
        NSButton *button = [[[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 80, 24)] autorelease];
        expect([[button cell] controlView] == button, @"-initWithFrame: attaches the default cell to its control");
        NSButtonCell *buttonCell = [[[NSButtonCell alloc] init] autorelease];
        [button setCell:buttonCell];
        expect([buttonCell controlView] == button, @"-setCell: attaches the cell to its control before any drawing");

        NSData *data = [NSKeyedArchiver archivedDataWithRootObject:button];
        NSButton *decoded = [NSKeyedUnarchiver unarchiveObjectWithData:data];
        expect(decoded != nil && [decoded cell] != nil, @"the button survives a keyed round trip with its cell");
        expect([[decoded cell] controlView] == decoded, @"a decoded control's cell knows its control");

        id connector = [[[NSClassFromString(@"NSNibHelpConnector") alloc] init] autorelease];
        [connector setFile:@"NSToolTipHelpKey"];
        [connector setMarker:@"A tip"];

        [connector setDestination:[decoded cell]];
        @try
        {
            [connector establishConnection];
        }
        @catch (NSException *exception)
        {
            expect(NO, [NSString stringWithFormat:@"establishConnection raised %@: %@", exception.name, exception.reason]);
        }
        expect([[decoded toolTip] isEqualToString:@"A tip"], @"the cell's tool tip lands on its decoded control");

        NSButtonCell *loose = [[[NSButtonCell alloc] init] autorelease];
        [connector setDestination:loose];
        [connector establishConnection]; // a cell without a control has nowhere to show a tip: no exception

        [connector setDestination:[[[NSObject alloc] init] autorelease]];
        [connector establishConnection]; // neither a cell nor tooltip capable: ignored, not an unrecognized selector

        NSMatrix *matrix = [[[NSMatrix alloc] initWithFrame:NSMakeRect(0, 0, 80, 24)] autorelease];
        NSButtonCell *matrixCell = [[[NSButtonCell alloc] init] autorelease];
        [matrixCell setControlView:matrix];
        [connector setDestination:matrixCell];
        [connector establishConnection];
        expect([matrix toolTip] == nil, @"a cell in a matrix does not overwrite the matrix's own tool tip");

        NSButton *other = [[[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 80, 24)] autorelease];
        [connector setDestination:other];
        [connector establishConnection];
        expect([[other toolTip] isEqualToString:@"A tip"], @"a view destination still gets its tool tip");
        NSLog(@"PASS: nib help connector tool tips for cells");
    }
    return 0;
}
