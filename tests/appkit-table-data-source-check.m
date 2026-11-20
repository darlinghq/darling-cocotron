// Copyright (C) 2026 Lubos Dolezel
//
// When NSTableView reports a data source that does not answer numberOfRowsInTableView:. Expected values are from
// black-box runs of this test on macOS 26.7.3 (x86_64) and, without the nib cases, Mac OS X 10.14.4 (i386).
//  - test_unbound_data_source: -setDataSource: logs "Illegal NSTableView data source" once for a data source
//    without numberOfRowsInTableView: (whether or not it has tableView:objectValueForTableColumn:row:), for cell-
//    and view-based tables; the table has no rows, and -numberOfRows and -reloadData log nothing more. A data
//    source with numberOfRowsInTableView: only, and a nil data source, log nothing.
//  - test_bound_content: with the content bound to an array controller first, such a data source logs nothing
//    and the table has the controller's rows; set before the binding, it is reported.
//  - test_nib (with fixtures/tables/BoundTable.nib and UnboundTable.nib, compiled by ibtool from the .xib files
//    next to them): a nib table whose data source outlet is such an object and whose content is bound logs
//    nothing, while loading or after; without the binding, nothing is logged while loading and the report
//    comes with the first -numberOfRows after it.
// Usage: appkit-table-data-source-check [BoundTable.nib UnboundTable.nib]
// Build: clang -framework AppKit appkit-table-data-source-check.m (no ARC)
#import <AppKit/AppKit.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

@interface Empty : NSObject
@end
@implementation Empty
@end

@interface RowsOnly : NSObject
@end
@implementation RowsOnly
- (NSInteger) numberOfRowsInTableView: (NSTableView *) t { return 1; }
@end

@interface ValueOnly : NSObject
@end
@implementation ValueOnly
- (id) tableView: (NSTableView *) t objectValueForTableColumn: (NSTableColumn *) c row: (NSInteger) r { return @"x"; }
@end

@interface ViewDelegate : NSObject <NSTableViewDelegate>
@end
@implementation ViewDelegate
- (NSView *) tableView: (NSTableView *) t viewForTableColumn: (NSTableColumn *) c row: (NSInteger) r { return nil; }
@end

// Collects what is written to stderr (where NSLog writes) between startLog() and the matching countReports().
static int savedStderr = -1;
static char logPath[64];

static void startLog(void) {
    fflush(stderr);
    strcpy(logPath, "/tmp/tdscXXXXXX");
    int fd = mkstemp(logPath);
    savedStderr = dup(2);
    dup2(fd, 2);
    close(fd);
}

// The number of "Illegal NSTableView data source" reports logged since startLog().
static int countReports(void) {
    fflush(stderr);
    dup2(savedStderr, 2);
    close(savedStderr);
    NSString *log = [NSString stringWithContentsOfFile: [NSString stringWithUTF8String: logPath] encoding: NSUTF8StringEncoding
                                                 error: NULL];
    unlink(logPath);
    return (int) [[log componentsSeparatedByString: @"Illegal NSTableView data source"] count] - 1;
}

static NSTableView *makeTable(BOOL viewBased) {
    NSTableView *table = [[NSTableView alloc] initWithFrame: NSMakeRect(0, 0, 200, 100)];
    [table addTableColumn: [[[NSTableColumn alloc] initWithIdentifier: @"c"] autorelease]];
    if (viewBased)
        [table setDelegate: [ViewDelegate new]];
    return table;
}

static void test_unbound_data_source(void) {
    for (int viewBased = 0; viewBased < 2; viewBased++) {
        NSTableView *table = makeTable(viewBased);
        startLog();
        [table setDataSource: (id) [Empty new]];
        int reports = countReports();
        CHECK(reports == 1);
        startLog();
        NSInteger rows = [table numberOfRows];
        [table reloadData];
        rows = [table numberOfRows];
        reports = countReports();
        CHECK(rows == 0);
        CHECK(reports == 0);

        table = makeTable(viewBased);
        startLog();
        [table setDataSource: (id) [ValueOnly new]];
        rows = [table numberOfRows];
        reports = countReports();
        CHECK(reports == 1);
        CHECK(rows == 0);

        table = makeTable(viewBased);
        startLog();
        [table setDataSource: (id) [RowsOnly new]];
        rows = [table numberOfRows];
        [table setDataSource: nil];
        reports = countReports();
        CHECK(reports == 0);
        CHECK(rows == 1);
    }
}

static void test_bound_content(void) {
    NSArrayController *controller = [[NSArrayController alloc] initWithContent:
            [NSMutableArray arrayWithObjects: @"a", @"b", @"c", nil]];
    for (int viewBased = 0; viewBased < 2; viewBased++) {
        NSTableView *table = makeTable(viewBased);
        startLog();
        [table bind: NSContentBinding toObject: controller withKeyPath: @"arrangedObjects" options: nil];
        [table setDataSource: (id) [Empty new]];
        [table reloadData];
        NSInteger rows = [table numberOfRows];
        int reports = countReports();
        CHECK(reports == 0);
        CHECK(rows == 3);

        table = makeTable(viewBased);
        startLog();
        [table setDataSource: (id) [Empty new]];
        [table bind: NSContentBinding toObject: controller withKeyPath: @"arrangedObjects" options: nil];
        rows = [table numberOfRows];
        reports = countReports();
        CHECK(reports == 1);
        CHECK(rows == 3);
    }
}

static NSTableView *loadTable(const char *path, NSArray **objects) {
    NSNib *nib = [[NSNib alloc] initWithNibData: [NSData dataWithContentsOfFile: [NSString stringWithUTF8String: path]]
                                         bundle: nil];
    CHECK([nib instantiateWithOwner: [Empty new] topLevelObjects: objects]);
    for (id object in *objects)
        if ([object isKindOfClass: [NSScrollView class]])
            return [object documentView];
    return nil;
}

static void test_nib(const char *bound, const char *unbound) {
    NSArray *objects = nil;
    startLog();
    NSTableView *table = loadTable(bound, &objects);
    int reports = countReports();
    CHECK(table != nil && [[table dataSource] isKindOfClass: [Empty class]]);
    CHECK(reports == 0);
    for (id object in objects)
        if ([object isKindOfClass: [NSArrayController class]])
            [object setContent: [NSMutableArray arrayWithObjects: @"a", @"b", nil]];
    startLog();
    NSInteger rows = [table numberOfRows];
    [table reloadData];
    reports = countReports();
    CHECK(reports == 0);
    CHECK(rows == 2);

    startLog();
    table = loadTable(unbound, &objects);
    reports = countReports();
    CHECK(table != nil && [[table dataSource] isKindOfClass: [Empty class]]);
    CHECK(reports == 0);
    startLog();
    rows = [table numberOfRows];
    [table reloadData];
    rows = [table numberOfRows];
    reports = countReports();
    CHECK(reports == 1);
    CHECK(rows == 0);
}

#define RUN(t) do { @try { t; } @catch (id e) { fprintf(stderr, "FAIL: %s raised %s\n", #t, [[e description] UTF8String]); failures++; } } while (0)

int main(int argc, char **argv) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [NSApplication sharedApplication];
    RUN(test_unbound_data_source());
    RUN(test_bound_content());
    if (argc > 2)
        RUN(test_nib(argv[1], argv[2]));
    if (failures == 0)
        printf("PASS appkit-table-data-source-check\n");
    [pool release];
    return failures != 0;
}
