#import <AppKit/NSSharingService.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSMenuItem.h>

NSSharingServiceName const NSSharingServiceNameAddToIPhoto = @"com.apple.share.System.add-to-iphoto";
NSSharingServiceName const NSSharingServiceNameAddToSafariReadingList = @"com.apple.share.System.add-to-safari-reading-list";
NSSharingServiceName const NSSharingServiceNameComposeEmail = @"com.apple.share.Mail.compose";
NSSharingServiceName const NSSharingServiceNameComposeMessage = @"com.apple.messages.ShareExtension";

NSSharingServiceName const NSSharingServiceNamePostOnFacebook = @"com.apple.share.Facebook.post";
NSSharingServiceName const NSSharingServiceNamePostOnTwitter = @"com.apple.share.Twitter.post";
NSSharingServiceName const NSSharingServiceNamePostOnSinaWeibo = @"com.apple.share.SinaWeibo.post";
NSSharingServiceName const NSSharingServiceNamePostOnTencentWeibo = @"com.apple.share.TencentWeibo.post";
NSSharingServiceName const NSSharingServiceNamePostOnLinkedIn = @"com.apple.share.LinkedIn.post";
NSSharingServiceName const NSSharingServiceNameSendViaAirDrop = @"com.apple.share.AirDrop.send";
NSSharingServiceName const NSSharingServiceNameCloudSharing = @"com.apple.share.CloudSharing";

// Not declared in a public header.
APPKIT_EXPORT NSSharingServiceName const NSSharingServiceNameUseAsAccountPicture;
APPKIT_EXPORT NSString *const NSSharingServiceParametersDefaultRecipientsKey;
NSSharingServiceName const NSSharingServiceNameUseAsAccountPicture = @"com.apple.share.System.set-account-picture";
NSString *const NSSharingServiceParametersDefaultRecipientsKey = @"NSSharingServiceParametersDefaultRecipientsKey";

@implementation NSSharingService

+ (NSArray<NSSharingService *> *) sharingServicesForItems: (NSArray *) items {
    return [NSArray array];
}

+ (NSSharingService *) sharingServiceNamed: (NSSharingServiceName) serviceName {
    return nil;
}

- (instancetype) initWithTitle: (NSString *) title image: (NSImage *) image alternateImage: (NSImage *) alternateImage handler: (void (^)(void)) block {
    if ((self = [super init])) {
        NS_EXTRA(NSSharingService, self)->_title = [title copy];
        NS_EXTRA(NSSharingService, self)->_image = [image retain];
        NS_EXTRA(NSSharingService, self)->_alternateImage = [alternateImage retain];
        NS_EXTRA(NSSharingService, self)->_handler = [block copy];
    }
    return self;
}

- (void) dealloc {
    [NS_EXTRA(NSSharingService, self)->_title release];
    [NS_EXTRA(NSSharingService, self)->_image release];
    [NS_EXTRA(NSSharingService, self)->_alternateImage release];
    [NS_EXTRA(NSSharingService, self)->_menuItemTitle release];
    [NS_EXTRA(NSSharingService, self)->_handler release];
    NS_EXTRA_FREE(NSSharingService, self);
    [super dealloc];
}

- (NSString *) title {
    return NS_EXTRA(NSSharingService, self)->_title;
}

- (NSImage *) image {
    return NS_EXTRA(NSSharingService, self)->_image;
}

- (NSImage *) alternateImage {
    return NS_EXTRA(NSSharingService, self)->_alternateImage;
}

- (NSString *) menuItemTitle {
    return NS_EXTRA(NSSharingService, self)->_menuItemTitle;
}

- (void) setMenuItemTitle: (NSString *) title {
    [NS_EXTRA(NSSharingService, self)->_menuItemTitle release];
    NS_EXTRA(NSSharingService, self)->_menuItemTitle = [title copy];
}

- (id <NSSharingServiceDelegate>) delegate {
    return NS_EXTRA(NSSharingService, self)->_delegate;
}

- (void) setDelegate: (id <NSSharingServiceDelegate>) delegate {
    NS_EXTRA(NSSharingService, self)->_delegate = delegate;
}

// Only a service created with a handler can perform; the built-in services
// are not available.
- (BOOL) canPerformWithItems: (NSArray *) items {
    return NS_EXTRA(NSSharingService, self)->_handler != nil;
}

