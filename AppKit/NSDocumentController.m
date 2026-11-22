/* Copyright (c) 2006-2007 Christopher J. W. Lloyd
                 2009 Markus Hitter <mah@jump-ing.de>

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import "NSDocumentTypeName.h"
#import <AppKit/NSApplication.h>
#import <AppKit/NSDocument.h>
#import <AppKit/NSDocumentController.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSMenuItem.h>
#import <AppKit/NSOpenPanel.h>
#import <AppKit/NSRaise.h>
#import <AppKit/NSWindowController.h>
#import <objc/runtime.h>

// UTType, when the application has loaded UniformTypeIdentifiers.
@interface NSObject (NSDocumentControllerContentTypes)
+ (id) typeWithIdentifier: (NSString *) identifier;
+ (id) typeWithFilenameExtension: (NSString *) extension;
- (NSString *) identifier;
- (NSString *) preferredFilenameExtension;
@end

@interface _NSUnsupportedDocument : NSObject

- (instancetype) initWithType: (NSString *) type error: (NSError **) error;
- (instancetype) initWithContentsOfURL: (NSURL *) url
                                ofType: (NSString *) typeName
                                 error: (NSError *_Nullable *) outError;
- (id) initWithContentsOfURL: (NSURL *) url ofType: (NSString *) typeName;
- (id) initWithContentsOfFile: (NSString *) absolutePath
                       ofType: (NSString *) typeName;

@end

@implementation _NSUnsupportedDocument

- (instancetype) initWithType: (NSString *) type error: (NSError **) error {
    *error = [NSError errorWithDomain: NSCocoaErrorDomain
                                 code: NSFeatureUnsupportedError
                             userInfo: nil];
    [self release];
    return nil;
}

- (instancetype) initWithContentsOfURL: (NSURL *) url
                                ofType: (NSString *) typeName
                                 error: (NSError *_Nullable *) outError
{

    if (outError) {
        *outError = [NSError errorWithDomain: NSCocoaErrorDomain
                                        code: NSFeatureUnsupportedError
                                    userInfo: nil];
    }

    [self release];
    return nil;
}

- (id) initWithContentsOfURL: (NSURL *) url ofType: (NSString *) typeName {
    [self release];
    return nil;
}

- (id) initWithContentsOfFile: (NSString *) absolutePath
                       ofType: (NSString *) typeName
{
    [self release];
    return nil;
}

@end

@interface NSDocument (private)
- (void) _setUntitledNumber: (int) number;
@end

@interface NSDocumentController (forward)
- (void) _updateRecentDocumentsMenu;
@end

@interface NSMenu (private)
- (NSMenu *) _menuWithName: (NSString *) name;
@end

@implementation NSDocumentController

static NSDocumentController *shared = nil;

+ sharedDocumentController {
    @synchronized([NSDocumentController class]) {
        if (shared == nil) {
            // NOTE: it is important that this is `self` and not `NSDocumentController` directly;
            //       Xcode subclasses NSDocumentController and invokes this class method on said subclass,
            //       expecting the shared controller to be allocated as that subclass instead of `NSDocumentController`.
            [[[self alloc] init] release]; // init makes it the shared controller
            [shared _updateRecentDocumentsMenu];
        }
    }

    return shared;
}

- init {
    // The first controller made becomes the shared one, however it was made
    // (an application can make its own subclass instance early, and releases
    // it), so the shared controller owns itself.
    if (shared == nil)
        shared = [self retain];

    _documents = [NSMutableArray new];
    _fileTypes = [[[[NSBundle mainBundle] infoDictionary]
            objectForKey: @"CFBundleDocumentTypes"] retain];
    _autosavingDelay = 0;

    // A controller made before the main menu was set (by the main nib, say)
    // could not list the recent documents yet; list them once launched.
    [[NSNotificationCenter defaultCenter]
            addObserver: self
               selector: @selector(_applicationDidFinishLaunching:)
                   name: NSApplicationDidFinishLaunchingNotification
                 object: nil];
    return self;
}

- (void) _applicationDidFinishLaunching: (NSNotification *) note {
    [self _updateRecentDocumentsMenu];
}

- (void) dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver: self];
    [_documents release];
    [_fileTypes release];
    [super dealloc];
}

- initWithCoder: (NSCoder *) coder {
    NSUnimplementedMethod();
    return nil;
}

- (void) encodeWithCoder: (NSCoder *) coder {
    NSUnimplementedMethod();
}

- (NSString *) defaultType {
    // The type new documents are made of is the first one the application can edit; an application
    // that declares none has no default.
    for (NSDictionary *fileType in _fileTypes) {
        // GUESS: an Editor entry that has neither a content type nor a name cannot be the default
        // (there is no type name to return), so the search goes on to the next Editor entry.
        NSString *name = NSDocumentTypeNameForInfo(fileType);
        if (name != nil && [[fileType objectForKey: @"CFBundleTypeRole"] isEqual: @"Editor"])
            return name;
    }

    return nil;
}

- (NSArray *) documentClassNames {
    NSMutableSet *result = [NSMutableSet set];

    for (NSDictionary *fileType in _fileTypes) {
        // An entry that declares no document class has no name to list.
        NSString *className = [fileType objectForKey: @"NSDocumentClass"];
        if (className != nil)
            [result addObject: className];
    }

    return [result allObjects];
}

- (NSTimeInterval) autosavingDelay {
    return _autosavingDelay;
}

// The CFBundleDocumentTypes entry for a type name: one of its LSItemContentTypes, or its
// CFBundleTypeName when it declares none.
- (NSDictionary *) _infoForType: (NSString *) type {
    if (type == nil)
        return nil;
    for (NSDictionary *check in _fileTypes) {
        if (NSDocumentInfoHasTypeName(check, type))
            return check;
    }
    return nil;
}

- (NSString *) displayNameForType: (NSString *) type {
    NSDictionary *info = [self _infoForType: type];
    NSString *result = [info objectForKey: @"CFBundleTypeName"];

    return (result == nil) ? type : result;
}

- (Class) documentClassForType: (NSString *) type {
    NSString *result = [[self _infoForType: type] objectForKey: @"NSDocumentClass"];

    return (result == nil) ? nil : NSClassFromString(result);
}

- (NSArray *) fileExtensionsFromType: (NSString *) type {
    NSDictionary *info = [self _infoForType: type];
    NSArray *extensions = [info objectForKey: @"CFBundleTypeExtensions"];
    if ([extensions count] > 0)
        return extensions;

    // Types named only by content type identifiers list no extensions; UTType knows them.
    NSArray *identifiers = [info objectForKey: @"LSItemContentTypes"];
    if (identifiers == nil && type != nil)
        identifiers = [NSArray arrayWithObject: type];
    Class contentType = NSClassFromString(@"UTType");
    NSMutableArray *result = [NSMutableArray array];
    for (NSString *identifier in identifiers) {
        NSString *extension = [[contentType typeWithIdentifier: identifier]
                preferredFilenameExtension];
        if ([extension length] > 0 && ![result containsObject: extension])
            [result addObject: extension];
    }
    return [result count] > 0 ? result : nil;
}

- (NSArray *) _allFileExtensions {
    NSMutableSet *set = [NSMutableSet set];
    int i, count = [_fileTypes count];

    for (i = 0; i < count; i++) {
        NSArray *add = [(NSDictionary *) [_fileTypes objectAtIndex: i]
                objectForKey: @"CFBundleTypeExtensions"];
        [set addObjectsFromArray: add];
    }

    return [set allObjects];
}

- (NSString *) typeFromFileExtension: (NSString *) extension {
    extension = [extension lowercaseString];
    for (NSDictionary *fileType in _fileTypes)
        for (NSString *name in
             [fileType objectForKey: @"CFBundleTypeExtensions"]) {
            if ([[name lowercaseString] isEqual: extension] ||
                [name isEqual: @"*"])
                return NSDocumentTypeNameForInfo(fileType);
        }

    // Modern bundles may declare only LSItemContentTypes. Keep explicit
    // extensions (including the legacy wildcard) ahead of registry lookup.
    if ([extension length] == 0)
        return nil;
    Class contentType = NSClassFromString(@"UTType");
    if (![contentType respondsToSelector: @selector(typeWithFilenameExtension:)])
        return nil;
    NSString *identifier = [[contentType typeWithFilenameExtension: extension] identifier];
    if (identifier != nil) {
        for (NSDictionary *fileType in _fileTypes) {
            if ([[fileType objectForKey: @"LSItemContentTypes"] containsObject: identifier])
                return identifier;
        }
    }
    return nil;
}

// Documents that autosave in place are autosaved this long after an edit (see -[NSDocument updateChangeCount:]).
- (void) setAutosavingDelay: (NSTimeInterval) value {
    _autosavingDelay = value;
}

- (NSArray *) documents {
    return _documents;
}

- (void) addDocument: (NSDocument *) document {
    [_documents addObject: document];
}

- (void) removeDocument: (NSDocument *) document {
    [_documents removeObjectIdenticalTo: document];
}

- documentForURL: (NSURL *) url {
    int i, count = [_documents count];

    for (i = 0; i < count; i++) {
        NSDocument *document = [_documents objectAtIndex: i];
        NSURL *check = [document fileURL];

        if (check != nil && [check isEqual: url])
            return document;
    }

    return nil;
}

- (id) documentForFileName: (NSString *) fileName {
    if (fileName == nil) return nil;
    return [self documentForURL: [NSURL fileURLWithPath: fileName]];
}

- currentDocument {
    return [[[NSApp mainWindow] windowController] document];
}

- (NSString *) currentDirectory {
    NSDocument *current = [self currentDocument];
    NSURL *url = [current fileURL];

    if (url != nil && [url isFileURL]) {
        NSString *check = [[url path] stringByDeletingLastPathComponent];
        BOOL isDirectory;

        if ([[NSFileManager defaultManager] fileExistsAtPath: check
                                                 isDirectory: &isDirectory])
            if (isDirectory)
                return check;
    }

    NSString *lastOpenPanelDirectory = [[NSUserDefaults standardUserDefaults]
            stringForKey: @"NSNavLastRootDirectory"];
    if (lastOpenPanelDirectory != nil)
        return lastOpenPanelDirectory;

    return NSHomeDirectory();
}

- (BOOL) hasEditedDocuments {
    int count = [_documents count];

    while (--count)
        if ([[_documents objectAtIndex: count] isDocumentEdited])
            return YES;

    return NO;
}

- documentForWindow: (NSWindow *) window {
    return [[window windowController] document];
}

// A URL that is not a file URL has no contents to look at here: nil with an error. The error code is
// not observed (GUESS: NSFileReadUnknownError, the one this controller uses for a file that cannot be
// read); the only observed failure is a missing file, which NSFileReadNoSuchFileError describes.
static NSError *TypeLookupError(NSURL *url, NSInteger code) {
    return [NSError errorWithDomain: NSCocoaErrorDomain
                               code: code
                           userInfo: url != nil ? @{NSURLErrorKey : url} : nil];
}

- (NSString *) typeForContentsOfURL: (NSURL *) url error: (NSError **) error {
    if (![url isFileURL]) {
        if (error != NULL)
            *error = TypeLookupError(url, NSFileReadUnknownError);
        return nil;
    }

    // Observed on macOS 26.7.3 and 10.14.4 (black-box test): a file that exists always has a type,
    // whether or not the application declares it (a type identifier derived from the extension, or
    // public.data without one, public.folder for a directory), and only a missing file gives
    // nil, with NSCocoaErrorDomain code 260 (NSFileReadNoSuchFileError).
    // Test: appkit-document-controller-type-for-contents.m
    BOOL isDirectory = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath: [url path] isDirectory: &isDirectory]) {
        if (error != NULL)
            *error = TypeLookupError(url, NSFileReadNoSuchFileError);
        return nil;
    }

    NSString *extension = [[url path] pathExtension];

    NSString *UTI = nil;
    NSError *resourceError = nil;

    BOOL success = [url getResourceValue: &UTI
                                  forKey: NSURLTypeIdentifierKey
                                   error: &resourceError];
    if (!success && resourceError != nil) {
        if (error != NULL)
            *error = resourceError;
        return nil;
    }

    if (error != NULL)
        *error = nil;
    for(NSDictionary *fileType in _fileTypes) {
        if (success && UTI != nil && [[fileType objectForKey: @"LSItemContentTypes"] containsObject: UTI]) {
            return UTI;
        }
    }
    NSString *type = isDirectory ? nil : [self typeFromFileExtension: extension];
    if (type == nil)
        type = UTI;
    if (type == nil)
        type = isDirectory ? @"public.folder" : @"public.data";
    return type;
}

- makeDocumentWithContentsOfFile: (NSString *) path ofType: (NSString *) type {
    id result;
    Class class = [self documentClassForType: type];

    result = [[[class alloc] initWithContentsOfFile: path
                                             ofType: type] autorelease];

    return result;
}

// The error shown to the user for a document that could not be opened although its class reported none.
// The same construction (Cocoa domain, NSFileReadUnknownError, the URL under NSURLErrorKey) is what
// siliconforest patch 0351 uses for the error of its type lookup. NSFileReadUnknownError (256) is what
// macOS 26.7.3 reports in the completion handler of -openDocumentWithContentsOfURL:display:completionHandler:
// when the class returned nil without an error (black-box observation).
static NSError *DocumentOpenFailureError(NSURL *url) {
    return [NSError errorWithDomain: NSCocoaErrorDomain
                               code: NSFileReadUnknownError
                           userInfo: url != nil ? @{NSURLErrorKey : url} : nil];
}

- makeDocumentWithContentsOfURL: (NSURL *) url
                         ofType: (NSString *) type
                          error: (NSError **) error
{
    Class class = [self documentClassForType: type];
    NSError *initError = nil;
    id result = [[[class alloc] initWithContentsOfURL: url
                                               ofType: type
                                                error: &initError] autorelease];

    // The error is what the initialiser reported. When it returns nil without one, the error stays nil:
    // observed on macOS 26.7.3 and 10.14.4 (black-box test, class reading nil with no error) and pinned by
    // appkit-document-controller-make-document-errors.m.
    if (result == nil && error != NULL)
        *error = initError;
    return result;
}

- makeDocumentForURL: (NSURL *) url
        withContentsOfURL: (NSURL *) contentsURL
                   ofType: (NSString *) type
                    error: (NSError **) error
{
    id result = nil;
    Class class = [self documentClassForType: type];

    result = [[[class alloc] initForURL: url
                      withContentsOfURL: contentsURL
                                 ofType: type
                                  error: error] autorelease];

    return result;
}

// A type with no document class gives nil with NSCocoaErrorDomain NSFileReadUnknownError (256, empty userInfo),
// also for a nil, empty or unknown type, and an error already in the caller's variable is replaced. Observed by
// black-box test on macOS 26.7.3 and 10.14.4 (identical); pinned by appkit-document-controller-make-untitled-error.m.
static NSError *UntitledDocumentError(void) {
    return [NSError errorWithDomain: NSCocoaErrorDomain code: NSFileReadUnknownError userInfo: nil];
}

- (id) makeUntitledDocumentOfType: (NSString *) type {
    static int nextUntitledNumber = 1;
    id result = nil;
    Class class = [self documentClassForType: type];

    NSError *error = nil;
    result = [[[class alloc] initWithType: type error: &error] autorelease];
    if (result)
        [result _setUntitledNumber: nextUntitledNumber++];
    else
        [self presentError: error != nil ? error : UntitledDocumentError()];

    return result;
}

- (id) makeUntitledDocumentOfType: (NSString *) type
                            error: (NSError **) outError
{
    /* Cocoa documentation says:
         "For backward binary compatibility with Mac OS X v10.3 and earlier,
          the default implementation of this method instead invokes
       makeUntitledDocumentOfType: if it is overridden." Hence we need to check
       if this class is a subclass that has this method overridden.
    */
    IMP mine = [NSDocumentController
            instanceMethodForSelector: @selector(makeUntitledDocumentOfType:)];
    IMP theirs =
            [self methodForSelector: @selector(makeUntitledDocumentOfType:)];
    if (mine != theirs) {
        return [self makeUntitledDocumentOfType: type];
    }

    static int nextUntitledNumber = 1;
    id result = nil;
    Class class = [self documentClassForType: type];

    NSError *error = nil;
    result = [[[class alloc] initWithType: type error: &error] autorelease];
    if (result)
        [result _setUntitledNumber: nextUntitledNumber++];
    else {
        // A type with no document class has no initialiser to report anything.
        if (error == nil)
            error = UntitledDocumentError();
        if (outError)
            *outError = error;
        else
            [self presentError: error];
    }

    return result;
}

