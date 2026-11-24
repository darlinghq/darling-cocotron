// Copyright (C) 2026 Lubos Dolezel
#import "_NSSavePanelNavigation.h"
#import <AppKit/NSApplication.h>
#import <AppKit/NSButton.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSLayoutConstraint.h>
#import <AppKit/NSMenuItem.h>
#import <AppKit/NSPanel.h>
#import <AppKit/NSPopUpButton.h>
#import <AppKit/NSScrollView.h>
#import <AppKit/NSTableColumn.h>
#import <AppKit/NSTableHeaderView.h>
#import <AppKit/NSTextField.h>
#import <AppKit/NSWorkspace.h>
#import <objc/runtime.h>

static const char navigationKey;

static const CGFloat contentWidth = 660, contentHeight = 460;
static const CGFloat sidebarWidth = 150, margin = 16, gap = 12;

// The sidebar's table: a source list, whose selected row is a soft gray band
// with the text staying dark, on a light gray background, as in macOS's panels.
@interface _NSSavePanelSidebarTableView : NSTableView
@end

@implementation _NSSavePanelSidebarTableView
- (void) drawHighlightedSelectionForColumn: (NSInteger) column
                                       row: (NSInteger) row
                                    inRect: (NSRect) rect
{
    [[NSColor colorWithCalibratedWhite: 0.80 alpha: 1.0] setFill];
    NSRectFill(rect);
}
@end

// The file list. Its clicks go through the navigation first, see -listClickEventForEvent:.
@interface _NSSavePanelListView : NSOutlineView
@end
@implementation _NSSavePanelListView
// Typing "/" or "~" in the list starts a path: the Go to Folder sheet opens with the character in its field.
- (void) keyDown: (NSEvent *) event {
    NSString *characters = [event characters];
    NSUInteger flags = [event modifierFlags] & (NSCommandKeyMask | NSControlKeyMask | NSAlternateKeyMask);
    _NSSavePanelNavigation *navigation =
            [_NSSavePanelNavigation navigationForPanel: (NSSavePanel *) [self window]];
    if (navigation != nil && flags == 0 && [characters length] == 1 &&
        ([characters isEqual: @"/"] || [characters isEqual: @"~"])) {
        [navigation showGoToFolderWithText: characters];
        return;
    }
    [super keyDown: event];
}
- (void) mouseDown: (NSEvent *) event {
    _NSSavePanelNavigation *navigation =
            [_NSSavePanelNavigation navigationForPanel: (NSSavePanel *) [self window]];
    [super mouseDown: navigation != nil ? [navigation listClickEventForEvent: event] : event];
}
@end

@implementation _NSSavePanelNavigation

+ (_NSSavePanelNavigation *) navigationForPanel: (NSSavePanel *) panel {
    return objc_getAssociatedObject(panel, &navigationKey);
}

- (id) initWithPanel: (NSSavePanel *) panel
         outlineView: (NSOutlineView *) list
           nameField: (NSTextField *) nameField
{
    self = [super init];
    _panel = panel;
    _list = list;
    _nameField = nameField;
    _history = [[NSMutableArray alloc] init];
    _historyIndex = -1;
    _source = [[_NSFileSystemDataSource alloc] init];
    // not retained by the block: the source is owned by this object
    __block _NSSavePanelNavigation *navigation = self;
    _source.enabledBlock = ^BOOL(NSURL *url, BOOL isDirectory) {
        return [navigation _isEnabledURL: url isDirectory: isDirectory];
    };
    // The panel owns the navigation; the caller's reference can go.
    objc_setAssociatedObject(panel, &navigationKey, self,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return self;
}

- (void) detachFromViews {
    [[NSNotificationCenter defaultCenter] removeObserver: self];
    _accessory = nil;
    _accessoryHost = nil;
    [_hostWidth release];
    [_hostHeight release];
    _hostWidth = nil;
    _hostHeight = nil;
    _optionsButton = nil;
    _content = nil;
    _listScroll = nil;
    _sidebarScroll = nil;
    [_list setDataSource: nil];
    [_list setDelegate: nil];
    [_list setTarget: nil];
    [_sidebar setDataSource: nil];
    [_sidebar setDelegate: nil];
    _list = nil;
    _sidebar = nil;
}

- (void) dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver: self];
    // The list and sidebar belong to the panel's windows and are gone by now: detachFromViews already ran, while the
    // panel was being deallocated and its views were alive.
    _source.enabledBlock = nil;
    [_source release];
    [_places release];
    [_history release];
    [_notifiedDirectory release];
    [_goToSheet release];
    [super dealloc];
}

#pragma mark - Layout

static NSTextField *makeLabel(NSString *text, NSRect frame) {
    NSTextField *label = [[[NSTextField alloc] initWithFrame: frame] autorelease];
    [label setStringValue: text];
    [label setEditable: NO];
    [label setSelectable: NO];
    [label setBezeled: NO];
    [label setDrawsBackground: NO];
    return label;
}

