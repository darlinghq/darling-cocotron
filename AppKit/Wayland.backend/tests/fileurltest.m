#import <Foundation/Foundation.h>
#import "WaylandFileURLs.m"
#include <stdio.h>
static int checks, failures;
static void fileCheck(BOOL pass,const char *name) { checks++; if(!pass) failures++; printf("%s %s\n",pass?"PASS":"FAIL",name); }
static NSData *bytes(NSString *s) { return [s dataUsingEncoding:NSUTF8StringEncoding]; }
int main(void) {
 @autoreleasepool {
    NSArray *files=@[@"/Volumes/SystemRoot/tmp/a b#%日本語",@"/Volumes/SystemRoot/tmp/new\nline"];
    NSData *wire=WaylandURIListFromFilenames(files);
    fileCheck([wire isEqual:bytes(@"file:///tmp/a%20b%23%25%E6%97%A5%E6%9C%AC%E8%AA%9E\r\nfile:///tmp/new%0Aline\r\n")],"exact UTF8 escaping and CRLF");
    fileCheck([WaylandFilenamesFromURIList(wire) isEqual:files],"multi-file roundtrip");
    fileCheck([WaylandFilenamesFromURIList(bytes(@"# comment\r\n\nFILE://LOCALHOST/tmp/a\r\nfile:/tmp/b\n")) isEqual:@[@"/Volumes/SystemRoot/tmp/a",@"/Volumes/SystemRoot/tmp/b"]],"comments localhost and case");
    for(NSString *bad in @[@"file://remote/tmp/a",@"file:relative",@"file:///a?query",@"file:///a#fragment",@"file:///a%",@"file:///a%GG",@"file:///a%00",@"file:///a%FF",@"file:///a/../b",@"file:///a/%2e%2e/b",@"file:////server/share",@"https://example.com/a",@"file:///raw space",@"file:///raw\rbreak",@"file:///a%2Fb",@"file:///a%2fb"]) {
        fileCheck(WaylandFilenamesFromURIList(bytes(bad))==nil,[bad UTF8String]);
        fileCheck(WaylandFilenamesFromURIList(bytes([@"file:///valid\n" stringByAppendingString:bad]))==nil,"invalid list entry rejects entire list");
    }
    fileCheck(WaylandURIListFromFilenames(@[@"/tmp/guest-only"])==nil,"guest-only export refused");
    fileCheck(WaylandURIListFromFilenames(@[@"/Volumes/SystemRoot/tmp/ok",@"/tmp/guest-only"])==nil,"mixed export all-or-nothing");
    fileCheck(WaylandURIListFromFilenames(@[@"/Volumes/SystemRooted/tmp/no"])==nil,"host boundary exact");
    fileCheck(WaylandURIListFromFilenames(@[@"/Volumes/SystemRoot/tmp/../no"])==nil,"export parent traversal refused");
    fileCheck(WaylandURIListFromFilenames(@[@42])==nil,"non-string entry refused");
    fileCheck(WaylandURIListFromFilenames(@[])==nil,"empty export refused");
    fileCheck(WaylandFilenamesFromURIList(bytes(@"# only comment\n"))==nil,"empty URI selection refused");
    char nul[]="file:///tmp/a\0hidden";
    fileCheck(WaylandFilenamesFromURIList([NSData dataWithBytes:nul length:sizeof(nul)-1])==nil,"embedded NUL refused");
    NSString *longPath=[@"/Volumes/SystemRoot/" stringByPaddingToLength:4096 withString:@"a" startingAtIndex:0];
    fileCheck(WaylandURIListFromFilenames(@[longPath])==nil,"path bound");
    fileCheck(WaylandFilenamesFromURIList(bytes([@"file:///" stringByPaddingToLength:16384 withString:@"a/" startingAtIndex:0]))==nil,"overlong component sequence refused");
    NSString *many=[@"" stringByPaddingToLength:4097 withString:@"\n" startingAtIndex:0];
    fileCheck(WaylandFilenamesFromURIList(bytes(many))==nil,"excessive blank records refused before split");
    NSMutableArray *manyFiles=[NSMutableArray array];
    for(int i=0;i<4097;i++)[manyFiles addObject:@"/Volumes/SystemRoot/tmp/a"];
    fileCheck(WaylandURIListFromFilenames(manyFiles)==nil,"excessive file records refused");
    printf("RESULT checks=%d failures=%d\n",checks,failures);
 }
 return failures?1:0;
}