- openUntitledDocumentOfType: (NSString *) type display: (BOOL) display {
    NSDocument *result = [self makeUntitledDocumentOfType: type error: NULL];

    if (result != nil)
        [self addDocument: result];

    [result makeWindowControllers];

    if (display)
        [result showWindows];

    return result;
}

- openUntitledDocumentAndDisplay: (BOOL) display error: (NSError **) error {
    NSString *type = [self defaultType];
    /* Cocoa documentation says:
         "For backward binary compatibility with Mac OS X v10.3 and earlier,
          the default implementation of this method instead invokes
       openUntitledDocumentOfType:display: if it is overridden." Hence we need
       to check if this class is a subclass that has this method overridden.
    */
    IMP mine = [NSDocumentController instanceMethodForSelector: @selector
                                     (openUntitledDocumentOfType:display:)];
    IMP theirs = [self
            methodForSelector: @selector(openUntitledDocumentOfType:display:)];
    if (mine != theirs) {
        return [self openUntitledDocumentOfType: type display: display];
    }

    NSDocument *result = [self makeUntitledDocumentOfType: type error: error];

    if (result != nil)
        [self addDocument: result];

    [result makeWindowControllers];

    if (display)
        [result showWindows];

    return result;
}

- openDocumentWithContentsOfFile: (NSString *) path display: (BOOL) display {
    NSString *extension = [path pathExtension];
    NSString *type = [self typeFromFileExtension: extension];
    NSDocument *result = [self makeDocumentWithContentsOfFile: path
                                                       ofType: type];

    if (result != nil)
        [self addDocument: result];

    [result makeWindowControllers];

    if (display)
        [result showWindows];

    [self noteNewRecentDocument: result];

    return result;
}