- (NSArray *) _favoritePlaces {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSBundle *bundle = [NSBundle bundleForClass: [NSSavePanel class]];
    NSString *home = NSHomeDirectory();
    NSMutableArray *places = [NSMutableArray array];
    [places addObject: @{@"title" : NSUserName(), @"path" : home}];
    NSArray *names = @[ @"Desktop", @"Documents", @"Downloads" ];
    for (NSString *name in names) {
        NSString *path = [home stringByAppendingPathComponent: name];
        BOOL isDirectory = NO;
        if ([manager fileExistsAtPath: path isDirectory: &isDirectory] &&
            isDirectory)
            [places addObject: @{
                @"title" : NSLocalizedStringFromTableInBundle(
                        name, nil, bundle, @"A favorite folder in a file panel"),
                @"path" : path
            }];
    }
    if ([manager fileExistsAtPath: @"/Applications"])
        [places addObject: @{
            @"title" : NSLocalizedStringFromTableInBundle(
                    @"Applications", nil, bundle,
                    @"A favorite folder in a file panel"),
            @"path" : @"/Applications"
        }];
    [places addObject: @{@"title" : @"/", @"path" : @"/"}];
    return places;
}

- (void) installLayout {
    // The nib's outline view becomes the panel's list view (the subclass adds no state).
    object_setClass(_list, [_NSSavePanelListView class]);
    NSScrollView *listScroll = [_list enclosingScrollView];
    NSView *content = [listScroll superview];
    NSButton *okButton = nil, *cancelButton = nil;
    for (NSView *view in [content subviews]) {
        if (![view isKindOfClass: [NSButton class]])
            continue;
        if ([(NSButton *) view action] == @selector(_cancel:))
            cancelButton = (NSButton *) view;
        else if ([(NSButton *) view action] == @selector(_selectFile:))
            okButton = (NSButton *) view;
    }

    [_panel setContentSize: NSMakeSize(contentWidth, contentHeight)];
    [_panel setMinSize: NSMakeSize(480, 320)];

    const CGFloat buttonHeight = 28, buttonWidth = 90, rowHeight = 26;
    CGFloat listX = sidebarWidth + gap;
    CGFloat right = contentWidth - margin;

    [okButton setFrame: NSMakeRect(right - buttonWidth, margin, buttonWidth,
                                   buttonHeight)];
    [okButton setAutoresizingMask: NSViewMinXMargin | NSViewMaxYMargin];
    [okButton setKeyEquivalent: @"\r"];
    [cancelButton setFrame: NSMakeRect(right - 2 * buttonWidth - gap, margin,
                                       buttonWidth, buttonHeight)];
    [cancelButton setAutoresizingMask: NSViewMinXMargin | NSViewMaxYMargin];
    [cancelButton setKeyEquivalent: @"\033"];

    CGFloat top = contentHeight - margin;
    if (_nameField != nil) {
        NSRect labelFrame = NSMakeRect(listX, top - 22, 70, 22);
        NSTextField *label = nil;
        for (NSView *view in [content subviews])
            if ([view isKindOfClass: [NSTextField class]] && view != _nameField)
                label = (NSTextField *) view;
        [label setFrame: labelFrame];
        [label setAutoresizingMask: NSViewMinYMargin];
        [_nameField setFrame: NSMakeRect(listX + 70, top - 22,
                                         right - listX - 70, 22)];
        [_nameField setAutoresizingMask: NSViewWidthSizable | NSViewMinYMargin];
        top -= 22 + gap;
    }

    NSBundle *bundle = [NSBundle bundleForClass: [NSSavePanel class]];
    _backButton = [[[NSButton alloc]
            initWithFrame: NSMakeRect(listX, top - rowHeight, 30, rowHeight)]
            autorelease];
    _forwardButton = [[[NSButton alloc]
            initWithFrame: NSMakeRect(listX + 32, top - rowHeight, 30, rowHeight)]
            autorelease];
    [_backButton setTitle: @"<"];
    [_forwardButton setTitle: @">"];
    [_backButton setToolTip: NSLocalizedStringFromTableInBundle(
                                     @"Back", nil, bundle,
                                     @"The back button of a file panel")];
    [_forwardButton setToolTip: NSLocalizedStringFromTableInBundle(
                                        @"Forward", nil, bundle,
                                        @"The forward button of a file panel")];
    for (NSButton *button in @[ _backButton, _forwardButton ]) {
        [button setBezelStyle: NSRoundedBezelStyle];
        [button setTarget: self];
        [button setAutoresizingMask: NSViewMinYMargin];
        [content addSubview: button];
    }
    [_backButton setAction: @selector(goBack:)];
    [_forwardButton setAction: @selector(goForward:)];

    CGFloat popUpX = listX + 70;
    _pathPopUp = [[[NSPopUpButton alloc]
            initWithFrame: NSMakeRect(popUpX, top - rowHeight, right - popUpX,
                                      rowHeight)
                pullsDown: NO] autorelease];
    [_pathPopUp setTarget: self];
    [_pathPopUp setAction: @selector(_pathPopUpChanged:)];
    [_pathPopUp setAutoresizingMask: NSViewWidthSizable | NSViewMinYMargin];
    [content addSubview: _pathPopUp];
    top -= rowHeight + gap;

    CGFloat bottom = margin + buttonHeight + gap;
    [listScroll setFrame: NSMakeRect(listX, bottom, right - listX, top - bottom)];
    [listScroll setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];

    // the list: names and kinds, one folder at a time
    NSTableColumn *nameColumn = [[_list tableColumns] firstObject];
    [nameColumn setIdentifier: @"name"];
    [[nameColumn headerCell]
            setStringValue: NSLocalizedStringFromTableInBundle(
                                    @"Name", nil, bundle,
                                    @"The name column of a file panel")];
    NSTableColumn *kindColumn =
            [[[NSTableColumn alloc] initWithIdentifier: @"kind"] autorelease];
    [[kindColumn headerCell]
            setStringValue: NSLocalizedStringFromTableInBundle(
                                    @"Kind", nil, bundle,
                                    @"The kind column of a file panel")];
    [kindColumn setWidth: 110];
    [kindColumn setMinWidth: 60];
    [kindColumn setEditable: NO];
    [nameColumn setEditable: NO];
    [_list addTableColumn: kindColumn];
    [nameColumn setWidth: right - listX - 110 - 4 - 16];
    if ([_list headerView] == nil) {
        NSTableHeaderView *header = [[[NSTableHeaderView alloc]
                initWithFrame: NSMakeRect(0, 0, right - listX, 17)] autorelease];
        [_list setHeaderView: header];
    }
    [_list setColumnAutoresizingStyle: NSTableViewFirstColumnOnlyAutoresizingStyle];
    [_list setIndentationPerLevel: 0];
    [_list setDataSource: _source];
    [_list setDelegate: self];
    [_list setTarget: self];
    [_list setDoubleAction: @selector(_listDoubleClicked:)];

    // the sidebar
    _places = [[self _favoritePlaces] retain];
    NSScrollView *sidebarScroll = [[[NSScrollView alloc]
            initWithFrame: NSMakeRect(0, 0, sidebarWidth, contentHeight)]
            autorelease];
    [sidebarScroll setHasVerticalScroller: YES];
    [sidebarScroll setBorderType: NSNoBorder];
    [sidebarScroll setAutoresizingMask: NSViewHeightSizable | NSViewMaxXMargin];
    _sidebar = [[[_NSSavePanelSidebarTableView alloc]
            initWithFrame: NSMakeRect(0, 0, sidebarWidth, contentHeight)]
            autorelease];
    NSTableColumn *placeColumn =
            [[[NSTableColumn alloc] initWithIdentifier: @"place"] autorelease];
    [placeColumn setWidth: sidebarWidth];
    [placeColumn setEditable: NO];
    [_sidebar addTableColumn: placeColumn];
    [_sidebar setHeaderView: nil];
    [_sidebar setBackgroundColor: [NSColor colorWithCalibratedWhite: 0.92 alpha: 1.0]];
    [sidebarScroll setBackgroundColor: [NSColor colorWithCalibratedWhite: 0.92 alpha: 1.0]];
    [_sidebar setRowHeight: 24];
    [_sidebar setAllowsEmptySelection: YES];
    [_sidebar setAllowsMultipleSelection: NO];
    [_sidebar setDataSource: self];
    [_sidebar setDelegate: self];
    [sidebarScroll setDocumentView: _sidebar];
    [content addSubview: sidebarScroll];
    [_sidebar reloadData];
    _content = content;
    _listScroll = listScroll;
    _sidebarScroll = sidebarScroll;
    _baseSize = NSMakeSize(contentWidth, contentHeight);
    _listTopInset = contentHeight - NSMaxY([listScroll frame]);
    // The window system may answer a resize later than the call (Wayland): the layout is applied again
    // whenever the panel's size changes.
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(_panelDidResize:)
                                                 name: NSWindowDidResizeNotification
                                               object: _panel];

    [self directoryDidChange];
}

