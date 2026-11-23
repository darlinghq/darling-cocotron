// Copyright (C) 2026 Lubos Dolezel
// nsworkspace-recycle <dir>: -[NSWorkspace recycleURLs:completionHandler:] with files made in <dir>:
//  - a file and a missing one: newURLs has the file only; the error has the missing one's code (4), a description
//    and the list of failures under "NSUnderlyingErrors" (macOS 26's key; a quirk, see MacWorkspace.m); the handler
//    runs on the main thread;
//  - a file alone: no error, and the file is in the trash;
//  - a file with a nil handler: it is trashed within 5 s.
// Prints "FAIL: ..." for each check that does not hold and exits 1 if any did; removes what it trashed. Prints the
// error's userInfo keys as "keys: ...". Link with -framework AppKit. Also passes on macOS; the behaviour is in
// darling's tests/volumes.md.
#import <AppKit/AppKit.h>

static int failures;

static void expect(BOOL ok, NSString *what)
{
    if (!ok)
    {
        printf("FAIL: %s\n", [what UTF8String]);
        failures++;
    }
}

static NSURL *makeFile(NSString *dir, NSString *name)
{
    NSString *path = [dir stringByAppendingPathComponent:name];
    [@"x" writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:NULL];
    return [NSURL fileURLWithPath:path];
}

// runs the main run loop until the handler has run, for at most 10 s
static void recycle(NSArray *urls, NSDictionary **outNew, NSError **outError, BOOL *outMain)
{
    __block BOOL done = NO;
    [[NSWorkspace sharedWorkspace] recycleURLs:urls completionHandler:^(NSDictionary *newURLs, NSError *error) {
        *outNew = [newURLs retain];
        *outError = [error retain];
        *outMain = [NSThread isMainThread];
        done = YES;
    }];
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:10];
    while (!done && [limit timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    expect(done, @"the handler did not run");
}

int main(int argc, char **argv)
{
    if (argc != 2)
    {
        fprintf(stderr, "usage: nsworkspace-recycle <dir>\n");
        return 2;
    }
    @autoreleasepool
    {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *dir = [NSString stringWithUTF8String:argv[1]];
        NSDictionary *newURLs = nil;
        NSError *error = nil;
        BOOL onMain = NO;

        NSURL *file = makeFile(dir, @"recycle-one.txt");
        NSURL *missing = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"recycle-missing.txt"]];
        recycle(@[ file, missing ], &newURLs, &error, &onMain);
        printf("keys: %s\n", [[[error.userInfo.allKeys sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@" "] UTF8String]);
        expect(onMain, @"the handler did not run on the main thread");
        expect(newURLs.count == 1 && newURLs[file] != nil, [NSString stringWithFormat:@"newURLs is %@", newURLs]);
        expect([error.domain isEqual:NSCocoaErrorDomain] && error.code == NSFileNoSuchFileError,
            [NSString stringWithFormat:@"the error is %@", error]);
        expect([error.localizedDescription length] > 0, @"the error has no description");
        NSArray *underlying = error.userInfo[@"NSUnderlyingErrors"];
        expect([underlying isKindOfClass:[NSArray class]] && underlying.count == 1,
            [NSString stringWithFormat:@"the underlying errors are %@", underlying]);
        if (newURLs[file])
            [fm removeItemAtURL:newURLs[file] error:NULL];
        [newURLs release];
        [error release];

        file = makeFile(dir, @"recycle-two.txt");
        recycle(@[ file ], &newURLs, &error, &onMain);
        NSURL *moved = newURLs[file];
        expect(error == nil, [NSString stringWithFormat:@"recycling one file gives %@", error]);
        expect(moved != nil && [fm fileExistsAtPath:moved.path] && ![fm fileExistsAtPath:file.path],
            [NSString stringWithFormat:@"the file moved to %@", moved]);
        if (moved)
            [fm removeItemAtURL:moved error:NULL];
        [newURLs release];
        [error release];

        file = makeFile(dir, @"recycle-three.txt");
        [[NSWorkspace sharedWorkspace] recycleURLs:@[ file ] completionHandler:nil];
        NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:5];
        while ([fm fileExistsAtPath:file.path] && [limit timeIntervalSinceNow] > 0)
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        expect(![fm fileExistsAtPath:file.path], @"with a nil handler the file was not trashed");
        NSURL *trash = [fm URLForDirectory:NSTrashDirectory inDomain:NSUserDomainMask appropriateForURL:[NSURL fileURLWithPath:dir] create:NO error:NULL];
        [fm removeItemAtURL:[trash URLByAppendingPathComponent:@"recycle-three.txt"] error:NULL];
    }
    if (failures)
        return 1;
    printf("PASS\n");
    return 0;
}