- openDocumentWithContentsOfURL: (NSURL *) url
                        display: (BOOL) display
                          error: (NSError **) error
{
    IMP mine = [NSDocumentController instanceMethodForSelector: @selector
                                     (openDocumentWithContentsOfFile:display:)];
    IMP theirs = [self methodForSelector: @selector
                       (openDocumentWithContentsOfFile:display:)];

    if ([url isFileURL] && mine != theirs)
        return [self openDocumentWithContentsOfFile: [url path]
                                            display: display];
    else {
        NSDocument *result = [self documentForURL: url];

        if (result == nil) {
            NSError *type_error = nil;
            NSString *type = [self typeForContentsOfURL: url
                                                  error: &type_error];

            if (type_error) {
                if (error) {
                    *error = type_error;
                }
                return result;
            }

            result = [self makeDocumentWithContentsOfURL: url
                                                  ofType: type
                                                   error: error];
            if (result != nil) {
                [self addDocument: result];
                [result makeWindowControllers];
                [self noteNewRecentDocument: result];
            }
        }
        if (display)
            [result showWindows];

        return result;
    }
}

- (void) openDocumentWithContentsOfURL: (NSURL *) url
                               display: (BOOL) display
                     completionHandler: (void (^)(NSDocument *document, BOOL documentWasAlreadyOpen, NSError *error)) completionHandler
{
    BOOL wasAlreadyOpen = url != nil && [self documentForURL: url] != nil;
    NSError *error = nil;
    NSDocument *document = [self openDocumentWithContentsOfURL: url
                                                       display: display
                                                         error: &error];
    if (document == nil && error == nil)
        error = [NSError errorWithDomain: NSCocoaErrorDomain
                                    code: NSFileReadUnknownError
                                userInfo: nil];
    if (completionHandler)
        completionHandler(document, document != nil && wasAlreadyOpen,
                          document != nil ? nil : error);
}

