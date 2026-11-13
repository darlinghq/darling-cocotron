// Copyright (C) 2026 Lubos Dolezel
//
// Decodes keyed archives of layers that were written by macOS 26.7.3 (archives
// of a CALayer with a sublayer and mask, a CAShapeLayer with a path and a
// CATextLayer, made with requiringSecureCoding), then checks that a default
// layer archived here has the layout macOS writes: the four default keys, the
// __CACodingContents list and the proxy classes. The archives hold only
// geometry, strings and constraints; they were produced by the probes
// vd-upstream/mac-probes/v316-calayer-archive.m (layer-set, shape-set, text-set)
// and v316-calayer-archive-more.m (constraints).
#import <QuartzCore/QuartzCore.h>
#include <stdio.h>

static int failures;
#define CHECK(cond, ...) do { if (!(cond)) { failures++; fprintf(stderr, "FAIL line %d: ", __LINE__); fprintf(stderr, __VA_ARGS__); fputc('\n', stderr); } } while (0)

static NSString *const layer_set =
    @"YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEI"
    "CVRyb290gAGvEDsLDENETFNZXV5lZmdoaWp0dSYdfn8agIOGh4iMkJGSlpqkpa2wtMchFSQTHhYQGxgSGSUfDyciDiAcEVUkbnVs"
    "bN8QGw0ODxAREhMUFRYXGBkaGxwdHh8gISIjJCUmJygpKisrLS4vMDEyLTQ1NjctOTo7PD0+MC0tQl5jb250ZW50c0Zvcm1hdFxz"
    "aGFkb3dSYWRpdXNYcG9zaXRpb25dY29udGVudHNTY2FsZVl6UG9zaXRpb25WaGlkZGVuW2JvcmRlcldpZHRoViRjbGFzc18QD2Jh"
    "Y2tncm91bmRDb2xvcl8QD2NvbnRlbnRzR3Jhdml0eVtjb3JuZXJDdXJ2ZV8QD2dlb21ldHJ5RmxpcHBlZFRtYXNrVG5hbWVcY29y"
    "bmVyUmFkaXVzWXRyYW5zZm9ybV8QEmFsbG93c0dyb3VwT3BhY2l0eVZib3VuZHNXb3BhY2l0eVlzdWJsYXllcnNbYW5jaG9yUG9p"
    "bnRdc2hhZG93T3BhY2l0eV8QEl9fQ0FDb2RpbmdDb250ZW50c1tib3JkZXJDb2xvcl1tYXNrc1RvQm91bmRzXxAWYWxsb3dzRWRn"
    "ZUFudGlhbGlhc2luZ1xzaGFkb3dPZmZzZXSACYAdgBqAC4ALgAKAB4AXgAWACoAMgAKADoAYgA2AJYACgAiAGYAegAOAHIAmgAWA"
    "AoACgBsQAdRFRkcUSElKS1F5VGtpbmRReCI/gAAAEAAiAAAAAIAE0k1OT1BaJGNsYXNzbmFtZVgkY2xhc3Nlc18QFExLTlNWYWx1"
    "ZUNvZGluZ1Byb3h5o09RUl1DQUNvZGluZ1Byb3h5WE5TT2JqZWN01VRVVlcUSEpKSFhRclFiUWdRYYAG0k1OWltfEBRMS0NHQ29s"
    "b3JDb2RpbmdQcm94eaNaXFJdQ0FDb2RpbmdQcm94eSM/8AAAAAAAANZFFEZHX2BKS2JKY2RVd2lkdGhWaGVpZ2h0gAQQAiJBIAAA"
    "IkGgAABVUkdCQThWY2VudGVyI0AAAAAAAAAAWGNpcmN1bGFyI0AIAAAAAAAA1xRrJiNsHRovMi1wKC1zW2Nvcm5lckN1cnZlXmNv"
    "bnRlbnRzRm9ybWF0gBeADIACgBCACYACgA9UbWFza9J2FHd9Wk5TLm9iamVjdHOleHl6e3yAEYASgBOAFIAVgBZeY29udGVudHNG"
    "b3JtYXRbY29ybmVyQ3VydmXSTU6BgldOU0FycmF5ooFS0k1OhIVXQ0FMYXllcqKEUlRyb290Ij8AAADURUZHFIlJiksiQMAAACJA"
    "oAAAgATURl9gFI1IjksQASJAAAAAgAQiPzMzMyNAEAAAAAAAANKTFJSVVWFycmF5gB+AJNJ2FJeZoZiAIIAj1xSbJiOcHRovMi2g"
    "KC2jW2Nvcm5lckN1cnZlXmNvbnRlbnRzRm9ybWF0gBeADIACgCKACYACgCFVY2hpbGTSdhSmfaV4eXp7fIARgBKAE4AUgBWAFtJN"
    "Tq6vXk5TTXV0YWJsZUFycmF5o66BUtJNTrGyXxAUTEtOU0FycmF5Q29kaW5nUHJveHmjsbNSXUNBQ29kaW5nUHJveHnfEBK1tre4"
    "ubq7vBS9vr/AwUbCw8RKSkpKSEiOjktKSkpKSsZKSkpTbTIxU200MVNtMjRTbTEzU200NFNtMzNTbTIyU20xMVNtNDJTbTMxU20x"
    "NFNtMzRTbTIzU20xMlNtNDNTbTMygAQQA9J2FMh9rxAZeHnLzM3Oz3rR0nvU1dbX2Hza29zd3t/g4YARgBKAJ4AogCmAKoArgBOA"
    "LIAtgBSALoAvgDCAMYAygBWAM4A0gDWANoA3gDiAOYA6gBYACAARABoAJAApADIANwBJAEwAUQBTAJEAlwDQAN8A7AD1AQMBDQEU"
    "ASABJwE5AUsBVwFpAW4BcwGAAYoBnwGmAa4BuAHEAdIB5wHzAgECGgInAikCKwItAi8CMQIzAjUCNwI5AjsCPQI/AkECQwJFAkcC"
    "SQJLAk0CTwJRAlMCVQJXAlkCWwJdAl8CaAJqAm8CcQJ2AngCfQJ/AoQCjwKYAq8CswLBAsoC1QLXAtkC2wLdAt8C5AL7Av8DDQMW"
    "AyMDKQMwAzIDNAM5Az4DRANLA1QDXQNmA3UDgQOQA5IDlAOWA5gDmgOcA54DowOoA7MDuQO7A70DvwPBA8MDxQPUA+AD5QPtA/AD"
    "9QP9BAAEBQQKBBMEGAQdBB8EKAQqBC8EMQQ2BD8ERARKBEwETgRTBFUEVwRZBGgEdASDBIUEhwSJBIsEjQSPBJEElwScBKIEpASm"
    "BKgEqgSsBK4EswTCBMYEywTiBOYE9AUbBR8FIwUnBSsFLwUzBTcFOwU/BUMFRwVLBU8FUwVXBVsFXQVfBWQFgAWCBYQFhgWIBYoF"
    "jAWOBZAFkgWUBZYFmAWaBZwFngWgBaIFpAWmBagFqgWsBa4FsAWyAAAAAAAAAgEAAAAAAAAA4wAAAAAAAAAAAAAAAAAABbQ="
    ;

