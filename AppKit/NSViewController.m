#import <objc/message.h>
#import <AppKit/NSNib.h>
#import <AppKit/NSNibLoading.h>
#import <AppKit/NSRaise.h>
#import <AppKit/NSStoryboard-Private.h>
#import <AppKit/NSViewController.h>
#import <AppKit/NSViewController-Private.h>
#import <AppKit/NSView.h>
#import <AppKit/NSWindow.h>

// How many views have a controller. While it is zero the appearance
// bookkeeping has nothing to look for and skips walking view hierarchies.
static NSUInteger linkedViewCount;

static void unlinkView(NSViewController *controller, NSView *view) {
    if (view != nil && [view _viewController] == controller) {
        [view _setViewController: nil];
        linkedViewCount--;
    }
}

@interface NSBundle (NSNibLoadingPath)
- (BOOL) _loadNibAtPath: (NSString *) path
        externalNameTable: (NSDictionary *) nameTable
                 withZone: (NSZone *) zone;
@end

@implementation NSViewController

NS_EXTRA_SYNTHESIZE_COPY(NSViewController, identifier, _identifier, NSUserInterfaceItemIdentifier, identifier, setIdentifier:)

// -init is initWithNibName:bundle: with no nib, so subclasses that set
// defaults in the designated initializer get them from a plain -init too.
- init {
    return [self initWithNibName: nil bundle: nil];
}

- initWithNibName: (NSString *) name bundle: (NSBundle *) bundle {
    _nibName = [name copy];
    _nibBundle = [bundle retain];
    return self;
}

- initWithCoder: (NSCoder *) coder {
    if ([coder allowsKeyedCoding]) {
        _nibName = [[coder decodeObjectForKey: @"NSNibName"] copy];
        _title = [[coder decodeObjectForKey: @"NSTitle"] copy];
        NSString *bundleIdentifier =
                [coder decodeObjectForKey: @"NSNibBundleIdentifier"];
        if (bundleIdentifier != nil)
            _nibBundle = [NSBundle bundleWithIdentifier: bundleIdentifier];
        NS_EXTRA(NSViewController, self)->_storyboard = [[NSStoryboard _instantiatingStoryboard] retain];

        // The objects the view's nib asks its loader for; a storyboard scene archives them with the
        // controller. The controller itself is usually one of them: it is stored as NSNull so that
        // the table does not retain its owner.
        NSDictionary *external = [coder decodeObjectForKey: @"NSExternalObjectsTableForViewLoading"];
        if ([external isKindOfClass: [NSDictionary class]]) {
            NSMutableDictionary *table = [NSMutableDictionary dictionaryWithCapacity: [external count]];

            for (id key in external) {
                id object = [external objectForKey: key];
                [table setObject: object == self ? (id) [NSNull null] : object forKey: key];
            }
            NS_EXTRA(NSViewController, self)->_externalObjectsTableForViewLoading = [table retain];
        }
    }

    return self;
}

- (void) dealloc {
    unlinkView(self, _view);
    [NS_EXTRA(NSViewController, self)->_externalObjectsTableForViewLoading release];
    [NS_EXTRA(NSViewController, self)->_identifier release];
    for (NSViewController *child in NS_EXTRA(NSViewController, self)->_childViewControllers)
        NS_EXTRA(NSViewController, child)->_parentViewController = nil;
    [NS_EXTRA(NSViewController, self)->_childViewControllers release];
    [NS_EXTRA(NSViewController, self)->_storyboard release];
    [NS_EXTRA(NSViewController, self)->_editors release];

    NS_EXTRA_FREE(NSViewController, self);
    [super dealloc];
}

- (NSSize) preferredContentSize {
    return NS_EXTRA(NSViewController, self)->_preferredContentSize;
}

- (void) setPreferredContentSize: (NSSize) size {
    NS_EXTRA(NSViewController, self)->_preferredContentSize = size;
}

- (NSString *) nibName {
    return _nibName;
}

