// Minimal private protocol server: validates negotiated child versions on wire.
// It renders nothing and is only for the no-window logical-probe executable.
#include <wayland-server.h>
#include <wayland-server-protocol.h>
#include "xdg-output-server.h"
#include "xdg-shell-server.h"
#include <stdio.h>
#include <stdlib.h>
static struct wl_display *display;
static unsigned output_version,manager_version;
static int failures,children,lifecycle,stage;
static struct wl_resource *child_resources[2],*child_outputs[2];
static struct wl_global *manager_global;
static struct wl_event_source *timer;
static void child_destroyed(struct wl_resource *r){for(int i=0;i<2;i++)if(child_resources[i]==r)child_resources[i]=NULL;}
static void destroy(struct wl_client *c,struct wl_resource *r){wl_resource_destroy(r);}
static const struct zxdg_output_v1_interface child_impl={destroy};
static void get_output(struct wl_client *c,struct wl_resource *r,uint32_t id,struct wl_resource *output){
    unsigned version=wl_resource_get_version(r);
    unsigned want=output_version<2 && manager_version>=3?2:manager_version;
    if(version!=want)failures++;
    struct wl_resource *child=wl_resource_create(c,&zxdg_output_v1_interface,version,id);
    wl_resource_set_implementation(child,&child_impl,NULL,child_destroyed);
    if(children<2){child_resources[children]=child;child_outputs[children]=output;}else failures++;
    zxdg_output_v1_send_logical_position(child,100+children*300,-50);
    zxdg_output_v1_send_logical_size(child,333,222);
    if(version>=3)wl_output_send_done(output);else zxdg_output_v1_send_done(child);
    printf("CHILD version=%u expected=%u count=%d failures=%d\n",version,want,++children,failures);fflush(stdout);
    if(lifecycle && children==2){if(stage!=3)failures++;printf("LIFECYCLE_COMPLETE failures=%d\n",failures);fflush(stdout);}
}
static const struct zxdg_output_manager_v1_interface manager_impl={destroy,get_output};
static void bind_manager(struct wl_client *c,void *data,uint32_t version,uint32_t id){
    struct wl_resource *r=wl_resource_create(c,&zxdg_output_manager_v1_interface,version,id);
    wl_resource_set_implementation(r,&manager_impl,NULL,NULL);
    printf("MANAGER version=%u\n",version);fflush(stdout);
}
static const struct wl_output_interface output_impl={destroy};
static void bind_output(struct wl_client *c,void *data,uint32_t version,uint32_t id){
    struct wl_resource *r=wl_resource_create(c,&wl_output_interface,version,id);
    wl_resource_set_implementation(r,&output_impl,NULL,NULL);
    wl_output_send_geometry(r,0,0,100,100,WL_OUTPUT_SUBPIXEL_UNKNOWN,"fixture","output",WL_OUTPUT_TRANSFORM_NORMAL);
    wl_output_send_mode(r,WL_OUTPUT_MODE_CURRENT,1200,800,60000);
    if(version>=2){wl_output_send_scale(r,2);wl_output_send_done(r);}
}
static const struct wl_surface_interface surface_impl={.destroy=destroy};
static void create_surface(struct wl_client *c,struct wl_resource *r,uint32_t id){
    struct wl_resource *surface=wl_resource_create(c,&wl_surface_interface,wl_resource_get_version(r),id);
    wl_resource_set_implementation(surface,&surface_impl,NULL,NULL);
}
static const struct wl_compositor_interface compositor_impl={.create_surface=create_surface};
static void bind_compositor(struct wl_client *c,void *data,uint32_t version,uint32_t id){
    struct wl_resource *r=wl_resource_create(c,&wl_compositor_interface,version,id);
    wl_resource_set_implementation(r,&compositor_impl,NULL,NULL);
}
static const struct xdg_wm_base_interface wm_impl={.destroy=destroy};
static void bind_wm(struct wl_client *c,void *data,uint32_t version,uint32_t id){
    struct wl_resource *r=wl_resource_create(c,&xdg_wm_base_interface,version,id);
    wl_resource_set_implementation(r,&wm_impl,NULL,NULL);
}
static int advance(void *data){
    if(!children){wl_event_source_timer_update(timer,100);return 0;}
    if(!child_resources[0])return 0;
    if(stage==0){
        wl_global_destroy(manager_global);manager_global=NULL;
        zxdg_output_v1_send_logical_size(child_resources[0],444,222);
        if(wl_resource_get_version(child_resources[0])>=3)wl_output_send_done(child_outputs[0]);
        else zxdg_output_v1_send_done(child_resources[0]);
        puts("FACTORY_REMOVED_CHILD_UPDATED");
    }else if(stage==1){
        manager_global=wl_global_create(display,&zxdg_output_manager_v1_interface,manager_version,NULL,bind_manager);
        puts("FACTORY_REANNOUNCED");
    }else if(stage==2){
        wl_global_create(display,&wl_output_interface,output_version,NULL,bind_output);
        puts("SECOND_OUTPUT_ADDED");
    }
    fflush(stdout);stage++;if(stage<3)wl_event_source_timer_update(timer,400);return 0;
}
int main(int argc,char **argv){
    if(argc!=4&&argc!=5)return 2;lifecycle=argc==5;manager_version=atoi(argv[1]);output_version=atoi(argv[2]);int reverse=atoi(argv[3]);
    if(manager_version<1||manager_version>3||output_version<1||output_version>2)return 2;
    display=wl_display_create();if(!display)return 2;
    wl_global_create(display,&wl_compositor_interface,4,NULL,bind_compositor);
    wl_display_init_shm(display);wl_global_create(display,&xdg_wm_base_interface,1,NULL,bind_wm);
    if(!reverse)manager_global=wl_global_create(display,&zxdg_output_manager_v1_interface,manager_version,NULL,bind_manager);
    wl_global_create(display,&wl_output_interface,output_version,NULL,bind_output);
    if(reverse)manager_global=wl_global_create(display,&zxdg_output_manager_v1_interface,manager_version,NULL,bind_manager);
    const char *socket=wl_display_add_socket_auto(display);if(!socket)return 2;
    printf("READY %s\n",socket);fflush(stdout);
    if(lifecycle){timer=wl_event_loop_add_timer(wl_display_get_event_loop(display),advance,NULL);wl_event_source_timer_update(timer,400);}
    wl_display_run(display);
    wl_display_destroy_clients(display);wl_display_destroy(display);return failures?1:0;
}
