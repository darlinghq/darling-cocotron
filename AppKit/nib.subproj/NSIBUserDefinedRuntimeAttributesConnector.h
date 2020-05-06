#import <Foundation/Foundation.h>

@interface NSIBUserDefinedRuntimeAttributesConnector : NSObject <NSCoding> {
    id _object;
    NSMutableArray *_keyPaths;
    NSMutableArray *_values;
}

- (void) establishConnection;
- (void) replaceObject: (id) original withObject: (id) replacement;

- (void) setLabel: (NSString *) label;
- (NSString *) label;
- (void) setDestination: (id) destination;
- (id) destination;
- (void) setSource: (id) source;
- (id) source;

- (void) setObject: (id) object;
- (id) object;
- (void) setValues: (NSArray *) values;
- (NSArray *) values;
- (void) setKeyPaths: (NSArray *) paths;
- (NSArray *) keyPaths;

@end
