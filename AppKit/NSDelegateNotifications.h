/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Private helper for the documented delegate behavior: the delegate of a class that posts notifications is
// an observer, for each of its delegate methods named after one of the class's notifications, of that
// notification posted by the delegating object, and it stops being one when replaced or removed. A class's
// -setDelegate: lists its notifications once and calls these around the assignment.
#import <Foundation/NSNotification.h>
#import <objc/runtime.h>

typedef struct {
    NSNotificationName name;
    SEL selector;
} NSDelegateNotification;

// notes ends with an entry whose name is nil.
static inline void NSDelegateNotificationsRemove(id delegate, id sender, const NSDelegateNotification *notes) {
    if (delegate == nil)
        return;
    for (; notes->name != nil; notes++)
        [[NSNotificationCenter defaultCenter] removeObserver: delegate name: notes->name object: sender];
}

static inline void NSDelegateNotificationsAdd(id delegate, id sender, const NSDelegateNotification *notes) {
    if (delegate == nil)
        return;
    for (; notes->name != nil; notes++)
        if ([delegate respondsToSelector: notes->selector])
            [[NSNotificationCenter defaultCenter] addObserver: delegate
                                                     selector: notes->selector
                                                         name: notes->name
                                                       object: sender];
}
