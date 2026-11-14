#import <AppKit/NSNib.h>
#import <AppKit/NSNibLoading.h>
#import <AppKit/NSRaise.h>
#import <AppKit/NSStoryboard-Private.h>
#import <AppKit/NSViewController.h>

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
    }

    return self;
}

- (void) dealloc {
    [NS_EXTRA(NSViewController, self)->_identifier release];
    for (NSViewController *child in NS_EXTRA(NSViewController, self)->_childViewControllers)
        NS_EXTRA(NSViewController, child)->_parentViewController = nil;
    [NS_EXTRA(NSViewController, self)->_childViewControllers release];
    [NS_EXTRA(NSViewController, self)->_storyboard release];

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
    [_view release];
    _view = value;
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

    NSDictionary *nameTable = [NSDictionary dictionaryWithObject: self
                                                          forKey: NSNibOwner];

    if (path == nil)
        NSLog(@"NSViewController unable to find nib named %@, bundle=%@", name,
              bundle);

    [bundle loadNibFile: path externalNameTable: nameTable withZone: NULL];
}

- (void) discardEditing {
    NSUnimplementedMethod();
}

- (BOOL) commitEditing {
    NSUnimplementedMethod();
    return NO;
}

- (void) commitEditingWithDelegate: delegate
                 didCommitSelector: (SEL) didCommitSelector
                       contextInfo: (void *) contextInfo
{
    NSUnimplementedMethod();
}

@end
