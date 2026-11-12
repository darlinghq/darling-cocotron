#import <Foundation/Foundation.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSScrollEdgeEffectStyle.h>
#import <AppKit/NSSearchField.h>
#import <AppKit/NSSearchFieldCell.h>
#import <AppKit/NSSearchToolbarItem.h>

int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSSearchToolbarItem *item = [[NSSearchToolbarItem alloc]
            initWithItemIdentifier: @"search"];
    if (![[item searchField] isKindOfClass: [NSSearchField class]]) return 1;
    if (![[[item searchField] cell] isKindOfClass: [NSSearchFieldCell class]]) return 2;
    if (![item resignsFirstResponderWithCancel]) return 3;

    [item setPreferredWidthForSearchField: 240];
    if ([[item searchField] frame].size.width != 240) return 4;
    [[item searchField] setStringValue: @"test"];
    NSSearchToolbarItem *copy = [item copy];
    if ([[copy searchField] frame].size.width != 240) return 5;
    if (![[[copy searchField] stringValue] isEqualToString: @"test"]) return 6;
    [copy release];

    if ([NSScrollEdgeEffectStyle hardStyle] == [NSScrollEdgeEffectStyle softStyle]) return 7;
    if (![NSImageHintSymbolScale isEqualToString: @"NSImageHintSymbolScale"]) return 8;

    [item release];
    [pool drain];
    return 0;
}