// The delegate hears willShareItems: before the handler runs and didShareItems:
// after it, for an empty array too. A handler cannot report a failure, so
// didFailToShareItems:error: is never sent. GUESS: the calls are made before
// this returns; the reference does not say whether they may come later.
- (void) performWithItems: (NSArray *) items {
    void (^handler)(void) = NS_EXTRA(NSSharingService, self)->_handler;
    id <NSSharingServiceDelegate> delegate = NS_EXTRA(NSSharingService, self)->_delegate;

    if (handler == nil)
        return;
    // The handler or a delegate method may release the service or the delegate.
    [self retain];
    [delegate retain];
    if ([delegate respondsToSelector: @selector(sharingService:willShareItems:)])
        [delegate sharingService: self willShareItems: items];
    handler();
    if ([delegate respondsToSelector: @selector(sharingService:didShareItems:)])
        [delegate sharingService: self didShareItems: items];
    [delegate autorelease];
    [self autorelease];
}

@end

@implementation NSSharingServicePicker

- (instancetype) initWithItems: (NSArray *) items {
    if ((self = [super init])) {
        NS_EXTRA(NSSharingServicePicker, self)->_items = [items retain];
    }
    return self;
}

- (void) dealloc {
    [NS_EXTRA(NSSharingServicePicker, self)->_items release];
    NS_EXTRA_FREE(NSSharingServicePicker, self);
    [super dealloc];
}

- (id <NSSharingServicePickerDelegate>) delegate {
    return NS_EXTRA(NSSharingServicePicker, self)->_delegate;
}

- (void) setDelegate: (id <NSSharingServicePickerDelegate>) delegate {
    NS_EXTRA(NSSharingServicePicker, self)->_delegate = delegate;
}

// What the picker lists: the services proposed for the items, which the
// delegate may remove from, add to or reorder. Darling proposes none itself.
- (NSArray *) _servicesToList {
    NSArray *items = NS_EXTRA(NSSharingServicePicker, self)->_items;
    id <NSSharingServicePickerDelegate> delegate = NS_EXTRA(NSSharingServicePicker, self)->_delegate;
    NSArray *list = [NSSharingService sharingServicesForItems: items];

    if ([delegate respondsToSelector: @selector(sharingServicePicker:sharingServicesForItems:proposedSharingServices:)])
        list = [delegate sharingServicePicker: self sharingServicesForItems: items proposedSharingServices: list];
    return list != nil ? list : [NSArray array];
}

- (NSMenu *) _menuListing: (NSArray *) services {
    NSMenu *menu = [[[NSMenu alloc] initWithTitle: @"Share"] autorelease];
    NSUInteger index;

    for (index = 0; index < [services count]; index++) {
        NSSharingService *service = [services objectAtIndex: index];
        NSString *title = [service menuItemTitle] != nil ? [service menuItemTitle] : [service title];
        NSMenuItem *entry = [menu addItemWithTitle: title != nil ? title : @""
                                            action: @selector(_pickedFromMenu:)
                                     keyEquivalent: @""];

        [entry setTarget: self];
        [entry setRepresentedObject: service];
    }
    return menu;
}

// -menu is not in the public reference; it lists the services as the menu that
// older systems showed.
- (NSMenu *) menu {
    return [self _menuListing: [self _servicesToList]];
}

// The delegate supplies the service's own delegate, hears which service was
// picked, and only then does the service get the items. GUESS: the reference
// fixes that the delegate is told before the service shares; asking for the
// service's delegate first is a choice. The picker is kept alive across the
// calls because the delegate may release it from its callback.
- (void) _pickedFromMenu: (NSMenuItem *) entry {
    NSSharingService *picked = [entry representedObject];
    id <NSSharingServicePickerDelegate> delegate = NS_EXTRA(NSSharingServicePicker, self)->_delegate;
    NSArray *items = NS_EXTRA(NSSharingServicePicker, self)->_items;

    [self retain];
    if ([delegate respondsToSelector: @selector(sharingServicePicker:delegateForSharingService:)])
        [picked setDelegate: [delegate sharingServicePicker: self delegateForSharingService: picked]];
    if ([delegate respondsToSelector: @selector(sharingServicePicker:didChooseSharingService:)])
        [delegate sharingServicePicker: self didChooseSharingService: picked];
    [picked performWithItems: items];
    [self release];
}

