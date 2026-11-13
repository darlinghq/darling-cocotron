#ifndef __CGBase_H__
#define __CGBase_H__

// As in the macOS SDK, CoreFoundation owns CGFloat and the geometry structs.
#include <CoreFoundation/CFCGTypes.h>

#if CGFLOAT_IS_DOUBLE
#define CGFLOAT_SCAN "%lg"
#else
#define CGFLOAT_SCAN "%g"
#endif


// Headers written against a recent macOS SDK annotate CoreGraphics pointer parameters with
// cg_nullable. Without it they do not parse. The qualifier goes after the '*'
// (float * cg_nullable p); before it, clang rejects it as applying to the pointee.
#if __has_feature(nullability)
#define cg_nullable __nullable
#else
#define cg_nullable
#endif

#endif
