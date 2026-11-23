// AppKit regression: an NSPopover decodes from a binary NIBArchive nib (not a keyed plist).
// usage: nibarchive-popover DIRECTORY_CONTAINING_NIBArchivePopover.nib   (needs no display)
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static int checks, failures;

static void expect(BOOL ok, const char *what) {
    checks++;
    if (!ok) {
        printf("FAIL %s\n", what);
        failures++;
    }
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc != 2) {
            puts("usage: nibarchive-popover DIRECTORY");
            return 2;
        }
        NSString *directory = [NSString stringWithUTF8String: argv[1]];
        NSData *raw = [NSData dataWithContentsOfFile: [directory stringByAppendingPathComponent: @"NIBArchivePopover.nib"]];
        expect([raw length] > 10 && memcmp([raw bytes], "NIBArchive", 10) == 0, "the fixture is a NIBArchive");

        // The forwarding stub for an unimplemented class logs to stderr; capture it.
        fflush(stderr);
        int savedStderr = dup(2);
        FILE *log = tmpfile();
        dup2(fileno(log), 2);

        [NSApplication sharedApplication];
        NSBundle *bundle = [NSBundle bundleWithPath: directory];
        NSNib *nib = [[NSNib alloc] initWithNibNamed: @"NIBArchivePopover" bundle: bundle];
        NSArray *objects = nil;
        BOOL loaded = nib != nil && [nib instantiateWithOwner: nil topLevelObjects: &objects];

        fflush(stderr);
        dup2(savedStderr, 2);
        close(savedStderr);
        long end = ftell(log);
        rewind(log);
        char *text = calloc(end + 1, 1);
        fread(text, 1, end, log);
        fclose(log);

        expect(loaded, "NIBArchivePopover.nib loads");
        NSPopover *popover = nil;
        for (id object in objects)
            if ([object isKindOfClass: [NSPopover class]])
                popover = object;
        expect(popover != nil, "the nib's popover decodes");
        expect([popover behavior] == NSPopoverBehaviorSemitransient, "NSBehavior 2 decodes");
        expect(![popover animates], "NSAnimates NO decodes");
        expect(NSEqualSizes([popover contentSize], NSZeroSize), "content size 0x0 decodes");
        expect(![popover isShown], "a decoded popover is not shown");
        expect(strcasestr(text, "stub") == NULL, "no stub was called");
        if (failures && *text)
            fputs(text, stdout);
        free(text);

        printf("nibarchive popover checks=%d failures=%d\n", checks, failures);
        return failures != 0;
    }
}