static NSString *const shape_set =
    @"YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEI"
    "CVRyb290gAGvECsLDCszOjs8QEZHSExQUVVdZGhtdnt+g4SFhoeIFQ2YmRoXFpoOExIRFJudVSRudWxs3xAPDQ4PEBESExQVFhcY"
    "GRobHB0eHyAhIiMcJSYnKCEqXxASYWxsb3dzR3JvdXBPcGFjaXR5WWxpbmVXaWR0aF8QD2xpbmVEYXNoUGF0dGVybl5jb250ZW50"
    "c0Zvcm1hdFlzdHJva2VFbmRbc3Ryb2tlQ29sb3JUcGF0aFtzdHJva2VTdGFydF8QFmFsbG93c0VkZ2VBbnRpYWxpYXNpbmdXbGlu"
    "ZUNhcFhmaWxsUnVsZV8QEl9fQ0FDb2RpbmdDb250ZW50c1YkY2xhc3NZZmlsbENvbG9yW2Nvcm5lckN1cnZlgBiADIAGgBmAFoAC"
    "gA2AF4AYgAWABIAbgCqAAoAa1SwtLi8ZMDExMDJRclFiUWdRYSI/gAAAIgAAAACAA9I0NTY3WiRjbGFzc25hbWVYJGNsYXNzZXNf"
    "EBRMS0NHQ29sb3JDb2RpbmdQcm94eaM2ODldQ0FDb2RpbmdQcm94eVhOU09iamVjdFhldmVuLW9kZFVyb3VuZNI9GT4/VWFycmF5"
    "gAeAC9JBGUJFWk5TLm9iamVjdHOiQ0SACIAJgAoQAhAD0jQ1SUpeTlNNdXRhYmxlQXJyYXmjSUs5V05TQXJyYXnSNDVNTl8QFExL"
    "TlNBcnJheUNvZGluZ1Byb3h5o01POV1DQUNvZGluZ1Byb3h5I0AAAAAAAAAA0lIZU1RfEBBMS0NHUGF0aFNlZ21lbnRzgA6AFdJB"
    "GVZFpVdYWVpbgA+AEYASgBOAFIAK1F5fYBlQYWJjXxAQTEtDR1BhdGhQb2ludDBfeV8QEExLQ0dQYXRoUG9pbnQwX3hcTEtDR1Bh"
    "dGhUeXBlIz/wAAAAAAAAEACAENI0NWVmXxAVQ0FDR1BhdGhDb2RpbmdTZWdtZW50omc5XxAVQ0FDR1BhdGhDb2RpbmdTZWdtZW50"
    "1F5fYBlpamtjI0AQAAAAAAAAI0AIAAAAAAAAEAGAENZeGW5fYG9wY3JzdHVfEBBMS0NHUGF0aFBvaW50MV94XxAQTEtDR1BhdGhQ"
    "b2ludDFfeSNAGAAAAAAAAIAQI0AcAAAAAAAAI0AUAAAAAAAAEAIjQCAAAAAAAADYdxlfb15geG5qY2FQYXpqUF8QEExLQ0dQYXRo"
    "UG9pbnQyX3lfEBBMS0NHUGF0aFBvaW50Ml94gBAQA9JgGXxjEASAENI0NX+AXxATQ0FDR1BhdGhDb2RpbmdQcm94eaOBgjlfEBND"
    "QUNHUGF0aENvZGluZ1Byb3h5XUNBQ29kaW5nUHJveHkjP+AAAAAAAAAjP9AAAAAAAAAQAVVSR0JBOFhjaXJjdWxhctJBGYmXrYqL"
    "jI2Oj5CRkpOUlZaAHIAdgB6AH4AggCGAIoAjgCSAJYAmgCeAKIApXmNvbnRlbnRzRm9ybWF0W2Nvcm5lckN1cnZlXxAPbGluZURh"
    "c2hQYXR0ZXJu0jQ1S5yiSznSNDWen1xDQVNoYXBlTGF5ZXKjoKE5XENBU2hhcGVMYXllcldDQUxheWVyAAgAEQAaACQAKQAyADcA"
    "SQBMAFEAUwCBAIcAqAC9AMcA2QDoAPIA/gEDAQ8BKAEwATkBTgFVAV8BawFtAW8BcQFzAXUBdwF5AXsBfQF/AYEBgwGFAYcBiQGU"
    "AZYBmAGaAZwBoQGmAagBrQG4AcEB2AHcAeoB8wH8AgICBwINAg8CEQIWAiECJAImAigCKgIsAi4CMwJCAkYCTgJTAmoCbgJ8AoUC"
    "igKdAp8CoQKmAqwCrgKwArICtAK2ArgCwQLUAucC9AL9Av8DAQMGAx4DIQM5A0IDSwNUA1YDWANlA3gDiwOUA5YDnwOoA6oDswPE"
    "A9cD6gPsA+4D8wP1A/cD/AQSBBYELAQ6BEMETAROBFQEXQRiBHAEcgR0BHYEeAR6BHwEfgSABIIEhASGBIgEigSMBJsEpwS5BL4E"
    "wQTGBNME1wTkAAAAAAAAAgEAAAAAAAAAogAAAAAAAAAAAAAAAAAABOw="
    ;

