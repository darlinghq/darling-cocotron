//
//  NSStatusItem+Private.h
//  AppKit
//
//  Created by Rhys Cox on 17/02/2012.
//  Copyright (c) 2012 BP Software. All rights reserved.
//
#import <CoreFoundation/CFBase.h>
#import <Foundation/Foundation.h>
#import <AppKit/NSStatusItem.h>
@class NSImage, NSStatusItem, NSMenuItem;
@interface NSStatusBarButton (Private)
- (void) _setStatusItem: (NSStatusItem *) item;
@end
@interface NSStatusItem (Private)
// The item joins and leaves the system tray along with the status bar.
- (void) _attachToStatusBar;
- (void) _detachFromStatusBar;
// Something about the item changed (see NSStatusItemNotifier.h).
- (void) _contentChanged: (NSUInteger) aspects;
// The primary (or secondary) click of the system tray: sends the action.
- (void) _sendActionForClick: (BOOL) secondary;
- (NSString *) _defaultAutosaveName;
- (void) _setDefaultAutosaveName: (NSString *) name;
- (void) _showContextMenu;
@end