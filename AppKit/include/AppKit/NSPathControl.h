#import <AppKit/NSControl.h>
#import <AppKit/NSDragging.h>
#import <AppKit/AppKitIvarLayout.h>
#import <AppKit/NSPathCell.h>

@class NSPathComponentCell;
@class NSPathControl;
@class NSOpenPanel;

@protocol NSPathControlDelegate

//@optional

- (BOOL) pathControl: (NSPathControl *) pathControl
          acceptDrop: (id<NSDraggingInfo>) info;
- (BOOL) pathControl: (NSPathControl *) pathControl
        shouldDragPathComponentCell: (NSPathComponentCell *) pathComponentCell
                     withPasteboard: (NSPasteboard *) pasteboard;
- (NSDragOperation) pathControl: (NSPathControl *) pathControl
                   validateDrop: (id<NSDraggingInfo>) info;

- (void) pathControl: (NSPathControl *) pathControl
        willDisplayOpenPanel: (NSOpenPanel *) openPanel;
- (void) pathControl: (NSPathControl *) pathControl
        willPopUpMenu: (NSMenu *) menu;

@end

#define _NS_SIDE_NSPathControl 0, 1,
@interface NSPathControl : NSControl {
    NS_LEGACY_IVAR_PAD(_NSPathControlReserved, 20)
    NS_EXTRA_IVARS_BEGIN(NSPathControl)
        id _delegate;
    NS_SIDE_IVARS_END(NSPathControl)
}

- (NSPathStyle) pathStyle;
- (void) setPathStyle: (NSPathStyle) style;

- (NSColor *) backgroundColor;
- (void) setBackgroundColor: (NSColor *) color;

- (NSPathComponentCell *) clickedPathComponentCell;
- (NSArray *) pathComponentCells;
- (void) setPathComponentCells: (NSArray *) cells;

- (SEL) doubleAction;
- (void) setDoubleAction: (SEL) action;

- (NSURL *) URL;
- (void) setURL: (NSURL *) url;

- (id<NSPathControlDelegate>) delegate;
- (void) setDelegate: (id<NSPathControlDelegate>) delegate;

- (void) setDraggingSourceOperationMask: (NSDragOperation) mask
                               forLocal: (BOOL) isLocal;

- (NSMenu *) menu;
- (void) setMenu: (NSMenu *) menu;

@end