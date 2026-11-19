// Copyright (C) 2026 Lubos Dolezel
//
// -[NSBundle loadNibFile:externalNameTable:withZone:] takes the name of a nib in the bundle, with or
// without the extension; on macOS 10.14.4 and 26.7.3 (black-box) it returns NO for the nib's full path
// and logs nothing, while +[NSBundle loadNibFile:externalNameTable:withZone:] takes the full path.
// NSViewController loads its nib from its nib bundle without logging anything.
//
// Usage: appkit-bundle-nib-name <fixtures/nibarchive directory>
// Build: clang -framework AppKit appkit-bundle-nib-name.m
#import <AppKit/AppKit.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

// The classes Custom.nib refers to (see fixtures/nibarchive/README.md).
@interface CustomHelper : NSObject {
    id owner;
}
@end
@implementation CustomHelper
- (void) setOwner: (id) o { owner = o; }
- (IBAction) go: (id) sender {}
@end
@interface CustomPanelView : NSView
@end
@implementation CustomPanelView
@end

@interface CustomOwner : NSObject {
@public
    id helper, panelView;
}
@end
@implementation CustomOwner
- (void) setHelper: (id) h { helper = h; }
- (void) setPanelView: (id) v { panelView = v; }
@end

// A view controller that is the nib's owner; its panel view is its view.
@interface CustomViewController : NSViewController {
@public
    id helper;
}
@end
@implementation CustomViewController
- (void) setHelper: (id) h { helper = h; }
- (void) setPanelView: (NSView *) v { [self setView: v]; }
@end

static int savedStderr = -1;
static char capturePath[64];

static void beginCapture(void) {
    fflush(stderr);
    strcpy(capturePath, "/tmp/bundle-nib-name-XXXXXX");
    int fd = mkstemp(capturePath);
    savedStderr = dup(2);
    dup2(fd, 2);
    close(fd);
}

static NSString *endCapture(void) {
    fflush(stderr);
    dup2(savedStderr, 2);
    close(savedStderr);
    NSString *text = [NSString stringWithContentsOfFile: [NSString stringWithUTF8String: capturePath]
                                               encoding: NSUTF8StringEncoding
                                                  error: NULL];
    unlink(capturePath);
    return text ? text : @"";
}

static BOOL loadByInstance(NSBundle *bundle, NSString *name, CustomOwner *owner) {
    NSMutableArray *top = [NSMutableArray array];
    NSDictionary *table = [NSDictionary dictionaryWithObjectsAndKeys: owner, NSNibOwner, top, NSNibTopLevelObjects, nil];
    return [bundle loadNibFile: name externalNameTable: table withZone: NULL];
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc < 2) {
            fprintf(stderr, "usage: %s <fixtures/nibarchive>\n", argv[0]);
            return 2;
        }
        [NSApplication sharedApplication];
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *source = [[[NSString stringWithUTF8String: argv[1]] stringByAppendingPathComponent: @"flat"]
                stringByAppendingPathComponent: @"Custom.nib"];
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
                [NSString stringWithFormat: @"bundle-nib-name-%d", getpid()]];
        [fm createDirectoryAtPath: dir withIntermediateDirectories: YES attributes: nil error: NULL];
        NSString *nibPath = [dir stringByAppendingPathComponent: @"Custom.nib"];
        CHECK([fm copyItemAtPath: source toPath: nibPath error: NULL]);
        NSBundle *bundle = [NSBundle bundleWithPath: dir];
        CHECK(bundle != nil);

        beginCapture();
        CustomOwner *byName = [CustomOwner new];
        BOOL loadedByName = loadByInstance(bundle, @"Custom", byName);
        CustomOwner *byFileName = [CustomOwner new];
        BOOL loadedByFileName = loadByInstance(bundle, @"Custom.nib", byFileName);
        CustomOwner *byPath = [CustomOwner new];
        BOOL loadedByPath = loadByInstance(bundle, nibPath, byPath);
        CustomOwner *byPathWithoutExtension = [CustomOwner new];
        BOOL loadedByPathWithoutExtension = loadByInstance(bundle, [nibPath stringByDeletingPathExtension],
                                                           byPathWithoutExtension);
        CustomOwner *byClass = [CustomOwner new];
        BOOL loadedByClass = [NSBundle loadNibFile: nibPath
                                 externalNameTable: [NSDictionary dictionaryWithObject: byClass forKey: NSNibOwner]
                                          withZone: NULL];
        CustomViewController *controller = [[CustomViewController alloc] initWithNibName: @"Custom" bundle: bundle];
        NSView *view = [controller view];
        NSString *logged = endCapture();

        CHECK(loadedByName && [byName->panelView isKindOfClass: [CustomPanelView class]]);
        CHECK(loadedByFileName && [byFileName->panelView isKindOfClass: [CustomPanelView class]]);
        CHECK(!loadedByPath && byPath->panelView == nil);
        CHECK(!loadedByPathWithoutExtension && byPathWithoutExtension->panelView == nil);
        CHECK(loadedByClass && [byClass->panelView isKindOfClass: [CustomPanelView class]]);
        CHECK([view isKindOfClass: [CustomPanelView class]] && controller->helper != nil);
        CHECK([logged length] == 0);
        if ([logged length] != 0)
            fprintf(stderr, "logged: %s\n", [logged UTF8String]);

        [fm removeItemAtPath: dir error: NULL];
    }
    if (failures)
        return 1;
    printf("PASS\n");
    return 0;
}
