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

@interface Target : NSObject
@property NSInteger clicks;
- (void)click:(id)sender;
@end
@implementation Target
- (void)click:(id)sender
{
    self.clicks++;
}
@end

int main(void)
{
    @autoreleasepool
    {
        [NSApplication sharedApplication];
        Target *target = [[[Target alloc] init] autorelease];
        NSImage *image = [[[NSImage alloc] initWithSize:NSMakeSize(16, 16)] autorelease];

        NSButton *push = [NSButton buttonWithTitle:@"Clear" target:target action:@selector(click:)];
        expect([push.title isEqual:@"Clear"] && push.target == target && push.action == @selector(click:), @"push button title, target, action");
        expect(push.bezelStyle == NSRoundedBezelStyle, @"push button bezel");
        expect(push.frame.size.width > 0 && push.frame.size.height > 0, @"push button is sized to fit");
        [push performClick:nil];
        expect(target.clicks == 1, @"push button sends its action");

        NSButton *withImage = [NSButton buttonWithTitle:@"Share" image:image target:target action:@selector(click:)];
        expect([withImage.title isEqual:@"Share"] && withImage.image == image && withImage.imagePosition == NSImageLeft,
               @"title and image button");

        NSButton *imageOnly = [NSButton buttonWithImage:image target:target action:@selector(click:)];
        expect(imageOnly.image == image && imageOnly.imagePosition == NSImageOnly, @"image button");

        NSButton *checkbox = [NSButton checkboxWithTitle:@"Wrap" target:target action:@selector(click:)];
        expect([checkbox.title isEqual:@"Wrap"] && checkbox.state == NSControlStateValueOff, @"checkbox starts off");
        [checkbox performClick:nil];
        expect(checkbox.state == NSControlStateValueOn && target.clicks == 2, @"checkbox toggles and sends its action");

        NSButton *radio = [NSButton radioButtonWithTitle:@"All" target:target action:@selector(click:)];
        [radio performClick:nil];
        expect([radio.title isEqual:@"All"] && radio.state == NSControlStateValueOn, @"radio button turns on");
        NSLog(@"PASS: NSButton convenience constructors");
    }
    return 0;
}
