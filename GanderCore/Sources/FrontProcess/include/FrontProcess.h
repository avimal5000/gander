#ifndef GANDER_FRONT_PROCESS_H
#define GANDER_FRONT_PROCESS_H

#include <sys/types.h>

/// Brings the app with this process ID to the front with only its frontmost window, the way a click on one of its
/// windows does (SPEC D53). Activation through NSRunningApplication instead brings the app's main and key windows,
/// and an app such as Terminal then also brings the window last typed in, on another display.
///
/// Wraps Carbon's GetProcessForPID and SetFrontProcessWithOptions(kSetFrontProcessFrontWindowOnly). They are public
/// but deprecated, and Swift cannot call APIs deprecated as of macOS 10.9, hence this C file.
///
/// Returns 0 when the request was accepted, else the OSStatus (unimpErr, -4, when this macOS no longer has the calls).
/// Acceptance does not mean the app came to the front: the caller verifies that.
int GanderFrontWindowOnly(pid_t processID);

#endif
