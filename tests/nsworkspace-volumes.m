// Copyright (C) 2026 Lubos Dolezel
// NSWorkspace's volume calls. Modes:
//  lists                 prints "local: <mountedLocalVolumePaths>" and "removable: <mountedRemovableMedia>", the
//                        paths separated by "|"
//  info <path>           prints "info <path>: <result> <removable> <writable> <unmountable> <description> <type>"
//                        from getFileSystemInfoForPath:...
//  eject <path>          prints "eject <path>: <result> <error domain> <error code> <userInfo count>" from
//                        unmountAndEjectDeviceAtURL:error: ("-" for no error)
//  eject-path <path>     prints "eject-path <path>: <result>" from unmountAndEjectDeviceAtPath:
// Link with -framework AppKit. Also builds on macOS; the values macOS gives are in darling's tests/volumes.md.
#import <AppKit/AppKit.h>

int main(int argc, char **argv)
{
    @autoreleasepool
    {
        NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
        NSString *mode = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : @"";
        NSString *path = argc > 2 ? [NSString stringWithUTF8String:argv[2]] : nil;

        if ([mode isEqual:@"lists"])
        {
            printf("local: %s\n", [[[workspace mountedLocalVolumePaths] componentsJoinedByString:@"|"] UTF8String]);
            printf("removable: %s\n", [[[workspace mountedRemovableMedia] componentsJoinedByString:@"|"] UTF8String]);
        }
        else if ([mode isEqual:@"info"] && path)
        {
            BOOL removable = NO, writable = NO, unmountable = NO;
            NSString *description = nil, *type = nil;
            BOOL result = [workspace getFileSystemInfoForPath:path isRemovable:&removable isWritable:&writable
                                                isUnmountable:&unmountable description:&description type:&type];
            printf("info %s: %d %d %d %d %s %s\n", argv[2], result, removable, writable, unmountable,
                [description ?: @"nil" UTF8String], [type ?: @"nil" UTF8String]);
        }
        else if ([mode isEqual:@"eject"] && path)
        {
            NSError *error = nil;
            BOOL result = [workspace unmountAndEjectDeviceAtURL:[NSURL fileURLWithPath:path] error:&error];
            printf("eject %s: %d %s %ld %lu\n", argv[2], result, error ? [error.domain UTF8String] : "-",
                (long)error.code, (unsigned long)error.userInfo.count);
        }
        else if ([mode isEqual:@"eject-path"] && path)
        {
            printf("eject-path %s: %d\n", argv[2], [workspace unmountAndEjectDeviceAtPath:path]);
        }
        else
        {
            fprintf(stderr, "usage: nsworkspace-volumes lists | info <path> | eject <path> | eject-path <path>\n");
            return 2;
        }
    }
    return 0;
}