- (NSBundle *) nibBundle {
    return _nibBundle;
}

- (NSStoryboard *) storyboard {
    return NS_EXTRA(NSViewController, self)->_storyboard;
}

- (NSView *) view {
    if (_view == nil) {
        [self loadView];
        if (_view != nil)
            [self viewDidLoad];
    }

    return _view;
}

- (void) viewDidLoad {
}

- (void) viewWillAppear {
}

- (void) viewDidAppear {
}

- (void) viewWillDisappear {
}

- (void) viewDidDisappear {
}

- (BOOL) isViewLoaded {
    return _view != nil;
}

- (void) loadViewIfNeeded {
    (void)[self view];
}

- (NSString *) title {
    return _title;
}

- representedObject {
    return _representedObject;
}

- (void) setRepresentedObject: object {
    object = [object retain];
    [_representedObject release];
    _representedObject = object;
}

- (void) setTitle: (NSString *) value {
    value = [value retain];
    [_title release];
    _title = value;
}

- (void) setView: (NSView *) value {
    value = [value retain];
    unlinkView(self, _view);
    [_view release];
    _view = value;
    if (_view != nil) {
        if ([_view _viewController] == nil)
            linkedViewCount++;
        [_view _setViewController: self];
    }
}

- (NSArray *) childViewControllers {
    return NS_EXTRA(NSViewController, self)->_childViewControllers ? [[NS_EXTRA(NSViewController, self)->_childViewControllers copy] autorelease]
                                 : [NSArray array];
}

- (void) setChildViewControllers: (NSArray *) children {
    while ([NS_EXTRA(NSViewController, self)->_childViewControllers count] > 0)
        [self removeChildViewControllerAtIndex:
                      [NS_EXTRA(NSViewController, self)->_childViewControllers count] - 1];
    for (NSViewController *child in children)
        [self addChildViewController: child];
}

- (NSViewController *) parentViewController {
    return NS_EXTRA(NSViewController, self)->_parentViewController;
}

- (void) addChildViewController: (NSViewController *) child {
    [self insertChildViewController: child
                            atIndex: [NS_EXTRA(NSViewController, self)->_childViewControllers count]];
}

- (void) insertChildViewController: (NSViewController *) child
                           atIndex: (NSInteger) index
{
    if (child == nil || index < 0 ||
        index > (NSInteger) [NS_EXTRA(NSViewController, self)->_childViewControllers count])
        [NSException raise: NSInvalidArgumentException
                    format: @"-[%@ %@] invalid child %@ or index %ld",
                            [self class], NSStringFromSelector(_cmd), child,
                            (long) index];

    [child retain];
    if ([child parentViewController] != nil)
        [child removeFromParentViewController];
    if (NS_EXTRA(NSViewController, self)->_childViewControllers == nil)
        NS_EXTRA(NSViewController, self)->_childViewControllers = [[NSMutableArray alloc] init];
    [NS_EXTRA(NSViewController, self)->_childViewControllers insertObject: child atIndex: index];
    NS_EXTRA(NSViewController, child)->_parentViewController = self;
    [child release];
}

- (void) removeChildViewControllerAtIndex: (NSInteger) index {
    if (index < 0 || index >= (NSInteger) [NS_EXTRA(NSViewController, self)->_childViewControllers count])
        [NSException raise: NSRangeException
                    format: @"-[%@ %@] index %ld out of bounds", [self class],
                            NSStringFromSelector(_cmd), (long) index];

    NSViewController *child = [NS_EXTRA(NSViewController, self)->_childViewControllers objectAtIndex: index];
    NS_EXTRA(NSViewController, child)->_parentViewController = nil;
    [NS_EXTRA(NSViewController, self)->_childViewControllers removeObjectAtIndex: index];
}

- (void) removeFromParentViewController {
    NSViewController *parent = NS_EXTRA(NSViewController, self)->_parentViewController;
    if (parent == nil)
        return;
    NSUInteger index = [NS_EXTRA(NSViewController, parent)->_childViewControllers indexOfObjectIdenticalTo: self];
    if (index != NSNotFound)
        [parent removeChildViewControllerAtIndex: index];
}

