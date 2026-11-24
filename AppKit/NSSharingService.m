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
    if ([delegate respondsToSelector: @selector(sharingService:willShareItems:)])
        [delegate sharingService: self willShareItems: items];
    handler();
    if ([delegate respondsToSelector: @selector(sharingService:didShareItems:)])
        [delegate sharingService: self didShareItems: items];
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

// Asks the delegate for the services now and pops the list up beside the named
// edge of the rectangle from the main queue, so this returns before the picker
// is on screen and does not wait for it to be dismissed.
// QUIRK: that return is not documented. Evidence: black-box observation on macOS
// 26.1 arm64 (tier 2): 15 of 15 cases returned after 122 to 291 ms with no
// window of the process on screen yet ("returned after 291.1 ms with 0
// window(s) already on screen", probe 643 case 0). The probe cannot say whether
// a second show while the picker is up also returns at once.
// Test: tests/appkit-sharing-service-picker.m (test_show_returns_before_presenting)
// GUESS: the reference does not say where on the edge the menu opens (the middle
// is used) or what happens with no services (nothing is shown).
- (void) showRelativeToRect: (NSRect) rect ofView: (NSView *) view preferredEdge: (NSRectEdge) preferredEdge {
    NSArray *services = [self _servicesToList];
    NSUInteger generation = ++NS_EXTRA(NSSharingServicePicker, self)->_showGeneration;

    if ([services count] == 0)
        return;

    // The block keeps the picker, the view and the services alive until it has run.
    dispatch_async(dispatch_get_main_queue(), ^{
        NSPoint anchor;

        if (generation != NS_EXTRA(NSSharingServicePicker, self)->_showGeneration)
            return;
        if (preferredEdge == NSMinXEdge)
            anchor = NSMakePoint(NSMinX(rect), NSMidY(rect));
        else if (preferredEdge == NSMaxXEdge)
            anchor = NSMakePoint(NSMaxX(rect), NSMidY(rect));
        else if (preferredEdge == NSMinYEdge)
            anchor = NSMakePoint(NSMidX(rect), NSMinY(rect));
        else
            anchor = NSMakePoint(NSMidX(rect), NSMaxY(rect));

        NS_EXTRA(NSSharingServicePicker, self)->_presentedMenu = [[self _menuListing: services] retain];
        [NS_EXTRA(NSSharingServicePicker, self)->_presentedMenu popUpMenuPositioningItem: nil atLocation: anchor inView: view];
        [NS_EXTRA(NSSharingServicePicker, self)->_presentedMenu release];
        NS_EXTRA(NSSharingServicePicker, self)->_presentedMenu = nil;
    });
}

// Dismisses the picker if it is up; a show that has not presented yet does not
// present afterwards.
- (void) close {
    NS_EXTRA(NSSharingServicePicker, self)->_showGeneration++;
    [NS_EXTRA(NSSharingServicePicker, self)->_presentedMenu cancelTracking];
}

@end
