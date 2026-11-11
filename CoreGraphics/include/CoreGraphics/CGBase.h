#ifndef __CGBase_H__
#define __CGBase_H__

// As in the macOS SDK, CoreFoundation owns CGFloat and the geometry structs.
#include <CoreFoundation/CFCGTypes.h>

#if CGFLOAT_IS_DOUBLE
#define CGFLOAT_SCAN "%lg"
#else
#define CGFLOAT_SCAN "%g"
#endif


#endif
