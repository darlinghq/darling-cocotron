#import "NSIBUserDefinedRuntimeAttributesConnector.h"
#import <AppKit/NSRaise.h>

@implementation NSIBUserDefinedRuntimeAttributesConnector

- (id) initWithCoder: (NSCoder *) decoder {
    _object = [[decoder decodeObjectForKey: @"NSObject"] retain];
    _keyPaths =
        [[[decoder decodeObjectForKey: @"NSKeyPaths"] mutableCopy] retain];
    _values = [[[decoder decodeObjectForKey: @"NSValues"] mutableCopy] retain];
    return self;
}

- (void) encodeWithCoder: (NSCoder *) coder {
    [coder encodeObject: _object forKey: @"NSObject"];
    [coder encodeObject: _keyPaths forKey: @"NSKeyPaths"];
    [coder encodeObject: _values forKey: @"NSValues"];
}

- (void) dealloc {
    [_object release];
    [_keyPaths release];
    [_values release];
    [super dealloc];
}

- (void) establishConnection {
    for (int i = 0; i < [_values count]; i++) {
        [_object setValue: _values[i] forKeyPath: _keyPaths[i]];
    }
}

- (void) replaceObject: (id) original withObject: (id) replacement {
    if (_object == original) {
        [self setObject: replacement];
    }
    for (int i = 0; i < [_values count]; i++) {
        if (_values[i] == original) {
            _values[i] = replacement;
        }
    }
}

- (void) setLabel: (NSString *) label {
    _keyPaths[0] = label;
}
- (NSString *) label {
    return _keyPaths[0];
}

- (void) setDestination: (id) destination {
    _values[0] = destination;
}
- (id) destination {
    return _values[0];
}

- (void) setSource: (id) source {
    source = [source retain];
    [_object release];
    _object = source;
}
- (id) source {
    return _object;
}

- (void) setObject: (id) object {
    object = [object retain];
    [_object release];
    _object = object;
}
- (id) object {
    return _object;
}

- (void) setValues: (NSArray *) values {
    NSMutableArray *values2 = [[values mutableCopy] retain];
    [_values release];
    _values = values2;
}
- (NSArray *) values {
    return _values;
}

- (void) setKeyPaths: (NSArray *) paths {
    NSMutableArray *paths2 = [[paths mutableCopy] retain];
    [_keyPaths release];
    _keyPaths = paths2;
}
- (NSArray *) keyPaths {
    return _keyPaths;
}

@end
