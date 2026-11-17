#import <AppKit/NSSharingService.h>
#import <AppKit/NSMenu.h>

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

- (void) performWithItems: (NSArray *) items {
    if (NS_EXTRA(NSSharingService, self)->_handler != nil)
        NS_EXTRA(NSSharingService, self)->_handler();
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

- (NSMenu *) menu {
    return [[[NSMenu alloc] initWithTitle: @"Share"] autorelease];
}

- (void) showRelativeToRect: (NSRect) rect ofView: (NSView *) view preferredEdge: (NSRectEdge) preferredEdge {
}

@end
