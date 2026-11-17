/* Copyright (C) 2026 Lubos Dolezel */
// -[NSDocument setDisplayName:] (NSDocument.h): the name the document is given for presentation; nil goes back
// to the default name. Link with the candidate AppKit; no windows are needed.
// The last two groups pin a QUIRK (see NSDocument.m -setFileURL:): assigning a file URL drops the set name.
#import <AppKit/NSDocument.h>
#include <stdlib.h>

static void expect(BOOL condition, NSString *message) {
    if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}

// A subclass that does not itself declare the method must still inherit it from NSDocument.
@interface NamedDocument : NSDocument
@end
@implementation NamedDocument
@end

@interface NameObserver : NSObject {
@public
    int _changes;
}
@end
@implementation NameObserver
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
                        change:(NSDictionary *)change context:(void *)context {
    if ([keyPath isEqual:@"displayName"]) _changes++;
}
@end

int main(void) {
    @autoreleasepool {
        NamedDocument *document = [NamedDocument new];
        expect([document respondsToSelector:@selector(setDisplayName:)], @"NSDocument answers setDisplayName:");

        NSString *derived = [[document displayName] copy];
        expect([derived length] > 0, @"an unsaved document has a default display name");

        NameObserver *observer = [NameObserver new];
        [document addObserver:observer forKeyPath:@"displayName" options:0 context:NULL];

        NSMutableString *name = [NSMutableString stringWithString:@"System Report"];
        [document setDisplayName:name];
        expect([[document displayName] isEqualToString:@"System Report"], @"the display name is the one set");
        [name appendString:@" edited"];
        expect([[document displayName] isEqualToString:@"System Report"], @"the display name is a copy");
        expect([[document valueForKey:@"displayName"] isEqualToString:@"System Report"], @"displayName key reads it");
        expect(observer->_changes == 1, @"setDisplayName: notifies displayName observers");

        [document setValue:@"Second" forKey:@"displayName"];
        expect([[document displayName] isEqualToString:@"Second"], @"displayName key writes it");

        [document setDisplayName:nil];
        expect([[document displayName] length] > 0 && ![[document displayName] isEqualToString:@"Second"],
               @"nil goes back to the default name");
        [document removeObserver:observer forKeyPath:@"displayName"];
        [observer release];

        // A set name also shows for a document that already has a file.
        [document setFileURL:[NSURL fileURLWithPath:@"/tmp/appkit-display-name-a.txt"]];
        expect([[document displayName] isEqualToString:@"appkit-display-name-a.txt"], @"the file name is the derived name");
        [document setDisplayName:@"Override"];
        expect([[document displayName] isEqualToString:@"Override"], @"a set name wins over the file name");
        // QUIRK pinned: nil gives the Untitled default even though a file URL is set.
        [document setDisplayName:nil];
        expect([[document displayName] length] > 0 && ![[document displayName] isEqualToString:@"appkit-display-name-a.txt"] &&
                   ![[document displayName] isEqualToString:@"Override"],
               @"nil gives the default name, not the file name");
        [document setFileURL:[NSURL fileURLWithPath:@"/tmp/appkit-display-name-a.txt"]];
        expect([[document displayName] isEqualToString:@"appkit-display-name-a.txt"], @"assigning a file URL restores the file name");

        // QUIRK pinned: assigning a file URL discards the set name.
        [document setDisplayName:@"Override"];
        [document setFileURL:[NSURL fileURLWithPath:@"/tmp/appkit-display-name-b.txt"]];
        expect([[document displayName] isEqualToString:@"appkit-display-name-b.txt"], @"a new file URL drops the set name");

        NSDocument *unsaved = [NSDocument new];
        [unsaved setDisplayName:@"Override"];
        [unsaved setFileURL:nil];
        expect(![[unsaved displayName] isEqualToString:@"Override"], @"a nil file URL drops the set name");

        [unsaved release];
        [derived release];
        [document release];
    }
    printf("PASS: document display name\n");
    return 0;
}
