#include "../WaylandScale.h"
#include <stdio.h>
#include <stdlib.h>
static unsigned checks, failures;
#define CHECK(x) do { checks++; if (!(x)) { failures++; fprintf(stderr,"line %d: %s\n",__LINE__,#x); } } while (0)
int main(void) {
    const uint32_t scales[] = {120,150,180,210,240};
    for (unsigned s=0;s<sizeof(scales)/sizeof(scales[0]);s++) {
        for (int n=1;n<=1025;n++) {
            int32_t px=0;
            CHECK(WaylandScaleExtent(n,scales[s],16384,&px));
            CHECK(px==(int32_t)floorl((long double)n*scales[s]/120+.5L));
            // Every trailing crop ends at the exact right/bottom buffer edge.
            for (int start=0;start<n;start++) {
                int32_t offset=-1,extent=-1;
                CHECK(WaylandScaleCrop(n,px,start,n,&offset,&extent));
                CHECK(offset>=0 && extent>0 && offset+extent==px*256);
            }
        }
    }
    // Independent long-double oracle for interior endpoints, including ties.
    for (int n=3;n<101;n++) for (int px=1;px<180;px++) {
        for (int start=1;start<n-1;start++) {
            int end=start+1;
            int32_t a,b;
            int32_t expectedA=(int32_t)floorl((long double)start*px*256/n+.5L);
            int32_t expectedB=(int32_t)floorl((long double)end*px*256/n+.5L);
            int ok=WaylandScaleCrop(n,px,start,end,&a,&b);
            CHECK(ok==(expectedB>expectedA));
            if(ok)CHECK(a==expectedA && b==expectedB-expectedA);
        }
    }
    int32_t px=99,a=99,b=99;
    CHECK(!WaylandScaleExtent(0,120,16384,&px));
    CHECK(!WaylandScaleExtent(1,0,16384,&px));
    CHECK(!WaylandScaleExtent(-1,120,16384,&px));
    CHECK(!WaylandScaleExtent(INT32_MAX,UINT32_MAX,INT32_MAX,&px));
    CHECK(!WaylandScaleExtent(16385,120,16384,&px));
    CHECK(WaylandScaleExtent(16384,120,16384,&px) && px==16384);
    CHECK(WaylandScaleExtent(1,1,16384,&px) && px==1);
    CHECK(!WaylandScaleCrop(10,10,-1,10,&a,&b));
    CHECK(!WaylandScaleCrop(10,10,0,11,&a,&b));
    CHECK(!WaylandScaleCrop(10,10,1,1,&a,&b));
    CHECK(!WaylandScaleCrop(10,INT32_MAX,0,10,&a,&b));
    printf("RESULT checks=%u failures=%u\n",checks,failures);
    return failures?1:0;
}
