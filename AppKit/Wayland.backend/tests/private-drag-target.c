// Adversarial native receiver: request the private marker and finish MOVE even
// with an empty payload. Run only in the fixture's isolated compositor.
#define _GNU_SOURCE
#include <wayland-client.h>
#include "xdg-shell-client.h"
#include <assert.h>
#include <fcntl.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
static struct wl_display *display;
static struct wl_compositor *compositor;
static struct wl_shm *shm;
static struct wl_seat *seat;
static struct wl_data_device_manager *manager;
static struct xdg_wm_base *wm;
static struct wl_surface *surface;
static struct wl_buffer *buffer;
static struct wl_data_offer *offer;
static char *mime;
static unsigned count,action;
static int input=-1,total;
static void offered(void *p,struct wl_data_offer *o,const char *type){count++;free(mime);mime=strdup(type);}
static void actions(void *p,struct wl_data_offer *o,uint32_t a){}
static void selected(void *p,struct wl_data_offer *o,uint32_t a){action=a;}
static const struct wl_data_offer_listener offers={offered,actions,selected};
static void new_offer(void *p,struct wl_data_device *d,struct wl_data_offer *o){offer=o;count=0;action=0;wl_data_offer_add_listener(o,&offers,NULL);}
static void enter(void *p,struct wl_data_device *d,uint32_t serial,struct wl_surface *s,wl_fixed_t x,wl_fixed_t y,struct wl_data_offer *o){
    assert(o==offer && count==1 && mime && !strncmp(mime,"application/x-darling-local-drag-",31));
    printf("PRIVATE_ENTER mimes=%u\n",count);fflush(stdout);
    wl_data_offer_accept(o,serial,mime);
    wl_data_offer_set_actions(o,WL_DATA_DEVICE_MANAGER_DND_ACTION_MOVE,WL_DATA_DEVICE_MANAGER_DND_ACTION_MOVE);
}
static void leave(void *p,struct wl_data_device *d){}
static void motion(void *p,struct wl_data_device *d,uint32_t t,wl_fixed_t x,wl_fixed_t y){}
static void drop(void *p,struct wl_data_device *d){
    assert(action==WL_DATA_DEVICE_MANAGER_DND_ACTION_MOVE);
    int fds[2];assert(pipe2(fds,O_CLOEXEC|O_NONBLOCK)==0);input=fds[0];
    wl_data_offer_receive(offer,mime,fds[1]);close(fds[1]);wl_display_flush(display);
}
static void selection(void *p,struct wl_data_device *d,struct wl_data_offer *o){}
static const struct wl_data_device_listener device_listener={new_offer,enter,leave,motion,drop,selection};
static void ping(void *p,struct xdg_wm_base *w,uint32_t serial){xdg_wm_base_pong(w,serial);}
static const struct xdg_wm_base_listener wm_listener={ping};
static void configure(void *p,struct xdg_surface *s,uint32_t serial){
    xdg_surface_ack_configure(s,serial);wl_surface_attach(surface,buffer,0,0);
    wl_surface_damage(surface,0,0,300,220);wl_surface_commit(surface);
}
static const struct xdg_surface_listener surface_listener={configure};
static void top_config(void *p,struct xdg_toplevel *t,int32_t w,int32_t h,struct wl_array *a){}
static void top_close(void *p,struct xdg_toplevel *t){exit(0);}
static const struct xdg_toplevel_listener top_listener={top_config,top_close};
static void global(void *p,struct wl_registry *r,uint32_t id,const char *name,uint32_t v){
    if(!strcmp(name,"wl_compositor"))compositor=wl_registry_bind(r,id,&wl_compositor_interface,3);
    if(!strcmp(name,"wl_shm"))shm=wl_registry_bind(r,id,&wl_shm_interface,1);
    if(!strcmp(name,"wl_seat"))seat=wl_registry_bind(r,id,&wl_seat_interface,1);
    if(!strcmp(name,"wl_data_device_manager")){assert(v>=3);manager=wl_registry_bind(r,id,&wl_data_device_manager_interface,3);}
    if(!strcmp(name,"xdg_wm_base"))wm=wl_registry_bind(r,id,&xdg_wm_base_interface,1);
}
static void removed(void *p,struct wl_registry *r,uint32_t id){}
static const struct wl_registry_listener registry_listener={global,removed};
int main(void){
    display=wl_display_connect(NULL);assert(display);struct wl_registry *r=wl_display_get_registry(display);
    wl_registry_add_listener(r,&registry_listener,NULL);assert(wl_display_roundtrip(display)>=0);
    assert(compositor && shm && seat && manager && wm);xdg_wm_base_add_listener(wm,&wm_listener,NULL);
    struct wl_data_device *device=wl_data_device_manager_get_data_device(manager,seat);
    wl_data_device_add_listener(device,&device_listener,NULL);
    int fd=memfd_create("private-target",MFD_CLOEXEC);assert(fd>=0 && ftruncate(fd,300*220*4)==0);
    uint32_t *pixels=mmap(NULL,300*220*4,PROT_READ|PROT_WRITE,MAP_SHARED,fd,0);assert(pixels!=MAP_FAILED);
    for(int i=0;i<300*220;i++)pixels[i]=0xff333333;
    struct wl_shm_pool *pool=wl_shm_create_pool(shm,fd,300*220*4);
    buffer=wl_shm_pool_create_buffer(pool,0,300,220,300*4,WL_SHM_FORMAT_XRGB8888);wl_shm_pool_destroy(pool);close(fd);
    surface=wl_compositor_create_surface(compositor);struct xdg_surface *xdg=xdg_wm_base_get_xdg_surface(wm,surface);
    xdg_surface_add_listener(xdg,&surface_listener,NULL);struct xdg_toplevel *top=xdg_surface_get_toplevel(xdg);
    xdg_toplevel_add_listener(top,&top_listener,NULL);xdg_toplevel_set_title(top,"Native outgoing target");
    wl_surface_commit(surface);wl_display_flush(display);puts("READY");fflush(stdout);
    for(;;){
        assert(wl_display_dispatch_pending(display)>=0);wl_display_flush(display);
        struct pollfd fds[2]={{wl_display_get_fd(display),POLLIN,0},{input,POLLIN,0}};
        assert(poll(fds,2,15000)>0);
        if(fds[0].revents)assert(wl_display_dispatch(display)>=0);
        if(input>=0 && fds[1].revents){
            char bytes[1024];ssize_t n=read(input,bytes,sizeof(bytes));assert(n>=0);
            if(n>0){total+=n;continue;}
            close(input);input=-1;printf("PRIVATE bytes=%d mimes=%u\n",total,count);fflush(stdout);
            assert(total==0);wl_data_offer_finish(offer);wl_display_flush(display);
        }
    }
}