#pragma mark - The accessory view

// The accessory view sits between the file list and the row of buttons, centred in the panel, and the panel is made
// as much taller as the view is high (and as wide as the view if it is wider than the panel), so that the file list
// keeps its size. The panel follows later changes of the view's frame and replacing or removing the view. The view is
// in the panel's view hierarchy from the moment it is set, shown or not, inside a plain host view (as on macOS, where
// the view's superview is an intermediate view too). An open panel shows it only while accessoryViewDisclosed is YES,
// which its "Options" button changes; a save panel always shows it.
//
// A view laid out by Auto Layout (translatesAutoresizingMaskIntoConstraints is NO) has the size its constraints ask
// for (-fittingSize); the host pins the view to its corner at that size. A view with a frame has its frame's size.

// The top of the accessory area: the buttons and the gap above them are below it.
static CGFloat accessoryAreaBottom(void) {
    return margin + 28 + gap;
}

- (BOOL) _isOpenPanel {
    return [_panel isKindOfClass: NSClassFromString(@"NSOpenPanel")];
}

- (BOOL) _accessoryIsShown {
    return _accessory != nil && (![self _isOpenPanel] || _accessoryDisclosed);
}

- (BOOL) _accessoryUsesConstraints {
    return ![_accessory translatesAutoresizingMaskIntoConstraints];
}

