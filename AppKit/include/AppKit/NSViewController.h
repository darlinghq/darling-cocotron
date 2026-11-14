#import <AppKit/NSResponder.h>
#import <AppKit/AppKitIvarLayout.h>
#import <AppKit/NSUserInterfaceItemIdentification.h>

@class NSView, NSStoryboard;

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
        NSSize _preferredContentSize;
    NS_EXTRA_IVARS_END(NSViewController)
}

- initWithNibName: (NSString *) name bundle: (NSBundle *) bundle;

- (NSString *) nibName;
- (NSBundle *) nibBundle;

@property (retain, nonnull) NSView *view;
@property(copy) NSArray<__kindof NSViewController *> *childViewControllers;
@property(readonly) NSViewController *parentViewController;

- (void) addChildViewController: (NSViewController *) childViewController;
// Subclasses that track their children override these two; the other child
// methods go through them.
- (void) insertChildViewController: (NSViewController *) childViewController
                           atIndex: (NSInteger) index;
- (void) removeChildViewControllerAtIndex: (NSInteger) index;
- (void) removeFromParentViewController;

@property(readonly, strong) NSStoryboard *storyboard;
// Stored for the controller's presenter; NSZeroSize until set.
@property NSSize preferredContentSize;
- (NSString *) title;
- representedObject;

- (void) setRepresentedObject: object;

- (void) setTitle: (NSString *) value;


- (void) loadView;
@property(readonly, getter=isViewLoaded) BOOL viewLoaded; // 10.10
- (void) loadViewIfNeeded;
// Called once -view has loaded the view with -loadView; does nothing by default.
- (void) viewDidLoad;

- (void) discardEditing;

- (BOOL) commitEditing;
- (void) commitEditingWithDelegate: delegate
                 didCommitSelector: (SEL) didCommitSelector
                       contextInfo: (void *) contextInfo;

@end
