#import "MacWorkspace.h"
#import <AppKit/NSApplication.h>
#import <AppKit/NSRaise.h>
#include <LaunchServices/LaunchServices.h>
#include <dispatch/dispatch.h>

@implementation NSWorkspace (macos)

+ allocWithZone: (NSZone *) zone {
    return NSAllocateObject([MacWorkspace class], 0, NULL);
}

@end

@implementation MacWorkspace

- (NSImage *) iconForFile: (NSString *) path {
    // TODO: call GetIconRefFromFileInfo()
    NSUnimplementedMethod();
    return NULL;
}

- (NSImage *) iconForFiles: (NSArray *) array {
    NSUnimplementedMethod();
    return NULL;
}

- (NSImage *) iconForFileType: (NSString *) type {
    // TODO: call GetIconRefFromTypeInfo()
    NSUnimplementedMethod();
    return NULL;
}

- (NSString *) localizedDescriptionForType: (NSString *) type {
    // TODO: call UTTypeCopyDescription()
    NSUnimplementedMethod();
    return NULL;
}

- (BOOL) filenameExtension: (NSString *) extension
            isValidForType: (NSString *) type
{
    // TODO: call UTTypeCreateAllIdentifiersForTag
    NSUnimplementedMethod();
    return NO;
}

- (NSString *) preferredFilenameExtensionForType: (NSString *) type {
    // TODO: call UTTypeCopyPreferredTagWithClass(kUTTagClassFilenameExtension)
    NSUnimplementedMethod();
    return NULL;
}

- (BOOL) type: (NSString *) type conformsToType: (NSString *) conformsToType {
    // TODO: call UTTypeConformsTo()
    NSUnimplementedMethod();
    return NO;
}

- (NSString *) typeOfFile: (NSString *) path error: (NSError **) error {
    // TODO: call LSCopyItemAttribute(kLSItemContentType)
    NSUnimplementedMethod();
    return NULL;
}

- (BOOL) openFile: (NSString *) path {
    return [self openFile: path withApplication: nil];
}

- (BOOL) openFile: (NSString *) path withApplication: (NSString *) application {
    return [self openFile: path
            withApplication: application
              andDeactivate: YES];
}

- (BOOL) openTempFile: (NSString *) path {
    return [self openFile: path withApplication: nil andDeactivate: YES];
}

- (BOOL) openFile: (NSString *) path
        fromImage: (NSImage *) image
               at: (NSPoint) point
           inView: (NSView *) view
{
    NSUnimplementedMethod();
    return NO;
}

- (BOOL) openFile: (NSString *) path
        withApplication: (NSString *) application
          andDeactivate: (BOOL) deactivate
{
    // TODO: Implement handling `deactivate` flag
    // TODO: Implement handling race-condition between inter-application (when target app is terminating)

    // On macOS, a nil path with a valid application simply launches the
    // application (and returns YES), so the file URL is only added when a
    // path was given.
    NSURL *url = nil;
    NSURL *appURL = nil;

    if (path != nil) {
        url = [NSURL fileURLWithPath:path];
    }

    if (application != nil) {
        appURL = [NSURL fileURLWithPath:application];
    }

    LSLaunchURLSpec spec;
    memset(&spec, 0, sizeof(spec));

    NSArray *urlArray = (url != nil) ? [NSArray arrayWithObject:url] : nil;
    spec.itemURLs = (CFArrayRef)urlArray;
    spec.appURL = (CFURLRef)appURL;
    spec.launchFlags = kLSLaunchDefaults;

    OSStatus status = LSOpenFromURLSpec(&spec, NULL);

    return (status == noErr);
}

- (BOOL) openURL: (NSURL *) url {
    if (url == nil) {
        return NO;
    }

    LSLaunchURLSpec spec;
    memset(&spec, 0, sizeof(spec));

    NSArray *urlArray = [NSArray arrayWithObject:url];
    spec.itemURLs = (CFArrayRef)urlArray;
    spec.launchFlags = kLSLaunchDefaults;

    OSStatus status = LSOpenFromURLSpec(&spec, NULL);

    return (status == noErr);
}

// Opens urls with LaunchServices; appURL nil means each URL's default
// application.
static OSStatus openURLsWithFlags(NSArray *urls, NSURL *appURL,
                                  LSLaunchFlags flags) {
    LSLaunchURLSpec spec;
    memset(&spec, 0, sizeof(spec));
    spec.appURL = (CFURLRef) appURL;
    spec.itemURLs = (CFArrayRef) urls;
    spec.launchFlags = flags;
    return LSOpenFromURLSpec(&spec, NULL);
}

