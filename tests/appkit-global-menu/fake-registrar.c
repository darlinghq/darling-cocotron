/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// A stand-in for a desktop's application menu registrar, for the host side of
// the global menu tests. It owns com.canonical.AppMenu.Registrar on the
// session bus and appends one line per call to the log file:
//
//   RegisterWindow <sender> <window id> <object path>
//   UnregisterWindow <sender> <window id>
//
// It exits after the number of seconds given, or when the file named by the
// third argument appears.
//
//   cc -o fake-registrar fake-registrar.c $(pkg-config --cflags --libs dbus-1)
//   fake-registrar LOGFILE SECONDS [STOPFILE]
#include <dbus/dbus.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define NAME "com.canonical.AppMenu.Registrar"
#define INTERFACE "com.canonical.AppMenu.Registrar"

int main(int argc, char **argv)
{
	if (argc < 3)
	{
		fprintf(stderr, "usage: %s LOGFILE SECONDS [STOPFILE]\n", argv[0]);
		return 2;
	}

	FILE *log = fopen(argv[1], "a");
	time_t end = time(NULL) + atoi(argv[2]);
	DBusError error;
	DBusConnection *connection;

	if (log == NULL)
		return 2;
	setvbuf(log, NULL, _IOLBF, 0);

	dbus_error_init(&error);
	connection = dbus_bus_get(DBUS_BUS_SESSION, &error);
	if (connection == NULL)
	{
		fprintf(stderr, "no session bus: %s\n", error.message);
		return 1;
	}
	if (dbus_bus_request_name(connection, NAME, 0, &error) != DBUS_REQUEST_NAME_REPLY_PRIMARY_OWNER)
	{
		fprintf(stderr, "cannot own %s\n", NAME);
		return 1;
	}
	fprintf(log, "READY\n");

	while (time(NULL) < end && (argc < 4 || access(argv[3], F_OK) != 0))
	{
		DBusMessage *message;

		dbus_connection_read_write(connection, 100);
		while ((message = dbus_connection_pop_message(connection)) != NULL)
		{
			if (dbus_message_is_method_call(message, INTERFACE, "RegisterWindow"))
			{
				dbus_uint32_t window = 0;
				const char *path = "";

				dbus_message_get_args(message, NULL, DBUS_TYPE_UINT32, &window, DBUS_TYPE_OBJECT_PATH, &path,
					DBUS_TYPE_INVALID);
				fprintf(log, "RegisterWindow %s %u %s\n", dbus_message_get_sender(message), window, path);
			}
			else if (dbus_message_is_method_call(message, INTERFACE, "UnregisterWindow"))
			{
				dbus_uint32_t window = 0;

				dbus_message_get_args(message, NULL, DBUS_TYPE_UINT32, &window, DBUS_TYPE_INVALID);
				fprintf(log, "UnregisterWindow %s %u\n", dbus_message_get_sender(message), window);
			}
			dbus_message_unref(message);
		}
	}
	return 0;
}