- (void) loadView {
    NSString *name = [self nibName];
    NSBundle *bundle = [self nibBundle];

    if (bundle == nil)
        bundle = [NSBundle mainBundle];

    // Since OS X 10.10 a nil nibName means the nib named after the class.
    BOOL named = name != nil;
    if (!named)
        name = NSStringFromClass([self class]);

    // A storyboard scene's view is archived in its own nib inside the storyboard.
    NSString *path = [NS_EXTRA(NSViewController, self)->_storyboard _pathForNibNamed: name];
    if (path == nil)
        path = [bundle pathForResource: name ofType: @"nib"];
    if (path == nil && !named)
        [NSException raise: NSInvalidArgumentException
                    format: @"-[%@ %@] nibName is nil and %@ has no nib named %@",
                            [self class], NSStringFromSelector(_cmd), bundle, name];

    NSMutableDictionary *nameTable = [NSMutableDictionary dictionaryWithObject: self forKey: NSNibOwner];
    NSDictionary *external = NS_EXTRA(NSViewController, self)->_externalObjectsTableForViewLoading;

    for (id key in external) {
        id object = [external objectForKey: key];
        [nameTable setObject: object == [NSNull null] ? self : object forKey: key];
    }

    if (path == nil)
        NSLog(@"NSViewController unable to find nib named %@, bundle=%@", name,
              bundle);

    // The path is resolved already; the bundle still supplies the nib's resources.
    [bundle _loadNibAtPath: path externalNameTable: nameTable withZone: NULL];
}

// The editors are the objects that announced uncommitted changes with -objectDidBeginEditing:, normally the
// controls bound to the view controller's content. An editor takes itself off the list with
// -objectDidEndEditing: once it has committed or discarded.
- (void) objectDidBeginEditing: (id) editor {
    if (editor == nil)
        return;
    if (NS_EXTRA(NSViewController, self)->_editors == nil)
        NS_EXTRA(NSViewController, self)->_editors = [[NSMutableArray alloc] init];
    [NS_EXTRA(NSViewController, self)->_editors addObject: editor];
}

- (void) objectDidEndEditing: (id) editor {
    NSMutableArray *editors = NS_EXTRA(NSViewController, self)->_editors;
    NSUInteger index = [editors indexOfObjectIdenticalTo: editor];
    if (index != NSNotFound)
        [editors removeObjectAtIndex: index];
}

- (void) discardEditing {
    // An editor may remove itself while it discards, so walk a snapshot.
    for (id editor in [[NS_EXTRA(NSViewController, self)->_editors copy] autorelease])
        [editor discardEditing];
}

// QUIRK: the editors are asked to commit most recently registered first, and the first one that refuses
// stops the pass (the editors not asked yet keep their uncommitted changes). Not documented. Evidence: black-box
// observation on macOS 26.7.3, x86_64 (tier 2): with a refusing editor registered after a committing one only the
// refusing one was asked and -commitEditing returned NO; registered the other way round both were asked.
// Test: viewcontroller-commit-editing.m (test_quirk_commit_order). YES when nothing is being edited.
- (BOOL) commitEditing {
    for (id editor in [[[NS_EXTRA(NSViewController, self)->_editors copy] autorelease] reverseObjectEnumerator]) {
        if (![editor commitEditing])
            return NO;
    }
    return YES;
}

- (void) commitEditingWithDelegate: delegate
                 didCommitSelector: (SEL) didCommitSelector
                       contextInfo: (void *) contextInfo
{
    BOOL committed = [self commitEditing];

    if (delegate != nil && didCommitSelector != NULL) {
        // The selector has the form -editor:didCommit:contextInfo:.
        void (*send)(id, SEL, id, BOOL, void *) = (void (*)(id, SEL, id, BOOL, void *)) objc_msgSend;
        send(delegate, didCommitSelector, self, committed, contextInfo);
    }
}

