#import <AppKit/NSView.h>
#ifdef __cplusplus
extern "C" {
#endif
// Solves the constraints of root's subtree and sets the frames of the views in it that are laid
// out with constraints. The solver is kept with the view, so a pass after a small change only
// updates what changed.
void DarlingLayoutSubtree(NSView *root);
// The smallest frame size of root that satisfies the constraints of its subtree;
// no frame is changed.
NSSize DarlingLayoutFittingSize(NSView *root);
// The size a window's content view takes when its subtree's constraints are solved with the
// root's size as a variable that resists change at NSLayoutPriorityWindowSizeStayPut. Returns
// currentSize when the subtree has no constraints or they cannot be satisfied.
NSSize DarlingLayoutPreferredSize(NSView *root, NSSize currentSize);

// Every change that can change a layout result (constraints, frames, intrinsic sizes, the view
// tree, layout flags) advances a generation count. A pass remembers the generation it was made
// at, so a display cycle can skip layout when nothing changed since.
void DarlingLayoutInputsChanged(void);
uint64_t DarlingLayoutGeneration(void);
typedef enum { DarlingLayoutKindLayout = 0, DarlingLayoutKindWindowFit = 1 } DarlingLayoutKind;
uint64_t DarlingLayoutLastGeneration(NSView *root, DarlingLayoutKind kind);
void DarlingLayoutSetLastGeneration(NSView *root, DarlingLayoutKind kind, uint64_t generation);
// Whether the view is in a subtree whose frame a layout pass is setting: the frame changes that
// result from it are not new input.
BOOL DarlingLayoutIsPlacing(NSView *view);
#ifdef __cplusplus
}
#endif
