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
#ifdef WIN32
#import <windows.h>
#endif
@class NSImage, NSStatusItem, NSMenuItem;
#ifndef WIN32
@interface NSStatusBarButton (Private)
- (void) _setStatusItem: (NSStatusItem *) item;
@end
#endif
@interface NSStatusItem (Private)
#ifdef WIN32
- (void) _createTrayIcon;
- (void) _setHICONFromImage: (NSImage *) image;
- (void) _removeTrayIcon;
- (int) trayIconID;
- (void) _processWin32Event: (int) event;
- (void) _w32loadMenuItem: (NSMenuItem *) item
           withIdentifier: (int) i
                 intoMenu: (HMENU) menu;
HWND _eventhWnd;
NOTIFYICONDATA niData;
#endif
#ifndef WIN32
// The item joins and leaves the system tray along with the status bar.
- (void) _attachToStatusBar;
- (void) _detachFromStatusBar;
// Something about the item changed (see NSStatusItemNotifier.h).
- (void) _contentChanged: (NSUInteger) aspects;
// The primary (or secondary) click of the system tray: sends the action.
- (void) _sendActionForClick: (BOOL) secondary;
#endif
- (NSString *) _defaultAutosaveName;
- (void) _setDefaultAutosaveName: (NSString *) name;
- (void) _showContextMenu;
@end