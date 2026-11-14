#import <AppKit/AppKitExport.h>
#import <Foundation/Foundation.h>
#import <OpenGL/gl.h>

#import <AppKit/NSOpenGLContext.h>
#import <AppKit/NSOpenGLPixelBuffer.h>
#import <AppKit/NSOpenGLPixelFormat.h>
#import <AppKit/NSOpenGLView.h>

// Library-wide options, read and written with NSOpenGLGetOption and
// NSOpenGLSetOption.
typedef NS_ENUM(uint32_t, NSOpenGLGlobalOption) {
    NSOpenGLGOFormatCacheSize = 501,
    NSOpenGLGOClearFormatCache = 502,
    NSOpenGLGORetainRenderers = 503,
    NSOpenGLGOResetLibrary = 504,
    NSOpenGLGOUseBuildCache = 506
};

APPKIT_EXPORT void NSOpenGLSetOption(NSOpenGLGlobalOption option, GLint value);
APPKIT_EXPORT void NSOpenGLGetOption(NSOpenGLGlobalOption option,
                                     GLint *_Nonnull value);
APPKIT_EXPORT void NSOpenGLGetVersion(GLint *_Nullable major,
                                      GLint *_Nullable minor);
