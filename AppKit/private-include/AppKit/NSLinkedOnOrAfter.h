// Copyright (C) 2026 Lubos Dolezel
//
// Checks of the SDK a program was built with. Where AppKit behaves differently for programs built
// against an older SDK, it asks this header instead of looking at the Mach-O image itself: the
// answer comes from dyld, which reads the version recorded by the linker (and, for a program
// without a version load command, derives it from the libSystem version it linked against).
#import <Foundation/NSObjCRuntime.h>
#include <mach-o/dyld_priv.h>
#include <stdint.h>

// Packed macOS release numbers, as dyld_get_program_sdk_version() returns them.
#define NS_SDK_VERSION_MACOSX_10_6 0x000a0600

// YES when the main program was built against an SDK of at least the given version. A program
// that records no SDK version at all, as programs built for 10.5 and earlier do, was built
// against an older SDK than any version asked about here.
static inline BOOL NSProgramLinkedOnOrAfterSDK(uint32_t packedVersion) {
    uint32_t sdk = dyld_get_program_sdk_version();

    return sdk != 0 && sdk >= packedVersion;
}
