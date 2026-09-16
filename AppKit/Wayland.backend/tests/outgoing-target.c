#include <gtk/gtk.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
static void received(GtkWidget *widget,GdkDragContext *context,gint x,gint y,
                     GtkSelectionData *data,guint info,guint time,gpointer unused) {
    const guchar *bytes=gtk_selection_data_get_data(data);
    gint length=gtk_selection_data_get_length(data);
    const char *expected="Darling outgoing — café";
    gboolean ok=length==(gint)strlen(expected) && bytes && !memcmp(bytes,expected,length);
    printf("RECEIVED length=%d pass=%d\n",length,ok);fflush(stdout);
    if (!getenv("HOLD_DROP")) gtk_drag_finish(context,ok,FALSE,time);
}
static gboolean dropped(GtkWidget *widget,GdkDragContext *context,gint x,gint y,
                        guint time,gpointer unused) {
    gtk_drag_get_data(widget,context,gdk_atom_intern_static_string("text/plain;charset=utf-8"),time);
    return TRUE;
}
/* A constant opaque destination makes drag-icon alpha checks independent of
 * theme, hover highlighting and text antialiasing. */
static gboolean draw_flat(GtkWidget *widget, cairo_t *cr, gpointer unused) {
    cairo_set_source_rgb(cr, 0.2, 0.2, 0.2);
    cairo_paint(cr);
    return TRUE;
}
int main(int argc,char **argv) {
    gtk_init(&argc,&argv);GtkWidget *w=gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_window_set_title(GTK_WINDOW(w),"Native outgoing target");
    gtk_window_set_default_size(GTK_WINDOW(w),300,220);
    GtkWidget *label=getenv("FLAT_TARGET") ? gtk_drawing_area_new() : gtk_label_new("Drop Darling text here");
    if (getenv("FLAT_TARGET")) g_signal_connect(label,"draw",G_CALLBACK(draw_flat),NULL);
    gtk_container_add(GTK_CONTAINER(w),label);
    GtkTargetEntry types[]={{"text/plain;charset=utf-8",0,0}};
    gtk_drag_dest_set(w,GTK_DEST_DEFAULT_MOTION | GTK_DEST_DEFAULT_HIGHLIGHT,types,1,GDK_ACTION_COPY);
    g_signal_connect(w,"drag-drop",G_CALLBACK(dropped),NULL);
    g_signal_connect(w,"drag-data-received",G_CALLBACK(received),NULL);
    gtk_widget_show_all(w);puts("READY");fflush(stdout);gtk_main();return 0;
}
