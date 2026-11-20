// Copyright (C) 2026 Lubos Dolezel
#import <AppKit/NSSavePanel.h>
#import <AppKit/NSTableView.h>
#import <AppKit/NSOutlineView.h>
#import "_NSFileSystemDataSource.h"

@class NSButton, NSPopUpButton, NSTextField;

// What the panels need to know about a panel for the navigation controls.
@interface NSSavePanel (NavigationSupport)
// Whether the user may select this entry of the shown folder.
- (BOOL) _canSelectURL: (NSURL *) url isDirectory: (BOOL) isDirectory;
- (void) _navigationSelectionChanged;
- (void) _installNavigation;
- (BOOL) _packageAtURL: (NSURL *) url;
- (BOOL) _fileURLMatchesAllowedTypes: (NSURL *) url;
- (BOOL) _validatePaths: (NSArray *) paths;
- (IBAction) _selectFile: (id) sender;
@end

// The controls around a panel's file list: a path pop-up, back and forward
// buttons, a sidebar of favorite folders and the Go to Folder sheet, and the
// behaviour behind them. The panel owns it (associated object) and sends it
// every change of the panel's directory.
@interface _NSSavePanelNavigation
        : NSObject <NSTableViewDataSource, NSTableViewDelegate, NSOutlineViewDelegate> {
    NSSavePanel *_panel; // not retained: the panel owns this object
    NSOutlineView *_list;
    NSTextField *_nameField; // the save panel's, or nil
    _NSFileSystemDataSource *_source;
    NSPopUpButton *_pathPopUp;
    NSButton *_backButton;
    NSButton *_forwardButton;
    NSTableView *_sidebar;
    NSArray *_places;
    NSMutableArray *_history;
    NSInteger _historyIndex;
    BOOL _navigatingHistory;
    BOOL _updatingSidebar;
    BOOL _shown;
    NSString *_notifiedDirectory;
    NSPanel *_goToSheet;
    NSTextField *_goToField;
    NSTextField *_goToMessage;
    NSInteger _lastClickCount;   // the click count of the latest mouse-down in the list
    NSInteger _clickCountOffset; // the clicks of that sequence that were made in an earlier listing
}

+ (_NSSavePanelNavigation *) navigationForPanel: (NSSavePanel *) panel;
- (id) initWithPanel: (NSSavePanel *) panel
         outlineView: (NSOutlineView *) list
           nameField: (NSTextField *) nameField;

// Rearranges the panel's window: sidebar, path row, list, buttons.
- (void) installLayout;
// The panel's directory or filtering settings changed.
- (void) directoryDidChange;
- (void) reloadList;
- (void) panelWillShow;
- (void) panelDidEnd;
// Breaks the links from the panel's views back to this object; called when the panel is deallocated.
- (void) detachFromViews;

- (void) goUp;
- (IBAction) goBack: (id) sender;
- (IBAction) goForward: (id) sender;
- (void) showGoToFolder;
// The Go to Folder sheet with text already in its field (the character that was typed to open it).
- (void) showGoToFolderWithText: (NSString *) text;
// The folder shown in the list, a folder the user chose in it, or nil.
- (NSURL *) selectedFolderToOpen;
- (BOOL) handleKeyEquivalent: (NSEvent *) event;
// The event a mouse-down in the list is handled as: clicks made in a listing that has since been replaced do not
// count towards a multiple click in the new one.
- (NSEvent *) listClickEventForEvent: (NSEvent *) event;
@end
