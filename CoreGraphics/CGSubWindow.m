#import <CoreGraphics/CGSubWindow.h>
#import <Onyx2D/O2Exceptions.h>

@implementation CGSubWindow

- (void *) nativeWindow {
    O2InvalidAbstractInvocation();
    return NULL;
}

// Backends without a parent drawable to lend never lend one.
- (void) setAllowsParentDrawable: (BOOL) allowed {
}

- (void) setSyncsToDisplay: (BOOL) syncs {
}

- (void *) sharedCGLWindow {
    return NULL;
}

- (CGFloat) backingScaleFactor { return 1.0; }
- (CGSize) drawablePixelSize { return CGSizeZero; }
- (void) flush {}
- (BOOL) requiresMainThreadPresentation { return NO; }

- (void) show {
    O2InvalidAbstractInvocation();
}

- (void) hide {
    O2InvalidAbstractInvocation();
}

- (void) setFrame: (CGRect) frame {
    O2InvalidAbstractInvocation();
}

@end
