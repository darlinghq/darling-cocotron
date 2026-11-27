/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// A stand-in for the desktop's GlobalShortcuts portal, for the host side of the
// Carbon hot key portal test. It owns org.freedesktop.portal.Desktop, answers
// Registry.Register and GlobalShortcuts.CreateSession/BindShortcuts, and logs
// every request to the given file. BindShortcuts reports that only darling-1
// was bound, then sends a stray Deactivated, an activation for the declined
// darling-2, an Activated and a duplicate Activated for darling-1, and two
// Deactivated signals for darling-1.
//
//   cc -o fake-portal fake-portal.c $(pkg-config --cflags --libs dbus-1)
//   fake-portal LOGFILE SECONDS
#include <dbus/dbus.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define NAME "org.freedesktop.portal.Desktop"
#define PATH "/org/freedesktop/portal/desktop"
#define SHORTCUTS_INTERFACE "org.freedesktop.portal.GlobalShortcuts"
#define REQUEST_INTERFACE "org.freedesktop.portal.Request"
#define SESSION_INTERFACE "org.freedesktop.portal.Session"
#define REGISTRY_INTERFACE "org.freedesktop.host.portal.Registry"

#define MAX_PATH 512

static FILE *log_file;
static char session_path[MAX_PATH];

static void log_line(const char *format, ...) {
    va_list args;
    va_start(args, format);
    vfprintf(log_file, format, args);
    va_end(args);
    fputc('\n', log_file);
    fflush(log_file);
}

static void appendStringOption(DBusMessageIter *dict, const char *key, const char *value) {
    DBusMessageIter entry, variant;

    if (!dbus_message_iter_open_container(dict, DBUS_TYPE_DICT_ENTRY, NULL, &entry))
        return;
    dbus_message_iter_append_basic(&entry, DBUS_TYPE_STRING, &key);
    dbus_message_iter_open_container(&entry, DBUS_TYPE_VARIANT, DBUS_TYPE_STRING_AS_STRING, &variant);
    dbus_message_iter_append_basic(&variant, DBUS_TYPE_STRING, &value);
    dbus_message_iter_close_container(&entry, &variant);
    dbus_message_iter_close_container(dict, &entry);
}

static void appendEmptyOptions(DBusMessageIter *arguments) {
    DBusMessageIter options;

    dbus_message_iter_open_container(arguments, DBUS_TYPE_ARRAY, "{sv}", &options);
    dbus_message_iter_close_container(arguments, &options);
}

// The portal's handles use the sender's unique name with its leading colon removed and its dots
// replaced by underscores.
static void senderToken(DBusMessage *message, char *out, size_t size) {
    const char *sender = dbus_message_get_sender(message);
    size_t i = 0, j = 0;

    if (sender == NULL || sender[0] != ':') {
        snprintf(out, size, "unknown");
        return;
    }
    for (i = 1; sender[i] != '\0' && j + 1 < size; i++)
        out[j++] = sender[i] == '.' ? '_' : sender[i];
    out[j] = '\0';
}

static void requestPath(DBusMessage *message, const char *token, char *out, size_t size) {
    char sender[128];

    senderToken(message, sender, sizeof(sender));
    snprintf(out, size, PATH "/request/%s/%s", sender, token);
}