static NSString *const text_set =
    @"YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEI"
    "CVRyb290gAGvEBoLDCcoKSoyOTo7PD0+TRYRTk8OGFASURBSVVUkbnVsbN0NDg8QERITFBUWFxgZGhscHR0fICEiHSQlJl50cnVu"
    "Y2F0aW9uTW9kZVRmb250XxAPZm9yZWdyb3VuZENvbG9yV3dyYXBwZWRfEBJhbGxvd3NHcm91cE9wYWNpdHlWc3RyaW5nXmNvbnRl"
    "bnRzRm9ybWF0XxASX19DQUNvZGluZ0NvbnRlbnRzViRjbGFzc18QFmFsbG93c0VkZ2VBbnRpYWxpYXNpbmddYWxpZ25tZW50TW9k"
    "ZVhmb250U2l6ZVtjb3JuZXJDdXJ2ZYAIgAOABYAJgAmAB4AKgAyAGYAJgAKABIALVmNlbnRlcllIZWx2ZXRpY2EjQCoAAAAAAADV"
    "KywtLhUvMDAvMVFyUWJRZ1FhIj+AAAAiAAAAAIAG0jM0NTZaJGNsYXNzbmFtZVgkY2xhc3Nlc18QFExLQ0dDb2xvckNvZGluZ1By"
    "b3h5ozU3OF1DQUNvZGluZ1Byb3h5WE5TT2JqZWN0VWhlbGxvU2VuZBABVVJHQkE4WGNpcmN1bGFy0j8VQExaTlMub2JqZWN0c6tB"
    "QkNERUZHSElKS4ANgA6AD4AQgBGAEoATgBSAFYAWgBeAGF1hbGlnbm1lbnRNb2RlXmNvbnRlbnRzRm9ybWF0W2Nvcm5lckN1cnZl"
    "XxAPZm9yZWdyb3VuZENvbG9yXnRydW5jYXRpb25Nb2Rl0jM0U1RXTlNBcnJheaJTONIzNFZXW0NBVGV4dExheWVyo1hZOFtDQVRl"
    "eHRMYXllcldDQUxheWVyAAgAEQAaACQAKQAyADcASQBMAFEAUwBwAHYAkQCgAKUAtwC/ANQA2wDqAP8BBgEfAS0BNgFCAUQBRgFI"
    "AUoBTAFOAVABUgFUAVYBWAFaAVwBYwFtAXYBgQGDAYUBhwGJAY4BkwGVAZoBpQGuAcUByQHXAeAB5gHqAewB8gH7AgACCwIXAhkC"
    "GwIdAh8CIQIjAiUCJwIpAisCLQIvAj0CTAJYAmoCeQJ+AoYCiQKOApoCngKqAAAAAAAAAgEAAAAAAAAAWgAAAAAAAAAAAAAAAAAA"
    "ArI="
    ;