// The size the accessory view asks for. The size constraints that pin a view laid out by constraints are taken out
// while its fitting size is measured, since they would decide the answer.
- (NSSize) _accessorySize {
    if (![self _accessoryUsesConstraints])
        return [_accessory frame].size;
    BOOL pinned = [[_accessoryHost constraints] containsObject: _hostWidth];
    if (pinned)
        [_accessoryHost removeConstraints: @[ _hostWidth, _hostHeight ]];
    NSSize fitting = [_accessory fittingSize];
    if (pinned)
        [_accessoryHost addConstraints: @[ _hostWidth, _hostHeight ]];
    return fitting.width > 0 && fitting.height > 0 ? fitting : [_accessory frame].size;
}

// Resizes the panel's content, keeping the top and the horizontal centre of the panel where they are.
- (void) _setPanelContentSize: (NSSize) size {
    NSRect frame = [_panel frame];
    NSRect contentRect = [_panel contentRectForFrameRect: frame];
    if (NSEqualSizes(contentRect.size, size)) {
        _hasRequest = NO;
        return;
    }
    contentRect.size = size;
    NSRect newFrame = [_panel frameRectForContentRect: contentRect];
    newFrame.origin.y = NSMaxY(frame) - NSHeight(newFrame);
    newFrame.origin.x = floor(NSMidX(frame) - NSWidth(newFrame) / 2);
    // set before the call: the window may answer within it
    _requestedSize = size;
    _hasRequest = YES;
    [_panel setFrame: newFrame display: [_panel isVisible]];
}

// Puts the views of the panel in their places for the panel's size at the moment. Safe to repeat.
- (void) _placeViews {
    BOOL shown = [self _accessoryIsShown];
    NSSize content = [_content frame].size;
    CGFloat listBottom = accessoryAreaBottom() + _reservedSize.height;
    NSRect listFrame = [_listScroll frame];
    listFrame.origin.y = listBottom;
    listFrame.size.height = MAX(content.height - _listTopInset - listBottom, 0);
    if (!NSEqualRects(listFrame, [_listScroll frame]))
        [_listScroll setFrame: listFrame];
    NSRect sidebarFrame = [_sidebarScroll frame];
    sidebarFrame.origin.y = shown ? listBottom : 0;
    sidebarFrame.size.height = MAX(content.height - sidebarFrame.origin.y, 0);
    if (!NSEqualRects(sidebarFrame, [_sidebarScroll frame]))
        [_sidebarScroll setFrame: sidebarFrame];
    if (_accessoryHost != nil && shown) {
        NSRect hostFrame = NSMakeRect(floor((content.width - _reservedSize.width) / 2), accessoryAreaBottom(),
                                      _reservedSize.width, _reservedSize.height);
        if (!NSEqualRects(hostFrame, [_accessoryHost frame]))
            [_accessoryHost setFrame: hostFrame];
    }
}

- (void) _panelDidResize: (NSNotification *) notification {
    if (_content == nil)
        return;
    NSSize live = [_content frame].size;
    if (_hasRequest) {
        // an answer to what was asked, or an earlier size still on its way
        if (NSEqualSizes(live, _requestedSize))
            _hasRequest = NO;
    } else {
        // resized by the user (or the window system): what is left of the size once the accessory view is out is
        // the panel's own
        _baseSize = NSMakeSize(live.width, live.height - _reservedSize.height);
    }
    [self _placeViews];
}

- (void) _layoutAccessory {
    // Laying the view out changes its frame and constraints, which are reported back here.
    if (_content == nil || _layingOutAccessory)
        return;
    _layingOutAccessory = YES;
    [self _layoutAccessoryNow];
    _layingOutAccessory = NO;
}

- (void) _layoutAccessoryNow {
    BOOL shown = [self _accessoryIsShown];
    NSSize wanted = shown ? [self _accessorySize] : NSZeroSize;
    _reservedSize = wanted;
    // a view wider than the panel makes it as wide; the panel is as wide as before when the view is gone or narrower
    [_panel setMinSize: NSMakeSize(MAX(480, wanted.width), 320)];
    [self _setPanelContentSize: NSMakeSize(MAX(_baseSize.width, wanted.width), _baseSize.height + wanted.height)];

    if (_accessoryHost != nil) {
        [_accessoryHost setHidden: !shown];
        if (shown) {
            if (_hostWidth != nil) {
                [_hostWidth setConstant: wanted.width];
                [_hostHeight setConstant: wanted.height];
                if (![[_accessoryHost constraints] containsObject: _hostWidth])
                    [_accessoryHost addConstraints: @[ _hostWidth, _hostHeight ]];
            }
            [_accessoryHost setAutoresizingMask: NSViewMinXMargin | NSViewMaxXMargin | NSViewMaxYMargin];
            [self _placeViews];
            [_accessory setFrameOrigin: NSZeroPoint];
            if (![self _accessoryUsesConstraints])
                [_accessory setFrameSize: wanted];
            else
                [_accessoryHost layoutSubtreeIfNeeded];
            return;
        }
    }
    [self _placeViews];
}

