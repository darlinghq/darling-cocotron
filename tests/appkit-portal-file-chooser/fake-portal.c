/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// A stand-in for the desktop's file chooser portal, for the host side of the
// portal file chooser tests. It owns org.freedesktop.portal.Desktop on the
// session bus, answers FileChooser.OpenFile and SaveFile, and appends one line
// to the log file for each call: the method name, then every argument in a
// plain text form (parent window, title, and the options one per line).
//
// The reply is the Request object's path built from the handle_token option,
// as the portal documents, and the Response signal follows after a short delay
// with the response code and the URIs given on the command line. Options:
//   --respond-first  send the Response before the method reply;
//   --impostor       first send a Response with code 0 and file:///impostor
//                    to the same path from another connection, which the
//                    client must ignore;
//   --vanish         leave the bus after the reply, without a Response;
//   --choice=ID=VALUE  answer the choice ID of the request's "choices" option with VALUE (an option id, or
//                    true or false for a check box) in the Response's "choices" (a(ss)); repeatable.
//
//   cc -o fake-portal fake-portal.c $(pkg-config --cflags --libs dbus-1)
//   fake-portal [OPTIONS] LOGFILE SECONDS CODE [URI...]
#include <dbus/dbus.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define NAME "org.freedesktop.portal.Desktop"
#define INTERFACE "org.freedesktop.portal.FileChooser"

static FILE *log_file;
#define MAX_CHOICES 16
static char *choice_ids[MAX_CHOICES], *choice_values[MAX_CHOICES];
static int choice_count;

static void dump(DBusMessageIter *iterator, int depth);

static void dump_value(DBusMessageIter *iterator, int depth)
{
	int type = dbus_message_iter_get_arg_type(iterator);

	switch (type)
	{
	case DBUS_TYPE_STRING:
	case DBUS_TYPE_OBJECT_PATH:
	{
		const char *s;
		dbus_message_iter_get_basic(iterator, &s);
		fprintf(log_file, "%c'%s'", type == DBUS_TYPE_STRING ? 's' : 'o', s);
		break;
	}
	case DBUS_TYPE_BOOLEAN:
	{
		dbus_bool_t b;
		dbus_message_iter_get_basic(iterator, &b);
		fprintf(log_file, "%s", b ? "true" : "false");
		break;
	}
	case DBUS_TYPE_UINT32:
	{
		dbus_uint32_t u;
		dbus_message_iter_get_basic(iterator, &u);
		fprintf(log_file, "%u", u);
		break;
	}
	case DBUS_TYPE_BYTE:
	{
		unsigned char c;
		dbus_message_iter_get_basic(iterator, &c);
		fprintf(log_file, "%02x", c);
		break;
	}
	case DBUS_TYPE_ARRAY:
	case DBUS_TYPE_STRUCT:
	case DBUS_TYPE_DICT_ENTRY:
	case DBUS_TYPE_VARIANT:
	{
		DBusMessageIter sub;
		const char open = type == DBUS_TYPE_ARRAY ? '[' : type == DBUS_TYPE_VARIANT ? '<' : '(';
		const char close = type == DBUS_TYPE_ARRAY ? ']' : type == DBUS_TYPE_VARIANT ? '>' : ')';
		int first = 1;

		dbus_message_iter_recurse(iterator, &sub);
		fputc(open, log_file);
		while (dbus_message_iter_get_arg_type(&sub) != DBUS_TYPE_INVALID)
		{
			if (!first)
				fputc(type == DBUS_TYPE_DICT_ENTRY ? ':' : ',', log_file);
			first = 0;
			dump_value(&sub, depth + 1);
			dbus_message_iter_next(&sub);
		}
		fputc(close, log_file);
		break;
	}
	default:
		fprintf(log_file, "?%c", type);
	}
}

// One line per top-level argument and per option.
static void dump(DBusMessageIter *iterator, int depth)
{
	int index = 0;

	while (dbus_message_iter_get_arg_type(iterator) != DBUS_TYPE_INVALID)
	{
		if (dbus_message_iter_get_arg_type(iterator) == DBUS_TYPE_ARRAY &&
		    dbus_message_iter_get_element_type(iterator) == DBUS_TYPE_DICT_ENTRY)
		{
			DBusMessageIter array;
			dbus_message_iter_recurse(iterator, &array);
			while (dbus_message_iter_get_arg_type(&array) != DBUS_TYPE_INVALID)
			{
				fprintf(log_file, "  option ");
				dump_value(&array, 0);
				fputc('\n', log_file);
				dbus_message_iter_next(&array);
			}
		}
		else
		{
			fprintf(log_file, "  arg%d ", index);
			dump_value(iterator, 0);
			fputc('\n', log_file);
		}
		index++;
		dbus_message_iter_next(iterator);
	}
}

