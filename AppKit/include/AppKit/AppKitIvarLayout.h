/*
 This file is part of Darling.

 Copyright (C) 2026 Lubos Dolezel

 Darling is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Darling is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with Darling.  If not, see <http://www.gnu.org/licenses/>.
*/

// Instance layout of AppKit classes on the legacy (fragile) Objective-C ABI.
//
// On the legacy ABI (i386, ppc: !__OBJC2__) an application's subclass of an
// AppKit class is compiled against Apple's instance layout: its own ivars sit
// at offsets fixed at compile time, right after Apple's instance size, and
// code in the subclass may read Apple's @protected ivars at their offsets.
// So on that ABI each affected class declares exactly Apple's footprint:
//   - ivars that Apple declared and that we keep, at Apple's offsets;
//   - NS_LEGACY_IVAR_PAD() where Apple has state we don't keep;
//   - all other state in an "extra ivars" struct, reached through a single
//     pointer ivar (NS_EXTRA_IVARS_END) allocated on first use and freed in
//     -dealloc, or, for a class whose Apple footprint has no room left for a
//     pointer, kept in storage associated with the object (NS_SIDE_IVARS_END).
// On the non-fragile ABI (x86_64, arm64) every macro here expands to plain
// ivars and plain ivar accesses: no indirection and no extra allocation.
//
// Declaring (inside the class's ivar block, always last in it):
//     NS_EXTRA_IVARS_BEGIN(NSView)
//         NSMenu *_menu;
//     NS_EXTRA_IVARS_END(NSView)        // or NS_SIDE_IVARS_END(NSView)
// Accessing, the same in source on both ABIs:
//     NS_EXTRA(NSView, self)->_menu, NS_EXTRA(NSView, otherView)->_menu
// NS_EXTRA_ALLOCATED(NSView, self) tells whether the extras exist yet, so
// -dealloc can skip releasing fields of a never-used struct.
// Lifetime: NS_EXTRA_FREE(NSView, self) right before [super dealloc], or
// NS_EXTRA_DEALLOC(NSView) in a class without -dealloc;
// NS_EXTRA_COPY(NSView, copy, self) right after NSCopyObject() or
// [super copyWithZone:], before the copy's extras are touched.
// @synthesize of an extra: NS_EXTRA_SYNTHESIZE_ASSIGN/RETAIN/COPY.
//
// Never add an ivar outside the extra struct to such a class: the class
// comment states the instance size the legacy ABI requires.

#ifndef APPKIT_IVAR_LAYOUT_H
#define APPKIT_IVAR_LAYOUT_H

#if !__OBJC2__

#import <Foundation/NSData.h>
#import <objc/runtime.h>
#include <stdlib.h>
#include <string.h>

#define NS_LEGACY_IVAR_PAD(name, bytes) unsigned char name[bytes];

// BEGIN switches to @public, so the extras must close the ivar block
#define NS_EXTRA_IVARS_BEGIN(cls)                                              \
  @public                                                                      \
    struct cls##ExtraIvars {
#define NS_EXTRA_IVARS_END(cls)                                                \
    }                                                                          \
    *_##cls##Extra;
#define NS_SIDE_IVARS_END(cls)                                                 \
    }                                                                          \
    _##cls##Extra[0];

// The accessors are only used by AppKit's own (manual reference counting)
// sources; ARC code that includes the AppKit headers needs only the
// declaration macros above.
#if !__has_feature(objc_arc)
static inline void *_NSExtraIvarsPointer(void **slot, size_t size) {
    if (__builtin_expect(*slot == NULL, 0))
        *slot = calloc(1, size);
    return *slot;
}

