// Compile the production layer implementation under a distinct class name and
// replace only GL calls, so this tests viewport/rejection behavior without EGL.
#define CALayerContext TestedLayerContext
#define CGLContextMakeCurrentAndAttachToWindow testAttach
#define CGLFlushDrawable testSwap
#define glEnable testEnable
#define glShadeModel testShadeModel
#define glViewport testViewport
#define glMatrixMode testMatrixMode
#define glLoadIdentity testLoadIdentity
#define glOrtho testOrtho
#define glGenTextures testGenTextures
#define glDeleteTextures testDeleteTextures
#include "../../../QuartzCore/CALayerContext.m"
#include <stdio.h>
static int calls,swaps,checks,failures;static GLsizei lastWidth,lastHeight;
CGLError testAttach(CGLContextObj context,CGLWindowRef window){return kCGLNoError;}
CGLError testSwap(CGLContextObj context){swaps++;return kCGLNoError;}
void testEnable(GLenum value){}
void testShadeModel(GLenum value){}
void testViewport(GLint x,GLint y,GLsizei w,GLsizei h){calls++;lastWidth=w;lastHeight=h;}
void testMatrixMode(GLenum value){}
void testLoadIdentity(void){}
void testOrtho(GLdouble a,GLdouble b,GLdouble c,GLdouble d,GLdouble e,GLdouble f){}
void testGenTextures(GLsizei n,GLuint *v){while(n--)*v++=1;}
void testDeleteTextures(GLsizei n,const GLuint *v){}
@interface LegacyDrawable : NSObject { @public CGFloat scale; } @end
@implementation LegacyDrawable
- (CGFloat)backingScaleFactor{return scale;}
@end
@interface ExactDrawable : LegacyDrawable { @public CGSize pixels; } @end
@implementation ExactDrawable
- (CGSize)drawablePixelSize{return pixels;}
@end
@interface LayerFixture : TestedLayerContext
- (void)configure:(id)drawable;
@end
@implementation LayerFixture
- (void)configure:(id)drawable{_frame=CGRectMake(0,0,101.2,51.2);_subwindow=[drawable retain];_rendered=YES;}
@end
static void test(id drawable,int width,int height){
    LayerFixture *ctx=[LayerFixture alloc];[ctx configure:drawable];calls=swaps=0;
    [ctx renderLayer:nil];[ctx flush];checks++;
    if(width>=0? calls!=1||swaps!=1||lastWidth!=width||lastHeight!=height : calls!=0||swaps!=0){failures++;printf("FAIL expected %dx%d got %dx%d calls%d swaps%d\n",width,height,lastWidth,lastHeight,calls,swaps);}
    [ctx release];
}
int main(void){@autoreleasepool{
    NSObject *original=[NSObject new];test(original,102,52);[original release];
    LegacyDrawable *old=[LegacyDrawable new];old->scale=1.25;test(old,127,65);
    ExactDrawable *exact=[ExactDrawable new];exact->scale=1.25;exact->pixels=CGSizeZero;test(exact,127,65);
    exact->scale=NAN;exact->pixels=CGSizeMake(128,66);test(exact,128,66);
    const CGSize sizes[]={{0,1},{1,0},{-1,2},{1.5,2},{NAN,1},{1,INFINITY},{16385,1},{1,16385},{1,1},{16384,16384}};
    for(unsigned i=0;i<sizeof(sizes)/sizeof(sizes[0]);i++){exact->pixels=sizes[i];test(exact,i>=8?(int)sizes[i].width:-1,i>=8?(int)sizes[i].height:0);}
    exact->pixels=CGSizeZero;test(exact,-1,0);exact->scale=0;test(exact,-1,0);
    old->scale=16384.5/102;test(old,-1,0);
    old->scale=.001;test(old,0,0);
    [exact release];[old release];printf("RESULT checks=%d failures=%d\n",checks,failures);return failures?1:0;
}}