static int findStringOption(DBusMessage *message, int wanted, const char *key,
                            char *out, size_t size) {
    DBusMessageIter iterator, array;
    int index = 0;

    out[0] = '\0';
    if (!dbus_message_iter_init(message, &iterator))
        return 0;
    while (dbus_message_iter_get_arg_type(&iterator) != DBUS_TYPE_INVALID) {
        if (index++ == wanted && dbus_message_iter_get_arg_type(&iterator) == DBUS_TYPE_ARRAY) {
            dbus_message_iter_recurse(&iterator, &array);
            while (dbus_message_iter_get_arg_type(&array) == DBUS_TYPE_DICT_ENTRY) {
                DBusMessageIter entry, variant;
                const char *entry_key = NULL, *value = NULL;

                dbus_message_iter_recurse(&array, &entry);
                if (dbus_message_iter_get_arg_type(&entry) != DBUS_TYPE_STRING)
                    break;
                dbus_message_iter_get_basic(&entry, &entry_key);
                if (!dbus_message_iter_next(&entry))
                    break;
                dbus_message_iter_recurse(&entry, &variant);
                if (strcmp(entry_key, key) == 0 &&
                    dbus_message_iter_get_arg_type(&variant) == DBUS_TYPE_STRING) {
                    dbus_message_iter_get_basic(&variant, &value);
                    if (value != NULL) {
                        snprintf(out, size, "%s", value);
                        return 1;
                    }
                }
                dbus_message_iter_next(&array);
            }
        }
        dbus_message_iter_next(&iterator);
    }
    return 0;
}

static void sendResponse(DBusConnection *connection, const char *path, unsigned code,
                         const char *session, const char *bound_id) {
    DBusMessage *signal = dbus_message_new_signal(path, REQUEST_INTERFACE, "Response");
    DBusMessageIter iterator, results, entry, variant;
    dbus_uint32_t response = code;

    dbus_message_iter_init_append(signal, &iterator);
    dbus_message_iter_append_basic(&iterator, DBUS_TYPE_UINT32, &response);
    dbus_message_iter_open_container(&iterator, DBUS_TYPE_ARRAY, "{sv}", &results);
    if (session != NULL)
        appendStringOption(&results, "session_handle", session);
    if (bound_id != NULL) {
        DBusMessageIter pair, details, list;

        if (dbus_message_iter_open_container(&results, DBUS_TYPE_DICT_ENTRY, NULL, &entry)) {
            const char *key = "shortcuts";
            dbus_message_iter_append_basic(&entry, DBUS_TYPE_STRING, &key);
            dbus_message_iter_open_container(&entry, DBUS_TYPE_VARIANT, "a(sa{sv})", &variant);
            dbus_message_iter_open_container(&variant, DBUS_TYPE_ARRAY, "(sa{sv})", &list);
            dbus_message_iter_open_container(&list, DBUS_TYPE_STRUCT, NULL, &pair);
            dbus_message_iter_append_basic(&pair, DBUS_TYPE_STRING, &bound_id);
            dbus_message_iter_open_container(&pair, DBUS_TYPE_ARRAY, "{sv}", &details);
            appendStringOption(&details, "description", "Bound Carbon hot key");
            appendStringOption(&details, "trigger_description", "Ctrl+A");
            dbus_message_iter_close_container(&pair, &details);
            dbus_message_iter_close_container(&list, &pair);
            dbus_message_iter_close_container(&variant, &list);
            dbus_message_iter_close_container(&entry, &variant);
            dbus_message_iter_close_container(&results, &entry);
        }
    }
    dbus_message_iter_close_container(&iterator, &results);
    dbus_connection_send(connection, signal, NULL);
    dbus_connection_flush(connection);
    dbus_message_unref(signal);
    log_line("RESPONSE %s code=%u", path, code);
}

static void sendShortcutSignal(DBusConnection *connection, const char *member,
                               const char *id) {
    DBusMessage *signal = dbus_message_new_signal(session_path, SHORTCUTS_INTERFACE, member);
    DBusMessageIter iterator;
    const char *path = session_path, *identifier = id;
    dbus_uint64_t timestamp = 1;

    dbus_message_iter_init_append(signal, &iterator);
    dbus_message_iter_append_basic(&iterator, DBUS_TYPE_OBJECT_PATH, &path);
    dbus_message_iter_append_basic(&iterator, DBUS_TYPE_STRING, &identifier);
    dbus_message_iter_append_basic(&iterator, DBUS_TYPE_UINT64, &timestamp);
    appendEmptyOptions(&iterator);
    dbus_connection_send(connection, signal, NULL);
    dbus_connection_flush(connection);
    dbus_message_unref(signal);
    log_line("SIGNAL %s %s", member, id);
}