static NSString *const constraints_set =
    @"YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEI"
    "CVRyb290gAGvEBoLDB0eIik1Nj1BQkdLT1BRU1cQFA1gYRFiZFUkbnVsbNgNDg8QERITFBUWFxgZGhsYW2NvbnN0cmFpbnRzW2Nv"
    "cm5lckN1cnZlViRjbGFzc18QFmFsbG93c0VkZ2VBbnRpYWxpYXNpbmddbGF5b3V0TWFuYWdlcl8QEl9fQ0FDb2RpbmdDb250ZW50"
    "c15jb250ZW50c0Zvcm1hdF8QEmFsbG93c0dyb3VwT3BhY2l0eYADgA6AGYACgA+AEYANgAIQAdIfDyAhVWFycmF5gASADNIjDyQo"
    "Wk5TLm9iamVjdHOjJSYngAWACIAKgAvWKissLS4PLzAxMjM0V0NBU2NhbGVWQ0FBdHRyWENBT2Zmc2V0V0NBU3JjSWRZQ0FTcmNB"
    "dHRyI0AAAAAAAAAAEAAjQAgAAAAAAACABhACgAdXc2libGluZ9I3ODk6WiRjbGFzc25hbWVYJGNsYXNzZXNcQ0FDb25zdHJhaW50"
    "ojs8XENBQ29uc3RyYWludFhOU09iamVjdNQrLS4PPj8+NBADgAmAB1pzdXBlcmxheWVy1SssLS4PQ0Q/QzQQBiNAHAAAAAAAAIAJ"
    "gAfSNzhISV5OU011dGFibGVBcnJheaNISjxXTlNBcnJhedI3OExNXxAUTEtOU0FycmF5Q29kaW5nUHJveHmjTE48XUNBQ29kaW5n"
    "UHJveHlVUkdCQThYY2lyY3VsYXLRD1KAENI3OFRVXxAZQ0FDb25zdHJhaW50TGF5b3V0TWFuYWdlcqJWPF8QGUNBQ29uc3RyYWlu"
    "dExheW91dE1hbmFnZXLSIw9YX6ZZWltcXV6AEoATgBSAFYAWgBeAGF5jb250ZW50c0Zvcm1hdFtjb3JuZXJDdXJ2ZdI3OEpjoko8"
    "0jc4ZWZXQ0FMYXllcqJlPAAIABEAGgAkACkAMgA3AEkATABRAFMAcAB2AIcAkwCfAKYAvwDNAOIA8QEGAQgBCgEMAQ4BEAESARQB"
    "FgEYAR0BIwElAScBLAE3ATsBPQE/AUEBQwFQAVgBXwFoAXABegGDAYUBjgGQAZIBlAGcAaEBrAG1AcIBxQHSAdsB5AHmAegB6gH1"
    "AgACAgILAg0CDwIUAiMCJwIvAjQCSwJPAl0CYwJsAm8CcQJ2ApIClQKxArYCvQK/AsECwwLFAscCyQLLAtoC5gLrAu4C8wL7AAAA"
    "AAAAAgEAAAAAAAAAZwAAAAAAAAAAAAAAAAAAAv4="
    ;

