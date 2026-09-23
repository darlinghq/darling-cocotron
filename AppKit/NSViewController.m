#import <AppKit/NSNib.h>
#import <AppKit/NSNibLoading.h>
#import <AppKit/NSRaise.h>
#import <AppKit/NSStoryboard-Private.h>
#import <AppKit/NSViewController.h>

@implementation NSViewController

@synthesize identifier = _identifier;

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
        _storyboard = [[NSStoryboard _instantiatingStoryboard] retain];
    }

    return self;
}

- (void) dealloc {
    [_identifier release];
    for (NSViewController *child in _childViewControllers)
        child->_parentViewController = nil;
    [_childViewControllers release];
    [_storyboard release];

    [super dealloc];
}

- (NSString *) nibName {
    return _nibName;
}

- (NSBundle *) nibBundle {
    return _nibBundle;
}

- (NSStoryboard *) storyboard {
    return _storyboard;
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
    return _childViewControllers ? [[_childViewControllers copy] autorelease]
                                 : [NSArray array];
}

- (void) setChildViewControllers: (NSArray *) children {
    while ([_childViewControllers count] > 0)
        [self removeChildViewControllerAtIndex:
                      [_childViewControllers count] - 1];
    for (NSViewController *child in children)
        [self addChildViewController: child];
}

- (NSViewController *) parentViewController {
    return _parentViewController;
}

- (void) addChildViewController: (NSViewController *) child {
    [self insertChildViewController: child
                            atIndex: [_childViewControllers count]];
}

- (void) insertChildViewController: (NSViewController *) child
                           atIndex: (NSInteger) index
{
    if (child == nil || index < 0 ||
        index > (NSInteger) [_childViewControllers count])
        [NSException raise: NSInvalidArgumentException
                    format: @"-[%@ %@] invalid child %@ or index %ld",
                            [self class], NSStringFromSelector(_cmd), child,
                            (long) index];

    [child retain];
    if ([child parentViewController] != nil)
        [child removeFromParentViewController];
    if (_childViewControllers == nil)
        _childViewControllers = [[NSMutableArray alloc] init];
    [_childViewControllers insertObject: child atIndex: index];
    child->_parentViewController = self;
    [child release];
}

- (void) removeChildViewControllerAtIndex: (NSInteger) index {
    if (index < 0 || index >= (NSInteger) [_childViewControllers count])
        [NSException raise: NSRangeException
                    format: @"-[%@ %@] index %ld out of bounds", [self class],
                            NSStringFromSelector(_cmd), (long) index];

    NSViewController *child = [_childViewControllers objectAtIndex: index];
    child->_parentViewController = nil;
    [_childViewControllers removeObjectAtIndex: index];
}

- (void) removeFromParentViewController {
    NSViewController *parent = _parentViewController;
    if (parent == nil)
        return;
    NSUInteger index = [parent->_childViewControllers indexOfObjectIdenticalTo: self];
    if (index != NSNotFound)
        [parent removeChildViewControllerAtIndex: index];
}

- (void) loadView {
    NSString *name = [self nibName];
    NSBundle *bundle = [self nibBundle];

    if (name == nil) {
        // should pathForResource assert name for non-nil?
        [NSException raise: NSInvalidArgumentException
                    format: @"-[%@ %s] nibName is nil", [self class], _cmd];
        return;
    }

    // A storyboard scene's view is archived in its own nib inside the storyboard.
    NSString *path = [_storyboard _pathForNibNamed: name];

    if (bundle == nil)
        bundle = [NSBundle mainBundle];
    if (path == nil)
        path = [bundle pathForResource: name ofType: @"nib"];
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
