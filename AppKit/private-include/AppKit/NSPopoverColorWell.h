#import <AppKit/NSColorWell.h>
#import <AppKit/NSPopover.h>
#import <AppKit/NSViewController.h>

@class NSButton, NSColorList, NSColorPopoverController;

@interface NSColorWell (NSPopoverColorWell)
+ (NSColorWell *)_exclusiveColorPanelOwner;
- (BOOL)_activationShowsColorPanel;
@end

// A grid of color swatches from a color list, filled row by row (macOS AppKit SPI).
@interface NSColorPickerMatrixView : NSView {
    NSColorList *_colorList;
    NSArray *_colors;
    NSUInteger _numberOfColumns;
    NSSize _swatchSize;
    NSInteger _selectedIndex;
    id _delegate;
}
@property (assign) id delegate;
@property (retain) NSColorList *colorList;
@property NSUInteger numberOfColumns;
@property NSSize swatchSize;
@property (readonly) NSUInteger numberOfRows;
- (NSColor *)colorAtIndex:(NSUInteger)index;
- (NSRect)rectForColorAtIndex:(NSUInteger)index;
// NSNotFound when no swatch is at the point.
- (NSUInteger)colorIndexAtPoint:(NSPoint)point;
- (void)selectColorAtIndex:(NSUInteger)index;
@end

// The content of a popover color well's popover: a bar of colors, a grid of colors and a button
// that shows the color panel (macOS AppKit SPI). The delegate is the color well.
@interface NSColorPopoverController : NSViewController {
    id _delegate;
    NSPopover *_popover;
    NSColorPickerMatrixView *_topBarMatrixView;
    NSColorPickerMatrixView *_matrixView;
    NSButton *_showColorsButton;
}
@property (assign) id delegate;
@property (assign) NSPopover *popover;
// Available once the view is loaded.
@property (assign) NSColorPickerMatrixView *topBarMatrixView;
@end

// A color well that shows a popover of colors when clicked, rather than the color panel
// (macOS AppKit SPI).
@interface NSPopoverColorWell : NSColorWell <NSPopoverDelegate> {
    NSPopover *_popover;
}
- (void)_showPopover;
@end