static inline void *_NSExtraIvarsSide(id object, SEL key, size_t size) {
    NSMutableData *storage = objc_getAssociatedObject(object, (const void *) key);
    if (storage == nil) {
        storage = [[NSMutableData alloc] initWithLength: size];
        objc_setAssociatedObject(object, (const void *) key, storage,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [storage release];
    }
    return [storage mutableBytes];
}

static inline BOOL _NSExtraIvarsSideExists(id object, SEL key) {
    return objc_getAssociatedObject(object, (const void *) key) != nil;
}

static inline void _NSExtraIvarsUnshare(void **slot, size_t size) {
    void *shared = *slot;
    *slot = NULL;
    if (shared != NULL) {
        *slot = malloc(size);
        memcpy(*slot, shared, size);
    }
}

#endif

#define _NS_EXTRA_IS_SIDE(cls) (sizeof(((cls *) 0)->_##cls##Extra) == 0)
#define _NS_EXTRA_SLOT(cls, obj) ((void **) &((cls *) (obj))->_##cls##Extra)
#define _NS_EXTRA_KEY(cls) @selector(cls##ExtraIvars)

#define NS_EXTRA(cls, obj)                                                     \
    ((struct cls##ExtraIvars *) __builtin_choose_expr(                         \
            _NS_EXTRA_IS_SIDE(cls),                                            \
            _NSExtraIvarsSide((id) (obj), _NS_EXTRA_KEY(cls),                  \
                              sizeof(struct cls##ExtraIvars)),                 \
            _NSExtraIvarsPointer(_NS_EXTRA_SLOT(cls, obj),                     \
                                 sizeof(struct cls##ExtraIvars))))

// whether the extras were ever touched (for -dealloc: don't create them there)
#define NS_EXTRA_ALLOCATED(cls, obj)                                           \
    (_NS_EXTRA_IS_SIDE(cls)                                                    \
             ? _NSExtraIvarsSideExists((id) (obj), _NS_EXTRA_KEY(cls))       \
             : *_NS_EXTRA_SLOT(cls, obj) != NULL)

// side storage goes away with the object's associations
#define NS_EXTRA_FREE(cls, obj)                                                \
    do {                                                                       \
        if (!_NS_EXTRA_IS_SIDE(cls)) {                                         \
            free(*_NS_EXTRA_SLOT(cls, obj));                                   \
            *_NS_EXTRA_SLOT(cls, obj) = NULL;                                  \
        }                                                                      \
    } while (0)

// NSCopyObject() copies the pointer (shared block) but not the side storage
#define NS_EXTRA_COPY(cls, dst, src)                                           \
    do {                                                                       \
        if (_NS_EXTRA_IS_SIDE(cls))                                            \
            memcpy(NS_EXTRA(cls, dst), NS_EXTRA(cls, src),                     \
                   sizeof(struct cls##ExtraIvars));                            \
        else                                                                   \
            _NSExtraIvarsUnshare(_NS_EXTRA_SLOT(cls, dst),                     \
                                 sizeof(struct cls##ExtraIvars));              \
    } while (0)

// for a class without a -dealloc of its own
#define NS_EXTRA_DEALLOC(cls)                                                  \
    -(void) dealloc {                                                          \
        NS_EXTRA_FREE(cls, self);                                              \
        [super dealloc];                                                       \
    }

// @synthesize can't name a field of the extra struct: plain (nonatomic)
// accessors instead. setter is written with its colon, e.g. setTag:
#define NS_EXTRA_SYNTHESIZE_ASSIGN(cls, prop, ivar, type, getter, setter)      \
    -(type) getter {                                                           \
        return NS_EXTRA(cls, self)->ivar;                                      \
    }                                                                          \
    -(void) setter(type) value {                                               \
        NS_EXTRA(cls, self)->ivar = value;                                     \
    }
#define NS_EXTRA_SYNTHESIZE_RETAIN(cls, prop, ivar, type, getter, setter)      \
    -(type) getter {                                                           \
        return NS_EXTRA(cls, self)->ivar;                                      \
    }                                                                          \
    -(void) setter(type) value {                                               \
        [value retain];                                                        \
        [NS_EXTRA(cls, self)->ivar release];                                   \
        NS_EXTRA(cls, self)->ivar = value;                                     \
    }
#define NS_EXTRA_SYNTHESIZE_COPY(cls, prop, ivar, type, getter, setter)        \
    -(type) getter {                                                           \
        return NS_EXTRA(cls, self)->ivar;                                      \
    }                                                                          \
    -(void) setter(type) value {                                               \
        type copied = [value copy];                                            \
        [NS_EXTRA(cls, self)->ivar release];                                   \
        NS_EXTRA(cls, self)->ivar = copied;                                    \
    }

#else // non-fragile ABI: plain ivars

#define NS_LEGACY_IVAR_PAD(name, bytes)
#define NS_EXTRA_IVARS_BEGIN(cls)
#define NS_EXTRA_IVARS_END(cls)
#define NS_SIDE_IVARS_END(cls)
#define NS_EXTRA(cls, obj) ((cls *) (obj))
#define NS_EXTRA_FREE(cls, obj) do { } while (0)
#define NS_EXTRA_COPY(cls, dst, src) do { } while (0)
#define NS_EXTRA_DEALLOC(cls)
#define NS_EXTRA_ALLOCATED(cls, obj) 1
#define NS_EXTRA_SYNTHESIZE_ASSIGN(cls, prop, ivar, type, getter, setter)      \
    @synthesize prop = ivar;
#define NS_EXTRA_SYNTHESIZE_RETAIN(cls, prop, ivar, type, getter, setter)      \
    @synthesize prop = ivar;
#define NS_EXTRA_SYNTHESIZE_COPY(cls, prop, ivar, type, getter, setter)        \
    @synthesize prop = ivar;

#endif

#endif
