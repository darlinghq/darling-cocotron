#import "NSMenuTemplate.h"

@implementation NSMenuTemplate

- (void) dealloc {
    [_realObject release];
    [_menuClass release];
    [super dealloc];
}

- (void) setClassName: (NSString *) className {
    [className retain];
    [_menuClass release];
    _menuClass = className;
}

- (NSString *) className {
    return _menuClass;
}

- (void) setRealObject: (id) o {
    [o retain];
    [_realObject release];
    _realObject = o;
}

- (id) realObject {
    return _realObject;
}

@end