static LSLaunchFlags launchFlagsForConfiguration(
        NSWorkspaceOpenConfiguration *configuration) {
    LSLaunchFlags flags = kLSLaunchDefaults;
    if (configuration == nil)
        return flags;
    if (![configuration activates])
        flags |= kLSLaunchDontSwitch;
    if ([configuration hides])
        flags |= kLSLaunchAndHide;
    if ([configuration hidesOthers])
        flags |= kLSLaunchAndHideOthers;
    if ([configuration createsNewApplicationInstance])
        flags |= kLSLaunchNewInstance;
    if (![configuration addsToRecentItems])
        flags |= kLSLaunchDontAddToRecents;
    if ([configuration isForPrinting])
        flags |= kLSLaunchAndPrint;
    return flags;
}

// The handler runs asynchronously, on a concurrent queue, as documented.
// Which application took the URL is not known here, so it gets nil.
- (void) openURL: (NSURL *) url
        configuration: (NSWorkspaceOpenConfiguration *) configuration
    completionHandler: (void (^)(NSRunningApplication *app, NSError *error)) completionHandler
{
    LSLaunchFlags flags = launchFlagsForConfiguration(configuration);
    [url retain];
    void (^handler)(NSRunningApplication *, NSError *) = [completionHandler copy];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        OSStatus status = url == nil
                ? paramErr
                : openURLsWithFlags([NSArray arrayWithObject: url], nil, flags);
        if (handler != nil) {
            NSError *error = nil;
            if (status != noErr)
                error = [NSError errorWithDomain: NSOSStatusErrorDomain
                                            code: status
                                        userInfo: nil];
            handler(nil, error);
        }
        [handler release];
        [url release];
    });
}

- (BOOL) openURLs: (NSArray<NSURL *> *) urls
           withAppBundleIdentifier: (NSString *) bundleIdentifier
                           options: (NSWorkspaceLaunchOptions) options
    additionalEventParamDescriptor: (NSAppleEventDescriptor *) descriptor
                 launchIdentifiers: (NSArray **) identifiers
{
    if (identifiers != NULL)
        *identifiers = nil;
    if ([urls count] == 0)
        return NO;

    NSURL *appURL = nil;
    if (bundleIdentifier != nil) {
        appURL = [self URLForApplicationWithBundleIdentifier: bundleIdentifier];
        if (appURL == nil)
            return NO;
    }

    // The launch options share their values with LaunchServices' launch flags.
    LSLaunchFlags flags = kLSLaunchDefaults |
            (options & (NSWorkspaceLaunchAndPrint |
                        NSWorkspaceLaunchWithoutAddingToRecents |
                        NSWorkspaceLaunchWithoutActivation |
                        NSWorkspaceLaunchAsync |
                        NSWorkspaceLaunchNewInstance |
                        NSWorkspaceLaunchAndHide |
                        NSWorkspaceLaunchAndHideOthers));
    return openURLsWithFlags(urls, appURL, flags) == noErr;
}

- (BOOL) selectFile: (NSString *) path
        inFileViewerRootedAtPath: (NSString *) rootedAtPath
{
    // TODO: call activateFileViewerSelectingURLs
    NSUnimplementedMethod();
    return NO;
}

- (void) slideImage: (NSImage *) image from: (NSPoint) from to: (NSPoint) to {
}

- (BOOL) performFileOperation: (NSString *) operation
                       source: (NSString *) source
                  destination: (NSString *) destination
                        files: (NSArray *) files
                          tag: (NSInteger *) tag
{
    NSUnimplementedMethod();
}

- (BOOL) getFileSystemInfoForPath: (NSString *) path
                      isRemovable: (BOOL *) isRemovable
                       isWritable: (BOOL *) isWritable
                    isUnmountable: (BOOL *) isUnmountable
                      description: (NSString **) description
                             type: (NSString **) type
{
    if (!path)
        return NO;

    // TODO: call statfs() to get filesystem information
    // Use DiskArbitration for the rest.
    NSUnimplementedMethod();
    return NO;
}

- (BOOL) getInfoForFile: (NSString *) path
            application: (NSString **) application
                   type: (NSString **) type
{
    // TODO: call LSGetApplicationForURL()
    NSUnimplementedMethod();
    return NO;
}

- (void) checkForRemovableMedia {
}

- (NSArray *) mountNewRemovableMedia {
    return [self mountedRemovableMedia];
}