// Like -commitEditing (same order, stops at the first refusal), asking each editor for its error where it can
// give one.
- (BOOL) commitEditingAndReturnError: (NSError **) error {
    for (id editor in [[[NS_EXTRA(NSViewController, self)->_editors copy] autorelease] reverseObjectEnumerator]) {
        BOOL committed = [editor respondsToSelector: @selector(commitEditingAndReturnError:)]
                ? [editor commitEditingAndReturnError: error]
                : [editor commitEditing];
        if (!committed)
            return NO;
    }
    return YES;
}

@end

static BOOL hiddenInHierarchy(NSView *view, NSView *root, NSView *rootSuperview,
                              BOOL useRootHidden, BOOL rootHidden) {
    for (NSView *v = view; v != nil;) {
        if (v == root) {
            if (useRootHidden ? rootHidden : [v isHidden])
                return YES;
            v = rootSuperview;
        } else {
            if ([v isHidden])
                return YES;
            v = [v superview];
        }
    }
    return NO;
}

static void collectTransitions(NSView *view, NSView *root, NSWindow *window, BOOL visible,
                               NSView *rootSuperview, BOOL useRootHidden, BOOL rootHidden,
                               NSMutableArray **list) {
    NSViewController *controller = [view _viewController];
    if (controller != nil) {
        BOOL target = visible && window != nil &&
                      !hiddenInHierarchy(view, root, rootSuperview, useRootHidden, rootHidden);
        if (target != [controller _appeared]) {
            if (*list == nil)
                *list = [NSMutableArray array];
            [*list addObject: controller];
            [*list addObject: [NSNumber numberWithBool: target]];
        }
    }
    for (NSView *subview in [view subviews])
        collectTransitions(subview, root, window, visible, rootSuperview, useRootHidden,
                           rootHidden, list);
}

@implementation NSViewController (NSViewController_appearance)

- (BOOL) _appeared {
    return NS_EXTRA(NSViewController, self)->_appeared;
}

- (void) _setAppeared: (BOOL) appeared {
    NS_EXTRA(NSViewController, self)->_appeared = appeared;
}

+ (NSArray *) _appearanceTransitionsUnder: (NSView *) root
                                   window: (NSWindow *) window
                            windowVisible: (BOOL) visible
                            rootSuperview: (NSView *) rootSuperview
                            useRootHidden: (BOOL) useRootHidden
                                rootHidden: (BOOL) rootHidden
{
    if (linkedViewCount == 0 || root == nil)
        return nil;
    NSMutableArray *list = nil;
    collectTransitions(root, root, window, visible, rootSuperview, useRootHidden, rootHidden,
                       &list);
    return list;
}

// The list alternates controller, target state. The state is recorded before the
// first callback so that anything the callbacks trigger sees the new one.
+ (void) _willPerformAppearanceTransitions: (NSArray *) transitions {
    NSUInteger count = [transitions count];
    for (NSUInteger i = 0; i < count; i += 2) {
        NSViewController *controller = [transitions objectAtIndex: i];
        BOOL target = [[transitions objectAtIndex: i + 1] boolValue];
        [controller _setAppeared: target];
    }
    for (NSUInteger i = 0; i < count; i += 2) {
        NSViewController *controller = [transitions objectAtIndex: i];
        if ([[transitions objectAtIndex: i + 1] boolValue])
            [controller viewWillAppear];
        else
            [controller viewWillDisappear];
    }
}

+ (void) _didPerformAppearanceTransitions: (NSArray *) transitions {
    NSUInteger count = [transitions count];
    for (NSUInteger i = 0; i < count; i += 2) {
        NSViewController *controller = [transitions objectAtIndex: i];
        if ([[transitions objectAtIndex: i + 1] boolValue])
            [controller viewDidAppear];
        else
            [controller viewDidDisappear];
    }
}

@end
