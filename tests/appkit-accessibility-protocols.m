// Copyright (C) 2026 Lubos Dolezel
//
// The documented accessibility role protocols and orientation type are available with their public values, so
// clients can declare conformance and switch on the orientation without redefining them.
// Build: clang -framework AppKit appkit-accessibility-protocols.m
#import <AppKit/AppKit.h>
#include <objc/runtime.h>
#include <stdio.h>

_Static_assert(NSAccessibilityOrientationUnknown == 0, "unexpected orientation value");
_Static_assert(NSAccessibilityOrientationVertical == 1, "unexpected orientation value");
_Static_assert(NSAccessibilityOrientationHorizontal == 2, "unexpected orientation value");

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

int main(void)
{
    Protocol *roles[] = {
        @protocol(NSAccessibilityButton),
        @protocol(NSAccessibilitySwitch),
        @protocol(NSAccessibilityRadioButton),
        @protocol(NSAccessibilityCheckBox),
        @protocol(NSAccessibilityStaticText),
        @protocol(NSAccessibilityNavigableStaticText),
        @protocol(NSAccessibilityProgressIndicator),
        @protocol(NSAccessibilityStepper),
        @protocol(NSAccessibilitySlider),
        @protocol(NSAccessibilityImage),
    };
    for (size_t i = 0; i < sizeof(roles) / sizeof(roles[0]); i++)
        CHECK(roles[i] != Nil);

    CHECK(protocol_conformsToProtocol(@protocol(NSAccessibilityNavigableStaticText),
                                      @protocol(NSAccessibilityStaticText)));

    if (failures == 0)
        printf("PASS: accessibility protocols and orientation\n");
    return failures ? 1 : 0;
}