- (BOOL) reopenDocumentForURL: (NSURL *) url
            withContentsOfURL: (NSURL *) contentsUL
                        error: (NSError **) error
{
    NSUnimplementedMethod();
    return 0;
}

- (void) _closeDocumentsStartingWith: (NSDocument *) document
                         shouldClose: (BOOL) shouldClose
                     closeAllContext: (NSDictionary *) context
{
    // This is a recursive callback method. Start it by passing in a document of
    // nil.
    void (*delegateMethod)(id, SEL, id, BOOL, void *);

    if (shouldClose) {
        [document close];
        if ([_documents count] > 0) {
            [[_documents lastObject]
                    canCloseDocumentWithDelegate: self
                             shouldCloseSelector: @selector
                             (_closeDocumentsStartingWith:
                                              shouldClose:closeAllContext:)
                                     contextInfo: context];
            return;
        }
    }

    // Inform our closeAllDocuments delegate of the results.
    id delegate = [context objectForKey: @"delegate"];
    SEL selector = NSSelectorFromString([context objectForKey: @"selector"]);
    void *info = [[context objectForKey: @"contextInfo"] pointerValue];
    [context release];
    if ([delegate respondsToSelector: selector]) {
        void (*delegateMethod)(id, SEL, id, BOOL, void *);
        delegateMethod =
                (void (*)(id, SEL, id, BOOL,
                          void *)) [delegate methodForSelector: selector];
        delegateMethod(delegate, selector, self, ([_documents count] == 0),
                       info);
    }
}