- (void) _accessoryFrameDidChange: (NSNotification *) notification {
    if (_layingOutAccessory)
        return;
    if ([self _accessoryIsShown] && !NSEqualSizes([self _accessorySize], _reservedSize))
        [self _layoutAccessory];
}

- (void) _toggleAccessory: (id) sender {
    [self setAccessoryViewDisclosed: [(NSButton *) sender state] == NSOnState];
}

// The "Options" button of an open panel that has an accessory view.
- (void) _updateOptionsButton {
    BOOL wanted = _accessory != nil && [self _isOpenPanel];
    if (wanted && _optionsButton == nil) {
        _optionsButton = [[[NSButton alloc]
                initWithFrame: NSMakeRect(margin, margin, 90, 28)] autorelease];
        [_optionsButton setTitle: NSLocalizedStringFromTableInBundle(
                                          @"Options", nil, [NSBundle bundleForClass: [NSSavePanel class]],
                                          @"The button of an open panel that discloses its accessory view")];
        [_optionsButton setBezelStyle: NSRoundedBezelStyle];
        [_optionsButton setButtonType: NSPushOnPushOffButton];
        [_optionsButton setTarget: self];
        [_optionsButton setAction: @selector(_toggleAccessory:)];
        [_optionsButton setAutoresizingMask: NSViewMaxXMargin | NSViewMaxYMargin];
        [_content addSubview: _optionsButton];
    }
    if (_optionsButton != nil) {
        [_optionsButton setHidden: !wanted];
        [_optionsButton setState: _accessoryDisclosed ? NSOnState : NSOffState];
    }
}

- (void) _removeAccessoryHost {
    [[NSNotificationCenter defaultCenter] removeObserver: self
                                                    name: NSViewFrameDidChangeNotification
                                                  object: _accessory];
    if ([_accessory superview] == _accessoryHost)
        [_accessory removeFromSuperview];
    [_accessoryHost removeFromSuperview];
    _accessoryHost = nil;
    [_hostWidth release];
    [_hostHeight release];
    _hostWidth = nil;
    _hostHeight = nil;
    _accessory = nil;
}

- (void) accessoryViewDidChangeFrom: (NSView *) oldView {
    if (_content == nil)
        return;
    NSView *view = [_panel accessoryView];
    if (view != _accessory) {
        if (_accessory != nil)
            [self _removeAccessoryHost];
        _accessory = view;
        if (view != nil) {
            _accessoryHost = [[[NSView alloc] initWithFrame: NSZeroRect] autorelease];
            [_accessoryHost setHidden: YES];
            [_content addSubview: _accessoryHost];
            [_accessoryHost addSubview: view];
            if ([self _accessoryUsesConstraints]) {
                // pin the view's corner, and its size once it is known, so that the constraint engine has nothing else to decide
                NSArray *pins = @[
                    [NSLayoutConstraint constraintWithItem: view attribute: NSLayoutAttributeLeading
                                                 relatedBy: NSLayoutRelationEqual toItem: _accessoryHost
                                                 attribute: NSLayoutAttributeLeading multiplier: 1 constant: 0],
                    [NSLayoutConstraint constraintWithItem: view attribute: NSLayoutAttributeTop
                                                 relatedBy: NSLayoutRelationEqual toItem: _accessoryHost
                                                 attribute: NSLayoutAttributeTop multiplier: 1 constant: 0],
                ];
                // owned here: they are in the host's constraints only while the view is shown
                _hostWidth = [[NSLayoutConstraint constraintWithItem: view attribute: NSLayoutAttributeWidth
                                                           relatedBy: NSLayoutRelationEqual toItem: nil
                                                           attribute: NSLayoutAttributeNotAnAttribute multiplier: 1 constant: 0] retain];
                _hostHeight = [[NSLayoutConstraint constraintWithItem: view attribute: NSLayoutAttributeHeight
                                                            relatedBy: NSLayoutRelationEqual toItem: nil
                                                            attribute: NSLayoutAttributeNotAnAttribute multiplier: 1 constant: 0] retain];
                [_accessoryHost addConstraints: pins];
                // the size constraints are added once the size is known, see -_layoutAccessory
            }
            [view setPostsFrameChangedNotifications: YES];
            [[NSNotificationCenter defaultCenter] addObserver: self
                                                     selector: @selector(_accessoryFrameDidChange:)
                                                         name: NSViewFrameDidChangeNotification
                                                       object: view];
        }
    }
    [self _updateOptionsButton];
    [self _layoutAccessory];
}

- (BOOL) accessoryViewDisclosed {
    return _accessoryDisclosed;
}

- (void) setAccessoryViewDisclosed: (BOOL) disclosed {
    if (_accessoryDisclosed == disclosed)
        return;
    _accessoryDisclosed = disclosed;
    [self _updateOptionsButton];
    [self _layoutAccessory];
}

#pragma mark - Which entries can be selected

- (BOOL) _isEnabledURL: (NSURL *) url isDirectory: (BOOL) isDirectory {
    BOOL enabled = [_panel _canSelectURL: url isDirectory: isDirectory];
    id delegate = [_panel delegate];
    if (enabled && [delegate respondsToSelector: @selector(panel:shouldEnableURL:)])
        enabled = [delegate panel: _panel shouldEnableURL: url];
    return enabled;
}

