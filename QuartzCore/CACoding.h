// Keyed-archive helpers for the Core Graphics values layers hold. Encoders raise
// NSInvalidArchiveOperationException for values that cannot be archived faithfully;
// decoders raise NSInvalidUnarchiveOperationException for malformed data.
#import <Foundation/Foundation.h>
#import <ApplicationServices/ApplicationServices.h>
#import <QuartzCore/CATransform3D.h>

void CARequireKeyedCoder(NSCoder *coder);

void CAEncodeDoubles(NSCoder *coder, const double *values, size_t count, NSString *key);
void CADecodeDoubles(NSCoder *coder, double *values, size_t count, NSString *key);

void CAEncodePoint(NSCoder *coder, CGPoint point, NSString *key);
CGPoint CADecodePoint(NSCoder *coder, NSString *key);
void CAEncodeSize(NSCoder *coder, CGSize size, NSString *key);
CGSize CADecodeSize(NSCoder *coder, NSString *key);
void CAEncodeRect(NSCoder *coder, CGRect rect, NSString *key);
CGRect CADecodeRect(NSCoder *coder, NSString *key);
void CAEncodeTransform3D(NSCoder *coder, CATransform3D t, NSString *key);
CATransform3D CADecodeTransform3D(NSCoder *coder, NSString *key);

// NULL is archived as an absent key. The decoders return a +1 reference or NULL.
void CAEncodeColor(NSCoder *coder, CGColorRef color, NSString *key);
CGColorRef CADecodeColor(NSCoder *coder, NSString *key);
void CAEncodePath(NSCoder *coder, CGPathRef path, NSString *key);
CGPathRef CADecodePath(NSCoder *coder, NSString *key);
void CAEncodeImage(NSCoder *coder, CGImageRef image, NSString *key);
CGImageRef CADecodeImage(NSCoder *coder, NSString *key);