// The token of the handle_token option, or NULL.
static const char *find_token(DBusMessage *message)
{
	DBusMessageIter iterator, array;
	int index = 0;

	if (!dbus_message_iter_init(message, &iterator))
		return NULL;
	while (dbus_message_iter_get_arg_type(&iterator) != DBUS_TYPE_INVALID)
	{
		if (index++ == 2 && dbus_message_iter_get_arg_type(&iterator) == DBUS_TYPE_ARRAY)
		{
			dbus_message_iter_recurse(&iterator, &array);
			while (dbus_message_iter_get_arg_type(&array) == DBUS_TYPE_DICT_ENTRY)
			{
				DBusMessageIter entry, variant;
				const char *key = NULL, *value = NULL;

				dbus_message_iter_recurse(&array, &entry);
				dbus_message_iter_get_basic(&entry, &key);
				dbus_message_iter_next(&entry);
				dbus_message_iter_recurse(&entry, &variant);
				if (strcmp(key, "handle_token") == 0 &&
				    dbus_message_iter_get_arg_type(&variant) == DBUS_TYPE_STRING)
				{
					dbus_message_iter_get_basic(&variant, &value);
					return value;
				}
				dbus_message_iter_next(&array);
			}
		}
		dbus_message_iter_next(&iterator);
	}
	return NULL;
}

static void send_response(DBusConnection *connection, const char *path, unsigned code,
			  int uri_count, char **uris)
{
	DBusMessage *signal = dbus_message_new_signal(path, "org.freedesktop.portal.Request", "Response");
	DBusMessageIter iterator, array, entry, variant, list;
	dbus_uint32_t response = code;
	const char *key = "uris";
	int i;

	dbus_message_iter_init_append(signal, &iterator);
	dbus_message_iter_append_basic(&iterator, DBUS_TYPE_UINT32, &response);
	dbus_message_iter_open_container(&iterator, DBUS_TYPE_ARRAY, "{sv}", &array);
	if (uri_count > 0)
	{
		dbus_message_iter_open_container(&array, DBUS_TYPE_DICT_ENTRY, NULL, &entry);
		dbus_message_iter_append_basic(&entry, DBUS_TYPE_STRING, &key);
		dbus_message_iter_open_container(&entry, DBUS_TYPE_VARIANT, "as", &variant);
		dbus_message_iter_open_container(&variant, DBUS_TYPE_ARRAY, "s", &list);
		for (i = 0; i < uri_count; i++)
			dbus_message_iter_append_basic(&list, DBUS_TYPE_STRING, &uris[i]);
		dbus_message_iter_close_container(&variant, &list);
		dbus_message_iter_close_container(&entry, &variant);
		dbus_message_iter_close_container(&array, &entry);
	}
	if (choice_count > 0)
	{
		const char *choices_key = "choices";
		DBusMessageIter pairs, pair;

		dbus_message_iter_open_container(&array, DBUS_TYPE_DICT_ENTRY, NULL, &entry);
		dbus_message_iter_append_basic(&entry, DBUS_TYPE_STRING, &choices_key);
		dbus_message_iter_open_container(&entry, DBUS_TYPE_VARIANT, "a(ss)", &variant);
		dbus_message_iter_open_container(&variant, DBUS_TYPE_ARRAY, "(ss)", &pairs);
		for (i = 0; i < choice_count; i++)
		{
			dbus_message_iter_open_container(&pairs, DBUS_TYPE_STRUCT, NULL, &pair);
			dbus_message_iter_append_basic(&pair, DBUS_TYPE_STRING, &choice_ids[i]);
			dbus_message_iter_append_basic(&pair, DBUS_TYPE_STRING, &choice_values[i]);
			dbus_message_iter_close_container(&pairs, &pair);
		}
		dbus_message_iter_close_container(&variant, &pairs);
		dbus_message_iter_close_container(&entry, &variant);
		dbus_message_iter_close_container(&array, &entry);
	}
	dbus_message_iter_close_container(&iterator, &array);
	dbus_connection_send(connection, signal, NULL);
	dbus_connection_flush(connection);
	dbus_message_unref(signal);
}