// The pop-up location (the menu's top left corner, in the view's coordinates)
// that puts a menu of `size` beside `edge` of `rect`, touching it and centred
// on the middle of that edge. Beside means on that edge's side in the view's
// own coordinates, so in a flipped view the minY edge is visually the top.
static NSPoint locationBesideEdge(NSRect rect, NSSize size, NSRectEdge edge, BOOL flipped) {
    NSPoint low;

    if (edge == NSMinXEdge)
        low.x = NSMinX(rect) - size.width;
    else if (edge == NSMaxXEdge)
        low.x = NSMaxX(rect);
    else
        low.x = NSMidX(rect) - size.width / 2;
    if (edge == NSMinYEdge)
        low.y = NSMinY(rect) - size.height;
    else if (edge == NSMaxYEdge)
        low.y = NSMaxY(rect);
    else
        low.y = NSMidY(rect) - size.height / 2;
    return NSMakePoint(low.x, flipped ? low.y : low.y + size.height);
}

// Asks the delegate for the services now and pops the list up beside the named
// edge of the rectangle from a block on the main run loop, so this returns before the picker
// is on screen and does not wait for it to be dismissed.
// QUIRK: that return is not documented. Evidence: black-box observation on macOS
// 26.1 arm64 (tier 2): 15 of 15 cases returned after 122 to 291 ms with no
// window of the process on screen yet ("returned after 291.1 ms with 0
// window(s) already on screen", probe 643 case 0). The probe cannot say whether
// a second show while the picker is up also returns at once.
// Test: tests/appkit-sharing-service-picker.m (test_show_returns_before_presenting)
// QUIRK: the placement is not documented. Evidence: macOS 26.1 arm64 (tier 2), 8
// of 8 edge cases with room on all sides: the picker window touches the named
// edge (gap 0) and is centred on the middle of that edge (offset 0, at most 0.5
// point), for two different window heights ("frame={{767,574},{266,288}} ...
// dx(left,mid,right)=(-103,0,103) dy(bottom,mid,top)=(30,159,288)" for maxY on an
// anchor {{870,544},{60,30}}). The probe had room on all sides: near a screen
// edge the pop-up moves the menu back onto the visible frame, which overrides this.
// Only that structure is copied, not the window size. A flipped view is not
// covered by the probe: GUESS: the edge is read in the view's own coordinates.
// Test: tests/appkit-sharing-service-picker.m (test_placement)
// GUESS: a second show before the first has presented replaces it (the probe did
// not call show twice); the reference is silent.
// GUESS: the reference does not say what happens with no services: nothing is
// shown. macOS 26.1 arm64 (tier 2) differs: it still presents a window for an
// empty list from the delegate, a nil list (treated the same as empty), an empty
// items array and an item nothing can share, 4 of 4 cases ("empty items array,
// no delegate ... own windows=1 ; layer=101 size={266,123}", probe 643 case 5).
// What the window holds is not visible to the probe, so no empty window is
// invented here. Sizes of the window are machine specific and not copied.
- (void) showRelativeToRect: (NSRect) rect ofView: (NSView *) view preferredEdge: (NSRectEdge) preferredEdge {
    NSArray *services = [self _servicesToList];
    NSUInteger generation = ++NS_EXTRA(NSSharingServicePicker, self)->_showGeneration;

    if ([services count] == 0)
        return;

    // The block keeps the picker, the view and the services alive until it has run.
    // Not dispatch_async to the main queue: the menu's tracking loop would run nested in
    // that block, and the main queue is not drained in a run loop nested in a main-queue
    // block, so every other main-queue block would wait until the picker closed. On macOS
    // the picker is an ordinary window and the application keeps running while it is up.
    CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopCommonModes, ^{
        if (generation != NS_EXTRA(NSSharingServicePicker, self)->_showGeneration)
            return;
        // The picker is already up (this block can run inside its tracking loop): a nested
        // pop-up would hide it from -close. GUESS: a show while it is up does nothing.
        if (NS_EXTRA(NSSharingServicePicker, self)->_presentedMenu != nil)
            return;
        // The view left its window before the picker could be placed: nowhere to anchor it.
        if (view != nil && [view window] == nil)
            return;

        NSMenu *menu = [[self _menuListing: services] retain];
        NSPoint location = locationBesideEdge(rect, [menu size], preferredEdge, [view isFlipped]);

        NS_EXTRA(NSSharingServicePicker, self)->_presentedMenu = menu;
        [menu popUpMenuPositioningItem: nil atLocation: location inView: view];
        NS_EXTRA(NSSharingServicePicker, self)->_presentedMenu = nil;
        [menu release];
    });
    CFRunLoopWakeUp(CFRunLoopGetMain());
}

// Dismisses the picker if it is up; a show that has not presented yet does not
// present afterwards.
- (void) close {
    NS_EXTRA(NSSharingServicePicker, self)->_showGeneration++;
    [NS_EXTRA(NSSharingServicePicker, self)->_presentedMenu cancelTracking];
}

@end
