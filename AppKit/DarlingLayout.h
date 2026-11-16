#import <AppKit/NSView.h>
#ifdef __cplusplus
extern "C" {
#endif
void DarlingLayoutSubtree(NSView *root);
// The smallest frame size of root that satisfies the constraints of its subtree;
// no frame is changed.
NSSize DarlingLayoutFittingSize(NSView *root);
// The size a window's content view takes when its subtree's constraints are solved with the
// root's size as a variable that resists change at NSLayoutPriorityWindowSizeStayPut. Returns
// currentSize when the subtree has no constraints or they cannot be satisfied.
NSSize DarlingLayoutPreferredSize(NSView *root, NSSize currentSize);
#ifdef __cplusplus
}
#endif
