/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// A process that runs an NSApplication takes the words on its command line that are not switches for
// documents to open (observed on macOS, see appkit-argument-documents.m): each word is offered to the
// application delegate, and when the delegate does not implement -application:openFiles: the document
// controller tries to open it and presents an error for a word that is no file ("wayland", "60").
// The fixtures that take their mode or duration as plain words call TestIgnoreArgumentWords() after they
// set their delegate and before they start the application: it gives the delegate (or a delegate of its
// own when there is none) an -application:openFiles: that does nothing, which is how a macOS program
// that does not open files keeps its words to itself.
#import <AppKit/AppKit.h>
#import <objc/runtime.h>

static void testIgnoreOpenFiles(id self, SEL _cmd, NSApplication *application, NSArray *files) {
}

@interface TestArgumentWordsDelegate : NSObject <NSApplicationDelegate>
@end
@implementation TestArgumentWordsDelegate
@end

static void TestIgnoreArgumentWords(void) {
    static id fallback;
    id delegate = [NSApp delegate];
    if (delegate == nil) {
        fallback = [TestArgumentWordsDelegate new];
        [NSApp setDelegate: fallback];
        delegate = fallback;
    }
    SEL selector = @selector(application:openFiles:);
    if (![delegate respondsToSelector: selector])
        class_addMethod([delegate class], selector, (IMP) testIgnoreOpenFiles, "v@:@@");
}
