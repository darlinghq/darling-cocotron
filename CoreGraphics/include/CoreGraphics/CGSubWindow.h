#ifdef __OBJC__

#import <CoreGraphics/CGGeometry.h>
#import <Foundation/Foundation.h>

@interface CGSubWindow : NSObject

- (void *) nativeWindow;

// Whether the owner may draw into the parent window's own drawable instead of
// this subwindow's while the subwindow covers the whole parent (NO by default).
- (void) setAllowsParentDrawable: (BOOL) allowed;
// Whether what the owner draws waits for the display refresh.
- (void) setSyncsToDisplay: (BOOL) syncs;
// The parent window's drawable (a CGL window) when the owner may and can draw
// into it, NULL to draw into -nativeWindow. The parent keeps it. Called again,
// it re-evaluates, as the subwindow's or its parent's geometry may have changed.
- (void *) sharedCGLWindow;

- (void) show;
- (void) hide;

- (void) setFrame: (CGRect) frame;

@end

#endif