#pragma mark - The directory

- (void) _updatePathPopUp {
    [_pathPopUp removeAllItems];
    NSString *directory = [_panel directory];
    if ([directory length] == 0)
        directory = @"/";
    NSString *path = directory;
    while (YES) {
        NSString *title = [path isEqual: @"/"] ? @"/" : [path lastPathComponent];
        [_pathPopUp addItemWithTitle: title];
        [[_pathPopUp lastItem] setRepresentedObject: path];
        if ([path isEqual: @"/"] || [path length] == 0)
            break;
        path = [path stringByDeletingLastPathComponent];
        if ([path length] == 0)
            path = @"/";
    }
    [_pathPopUp selectItemAtIndex: 0];
}

- (void) _updateSidebarSelection {
    NSString *directory = [[_panel directory] stringByStandardizingPath];
    NSInteger match = -1;
    for (NSUInteger i = 0; i < [_places count]; i++)
        if ([[[_places objectAtIndex: i] objectForKey: @"path"]
                    isEqual: directory])
            match = i;
    _updatingSidebar = YES;
    if (match >= 0)
        [_sidebar selectRowIndexes: [NSIndexSet indexSetWithIndex: match]
              byExtendingSelection: NO];
    else
        [_sidebar deselectAll: nil];
    _updatingSidebar = NO;
}

// A double-click is two clicks on one listing. The window system counts clicks at one place in quick succession
// (a third and fourth click are what a second double-click on the same spot is), but once the list shows another
// folder the clicks made on the earlier one are no part of the next click sequence: a double-click on a folder
// entered by double-click must enter the next one, not be taken for a third and fourth click.
- (NSEvent *) listClickEventForEvent: (NSEvent *) event {
    if ([event type] != NSLeftMouseDown)
        return event;
    NSInteger count = [event clickCount];
    if (count <= 1)
        _clickCountOffset = 0;
    _lastClickCount = count;
    NSInteger effective = count - _clickCountOffset;
    if (effective < 1)
        effective = 1;
    if (effective == count)
        return event;
    return [NSEvent mouseEventWithType: [event type]
                              location: [event locationInWindow]
                         modifierFlags: [event modifierFlags]
                             timestamp: [event timestamp]
                          windowNumber: [event windowNumber]
                               context: nil
                           eventNumber: [event eventNumber]
                            clickCount: effective
                              pressure: 1.0];
}

- (void) reloadList {
    _clickCountOffset = _lastClickCount;
    NSString *directory = [_panel directory];
    [_source setRootURL: [directory length] > 0
                                 ? [NSURL fileURLWithPath: directory isDirectory: YES]
                                 : nil];
    [_source setShowsHiddenFiles: [_panel showsHiddenFiles]];
    // Entries are only offered to the delegate once the panel is on screen.
    if (_shown)
        [_source reload];
    [_list deselectAll: nil];
    [_list reloadData];
}

- (void) _notifyDirectoryChange {
    NSString *directory = [_panel directory];
    id delegate = [_panel delegate];
    if (![directory length] || [directory isEqual: _notifiedDirectory])
        return;
    [_notifiedDirectory release];
    _notifiedDirectory = [directory copy];
    if ([delegate respondsToSelector: @selector(panel:didChangeToDirectoryURL:)])
        [delegate panel: _panel
                didChangeToDirectoryURL: [NSURL fileURLWithPath: directory
                                                    isDirectory: YES]];
}

- (void) _updateHistory {
    NSString *directory = [_panel directory];
    if (!_navigatingHistory && [directory length] > 0 &&
        ![directory isEqual: [_history lastObject]] &&
        !(_historyIndex >= 0 &&
          [directory isEqual: [_history objectAtIndex: _historyIndex]])) {
        while ((NSInteger) [_history count] > _historyIndex + 1)
            [_history removeLastObject];
        [_history addObject: directory];
        _historyIndex = [_history count] - 1;
    }
    [_backButton setEnabled: _historyIndex > 0];
    [_forwardButton setEnabled: _historyIndex + 1 < (NSInteger) [_history count]];
}

- (void) directoryDidChange {
    [self _updatePathPopUp];
    [self _updateSidebarSelection];
    [self _updateHistory];
    [self reloadList];
    if (_shown)
        [self _notifyDirectoryChange];
}

- (void) panelWillShow {
    _shown = YES;
    NSBundle *bundle = [NSBundle bundleForClass: [NSSavePanel class]];
    for (NSView *view in [[[_list enclosingScrollView] superview] subviews]) {
        if (![view isKindOfClass: [NSButton class]] ||
            [(NSButton *) view action] != @selector(_selectFile:))
            continue;
        NSString *prompt = [_panel prompt];
        if ([prompt length] == 0)
            prompt = [_panel isKindOfClass: NSClassFromString(@"NSOpenPanel")]
                             ? NSLocalizedStringFromTableInBundle(
                                       @"Open", nil, bundle,
                                       @"The default button of the open panel")
                             : NSLocalizedStringFromTableInBundle(
                                       @"Save", nil, bundle,
                                       @"The default button of the save panel");
        [(NSButton *) view setTitle: prompt];
    }
    if ([_panel respondsToSelector: @selector(allowsMultipleSelection)])
        [_list setAllowsMultipleSelection:
                       [(id) _panel allowsMultipleSelection]];
    [self reloadList];
    [self _notifyDirectoryChange];
}