int main(int argc, char **argv)
{
	int first_arg = 1, respond_first = 0, impostor = 0, vanish = 0;
	DBusConnection *other = NULL;
	DBusError error;
	DBusConnection *connection;
	time_t end;
	unsigned code;

	for (; first_arg < argc && strncmp(argv[first_arg], "--", 2) == 0; first_arg++)
	{
		if (strcmp(argv[first_arg], "--respond-first") == 0)
			respond_first = 1;
		else if (strcmp(argv[first_arg], "--impostor") == 0)
			impostor = 1;
		else if (strcmp(argv[first_arg], "--vanish") == 0)
			vanish = 1;
		else if (strncmp(argv[first_arg], "--choice=", 9) == 0 && choice_count < MAX_CHOICES)
		{
			char *id = strdup(argv[first_arg] + 9), *value = strchr(id, '=');

			if (value == NULL)
				return 2;
			*value++ = 0;
			choice_ids[choice_count] = id;
			choice_values[choice_count++] = value;
		}
		else
			return 2;
	}
	if (argc < first_arg + 3)
	{
		fprintf(stderr, "usage: %s [OPTIONS] LOGFILE SECONDS CODE [URI...]\n", argv[0]);
		return 2;
	}
	log_file = fopen(argv[first_arg], "a");
	if (log_file == NULL)
		return 2;
	setvbuf(log_file, NULL, _IOLBF, 0);
	end = time(NULL) + atoi(argv[first_arg + 1]);
	code = (unsigned) atoi(argv[first_arg + 2]);

	dbus_error_init(&error);
	connection = dbus_bus_get(DBUS_BUS_SESSION, &error);
	if (connection == NULL)
		return 1;
	if (dbus_bus_request_name(connection, NAME, 0, &error) != DBUS_REQUEST_NAME_REPLY_PRIMARY_OWNER)
		return 1;
	if (impostor && (other = dbus_bus_get_private(DBUS_BUS_SESSION, &error)) == NULL)
		return 1;
	fprintf(log_file, "READY\n");

	while (time(NULL) < end)
	{
		DBusMessage *message;

		dbus_connection_read_write(connection, 100);
		while ((message = dbus_connection_pop_message(connection)) != NULL)
		{
			if (dbus_message_is_method_call(message, INTERFACE, "OpenFile") ||
			    dbus_message_is_method_call(message, INTERFACE, "SaveFile"))
			{
				DBusMessageIter iterator;
				const char *token = find_token(message);
				const char *sender = dbus_message_get_sender(message);
				char path[512];
				char *p;
				DBusMessage *reply;
				const char *path_pointer = path;

				snprintf(path, sizeof(path), "/org/freedesktop/portal/desktop/request/%s/%s",
					 sender + 1, token != NULL ? token : "none");
				for (p = path; *p; p++)
					if (*p == '.')
						*p = '_';

				fprintf(log_file, "CALL %s\n", dbus_message_get_member(message));
				dbus_message_iter_init(message, &iterator);
				dump(&iterator, 0);
				fprintf(log_file, "END\n");

				if (impostor)
				{
					char *fake_uri = "file:///impostor";
					send_response(other, path, 0, 1, &fake_uri);
					usleep(100000);
				}
				if (respond_first)
					send_response(connection, path, code, argc - first_arg - 3,
						      argv + first_arg + 3);
				reply = dbus_message_new_method_return(message);
				dbus_message_iter_init_append(reply, &iterator);
				dbus_message_iter_append_basic(&iterator, DBUS_TYPE_OBJECT_PATH, &path_pointer);
				dbus_connection_send(connection, reply, NULL);
				dbus_connection_flush(connection);
				dbus_message_unref(reply);
				if (vanish)
				{
					fprintf(log_file, "VANISH\n");
					return 0;
				}
				if (!respond_first)
				{
					usleep(300000);
					send_response(connection, path, code, argc - first_arg - 3,
						      argv + first_arg + 3);
				}
			}
			if (message != NULL)
				dbus_message_unref(message);
		}
	}
	return 0;
}