- (void) closeAllDocumentsWithDelegate: delegate
                   didCloseAllSelector: (SEL) selector
                           contextInfo: (void *) info
{
    NSDictionary *closeAllContext = [[NSDictionary alloc]
            initWithObjectsAndKeys: delegate, @"delegate",
                                    NSStringFromSelector(selector), @"selector",
                                    [NSValue valueWithPointer: info],
                                    @"contextInfo", nil];
    [self _closeDocumentsStartingWith: nil
                          shouldClose: YES
                      closeAllContext: closeAllContext];
}

- (void) reviewUnsavedDocumentsWithAlertTitle: (NSString *) title
                                  cancellable: (BOOL) cancellable
                                     delegate: delegate
                         didReviewAllSelector: (SEL) selector
                                         info: (void *) info
{
    NSUnimplementedMethod();
}

- (NSError *) willPresentError: (NSError *) error {
    // do nothing
    return error;
}

- (BOOL) presentError: (NSError *) error {
    return [NSApp presentError: [self willPresentError: error]];
}

- (void) presentError: (NSError *) error
            modalForWindow: (NSWindow *) window
                  delegate: delegate
        didPresentSelector: (SEL) selector
               contextInfo: (void *) info
{
    [NSApp presentError: [self willPresentError: error]
                modalForWindow: window
                      delegate: delegate
            didPresentSelector: selector
                   contextInfo: info];
}

