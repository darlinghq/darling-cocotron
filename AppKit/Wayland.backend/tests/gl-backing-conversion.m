#import <AppKit/AppKit.h>
#include <math.h>
#include <stdio.h>
static int checks,failures,contextCreations;
@interface PixelContext : NSObject { @public NSSize pixels; id target; } @end
@implementation PixelContext
- (void)clearDrawable{target=nil;}
- (void)setView:(id)view{target=view;}
- (id)view{return target;}
- (NSSize)_drawablePixelSize{return pixels;}
@end
@interface ConversionView : NSOpenGLView @end
@implementation ConversionView
- (NSOpenGLContext *)openGLContext{contextCreations++;return nil;}
@end
static void same(CGFloat value,CGFloat expected){checks++;if(fabs(value-expected)>1e-9||!isfinite(value)){failures++;printf("FAIL %.12g expected %.12g\n",(double)value,(double)expected);}}
static void rectSame(NSRect a,NSRect b){same(a.origin.x,b.origin.x);same(a.origin.y,b.origin.y);same(a.size.width,b.size.width);same(a.size.height,b.size.height);}
int main(void){@autoreleasepool{
    ConversionView *view=[[ConversionView alloc]initWithFrame:NSMakeRect(0,0,101,51) pixelFormat:nil];
    [view setBounds:NSMakeRect(3,7,101,51)];NSRect rect=NSMakeRect(2.25,-3.5,20.3,25.7);
    rectSame([view convertRectToBacking:rect],rect);same(contextCreations,0);
    PixelContext *ctx=[PixelContext new];[view setOpenGLContext:(id)ctx];
    ctx->pixels=NSMakeSize(126,64);[ctx setView:nil];
    rectSame([view convertRectToBacking:rect],rect);rectSame([view convertRectFromBacking:rect],rect);
    [ctx setView:[NSObject new]];
    rectSame([view convertRectToBacking:rect],rect);rectSame([view convertRectFromBacking:rect],rect);
    [[ctx view] release];[ctx setView:view];
    const NSSize sizes[]={{126,64},{152,77},{177,89},{1,1},{202,102}};
    for(unsigned i=0;i<sizeof(sizes)/sizeof(sizes[0]);i++){
        ctx->pixels=sizes[i];NSRect full=[view convertRectToBacking:[view bounds]];
        same(full.size.width,sizes[i].width);same(full.size.height,sizes[i].height);
        same(full.origin.x,3*sizes[i].width/101);same(full.origin.y,7*sizes[i].height/51);
        rectSame([view convertRectFromBacking:[view convertRectToBacking:rect]],rect);
        NSPoint point=[view convertPointFromBacking:[view convertPointToBacking:rect.origin]];
        same(point.x,rect.origin.x);same(point.y,rect.origin.y);
        NSSize size=[view convertSizeFromBacking:[view convertSizeToBacking:rect.size]];
        same(size.width,rect.size.width);same(size.height,rect.size.height);
    }
    // A viewport often casts these values to integer. Test exact full-extent
    // conversion, including 71->124 where multiply-after-ratio loses one ULP.
    for(int n=1;n<=257;n++){
        [view setBounds:NSMakeRect(3,7,n,n)];int px=(int)floor(n*1.75+.5);
        ctx->pixels=NSMakeSize(px,px);NSSize full=[view convertRectToBacking:[view bounds]].size;
        same((int)full.width,px);same((int)full.height,px);
    }
    [view setBounds:NSMakeRect(3,7,101,51)];
    const NSSize invalid[]={{0,0},{0,1},{-1,1},{NAN,1},{1,INFINITY},{1.5,1}};
    for(unsigned i=0;i<sizeof(invalid)/sizeof(invalid[0]);i++){
        ctx->pixels=invalid[i];rectSame([view convertRectToBacking:rect],rect);rectSame([view convertRectFromBacking:rect],rect);
    }
    same(contextCreations,0);[view release];[ctx release];
    printf("RESULT checks=%d failures=%d\n",checks,failures);return failures?1:0;
}}
