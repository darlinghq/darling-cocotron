/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// On the legacy (fragile) Objective-C ABI (i386) AppKit keeps part of some
// classes' state in an "extras" block created the first time it is needed:
// behind a pointer ivar (NSView) or in storage associated with the object
// (NSButton, whose Apple instance size leaves no room for a pointer). Two
// threads that touch the state of a fresh object at the same time must share
// one block: if each created its own, one thread's write would land in a block
// that is then dropped, or in storage that is already freed.
//
// For many freshly allocated objects (before any initializer could have
// created the extras), two threads are released together (a spin barrier
// per object) and each stores a different extras field of the same object;
// afterwards both values must be there. On the non-fragile ABI (x86_64) the
// fields are plain ivars and the test passes trivially.
//
// Build: clang -framework AppKit -framework Foundation -lpthread (i386 and
// x86_64). Exits non-zero on failure.
#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#include <pthread.h>
#include <stdio.h>

#define OBJECTS 20000

static NSMutableArray *views;
static NSMutableArray *buttons;
static NSMenu *sharedMenu;
static NSColor *sharedColor;
static int ready[2][OBJECTS];
static int lost;

typedef enum { WorkerFirst, WorkerSecond } Worker;

// both workers arrive at an object, then run its operation at the same moment
static void rendezvous(int kind, int index) {
    __atomic_add_fetch(&ready[kind][index], 1, __ATOMIC_ACQ_REL);
    while (__atomic_load_n(&ready[kind][index], __ATOMIC_ACQUIRE) < 2)
        ;
}

static void *worker(void *arg) {
    Worker which = (Worker) (intptr_t) arg;
    @autoreleasepool {
        for (int i = 0; i < OBJECTS; i++) {
            rendezvous(0, i);
            NSView *view = [views objectAtIndex: i];
            if (which == WorkerFirst)
                [view setHidden: YES];
            else
                [view setMenu: sharedMenu];
        }
        for (int i = 0; i < OBJECTS; i++) {
            rendezvous(1, i);
            NSButton *button = [buttons objectAtIndex: i];
            if (which == WorkerFirst)
                [button setHasDestructiveAction: YES];
            else
                [button setContentTintColor: sharedColor];
        }
    }
    return NULL;
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    @autoreleasepool {
        [NSApplication sharedApplication];
        sharedMenu = [[NSMenu alloc] initWithTitle: @"m"];
        sharedColor = [[NSColor blueColor] retain];
        views = [[NSMutableArray alloc] init];
        buttons = [[NSMutableArray alloc] init];
        for (int i = 0; i < OBJECTS; i++) {
            // only allocated: an initializer would already create the extras
            [views addObject: [NSView alloc]];
            [buttons addObject: [NSButton alloc]];
        }

        pthread_t threads[2];
        for (intptr_t i = 0; i < 2; i++)
            pthread_create(&threads[i], NULL, worker, (void *) i);
        for (int i = 0; i < 2; i++)
            pthread_join(threads[i], NULL);

        for (int i = 0; i < OBJECTS; i++) {
            NSView *view = [views objectAtIndex: i];
            if (![view isHidden] || [view menu] != sharedMenu)
                lost++;
            NSButton *button = [buttons objectAtIndex: i];
            if (![button hasDestructiveAction] || [button contentTintColor] != sharedColor)
                lost++;
        }
        if (lost != 0)
            printf("FAIL: %d objects lost a concurrent first write\n", lost);
        // the objects are never initialized, so they are not released either
    }
    if (lost == 0)
        printf("PASS\n");
    return lost != 0;
}
