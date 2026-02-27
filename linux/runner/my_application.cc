#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"
#include <gio/gio.h>

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView *view)
{
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Function to handle dropped files
static void on_drag_data_received(GtkWidget *widget, GdkDragContext *context,
                                 gint x, gint y, GtkSelectionData *data,
                                 guint info, guint time, gpointer user_data) {
  gchar **uris = gtk_selection_data_get_uris(data);
  if (uris != NULL) {
    MyApplication* self = MY_APPLICATION(user_data);
    g_autoptr(GPtrArray) new_arguments = g_ptr_array_new_with_free_func(g_free);
    
    // Copy existing arguments
    if (self->dart_entrypoint_arguments) {
      for (int i = 0; self->dart_entrypoint_arguments[i] != NULL; i++) {
        g_ptr_array_add(new_arguments, g_strdup(self->dart_entrypoint_arguments[i]));
      }
    }
    
    // Process dropped files
    for (int i = 0; uris[i] != NULL; i++) {
      gchar *uri = uris[i];
      // Convert file URI to local path
      gchar *path = g_filename_from_uri(uri, NULL, NULL);
      if (path != NULL) {
        // Check if it's a markdown file
        if (g_str_has_suffix(path, ".md") || g_str_has_suffix(path, ".markdown") || g_str_has_suffix(path, ".txt")) {
          g_ptr_array_add(new_arguments, g_strdup("--file"));
          g_ptr_array_add(new_arguments, g_strdup(path));
          g_free(path);
          break; // Only handle the first markdown file for now
        }
        g_free(path);
      }
    }
    
    g_ptr_array_add(new_arguments, NULL);
    // Free old arguments
    g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
    // Set new arguments
    self->dart_entrypoint_arguments = (char**)g_ptr_array_free(new_arguments, FALSE);
    
    g_strfreev(uris);
  }
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "doc_searcher");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "doc_searcher");
  }

  gtk_window_set_default_size(window, 1280, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000 for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Enable drag-and-drop on the window
  gtk_drag_dest_set(GTK_WIDGET(window), GTK_DEST_DEFAULT_ALL, NULL, 0, GDK_ACTION_COPY);
  gtk_drag_dest_add_uri_targets(GTK_WIDGET(window));
  g_signal_connect(window, "drag-data-received", G_CALLBACK(on_drag_data_received), self);

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb), self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application, gchar*** arguments, int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is binary name.
  // Check if we have file arguments and handle them
  if (*arguments && *(arguments + 1)) {
    gchar** file_args = *arguments + 1;
    // Process file arguments here - pass them to Flutter
    g_autoptr(GPtrArray) new_arguments = g_ptr_array_new_with_free_func(g_free);
    // Add original arguments first
    for (int i = 1; (*arguments)[i] != nullptr; i++) {
      if (g_strcmp0((*arguments)[i], "%U") != 0) { // Skip %U placeholder
        g_ptr_array_add(new_arguments, g_strdup((*arguments)[i]));
      }
    }
    // If there are file arguments, add them with --file flag
    for (int i = 0; file_args[i] != nullptr; i++) {
      if (g_str_has_suffix(file_args[i], ".md") || g_str_has_suffix(file_args[i], ".markdown")) {
        g_ptr_array_add(new_arguments, g_strdup("--file"));
        g_ptr_array_add(new_arguments, g_strdup(file_args[i]));
        break; // Only handle the first markdown file
      }
    }
    g_ptr_array_add(new_arguments, NULL);
    self->dart_entrypoint_arguments = (char**)g_ptr_array_free(new_arguments, FALSE);
  }

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
     g_warning("Failed to register: %s", error->message);
     *exit_status = 1;
     return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  //MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  //MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line = my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID,
                                     "flags", G_APPLICATION_NON_UNIQUE,
                                     nullptr));
}
