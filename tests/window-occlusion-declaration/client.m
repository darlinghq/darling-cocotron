#import <AppKit/NSWindow.h>
BOOL authoredWindowVisible(NSWindow *window) {
 return (window.occlusionState & NSWindowOcclusionStateVisible) != 0;
}
