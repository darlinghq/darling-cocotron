#import <AppKit/NSResponder.h>
#import <AppKit/AppKitIvarLayout.h>
#import <AppKit/NSUserInterfaceItemIdentification.h>

@class NSView, NSStoryboard;

NS_ASSUME_NONNULL_BEGIN

typedef NS_OPTIONS(NSUInteger, NSViewControllerTransitionOptions) {
    NSViewControllerTransitionNone = 0x0,
    NSViewControllerTransitionCrossfade = 0x1,
    NSViewControllerTransitionSlideUp = 0x10,
    NSViewControllerTransitionSlideDown = 0x20,
    NSViewControllerTransitionSlideLeft = 0x40,
    NSViewControllerTransitionSlideRight = 0x80,
    NSViewControllerTransitionSlideForward = 0x140,
    NSViewControllerTransitionSlideBackward = 0x180,
    NSViewControllerTransitionAllowUserInteraction = 0x1000,
};

// Legacy ObjC ABI (i386): instance size must stay 0x34, Apple's; the ivars
// before the extras sit at Apple's offsets. Add new state to the extra
// struct, never as an ivar.
@interface NSViewController : NSResponder <NSUserInterfaceItemIdentification> {
    NSString *_nibName;
    NSBundle *_nibBundle;
    id _representedObject;
    NSString *_title;
    NSView *_view;
    NS_LEGACY_IVAR_PAD(_NSViewControllerReserved1, 20)
    NS_EXTRA_IVARS_BEGIN(NSViewController)
        NSUserInterfaceItemIdentifier _identifier;
        NSMutableArray *_childViewControllers;
        NSViewController *_parentViewController;
        NSStoryboard *_storyboard;
        NSDictionary *_externalObjectsTableForViewLoading;
        NSSize _preferredContentSize;
        NSMutableArray *_editors; // registered via objectDidBeginEditing:
        BOOL _appeared; // between -viewWillAppear and -viewWillDisappear
    NS_EXTRA_IVARS_END(NSViewController)
}

- (instancetype) initWithNibName: (null_unspecified NSString *) name bundle: (nullable NSBundle *) bundle;

- (null_unspecified NSString *) nibName;
- (nullable NSBundle *) nibBundle;

@property (retain, nonnull) NSView *view;
@property(copy) NSArray<__kindof NSViewController *> *childViewControllers;
@property(nullable, readonly) NSViewController *parentViewController;

- (void) addChildViewController: (NSViewController *) childViewController;
// Subclasses that track their children override these two; the other child
// methods go through them.
- (void) insertChildViewController: (NSViewController *) childViewController
                           atIndex: (NSInteger) index;
- (void) removeChildViewControllerAtIndex: (NSInteger) index;
- (void) removeFromParentViewController;

@property(nullable, readonly, strong) NSStoryboard *storyboard;
// Stored for the controller's presenter; NSZeroSize until set.
@property NSSize preferredContentSize;
@property(nullable, nonatomic, copy) NSString *title;
- (nullable id) representedObject;

- (void) setRepresentedObject: (nullable id) object;



- (void) loadView;
@property(readonly, getter=isViewLoaded) BOOL viewLoaded; // 10.10
- (void) loadViewIfNeeded;
// Called once -view has loaded the view with -loadView; does nothing by default.
- (void) viewDidLoad;

// Sent when the view is about to be, or has just been, put into a visible
// window (added to one that is shown, or its window is ordered in) and when it is
// about to be, or has just been, taken out of one (removed, hidden, its window
// ordered out or closed). Each pair is sent for a controller and its children
// and does nothing by default.
- (void) viewWillAppear;
- (void) viewDidAppear;
- (void) viewWillDisappear;
- (void) viewDidDisappear;

- (void) discardEditing;

- (BOOL) commitEditing;
- (void) commitEditingWithDelegate: (nullable id) delegate
                 didCommitSelector: (nullable SEL) didCommitSelector
                       contextInfo: (nullable void *) contextInfo;
- (BOOL) commitEditingAndReturnError: (NSError **) error;

// NSEditorRegistration: the bound controls and objects that have uncommitted changes.
- (void) objectDidBeginEditing: (id) editor;
- (void) objectDidEndEditing: (id) editor;

@end

NS_ASSUME_NONNULL_END
