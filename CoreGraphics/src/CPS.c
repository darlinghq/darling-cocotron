/*
 This file is part of Darling.

 Copyright (C) 2026 Lubos Dolezel

 Darling is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Darling is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with Darling.  If not, see <http://www.gnu.org/licenses/>.
*/

#include <CoreGraphics/CoreGraphicsPrivate.h>
#include <errno.h>
#include <limits.h>
#include <signal.h>
#include <unistd.h>

// The CPS calls are the window system's per-process calls (becoming a foreground application, taking the
// front process). The Process Manager (HIServices) is built on them, so they live in CoreGraphics, the layer
// that holds the window system state, and do not use the Process Manager or LaunchServices. A process serial
// number is (0, pid) here, as it is for the Process Manager.

// Observed on macOS 10.14 and 26 in a session without a window server connection: a NULL serial number makes
// all three calls fail with 1003.
#define kCPSInvalidArgument 1003

// The special serial numbers of the Process Manager (kSystemProcess, kCurrentProcess).
#define kCPSSystemProcess 1
#define kCPSCurrentProcess 2

// Resolves a serial number to a live process; *system is set for the system process, which is no process of
// this window system. A serial number that names no live process is kCGErrorNoneAvailable.
static CGError resolveSerialNumber(const CPSProcessSerNum* psn, pid_t* pid, Boolean* system)
{
	*system = false;
	if (psn->hi != 0 || psn->lo == 0 || psn->lo > INT_MAX)
		return kCGErrorNoneAvailable;
	if (psn->lo == kCPSSystemProcess)
	{
		*system = true;
		return kCGErrorSuccess;
	}
	if (psn->lo == kCPSCurrentProcess)
	{
		*pid = getpid();
		return kCGErrorSuccess;
	}
	if (kill((pid_t) psn->lo, 0) != 0 && errno != EPERM)
		return kCGErrorNoneAvailable;
	*pid = (pid_t) psn->lo;
	return kCGErrorSuccess;
}

CGError _CGSRequestFrontApplication(pid_t pid, uint32_t options)
{
	if (options & ~(uint32_t) kCGSRequestFrontProcessFrontWindowOnly)
		return kCGErrorIllegalArgument;

	// The activation policy is what the application published (-1: none, as for a program that never
	// became an application of the window system, which is not refused).
	int policy = -1;

	if (_CGSGetProcessActivationPolicy(pid, &policy) != kCGErrorSuccess)
		policy = -1;
	if (policy == 2 /* prohibited */)
		return kCGErrorInvalidOperation;
	// A regular application takes the menu bar over; an agent keeps the owner that was.
	return _CGSRequestFrontProcess(pid, options | (policy == 0 /* regular */ ? kCGSRequestFrontProcessMenuBarOwner : 0));
}

int CPSGetCurrentProcess(CPSProcessSerNum* psn)
{
	if (psn == NULL)
		return kCPSInvalidArgument;
	psn->hi = 0;
	psn->lo = (uint32_t) getpid();
	return kCGErrorSuccess;
}

// The four trailing words are opaque flags and do not change the outcome. The process becomes a regular
// application of the window system: the policy it publishes is what the other processes see. Only the calling
// process can publish for itself.
int CPSEnableForegroundOperation(CPSProcessSerNum* psn, uint32_t flags1, uint32_t flags2, uint32_t flags3, uint32_t flags4)
{
	pid_t pid = 0;
	Boolean system;

	if (psn == NULL)
		return kCPSInvalidArgument;
	if (resolveSerialNumber(psn, &pid, &system) != kCGErrorSuccess || system)
		return kCGErrorNoneAvailable;
	if (pid != getpid())
		return kCGErrorCannotComplete;
	_CGSSetProcessActivationPolicy(0 /* regular */);
	return kCGErrorSuccess;
}

int CPSSetFrontProcess(CPSProcessSerNum* psn)
{
	pid_t pid = 0;
	Boolean system;
	CGError err;

	if (psn == NULL)
		return kCPSInvalidArgument;
	err = resolveSerialNumber(psn, &pid, &system);
	if (err != kCGErrorSuccess)
		return err;
	// The system process is accepted and left alone.
	if (system)
		return kCGErrorSuccess;
	return _CGSRequestFrontApplication(pid, 0);
}
