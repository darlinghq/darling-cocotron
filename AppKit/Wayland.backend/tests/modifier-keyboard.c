// Native Linux fixture: inject physical evdev transitions, with authoritative
// XKB modifier updates only when the state changes. Run in a private compositor.
#define _GNU_SOURCE
#include <wayland-client.h>
#include <xkbcommon/xkbcommon.h>
#include "virtual-keyboard-client.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
static struct wl_seat *seat;
static struct zwp_virtual_keyboard_manager_v1 *manager;
static void global(void *data, struct wl_registry *r, uint32_t id,
                   const char *name, uint32_t version) {
    if (!strcmp(name, "wl_seat")) seat = wl_registry_bind(r,id,&wl_seat_interface,1);
    if (!strcmp(name,"zwp_virtual_keyboard_manager_v1"))
        manager = wl_registry_bind(r,id,&zwp_virtual_keyboard_manager_v1_interface,1);
}
static void removed(void *data,struct wl_registry *r,uint32_t id) {}
static const struct wl_registry_listener listener = {global,removed};
int main(int argc,char **argv) {
    struct wl_display *d=wl_display_connect(NULL); assert(d);
    struct wl_registry *r=wl_display_get_registry(d);
    wl_registry_add_listener(r,&listener,NULL); assert(wl_display_roundtrip(d)>=0);
    assert(seat && manager);
    struct xkb_context *c=xkb_context_new(XKB_CONTEXT_NO_FLAGS);
    struct xkb_rule_names names={.layout="us,de"};
    struct xkb_keymap *map=xkb_keymap_new_from_names(c,&names,0); assert(map);
    struct xkb_state *state=xkb_state_new(map); assert(state);
    char *text=xkb_keymap_get_as_string(map,XKB_KEYMAP_FORMAT_TEXT_V1);
    const char *path=getenv("KEYMAP_FILE");
    if(path){FILE *out=fopen(path,"wx");assert(out);assert(fwrite(text,1,strlen(text)+1,out)==strlen(text)+1);assert(fclose(out)==0);}
    int fd=memfd_create("modifier-test",MFD_CLOEXEC); assert(fd>=0);
    size_t size=strlen(text)+1; assert(write(fd,text,size)==(ssize_t)size);
    struct zwp_virtual_keyboard_v1 *k=zwp_virtual_keyboard_manager_v1_create_virtual_keyboard(manager,seat);
    zwp_virtual_keyboard_v1_keymap(k,WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1,fd,size);
    close(fd);free(text);assert(wl_display_roundtrip(d)>=0);usleep(600000);
    puts("KEYBOARD_READY");fflush(stdout);
    for(int i=1;i<argc;i+=2) {
        assert(i+1<argc);int value=atoi(argv[i+1]);assert(value>=0);
        if(!strcmp(argv[i],"sleep")){usleep(value*1000);continue;}
        int down=!strcmp(argv[i],"down");assert(down||!strcmp(argv[i],"up"));
        struct timespec now;clock_gettime(CLOCK_MONOTONIC,&now);
        zwp_virtual_keyboard_v1_key(k,now.tv_sec*1000+now.tv_nsec/1000000,value,down);
        enum xkb_state_component changed=xkb_state_update_key(state,value+8,down?XKB_KEY_DOWN:XKB_KEY_UP);
        if(changed) zwp_virtual_keyboard_v1_modifiers(k,
            xkb_state_serialize_mods(state,XKB_STATE_MODS_DEPRESSED),
            xkb_state_serialize_mods(state,XKB_STATE_MODS_LATCHED),
            xkb_state_serialize_mods(state,XKB_STATE_MODS_LOCKED),
            xkb_state_serialize_layout(state,XKB_STATE_LAYOUT_EFFECTIVE));
        assert(wl_display_roundtrip(d)>=0);
        printf("PHYSICAL key=%d down=%d changed=%u\n",value,down,changed);fflush(stdout);
    }
    usleep(200000);
    zwp_virtual_keyboard_v1_destroy(k);assert(wl_display_roundtrip(d)>=0);
    xkb_state_unref(state);xkb_keymap_unref(map);xkb_context_unref(c);
    wl_registry_destroy(r);wl_seat_destroy(seat);
    zwp_virtual_keyboard_manager_v1_destroy(manager);wl_display_disconnect(d);
    return 0;
}
