/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
#import <AppKit/NSOpenGL.h>

// The library options are plain process-wide settings: NSOpenGLSetOption
// records a value and NSOpenGLGetOption returns the last value set for the
// option, or zero if it was never set. Darling's OpenGL does not keep a pixel
// format cache or a renderer list, so no value changes any behaviour. A value
// for an option that is not declared in NSOpenGL.h is stored the same way.
static NSLock *optionLock;
static NSMutableDictionary *optionValues;

static void initOptions(void) {
    static dispatch_once_t once;

    dispatch_once(&once, ^{
      optionLock = [[NSLock alloc] init];
      optionValues = [[NSMutableDictionary alloc] init];
    });
}

void NSOpenGLSetOption(NSOpenGLGlobalOption option, GLint value) {
    initOptions();
    [optionLock lock];
    [optionValues setObject: [NSNumber numberWithInt: value]
                     forKey: [NSNumber numberWithUnsignedInt: option]];
    [optionLock unlock];
}

void NSOpenGLGetOption(NSOpenGLGlobalOption option, GLint *value) {
    initOptions();
    [optionLock lock];
    NSNumber *stored =
            [optionValues objectForKey: [NSNumber numberWithUnsignedInt: option]];
    *value = stored != nil ? [stored intValue] : 0;
    [optionLock unlock];
}

// The version of the NSOpenGL library itself is not something Darling can
// report: it reports zero for both parts, so that callers see "unknown" and
// not a version it does not provide.
void NSOpenGLGetVersion(GLint *major, GLint *minor) {
    if (major != NULL)
        *major = 0;
    if (minor != NULL)
        *minor = 0;
}
