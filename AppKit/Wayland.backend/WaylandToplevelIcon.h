/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/

#import <Foundation/Foundation.h>
#include <wayland-util.h>

@class WaylandDisplay;

// The xdg-toplevel-icon protocol (xdg_toplevel_icon_manager_v1): gives every toplevel the application icon,
// -[NSApplication applicationIconImage], as wl_shm buffers, so the compositor shows it in decorations, task
// lists and switchers instead of looking for a desktop entry named after the app_id. One icon object serves
// all windows. The icon is rendered at the sizes the compositor prefers (its icon_size events, or a default
// list when it names none), at scale 1 and 2.
@interface WaylandToplevelIcons : NSObject {
    WaylandDisplay *_display; // owner, not retained
    struct wl_proxy *_manager;
    uint32_t _name;
    NSMutableArray *_sizes, *_pendingSizes;
    // The icon given to the windows and the buffers it refers to (they must outlive it). Both are created
    // when a window first needs them and again when the sizes or the application icon change.
    struct wl_proxy *_icon;
    NSMutableArray *_buffers;
    BOOL _built;
}

- (instancetype) initWithDisplay: (WaylandDisplay *) display;
// The manager's proxy and the registry name it was bound from.
- (void) setManager: (struct wl_proxy *) manager name: (uint32_t) name;
- (uint32_t) name;

- (void) handleEvent: (uint32_t) opcode arguments: (union wl_argument *) args;

// The application icon (or the compositor's size preference) changed: renders it again and gives it to
// every window.
- (void) applicationIconChanged;

// Gives the toplevel the current icon, or clears the icon when the application has none and the toplevel
// had one (*hadIcon says whether it did, and is updated). Returns YES when a request was sent, which takes
// effect with the surface's next commit.
- (BOOL) applyToToplevel: (struct wl_proxy *) toplevel hadIcon: (BOOL *) hadIcon;

// The global went away: the icon and its buffers are released; windows keep what they were given.
- (void) managerRemoved;

@end
