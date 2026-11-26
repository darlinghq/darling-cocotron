// Copyright (C) 2026 Lubos Dolezel
//
// Guest test: +[NSSpellChecker grammarCheckingEnabled], AppKit SPI that
// WebKit's text checker calls. Observed on macOS 26.7.3 (x86_64) with the
// same calls, in a process with no preferences set: it is a class method (not
// an instance method) and returns YES.
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#include <stdio.h>

@interface NSSpellChecker (GrammarCheckingSPI)
+ (BOOL)grammarCheckingEnabled;
@end

static int failures;

static void report(const char *name, BOOL ok)
{
    printf("%s: %s\n", ok ? "PASS" : "FAIL", name);
    if (!ok)
        failures++;
}

int main(void)
{
    @autoreleasepool {
        report("class method", class_getClassMethod([NSSpellChecker class], @selector(grammarCheckingEnabled)) != NULL);
        report("not an instance method", class_getInstanceMethod([NSSpellChecker class], @selector(grammarCheckingEnabled)) == NULL);
        report("enabled by default", [NSSpellChecker grammarCheckingEnabled]);
    }
    return failures != 0;
}
