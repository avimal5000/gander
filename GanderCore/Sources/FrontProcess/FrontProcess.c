#include "FrontProcess.h"

#include <ApplicationServices/ApplicationServices.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

// Weak imports: on a macOS without these calls they resolve to NULL and Gander still launches, with the caller's
// fallback doing the activation (SPEC D53). scripts/release.sh fails if the shipped binary imports them strongly.
extern OSStatus GetProcessForPID(pid_t pid, ProcessSerialNumber *psn) __attribute__((weak_import));
extern OSStatus SetFrontProcessWithOptions(const ProcessSerialNumber *inProcess, OptionBits inOptions)
    __attribute__((weak_import));

int GanderFrontWindowOnly(pid_t processID) {
    if (GetProcessForPID == NULL || SetFrontProcessWithOptions == NULL) {
        return unimpErr;
    }
    ProcessSerialNumber process;
    OSStatus status = GetProcessForPID(processID, &process);
    if (status != noErr) {
        return (int)status;
    }
    return (int)SetFrontProcessWithOptions(&process, kSetFrontProcessFrontWindowOnly);
}

#pragma clang diagnostic pop
