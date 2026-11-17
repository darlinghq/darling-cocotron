#import <AppKit/AppKit.h>
#include <stdlib.h>

static void expect(BOOL condition, NSString *message)
{
    if (!condition)
    {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

static NSString *raisedName(void (^block)(void))
{
    @try {
        block();
    } @catch (NSException *exception) {
        return [exception name];
    }
    return nil;
}

// A storyboard with one scene whose nib file is missing: instantiating it raises NSInternalInconsistencyException
// after the identifier is found, which tells the plain path from the rejection of a creator.
// GUESS (not in the public documentation, not observed): a nil creator is the plain method; a creator block raises
// NSInvalidArgumentException and is never called. The GUESS EXPECT messages are those.
int main(void)
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:
                                                     [NSString stringWithFormat:@"storyboard-creator-%d", getpid()]];
    NSString *storyboardc = [directory stringByAppendingPathComponent:@"Fixture.storyboardc"];
    [[NSFileManager defaultManager] createDirectoryAtPath:storyboardc withIntermediateDirectories:YES attributes:nil error:NULL];
    NSDictionary *info = @{
        @"NSStoryboardDesignatedEntryPointIdentifier" : @"Scene",
        @"NSViewControllerIdentifiersToNibNames" : @{@"Scene" : @"MissingNib"},
    };
    expect([info writeToFile:[storyboardc stringByAppendingPathComponent:@"Info.plist"] atomically:YES], @"fixture written");

    NSStoryboard *storyboard = [NSStoryboard storyboardWithName:@"Fixture" bundle:[NSBundle bundleWithPath:directory]];
    expect(storyboard != nil, @"the fixture storyboard loads");

    expect([raisedName(^{ [storyboard instantiateControllerWithIdentifier:@"Scene"]; })
               isEqual:NSInternalInconsistencyException],
           @"the plain method finds the scene and fails on its missing nib");
    expect([raisedName(^{ [storyboard instantiateControllerWithIdentifier:@"Scene" creator:nil]; })
               isEqual:NSInternalInconsistencyException],
           @"GUESS: a nil creator is the plain method");
    expect([raisedName(^{ [storyboard instantiateControllerWithIdentifier:@"Other" creator:nil]; })
               isEqual:NSInvalidArgumentException],
           @"GUESS: a nil creator with an unknown identifier raises like the plain method");
    expect([raisedName(^{ [storyboard instantiateInitialControllerWithCreator:nil]; })
               isEqual:NSInternalInconsistencyException],
           @"GUESS: the initial controller with a nil creator is the plain method");

    __block int called = 0;
    NSStoryboardControllerCreator creator = ^id(NSCoder *coder) {
        called++;
        return nil;
    };
    expect([raisedName(^{ [storyboard instantiateControllerWithIdentifier:@"Scene" creator:creator]; })
               isEqual:NSInvalidArgumentException],
           @"GUESS: a creator block raises NSInvalidArgumentException");
    expect([raisedName(^{ [storyboard instantiateInitialControllerWithCreator:creator]; })
               isEqual:NSInvalidArgumentException],
           @"GUESS: a creator block on the initial controller raises NSInvalidArgumentException");
    expect(called == 0, @"GUESS: the creator block is never called");

    [[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
    [pool drain];
    printf("PASS: NSStoryboard creator variants\n");
    return 0;
}