- (void) panelDidEnd {
    _shown = NO;
    [_notifiedDirectory release];
    _notifiedDirectory = nil;
}

#pragma mark - Moving around

- (void) goUp {
    NSString *directory = [_panel directory];
    if ([directory length] == 0 || [directory isEqual: @"/"])
        return;
    [_panel setDirectory: [directory stringByDeletingLastPathComponent]];
}

- (void) _goToHistoryIndex: (NSInteger) index {
    if (index < 0 || index >= (NSInteger) [_history count])
        return;
    _historyIndex = index;
    _navigatingHistory = YES;
    [_panel setDirectory: [_history objectAtIndex: index]];
    _navigatingHistory = NO;
    [self _updateHistory];
}

- (IBAction) goBack: (id) sender {
    [self _goToHistoryIndex: _historyIndex - 1];
}

- (IBAction) goForward: (id) sender {
    [self _goToHistoryIndex: _historyIndex + 1];
}

- (IBAction) _pathPopUpChanged: (id) sender {
    NSString *path = [[_pathPopUp selectedItem] representedObject];
    if ([path length] > 0)
        [_panel setDirectory: path];
}

- (NSURL *) selectedFolderToOpen {
    if ([_list numberOfSelectedRows] != 1)
        return nil;
    NSURL *url = [_list itemAtRow: [_list selectedRow]];
    if ([_source isDirectoryEntry: url] && [_source isEnabledEntry: url] &&
        ![[NSWorkspace sharedWorkspace] isFilePackageAtPath: [url path]])
        return url;
    return nil;
}

- (IBAction) _listDoubleClicked: (id) sender {
    NSInteger row = [_list clickedRow];
    if (row < 0)
        return;
    NSURL *url = [_list itemAtRow: row];
    if (![_source isEnabledEntry: url])
        return;
    if ([_source isDirectoryEntry: url] &&
        ![[NSWorkspace sharedWorkspace] isFilePackageAtPath: [url path]])
        [_panel setDirectory: [url path]];
    else
        [_panel _selectFile: self];
}

#pragma mark - Go to Folder

- (void) showGoToFolder {
    [self showGoToFolderWithText: @""];
}

- (void) showGoToFolderWithText: (NSString *) text {
    if (_goToSheet != nil)
        return;
    NSBundle *bundle = [NSBundle bundleForClass: [NSSavePanel class]];
    const CGFloat width = 420, height = 130;
    _goToSheet = [[NSPanel alloc]
            initWithContentRect: NSMakeRect(0, 0, width, height)
                      styleMask: NSTitledWindowMask
                        backing: NSBackingStoreBuffered
                          defer: NO];
    NSView *content = [_goToSheet contentView];
    [content addSubview:
                     makeLabel(NSLocalizedStringFromTableInBundle(
                                       @"Go to the folder:", nil, bundle,
                                       @"The prompt of the Go to Folder sheet"),
                               NSMakeRect(margin, height - 36, width - 2 * margin,
                                          20))];
    _goToField = [[[NSTextField alloc]
            initWithFrame: NSMakeRect(margin, height - 64, width - 2 * margin, 24)]
            autorelease];
    [_goToField setStringValue: text];
    [content addSubview: _goToField];
    _goToMessage = makeLabel(@"", NSMakeRect(margin, height - 86,
                                             width - 2 * margin, 18));
    [content addSubview: _goToMessage];

    NSButton *go = [[[NSButton alloc]
            initWithFrame: NSMakeRect(width - margin - 80, 12, 80, 28)] autorelease];
    [go setTitle: NSLocalizedStringFromTableInBundle(
                          @"Go", nil, bundle, @"The Go to Folder sheet's button")];
    [go setBezelStyle: NSRoundedBezelStyle];
    [go setKeyEquivalent: @"\r"];
    [go setTarget: self];
    [go setAction: @selector(_goToFolderConfirmed:)];
    [content addSubview: go];
    NSButton *cancel = [[[NSButton alloc]
            initWithFrame: NSMakeRect(width - margin - 172, 12, 80, 28)] autorelease];
    [cancel setTitle: NSLocalizedStringFromTableInBundle(
                              @"Cancel", nil, bundle,
                              @"The Go to Folder sheet's cancel button")];
    [cancel setBezelStyle: NSRoundedBezelStyle];
    [cancel setKeyEquivalent: @"\033"];
    [cancel setTarget: self];
    [cancel setAction: @selector(_goToFolderCancelled:)];
    [content addSubview: cancel];

    [_goToSheet makeFirstResponder: _goToField];
    if ([text length] > 0)
        [[_goToField currentEditor] setSelectedRange: NSMakeRange([text length], 0)];
    [NSApp beginSheet: _goToSheet
            modalForWindow: _panel
             modalDelegate: self
            didEndSelector: @selector(_goToSheetDidEnd:returnCode:contextInfo:)
               contextInfo: NULL];
}

