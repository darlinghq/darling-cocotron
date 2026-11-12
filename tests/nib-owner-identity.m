// Compile as an AppKit executable. Include the implementation under a distinct
// class name so this tests this checkout rather than an installed AppKit copy.
#import <AppKit/AppKit.h>
#define NSIBObjectData OwnerIdentityObjectData
#define IBCocoaFramework OwnerIdentityCocoaFramework
#include "../AppKit/nib.subproj/NSIBObjectData.m"
#include <stdio.h>

static int created;
@interface IdentityOwner : NSObject { id _delegate; }
@property(assign) id delegate;
@end
@implementation IdentityOwner
@synthesize delegate=_delegate;
@end
@interface IdentityChild : NSObject @end
@implementation IdentityChild
- (id)init { if ((self=[super init])) created++; return self; }
@end
@interface IdentityDecoder : NSKeyedUnarchiver {
@public NSDictionary *values; NSDictionary *external;
}
@end
@implementation IdentityDecoder
- (BOOL)allowsKeyedCoding { return YES; }
- (id)delegate { return self; }
- (NSDictionary *)externalNameTable { return external; }
- (id)decodeObjectForKey:(NSString *)key { return [values objectForKey:key]; }
- (int64_t)decodeInt64ForKey:(NSString *)key { return 1; }
- (void)replaceObject:(id)object withObject:(id)replacement {
    // Accept replacement without rewriting previously decoded references.
}
@end

int main(void) {
    @autoreleasepool {
        for (int parentIsOwner=0; parentIsOwner<2; parentIsOwner++) {
            created=0;
            IdentityOwner *owner=[IdentityOwner new];
            NSCustomObject *placeholder=[NSCustomObject new];
            placeholder.className=@"NSObject";
            NSCustomObject *child=[NSCustomObject new];
            child.className=@"IdentityChild";
            NSNibOutletConnector *connection=[NSNibOutletConnector new];
            [connection setSource:placeholder];
            [connection setDestination:child];
            [connection setLabel:@"delegate"];
            // No data initializer: every decode operation is controlled here.
            IdentityDecoder *decoder=[IdentityDecoder alloc];
            decoder->external=@{NSNibOwner:owner};
            decoder->values=@{@"NSRoot":placeholder,
                @"NSConnections":@[connection], @"NSObjectsKeys":@[child],
                @"NSObjectsValues":@[parentIsOwner ? owner : placeholder],
                @"NSVisibleWindows":[NSSet set]};
            NSIBObjectData *data=[[NSIBObjectData alloc] initWithCoder:decoder];
            [data buildConnectionsWithNameTable:decoder->external];
            NSArray *top=[data topLevelObjects];
            BOOL pass=created==1 && top.count==1 &&
                [[top objectAtIndex:0] isKindOfClass:[IdentityChild class]] &&
                owner.delegate==[top objectAtIndex:0];
            printf("parentIsOwner=%d created=%d top=%lu pass=%d\n",
                parentIsOwner,created,(unsigned long)top.count,pass);
            if (!pass) return 1;
        }
        puts("owner identity PASS");
    }
    return 0;
}
