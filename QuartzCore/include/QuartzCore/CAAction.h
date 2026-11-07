#import <Foundation/NSObject.h>

@class NSString, NSDictionary;

@protocol CAAction

// Runs the action found for event on anObject, normally a CALayer.
- (void) runActionForKey: (NSString *) event
                  object: (id) anObject
               arguments: (NSDictionary *) dict;

@end