- (void) _goToSheetDidEnd: (NSWindow *) sheet
               returnCode: (NSInteger) code
              contextInfo: (void *) info
{
    [sheet orderOut: nil];
    [_goToSheet release];
    _goToSheet = nil;
    _goToField = nil;
    _goToMessage = nil;
}

- (IBAction) _goToFolderCancelled: (id) sender {
    [NSApp endSheet: _goToSheet returnCode: NSCancelButton];
}

- (IBAction) _goToFolderConfirmed: (id) sender {
    NSString *typed = [[_goToField stringValue]
            stringByTrimmingCharactersInSet:
                    [NSCharacterSet whitespaceCharacterSet]];
    NSString *path = [typed stringByExpandingTildeInPath];
    if (![path isAbsolutePath])
        path = [[_panel directory] stringByAppendingPathComponent: path];
    path = [path stringByStandardizingPath];

    BOOL isDirectory = NO;
    if ([typed length] == 0 ||
        ![[NSFileManager defaultManager] fileExistsAtPath: path
                                              isDirectory: &isDirectory]) {
        [_goToMessage setStringValue:
                              NSLocalizedStringFromTableInBundle(
                                      @"The folder can't be found.", nil,
                                      [NSBundle bundleForClass: [NSSavePanel class]],
                                      @"Shown when Go to Folder gets a missing path")];
        NSBeep();
        return;
    }
    // a file: show the folder holding it
    NSString *selectName = nil;
    if (!isDirectory) {
        selectName = [path lastPathComponent];
        path = [path stringByDeletingLastPathComponent];
    }
    [NSApp endSheet: _goToSheet returnCode: NSOKButton];
    [_panel setDirectory: path];
    if (selectName != nil) {
        NSArray *entries = [_source entries];
        for (NSUInteger i = 0; i < [entries count]; i++)
            if ([[[entries objectAtIndex: i] lastPathComponent]
                        isEqual: selectName] &&
                [_source isEnabledEntry: [entries objectAtIndex: i]])
                [_list selectRowIndexes: [NSIndexSet indexSetWithIndex: i]
                   byExtendingSelection: NO];
    }
}

- (BOOL) handleKeyEquivalent: (NSEvent *) event {
    if ([event type] != NSKeyDown)
        return NO;
    NSUInteger flags = [event modifierFlags] & (NSCommandKeyMask | NSShiftKeyMask |
                                                NSAlternateKeyMask |
                                                NSControlKeyMask);
    NSString *key = [event charactersIgnoringModifiers];
    if ([key length] != 1)
        return NO;
    unichar c = [key characterAtIndex: 0];
    if (flags == (NSCommandKeyMask | NSShiftKeyMask) && (c == 'g' || c == 'G')) {
        [self showGoToFolder];
        return YES;
    }
    if (flags == (NSCommandKeyMask | NSShiftKeyMask) && (c == '.' || c == '>')) {
        [_panel setShowsHiddenFiles: ![_panel showsHiddenFiles]];
        [self reloadList];
        return YES;
    }
    if (flags == NSCommandKeyMask && c == '[') {
        [self goBack: nil];
        return YES;
    }
    if (flags == NSCommandKeyMask && c == ']') {
        [self goForward: nil];
        return YES;
    }
    if (flags == NSCommandKeyMask && c == NSUpArrowFunctionKey) {
        [self goUp];
        return YES;
    }
    return NO;
}

#pragma mark - The sidebar

- (NSInteger) numberOfRowsInTableView: (NSTableView *) tableView {
    return [_places count];
}

- (id) tableView: (NSTableView *) tableView
        objectValueForTableColumn: (NSTableColumn *) column
                              row: (NSInteger) row
{
    return [[_places objectAtIndex: row] objectForKey: @"title"];
}

- (void) tableView: (NSTableView *) tableView
        willDisplayCell: (id) cell
         forTableColumn: (NSTableColumn *) column
                    row: (NSInteger) row
{
    if (tableView == _sidebar) {
        [cell setTextColor: [NSColor blackColor]];
    }
}

- (void) tableViewSelectionDidChange: (NSNotification *) notification {
    if ([notification object] != _sidebar || _updatingSidebar)
        return;
    NSInteger row = [_sidebar selectedRow];
    if (row >= 0)
        [_panel setDirectory: [[_places objectAtIndex: row] objectForKey: @"path"]];
}

#pragma mark - The list

- (BOOL) outlineView: (NSOutlineView *) outlineView shouldSelectItem: (NSURL *) url {
    return [_source isEnabledEntry: url];
}

- (void) outlineView: (NSOutlineView *) outlineView
         willDisplayCell: (id) cell
          forTableColumn: (NSTableColumn *) column
                    item: (NSURL *) url
{
    [cell setEnabled: [_source isEnabledEntry: url]];
}

- (void) outlineViewSelectionDidChange: (NSNotification *) notification {
    [_panel _navigationSelectionChanged];
}

@end