- (int) runModalOpenPanel: (NSOpenPanel *) openPanel
                 forTypes: (NSArray *) extensions
{
    int result = [openPanel runModalForDirectory: [self currentDirectory]
                                            file: nil
                                           types: extensions];
    if (result)
        [[NSUserDefaults standardUserDefaults]
                setObject: [openPanel directory]
                   forKey: @"NSNavLastRootDirectory"];
    return result;
}

- (NSOpenPanel *) _runOpenPanel {
    NSOpenPanel *openPanel = [NSOpenPanel openPanel];

    [openPanel setAllowsMultipleSelection: YES];

    if ([self runModalOpenPanel: openPanel
                       forTypes: [self _allFileExtensions]]) {
        return openPanel;
    }

    return nil;
}

- (NSArray *) fileNamesFromRunningOpenPanel {
    return [[self _runOpenPanel] filenames];
}

- (NSArray *) URLsFromRunningOpenPanel {
    return [[self _runOpenPanel] URLs];
}

- (NSMutableArray *) _recentDocumentPaths {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSMutableArray *paths = [NSMutableArray
            arrayWithArray: [[NSUserDefaults standardUserDefaults]
                                    arrayForKey: @"NSRecentDocumentPaths"]];
    int i, count = [paths count];

    for (i = count - 1; i >= 0; i--)
        if (![fileManager fileExistsAtPath: [paths objectAtIndex: i]])
            [paths removeObjectAtIndex: i];

    if ([paths count] != count)
        [[NSUserDefaults standardUserDefaults]
                setObject: paths
                   forKey: @"NSRecentDocumentPaths"];

    return paths;
}

// Tells the user why a document could not be opened. GUESS: the documentation says nothing about who
// presents a failure to open (the legacy initialiser used to show an alert itself). An error that says
// the user cancelled is not presented; that is this method's own rule (Darling's -presentError: does
// not skip such errors).
- (void) _presentOpenError: (NSError *) error forURL: (NSURL *) url {
    // A failure that reported no error is still told to the user, with the generic error.
    if (error == nil)
        error = DocumentOpenFailureError(url);
    if ([[error domain] isEqual: NSCocoaErrorDomain] && [error code] == NSUserCancelledError)
        return;
    [self presentError: error];
}

- (void) _openRecentDocument: sender {
    NSArray *paths = [self _recentDocumentPaths];
    NSMenuItem *item = sender;
    int tag = [item tag];

    if (tag >= 0 && tag < [paths count]) {
        NSError *error = nil;
        NSURL *url = [NSURL fileURLWithPath: [paths objectAtIndex: tag]];

        if (![self openDocumentWithContentsOfURL: url
                                         display: YES
                                           error: &error] ||
            error) {
            if ([url isFileURL]) {
                NSObject<NSApplicationDelegate> *appDelegate = [NSApp delegate];
                if ([appDelegate respondsToSelector: @selector(application:
                                                                 openFiles:)]) {
                    [appDelegate
                            application: NSApp
                              openFiles: [NSArray arrayWithObject: [url path]]];
                } else if ([appDelegate respondsToSelector: @selector
                                        (application:openFile:)]) {
                    [appDelegate application: NSApp openFile: [url path]];
                } else {
                    [self _presentOpenError: error forURL: url];
                }
            }
        }
    }
}

