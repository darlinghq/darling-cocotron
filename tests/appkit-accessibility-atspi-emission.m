// Copyright (C) 2026 Lubos Dolezel
//
// The optional AT-SPI bridge emits org.a11y.atspi.Event.Object signals with the (siiva{sv}) body published by
// at-spi2-core. The test connects to a private bus supplied in AT_SPI_BUS_ADDRESS, asks AppKit for that same
// address, emits a signal and reads it back. No application-specific state is involved.
//
// Run in a private bus, for example:
//   addr=$(dbus-daemon --session --print-address --fork)
//   AT_SPI_BUS_ADDRESS="$addr" ./appkit-accessibility-atspi-emission
#import <AppKit/NSAccessibility+Private.h>
#import <dbus/dbus.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures;

static void Check(bool condition, const char *message)
{
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message);
        failures++;
    }
}

int main(void)
{
    const char *address = getenv("AT_SPI_BUS_ADDRESS");
    if (address == NULL || *address == '\0') {
        fprintf(stderr, "SKIP: AT_SPI_BUS_ADDRESS is not set\n");
        return 0;
    }

    char *reported = NSAccessibilityATSPIBusAddress();
    Check(reported != NULL && strcmp(reported, address) == 0, "the bus address is not honored");

    DBusError error;
    dbus_error_init(&error);
    DBusConnection *bus = dbus_connection_open_private(address, &error);
    Check(bus != NULL, "could not open the test bus");
    if (bus == NULL) {
        dbus_error_free(&error);
        free(reported);
        return 1;
    }
    dbus_bus_add_match(bus, "type='signal',interface='org.a11y.atspi.Event.Object'", &error);
    Check(!dbus_error_is_set(&error), "could not install the signal match");
    dbus_error_free(&error);
    dbus_connection_flush(bus);

    NSAccessibilityATSPIEvent("StateChanged", "focused", 1, "0");

    DBusMessage *message = NULL;
    for (int i = 0; i < 100 && message == NULL; i++) {
        dbus_connection_read_write_dispatch(bus, 20);
        while ((message = dbus_connection_pop_message(bus)) != NULL) {
            if (dbus_message_is_signal(message, "org.a11y.atspi.Event.Object", "StateChanged"))
                break;
            dbus_message_unref(message);
            message = NULL;
        }
    }
    Check(message != NULL, "no StateChanged signal was received");
    if (message != NULL) {
        Check(strcmp(dbus_message_get_path(message), "/org/a11y/atspi/accessible/root") == 0,
              "wrong object path");
        Check(strcmp(dbus_message_get_signature(message), "siiva{sv}") == 0,
              "wrong signal signature");

        DBusMessageIter arguments;
        const char *detail = NULL;
        dbus_bool_t parsed = dbus_message_iter_init(message, &arguments)
            && dbus_message_iter_get_arg_type(&arguments) == DBUS_TYPE_STRING;
        if (parsed)
            dbus_message_iter_get_basic(&arguments, &detail);
        parsed = parsed && dbus_message_iter_next(&arguments)
            && dbus_message_iter_get_arg_type(&arguments) == DBUS_TYPE_INT32;
        int enabled = 0;
        if (parsed)
            dbus_message_iter_get_basic(&arguments, &enabled);
        Check(parsed && detail != NULL && strcmp(detail, "focused") == 0 && enabled == 1,
              "wrong StateChanged body");
        dbus_message_unref(message);
    }

    dbus_connection_close(bus);
    dbus_connection_unref(bus);
    free(reported);
    if (failures == 0)
        printf("PASS: AT-SPI signal emission\n");
    return failures ? 1 : 0;
}
