/* CoreGraphics: the device-dependent modifier flag bits, shared by the window system backends' keyboards.

 Permission is hereby granted, free of charge, to any person obtaining a copy of
 this software and associated documentation files (the "Software"), to deal in
 the Software without restriction, including without limitation the rights to
 use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
 of the Software, and to permit persons to whom the Software is furnished to do
 so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE. */

#ifndef CGS_MODIFIER_KEYS_H
#define CGS_MODIFIER_KEYS_H

#include <stdint.h>
#include "CarbonKeys.h"

// The device-dependent bits of the modifier flags (IOKit's IOLLEvent.h) that say which key of a pair is
// down, for the virtual key code of a modifier key. The flags that apply to the keyboard as a whole come
// from the window system's modifier state, not from these.
static inline uint64_t CGSModifierDeviceMask(int code) {
    switch (code) {
    case kVK_Control: return 0x0001;
    case kVK_Shift: return 0x0002;
    case kVK_RightShift: return 0x0004;
    case kVK_Command: return 0x0008;
    case 0x36: return 0x0010; // The right Command key.
    case kVK_Option: return 0x0020;
    case kVK_RightOption: return 0x0040;
    case kVK_RightControl: return 0x2000;
    default: return 0;
    }
}

#endif