- (void) _removeAllRecentDocumentsFromMenu: (NSMenu *) menu {
    int count = [[menu itemArray] count];

    while (--count >= 0) {
        NSMenuItem *check = [[menu itemArray] objectAtIndex: count];

        if (sel_isEqual([check action], @selector(_openRecentDocument:))) {
            [menu removeItemAtIndex: count];
        }
    }
}

- (void) _updateRecentDocumentsMenu {
    NSMenu *mainMenu = [NSApp mainMenu];
    if (mainMenu == nil)
        return;
    NSMenu *menu = [mainMenu _menuWithName: @"_NSRecentDocumentsMenu"];
    if (menu == nil)
        return;
    NSArray *array = [self _recentDocumentPaths];
    int i, j, count = [array count];
    NSMutableArray *lastPathArray = [[NSMutableArray alloc] init];

    [self _removeAllRecentDocumentsFromMenu: menu];

    if ([[menu itemArray] count] > 0) {
        if ([array count] == 0) {
            if ([[[menu itemArray] objectAtIndex: 0] isSeparatorItem])
                [menu removeItemAtIndex: 0];
        } else {
            if (![[[menu itemArray] objectAtIndex: 0] isSeparatorItem])
                [menu insertItem: [NSMenuItem separatorItem] atIndex: 0];
        }
    }

    // Shorten entries to the last path component, but not for then-duplicates.
    for (i = 0; i < count; i++) {
        NSString *lastPath =
                [(NSString *) [array objectAtIndex: i] lastPathComponent];
        NSInteger occurences = 0;

        for (j = 0; j < count; j++) {
            if ([[(NSString *) [array objectAtIndex: j] lastPathComponent]
                        isEqualToString: lastPath])
                occurences++;
        }
        if (occurences > 1)
            [lastPathArray addObject: [array objectAtIndex: i]];
        else
            [lastPathArray addObject: lastPath];
    }

    while (--count >= 0) {
        NSString *path = [lastPathArray objectAtIndex: count];
        NSMenuItem *item = [[[NSMenuItem alloc]
                initWithTitle: path
                       action: @selector(_openRecentDocument:)
                keyEquivalent: @""] autorelease];

        [item setTag: count];
        [menu insertItem: item atIndex: 0];
    }
    [lastPathArray release];
}

- (NSArray *) recentDocumentURLs {
    NSArray *paths = [self _recentDocumentPaths];
    int i, count = [paths count];
    NSMutableArray *result = [NSMutableArray arrayWithCapacity: count];

    for (i = 0; i < count; i++)
        [result addObject: [NSURL fileURLWithPath: [paths objectAtIndex: i]]];

    return result;
}

- (NSArray *) _recentDocumentURLsForKey: (NSString *) key {
    if (key == nil) key = @"NSRecentDocumentPaths";

    NSArray *paths = [[NSUserDefaults standardUserDefaults] arrayForKey: key];
    if (paths == nil)
        paths = [self _recentDocumentPaths];

    NSMutableArray *result = [NSMutableArray arrayWithCapacity: [paths count]];
    for (id item in paths) {
        if ([item isKindOfClass: [NSURL class]])
            [result addObject: item];
        else if ([item isKindOfClass: [NSString class]])
            [result addObject: [NSURL fileURLWithPath: item]];
    }
    return result;
}

- (unsigned) maximumRecentDocumentCount {
    NSString *value = [[NSUserDefaults standardUserDefaults]
            stringForKey: @"NSRecentDocumentMaximum"];

    return (value == nil) ? 10 : [value intValue];
}

