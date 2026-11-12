// Link with candidate AppKit; no windows are needed.
#import <AppKit/NSDocument.h>
#include <stdlib.h>

static void expect(BOOL condition, NSString *message) {
    if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}

@interface DraftObserver : NSObject {
@public
    int _changes;
}
@end
@implementation DraftObserver
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
                        change:(NSDictionary *)change context:(void *)context {
    if ([keyPath isEqual:@"draft"]) _changes++;
}
@end

int main(void) {
    @autoreleasepool {
        NSDocument *document = [NSDocument new];
        expect(![document isDraft], @"new document is not a draft");

        // Apps observe their documents, so the receiver is often a KVO subclass.
        DraftObserver *observer = [DraftObserver new];
        [document addObserver:observer forKeyPath:@"draft" options:0 context:NULL];
        expect([document respondsToSelector:@selector(isDraft)], @"KVO subclass answers isDraft");

        [document setDraft:YES];
        expect([document isDraft], @"setDraft:YES round-trips");
        expect([[document valueForKey:@"draft"] boolValue], @"draft key resolves to isDraft");
        expect(observer->_changes == 1, @"setDraft: notifies draft observers");

        [document setValue:@NO forKey:@"draft"];
        expect(![document isDraft], @"draft key resolves to setDraft:");
        expect(observer->_changes == 2, @"KVC set notifies draft observers");

        [document removeObserver:observer forKeyPath:@"draft"];
        [observer release];
        [document release];
    }
    return 0;
}