static void reply(DBusConnection *connection, DBusMessage *message) {
    DBusMessage *answer = dbus_message_new_method_return(message);

    dbus_connection_send(connection, answer, NULL);
    dbus_connection_flush(connection);
    dbus_message_unref(answer);
}

static void replyWithPath(DBusConnection *connection, DBusMessage *message, const char *path) {
    DBusMessage *answer = dbus_message_new_method_return(message);
    DBusMessageIter iterator;
    const char *value = path;

    dbus_message_iter_init_append(answer, &iterator);
    dbus_message_iter_append_basic(&iterator, DBUS_TYPE_OBJECT_PATH, &value);
    dbus_connection_send(connection, answer, NULL);
    dbus_connection_flush(connection);
    dbus_message_unref(answer);
}

static DBusHandlerResult createSession(DBusConnection *connection, DBusMessage *message) {
    char handle[128], session_token[128], sender[128], request[MAX_PATH];

    findStringOption(message, 0, "handle_token", handle, sizeof(handle));
    findStringOption(message, 0, "session_handle_token", session_token, sizeof(session_token));
    if (handle[0] == '\0' || session_token[0] == '\0')
        return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;
    requestPath(message, handle, request, sizeof(request));
    senderToken(message, sender, sizeof(sender));
    snprintf(session_path, sizeof(session_path), PATH "/session/%s/%s", sender, session_token);

    log_line("CALL CreateSession handle_token=%s session_handle_token=%s", handle, session_token);
    replyWithPath(connection, message, request);
    sendResponse(connection, request, 0, session_path, NULL);
    return DBUS_HANDLER_RESULT_HANDLED;
}

static void logShortcuts(DBusMessage *message) {
    DBusMessageIter iterator, array;

    if (!dbus_message_iter_init(message, &iterator))
        return;
    /* BindShortcuts(session_handle, shortcuts, parent_window, options): the shortcuts are the second argument. */
    if (!dbus_message_iter_next(&iterator) || dbus_message_iter_get_arg_type(&iterator) != DBUS_TYPE_ARRAY)
        return;
    dbus_message_iter_recurse(&iterator, &array);
    while (dbus_message_iter_get_arg_type(&array) == DBUS_TYPE_STRUCT) {
        DBusMessageIter entry, details;
        const char *id = NULL;

        dbus_message_iter_recurse(&array, &entry);
        if (dbus_message_iter_get_arg_type(&entry) == DBUS_TYPE_STRING)
            dbus_message_iter_get_basic(&entry, &id);
        log_line("SHORTCUT %s", id == NULL ? "?" : id);
        if (dbus_message_iter_next(&entry) &&
            dbus_message_iter_get_arg_type(&entry) == DBUS_TYPE_ARRAY) {
            dbus_message_iter_recurse(&entry, &details);
            while (dbus_message_iter_get_arg_type(&details) == DBUS_TYPE_DICT_ENTRY) {
                DBusMessageIter value, variant;
                const char *key = NULL, *text = NULL;

                dbus_message_iter_recurse(&details, &value);
                if (dbus_message_iter_get_arg_type(&value) != DBUS_TYPE_STRING)
                    break;
                dbus_message_iter_get_basic(&value, &key);
                if (!dbus_message_iter_next(&value))
                    break;
                dbus_message_iter_recurse(&value, &variant);
                if (dbus_message_iter_get_arg_type(&variant) == DBUS_TYPE_STRING)
                    dbus_message_iter_get_basic(&variant, &text);
                log_line("  %s=%s", key, text == NULL ? "" : text);
                dbus_message_iter_next(&details);
            }
        }
        dbus_message_iter_next(&array);
    }
}