- (void) _noteNewRecentDocumentURL: (NSURL *) url forKey: (NSString *) key {
    if (url == nil) return;
    if (key == nil) key = @"NSRecentDocumentPaths";
    NSString *path = [url path];
    if (path == nil) return;

    NSArray *existing = [[NSUserDefaults standardUserDefaults] arrayForKey: key];
    NSMutableArray *array = existing ? [[existing mutableCopy] autorelease] : [NSMutableArray array];

    [array removeObject: path];
    [array insertObject: path atIndex: 0];

    while ([array count] > [self maximumRecentDocumentCount])
        [array removeLastObject];

    [[NSUserDefaults standardUserDefaults] setObject: array forKey: key];
    [self _updateRecentDocumentsMenu];
}

- (void) noteNewRecentDocumentURL: (NSURL *) url {
    [self _noteNewRecentDocumentURL: url forKey: @"NSRecentDocumentPaths"];
}

- (void) noteNewRecentDocument: (NSDocument *) document {
    NSURL *url = [document fileURL];

    if (url != nil)
        [self noteNewRecentDocumentURL: url];
}

- (void) clearRecentDocuments: sender {
    NSArray *array = [NSArray array];

    [[NSUserDefaults standardUserDefaults] setObject: array
                                              forKey: @"NSRecentDocumentPaths"];
    [self _updateRecentDocumentsMenu];
}

- (void) newDocument: sender {
    [self openUntitledDocumentAndDisplay: YES error: NULL];
}

- (void) openDocument: sender {
    NSArray *files = [self fileNamesFromRunningOpenPanel];
    int i, count = [files count];

    for (i = 0; i < count; i++) {
        NSError *error = nil;
        NSURL *url = [NSURL fileURLWithPath: [files objectAtIndex: i]];

        if ([self openDocumentWithContentsOfURL: url display: YES error: &error] == nil)
            [self _presentOpenError: error forURL: url];
    }
}

- (void) saveAllDocuments: sender {
    int i, count = [_documents count];

    while (--count >= 0) {
        NSDocument *document = [_documents objectAtIndex: count];

        if ([document isDocumentEdited])
            [document saveDocument: sender];
    }
}

static BOOL actionIsDocumentController(SEL selector) {
    if (sel_isEqual(selector, @selector(saveAllDocuments:)))
        return YES;
    if (sel_isEqual(selector, @selector(openDocument:)))
        return YES;
    if (sel_isEqual(selector, @selector(newDocument:)))
        return YES;
    if (sel_isEqual(selector, @selector(clearRecentDocuments:)))
        return YES;
    if (sel_isEqual(selector, @selector(_openRecentDocument:)))
        return YES;

    return NO;
}

- (BOOL) validateMenuItem: (NSMenuItem *) item {
    return (actionIsDocumentController([item action]) ||
            [self respondsToSelector: [item action]]);
}

- (BOOL) validateUserInterfaceItem: (id<NSValidatedUserInterfaceItem>) item {
    return (actionIsDocumentController([item action]) ||
            [self respondsToSelector: [item action]]);
}

- (BOOL) application: sender openFile: (NSString *) path {
    NSError *error = nil;
    NSURL *url = [NSURL fileURLWithPath: path];
    NSDocument *document = [self openDocumentWithContentsOfURL: url
                                                       display: YES
                                                         error: &error];

    if (document == nil)
        [self _presentOpenError: error forURL: url];
    return (document != nil) ? YES : NO;
}

- (BOOL) closeAllDocuments {
    NSUnimplementedMethod();
    return NO;
}

- (BOOL) reviewUnsavedDocumentsWithAlertTitle: (NSString *) title
                                  cancellable: (BOOL) cancellable
{
    NSUnimplementedMethod();
    return 0;
}

+ (BOOL) shouldCreateUI {
    return YES;
}

- (BOOL) shouldCreateUI {
    return YES;
}

@end

@implementation NSDocumentController (NSDocumentDuplication)

- (id) duplicateDocumentWithContentsOfURL: (NSURL *) url
                                  copying: (BOOL) duplicateByCopying
                              displayName: (NSString *) displayNameOrNil
                                    error: (NSError **) error
{
    NSString *type = [self typeForContentsOfURL: url error: error];
    NSDocument *document = nil;
    if (type != nil)
        document = [self makeDocumentForURL: nil
                          withContentsOfURL: url
                                     ofType: type
                                      error: error];
    if (document == nil) {
        if (error != NULL && *error == nil)
            *error = [NSError errorWithDomain: NSCocoaErrorDomain
                                         code: NSFileReadUnknownError
                                     userInfo: nil];
        return nil;
    }
    [self addDocument: document];
    [document makeWindowControllers];
    [document showWindows];
    return document;
}

@end