static BOOL near(double a, double b) { return a - b < 1e-6 && b - a < 1e-6; }

static BOOL isSRGBRed(CGColorRef c) {
    if (c == NULL || CGColorGetNumberOfComponents(c) != 4)
        return NO;
    const CGFloat *p = CGColorGetComponents(c);
    return near(p[0], 1) && near(p[1], 0) && near(p[2], 0) && near(p[3], 1);
}

static id decode(NSString *base64) {
    NSData *data = [[[NSData alloc] initWithBase64EncodedString: base64 options: 0] autorelease];
    NSError *error = nil;
    id object = [NSKeyedUnarchiver unarchivedObjectOfClass: [CALayer class] fromData: data error: &error];
    if (object == nil)
        fprintf(stderr, "decode failed: %s\n", [[error description] UTF8String]);
    return object;
}

int main(void) {
    @autoreleasepool {
        CALayer *l = decode(layer_set);
        CHECK(l != nil && [l class] == [CALayer class], "layer decoded");
        if (l != nil) {
            CHECK([l.name isEqualToString: @"root"], "name");
            CHECK(CGRectEqualToRect(l.bounds, CGRectMake(0, 0, 10, 20)), "bounds");
            CHECK(CGPointEqualToPoint(l.position, CGPointMake(5, 6)), "position");
            CHECK(CGPointEqualToPoint(l.anchorPoint, CGPointMake(0, 1)), "anchorPoint");
            CHECK(l.opacity == 0.5f && l.hidden && l.masksToBounds && l.geometryFlipped, "opacity, hidden, masksToBounds, flipped");
            CHECK(l.cornerRadius == 3 && l.borderWidth == 1 && l.zPosition == 2 && l.contentsScale == 2, "scalars");
            CHECK([l.contentsGravity isEqualToString: kCAGravityCenter], "gravity");
            CHECK(isSRGBRed(l.backgroundColor) && isSRGBRed(l.borderColor), "colors");
            CHECK(CATransform3DEqualToTransform(l.transform, CATransform3DMakeScale(2, 2, 1)), "transform");
            CHECK(l.shadowOpacity == 0.7f && l.shadowRadius == 4 && CGSizeEqualToSize(l.shadowOffset, CGSizeMake(1, 2)), "shadow");
            CHECK(l.sublayers.count == 1 && [[l.sublayers[0] name] isEqualToString: @"child"] &&
                      [l.sublayers[0] superlayer] == l, "sublayer");
            CHECK([l.mask.name isEqualToString: @"mask"], "mask");
            CHECK([l.contentsFormat isEqualToString: kCAContentsFormatRGBA8Uint] && [l.cornerCurve isEqualToString: kCACornerCurveCircular],
                  "default format and curve");
        }

        CAShapeLayer *s = decode(shape_set);
        CHECK([s isKindOfClass: [CAShapeLayer class]], "shape layer decoded");
        if ([s isKindOfClass: [CAShapeLayer class]]) {
            CHECK(s.lineWidth == 2 && s.strokeStart == 0.25 && s.strokeEnd == 0.5, "stroke scalars");
            CHECK([s.fillRule isEqualToString: kCAFillRuleEvenOdd] && [s.lineCap isEqualToString: kCALineCapRound], "rule and cap");
            CHECK([s.lineDashPattern isEqualToArray: (@[ @2, @3 ])], "dash pattern");
            CHECK(isSRGBRed(s.fillColor) && isSRGBRed(s.strokeColor), "shape colors");
            CGMutablePathRef expected = CGPathCreateMutable();
            CGPathMoveToPoint(expected, NULL, 1, 2);
            CGPathAddLineToPoint(expected, NULL, 3, 4);
            CGPathAddQuadCurveToPoint(expected, NULL, 5, 6, 7, 8);
            CGPathAddCurveToPoint(expected, NULL, 1, 1, 2, 2, 3, 3);
            CGPathCloseSubpath(expected);
            CHECK(s.path != NULL && CGPathEqualToPath(s.path, expected), "path");
            CGPathRelease(expected);
        }

        CATextLayer *t = decode(text_set);
        CHECK([t isKindOfClass: [CATextLayer class]], "text layer decoded");
        if ([t isKindOfClass: [CATextLayer class]]) {
            CHECK([t.string isEqual: @"hello"] && [(id) t.font isEqual: @"Helvetica"] && t.fontSize == 13, "string, font, size");
            CHECK(t.wrapped && [t.alignmentMode isEqualToString: kCAAlignmentCenter] &&
                      [t.truncationMode isEqualToString: kCATruncationEnd], "wrapping, alignment, truncation");
            CHECK(isSRGBRed(t.foregroundColor), "foreground color");
        }

        // Constraints and the layout manager: CAAttr, CASrcId, CASrcAttr, CAScale and CAOffset keys.
        CALayer *c = decode(constraints_set);
        CHECK(c != nil && [c.layoutManager isKindOfClass: [CAConstraintLayoutManager class]] && c.constraints.count == 3, "constraint layer");
        if (c.constraints.count == 3) {
            CAConstraint *first = c.constraints[0], *second = c.constraints[1], *third = c.constraints[2];
            CHECK(first.attribute == kCAConstraintMinX && first.sourceAttribute == kCAConstraintMaxX &&
                      [first.sourceName isEqualToString: @"sibling"] && first.scale == 2 && first.offset == 3, "first constraint");
            CHECK(second.attribute == kCAConstraintWidth && second.sourceAttribute == kCAConstraintWidth &&
                      [second.sourceName isEqualToString: @"superlayer"] && second.scale == 1 && second.offset == 0, "second constraint");
            CHECK(third.attribute == kCAConstraintMaxY && third.sourceAttribute == kCAConstraintMaxY && third.offset == 7, "third constraint");
        }

        if (failures == 0) puts("PASS: layer archives written by macOS decode");
        return failures != 0;
    }
}