- (NSArray *) mountedRemovableMedia {
    // TODO: call [[NSFileManager defaultManager]
    // mountedVolumeURLsIncludingResourceValuesForKeys:@[NSURLVolumeIsRemovableKey]
    // options:NSVolumeEnumerationSkipHiddenVolumes]
    NSUnimplementedMethod();
    return @[];
}

- (NSArray *) mountedLocalVolumePaths {
    // TODO: call [[NSFileManager defaultManager]
    // mountedVolumeURLsIncludingResourceValuesForKeys:@[]
    // options:NSVolumeEnumerationSkipHiddenVolumes]
    NSUnimplementedMethod();
    return @[];
}

- (BOOL) unmountAndEjectDeviceAtPath: (NSString *) path {
    // TODO: call FSEjectVolumeSync()
    NSUnimplementedMethod();
    return NO;
}

- (BOOL) fileSystemChanged {
    return NO;
}

- (BOOL) userDefaultsChanged {
    return NO;
}

- (void) noteFileSystemChanged {
    [self noteFileSystemChanged: @"/"];
}

- (void) noteFileSystemChanged: (NSString *) path {
    // TODO: call FNNotifyByPath()
    NSUnimplementedMethod();
}

- (void) noteUserDefaultsChanged {
}

- (BOOL) isFilePackageAtPath: (NSString *) path {
    NSUnimplementedMethod();
}

- (NSString *) absolutePathForAppBundleWithIdentifier: (NSString *) identifier {
    // TODO: call LSFindApplicationForInfo() /
    // LSCopyApplicationURLsForBundleIdentifier()
    NSUnimplementedMethod();
    return NULL;
}

- (NSString *) pathForApplication: (NSString *) application {
    // This method doesn't exist on macOS?!
    return NULL;
}

- (NSArray *) launchedApplications {
    // TODO: call _LSCopyRunningApplicationArray()
    NSUnimplementedMethod();
    return @[];
}

- (NSArray *) runningApplications {
    NSUnimplementedMethod();
    return @[];
}

- (BOOL) launchApplication: (NSString *) application {
    return [self openFile: nil withApplication: application andDeactivate: YES];
}

- (BOOL) launchApplication: (NSString *) application
                  showIcon: (BOOL) showIcon
                autolaunch: (BOOL) autolaunch
{
    return [self openFile: nil withApplication: application andDeactivate: YES];
}

- (void) findApplications {
}

- (NSDictionary *) activeApplication {
    // TODO: call _LSCopyFrontApplication() and _LSCopyApplicationInformation()
    NSUnimplementedMethod();
    return NULL;
}

- (void) hideOtherApplications {
    [NSApp hideOtherApplications: self];
}

- (NSInteger) extendPowerOffBy: (NSInteger) milliseconds {
    return 0;
}

- (BOOL) setIcon: (NSImage *) image
         forFile: (NSString *) fullPath
         options: (NSWorkspaceIconCreationOptions) options
{
    // For directories, we would call the NSFileManager to create a file named
    // "Icon\r" with icon data. For files, we would call
    // FSCreateResFile/FSOpenResFile, FSSetCatalogInfo and other historical
    // functions. But none of these would have effect when viewed from Linux
    // desktop environments...
    NSUnimplementedMethod();
    return NO;
}

- (void) activateFileViewerSelectingURLs: (NSArray<NSURL *> *) fileURLs {
    // TODO: Get the current file viewer app by calling [[NSUserDefaults
    // standardUserDefaults] stringForKey: @"NSFileViewer"] Get its path via
    // [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier]
    // Call [self openFile:withApplication:]
    NSUnimplementedMethod();
}

- (NSURL *) URLForApplicationWithBundleIdentifier: (NSString *) bundleIdentifier
{
    CFURLRef url;
    OSStatus status = LSFindApplicationForInfo(kLSUnknownCreator,
                                               (CFStringRef) bundleIdentifier,
                                               NULL, NULL, &url);

    if (status != noErr)
        return nil;

    return [(NSURL *) url autorelease];
}

- (NSString *) fullPathForApplication: (NSString *) appName {
    // If absolute, return as-is
    if ([appName isAbsolutePath])
        return appName;

    // If it doesn't have an suffix, add .app
    if ([[appName pathExtension] isEqualToString: @""])
        appName = [appName stringByAppendingPathExtension: @"app"];

    CFURLRef url;
    OSStatus status = LSFindApplicationForInfo(
            kLSUnknownCreator, NULL, (CFStringRef) appName, NULL, &url);

    if (status != noErr)
        return nil;

    NSString *path = [(NSURL *) url path];
    CFRelease(url);

    return path;
}

@end
