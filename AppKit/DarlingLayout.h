#import <AppKit/NSView.h>
#ifdef __cplusplus
extern "C" {
#endif
void DarlingLayoutSubtree(NSView *root);
// The smallest frame size of root that satisfies the constraints of its subtree;
// no frame is changed.
NSSize DarlingLayoutFittingSize(NSView *root);
#ifdef __cplusplus
}
#endif
