/* Native GTK3 drag source for the isolated Wayland integration fixture.
 * DROP_MODE: accept, leave, prepare-reject, unsupported, move-only, oversize.
 * Run only on the private compositor used by droptest.m. */
#include <gtk/gtk.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
static const char *mode;
static void get_data(GtkWidget *w,GdkDragContext *c,GtkSelectionData *s,guint info,guint time,gpointer unused) {
    if (!strcmp(mode,"timeout")) sleep(8);
    const char *text=getenv("FILE_DRAG") ? getenv("FILE_WIRE") : "Native drop: ăîșț 日本語";
    if (!strcmp(mode,"oversize")) {
        size_t n=17*1024*1024; char *bytes=g_malloc(n); memset(bytes,'x',n);
        gtk_selection_data_set(s,gtk_selection_data_get_target(s),8,(const guchar*)bytes,n);g_free(bytes);
    } else gtk_selection_data_set(s,gtk_selection_data_get_target(s),8,(const guchar*)text,strlen(text));
    puts("SOURCE_SEND");fflush(stdout);
}
static void begin(GtkWidget *w,GdkDragContext *c,gpointer unused) {puts("SOURCE_BEGIN");fflush(stdout);}
static void end(GtkWidget *w,GdkDragContext *c,gpointer unused) {printf("SOURCE_END action=%u\n",gdk_drag_context_get_selected_action(c));fflush(stdout);}
static void deleted(GtkWidget*w,GdkDragContext*c,gpointer unused) { puts("SOURCE_DELETE_REQUEST");fflush(stdout); }
static gboolean failed(GtkWidget*w,GdkDragContext*c,GtkDragResult result,gpointer unused) {printf("SOURCE_FAILED result=%d\n",result);fflush(stdout);return FALSE;}
int main(int argc,char **argv) {
    mode=getenv("DROP_MODE");if(!mode)mode="accept";
    gtk_init(&argc,&argv);
    GtkWidget *window=gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_window_set_title(GTK_WINDOW(window),"Native drop source");gtk_window_set_default_size(GTK_WINDOW(window),250,200);
    GtkWidget *label=gtk_event_box_new();
    gtk_container_add(GTK_CONTAINER(label),gtk_label_new("Drag this text to the green target"));
    gtk_container_add(GTK_CONTAINER(window),label);
    GtkTargetEntry target={(gchar*)(!strcmp(mode,"unsupported")?"application/x-unsupported-test":(getenv("FILE_DRAG")?"text/uri-list":"text/plain;charset=utf-8")),0,0};
    gtk_drag_source_set(label,GDK_BUTTON1_MASK,&target,1,(!strcmp(mode,"move-only") || !strcmp(mode,"move-accept"))?GDK_ACTION_MOVE:GDK_ACTION_COPY);
    g_signal_connect(label,"drag-begin",G_CALLBACK(begin),NULL);
    g_signal_connect(label,"drag-data-get",G_CALLBACK(get_data),NULL);
    g_signal_connect(label,"drag-data-delete",G_CALLBACK(deleted),NULL);
    g_signal_connect(label,"drag-end",G_CALLBACK(end),NULL);
    g_signal_connect(label,"drag-failed",G_CALLBACK(failed),NULL);
    gtk_widget_show_all(window);puts("SOURCE_READY");fflush(stdout);gtk_main();return 0;
}