static DBusHandlerResult bindShortcuts(DBusConnection *connection, DBusMessage *message) {
    char handle[128], request[MAX_PATH];

    findStringOption(message, 3, "handle_token", handle, sizeof(handle));
    if (handle[0] == '\0')
        return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;
    requestPath(message, handle, request, sizeof(request));
    {
        DBusMessageIter first;
        const char *session = "?";
        if (dbus_message_iter_init(message, &first) &&
            dbus_message_iter_get_arg_type(&first) == DBUS_TYPE_OBJECT_PATH)
            dbus_message_iter_get_basic(&first, &session);
        log_line("CALL BindShortcuts session=%s parent=''", session);
    }
    logShortcuts(message);

    replyWithPath(connection, message, request);
    sendResponse(connection, request, 0, NULL, "darling-1");

    sendShortcutSignal(connection, "Deactivated", "darling-1");
    sendShortcutSignal(connection, "Activated", "darling-2");
    sendShortcutSignal(connection, "Activated", "darling-1");
    sendShortcutSignal(connection, "Activated", "darling-1");
    sendShortcutSignal(connection, "Deactivated", "darling-1");
    sendShortcutSignal(connection, "Deactivated", "darling-1");
    return DBUS_HANDLER_RESULT_HANDLED;
}

static DBusHandlerResult shortcutsMessage(DBusConnection *connection, DBusMessage *message,
                                          void *user_data) {
    (void) user_data;

    if (dbus_message_is_method_call(message, REGISTRY_INTERFACE, "Register")) {
        log_line("CALL Register");
        reply(connection, message);
        return DBUS_HANDLER_RESULT_HANDLED;
    }
    if (dbus_message_is_method_call(message, SHORTCUTS_INTERFACE, "CreateSession"))
        return createSession(connection, message);
    if (dbus_message_is_method_call(message, SHORTCUTS_INTERFACE, "BindShortcuts"))
        return bindShortcuts(connection, message);
    return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;
}

static DBusHandlerResult sessionMessage(DBusConnection *connection, DBusMessage *message,
                                        void *user_data) {
    (void) user_data;

    if (dbus_message_is_method_call(message, SESSION_INTERFACE, "Close")) {
        log_line("CALL Close %s", dbus_message_get_path(message));
        reply(connection, message);
        return DBUS_HANDLER_RESULT_HANDLED;
    }
    return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;
}

int main(int argc, char **argv) {
    DBusConnection *connection;
    DBusError error;
    DBusObjectPathVTable shortcuts = {NULL, shortcutsMessage, NULL, NULL, NULL, NULL};
    DBusObjectPathVTable sessions = {NULL, sessionMessage, NULL, NULL, NULL, NULL};
    int seconds;

    if (argc != 3) {
        fprintf(stderr, "usage: %s LOGFILE SECONDS\n", argv[0]);
        return 2;
    }
    seconds = atoi(argv[2]);
    log_file = fopen(argv[1], "w");
    if (log_file == NULL) {
        perror(argv[1]);
        return 2;
    }

    dbus_error_init(&error);
    connection = dbus_bus_get_private(DBUS_BUS_SESSION, &error);
    if (connection == NULL) {
        fprintf(stderr, "dbus_bus_get_private: %s\n", error.message);
        return 2;
    }
    dbus_connection_set_exit_on_disconnect(connection, FALSE);
    dbus_bus_request_name(connection, NAME, 0, &error);
    if (dbus_error_is_set(&error)) {
        fprintf(stderr, "request_name: %s\n", error.message);
        return 2;
    }
    dbus_connection_register_object_path(connection, PATH, &shortcuts, NULL);
    dbus_connection_register_fallback(connection, PATH "/session", &sessions, NULL);
    log_line("READY");

    while (seconds-- > 0 && dbus_connection_read_write_dispatch(connection, 1000))
        ;
    dbus_connection_close(connection);
    dbus_connection_unref(connection);
    fclose(log_file);
    return 0;
}
