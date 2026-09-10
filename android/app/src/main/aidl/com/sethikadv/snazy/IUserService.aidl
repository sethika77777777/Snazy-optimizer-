// Snazy Optimizer — Shizuku privileged bridge.
//
// This interface is bound out-of-process by Shizuku (see ShizukuManager.kt)
// and runs with "shell" (adb) or "root" identity depending on how the user
// started Shizuku/Sui. It lets non-rooted users reach the same real
// shell-level actions (am force-stop, cpufreq governor writes, pm enable)
// that rooted users get through `su`, without Snazy ever claiming to be
// something it isn't: no root is granted here, only whatever privilege the
// user's own Shizuku/Sui session already has.
package com.sethikadv.snazy;

interface IUserService {

    // Reserved by the Shizuku API itself — DO NOT rename or renumber.
    // Shizuku transacts this code directly when the service is unbound
    // (see Shizuku.unbindUserService(..., remove = true)) so the privileged
    // process can clean up and exit instead of lingering.
    void destroy() = 16777114;

    // Runs a single shell command (via `sh -c`) with the caller's Shizuku
    // privilege and returns combined stdout+stderr. Exceptions on the far
    // side are caught and returned as a string prefixed with "ERROR:" so a
    // single bad command can never crash the privileged process.
    String exec(String command) = 1;

    // Same as exec(), but only reports whether the process exited 0 —
    // cheaper when the caller doesn't need the output text.
    boolean execSilent(String command) = 2;
}
