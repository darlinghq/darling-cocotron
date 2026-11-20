// Copyright (C) 2026 Lubos Dolezel
//
// NSWorkspace type queries: -typeOfFile:error:, -localizedDescriptionForType:, -preferredFilenameExtensionForType:
// and -filenameExtension:isValidForType:. Values observed on macOS 26.7.3 (x86_64) and macOS 10.14.4, black-box,
// identical on both unless noted: typeOfFile gives the content type of the item (public.data without an extension,
// extension types case-insensitively, public.folder, com.apple.application-bundle for a *.app directory,
// public.symlink for a link even when it dangles, a dyn.* identifier for an unknown extension); a missing item
// gives nil and NSCocoaErrorDomain 260 (NSFileReadNoSuchFileError), an empty path gives 256; a NULL error is fine.
// The description of public.mp3 is "MP3 audio", of public.jpeg "JPEG image"; the preferred extension of public.mp3 is
// mp3, of public.audio nil; extensions are valid for a type they conform to (flac for public.audio) in any case, not
// for another type, not empty, not with a leading dot; nil arguments give nil/NO.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
// The domain is spelled out: a binary built against the Darling SDK binds NSCocoaErrorDomain to a library macOS lacks it in.

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)
#define CHECK_STR(got, want) do { NSString *g_ = (got); NSString *w_ = (want); \
    if (!(g_ == w_ || [g_ isEqualToString: w_])) { fprintf(stderr, "FAIL line %d: %s = %s, want %s\n", __LINE__, #got, \
        g_ ? [g_ UTF8String] : "(nil)", w_ ? [w_ UTF8String] : "(nil)"); failures++; } } while (0)

int main(void) {
    @autoreleasepool {
        NSWorkspace *ws = [NSWorkspace sharedWorkspace];
        NSFileManager *fm = [NSFileManager defaultManager];
        char tmpl[] = "/tmp/wsfiletype.XXXXXX";
        if (mkdtemp(tmpl) == NULL)
            return 2;
        NSString *dir = [fm stringWithFileSystemRepresentation: tmpl length: strlen(tmpl)];
        NSData *data = [NSData dataWithBytes: "abcd" length: 4];
        NSString *(^path)(NSString *) = ^(NSString *name) { return [dir stringByAppendingPathComponent: name]; };
        [fm createFileAtPath: path(@"noext") contents: data attributes: nil];
        [fm createFileAtPath: path(@"a.TXT") contents: data attributes: nil];
        [fm createFileAtPath: path(@"UP.MP3") contents: data attributes: nil];
        [fm createFileAtPath: path(@"x.zzqqunknown") contents: data attributes: nil];
        [fm createDirectoryAtPath: path(@"folder") withIntermediateDirectories: YES attributes: nil error: NULL];
        [fm createDirectoryAtPath: path(@"thing.app") withIntermediateDirectories: YES attributes: nil error: NULL];
        [fm createSymbolicLinkAtPath: path(@"lnk.mp3") withDestinationPath: path(@"missing.mp3") error: NULL];

        NSError *error = nil;
        CHECK_STR([ws typeOfFile: path(@"UP.MP3") error: &error], @"public.mp3");
        CHECK(error == nil);
        CHECK_STR([ws typeOfFile: path(@"noext") error: NULL], @"public.data");
        CHECK_STR([ws typeOfFile: path(@"a.TXT") error: NULL], @"public.plain-text");
        CHECK_STR([ws typeOfFile: path(@"folder") error: NULL], @"public.folder");
        CHECK_STR([ws typeOfFile: path(@"thing.app") error: NULL], @"com.apple.application-bundle");
        CHECK_STR([ws typeOfFile: path(@"lnk.mp3") error: NULL], @"public.symlink");
        NSString *unknown = [ws typeOfFile: path(@"x.zzqqunknown") error: NULL];
        CHECK([unknown hasPrefix: @"dyn."]);
        CHECK_STR([ws typeOfFile: dir error: NULL], @"public.folder");

        error = nil;
        CHECK_STR([ws typeOfFile: path(@"missing.mp3") error: &error], nil);
        CHECK([[error domain] isEqualToString: @"NSCocoaErrorDomain"]);
        CHECK([error code] == 260);
        error = nil;
        CHECK_STR([ws typeOfFile: @"" error: &error], nil);
        CHECK([[error domain] isEqualToString: @"NSCocoaErrorDomain"]);
        CHECK([error code] == 256);
        CHECK_STR([ws typeOfFile: path(@"missing.mp3") error: NULL], nil);

        CHECK_STR([ws localizedDescriptionForType: @"public.mp3"], @"MP3 audio");
        CHECK_STR([ws localizedDescriptionForType: @"public.jpeg"], @"JPEG image");
        CHECK_STR([ws localizedDescriptionForType: @"com.example.nope"], nil);
        CHECK_STR([ws localizedDescriptionForType: @""], nil);
        CHECK_STR([ws preferredFilenameExtensionForType: @"public.mp3"], @"mp3");
        CHECK_STR([ws preferredFilenameExtensionForType: @"public.jpeg"], @"jpeg");
        CHECK_STR([ws preferredFilenameExtensionForType: @"public.plain-text"], @"txt");
        CHECK_STR([ws preferredFilenameExtensionForType: @"com.apple.application-bundle"], @"app");
        CHECK_STR([ws preferredFilenameExtensionForType: @"public.audio"], nil);
        CHECK_STR([ws preferredFilenameExtensionForType: @"public.folder"], nil);
        CHECK_STR([ws preferredFilenameExtensionForType: @"mp3"], nil);
        CHECK_STR([ws preferredFilenameExtensionForType: @"com.example.nope"], nil);

        CHECK([ws filenameExtension: @"mp3" isValidForType: @"public.mp3"]);
        CHECK([ws filenameExtension: @"MP3" isValidForType: @"public.mp3"]);
        CHECK([ws filenameExtension: @"mp3" isValidForType: @"public.audio"]);
        CHECK([ws filenameExtension: @"jpg" isValidForType: @"public.jpeg"]);
        CHECK([ws filenameExtension: @"jpeg" isValidForType: @"public.image"]);
        CHECK([ws filenameExtension: @"txt" isValidForType: @"public.data"]);
        CHECK(![ws filenameExtension: @"mp3" isValidForType: @"public.jpeg"]);
        CHECK(![ws filenameExtension: @"" isValidForType: @"public.mp3"]);
        CHECK(![ws filenameExtension: @".mp3" isValidForType: @"public.mp3"]);
        CHECK(![ws filenameExtension: @"mp3" isValidForType: @"com.example.nope"]);
        CHECK(![ws filenameExtension: @"zzqqunknown" isValidForType: @"public.data"]);

        for (NSString *name in [fm contentsOfDirectoryAtPath: dir error: NULL])
            [fm removeItemAtPath: path(name) error: NULL];
        rmdir(tmpl);
    }
    if (failures == 0)
        printf("PASS\n");
    return failures != 0;
}
