package com.sethikadv.snazy

import android.content.Context

/**
 * Everything PerformanceManager does (governor/clock unlocking) stops the
 * chip from being artificially slow. It does not raise the frame ceiling a
 * game engine actually renders at. GameBoostManager is the piece that
 * targets FPS directly, using the same techniques OEM "Game Turbo" /
 * "Game Booster" system apps use under the hood — all of them real,
 * verifiable shell actions gated behind root or a granted Shizuku session:
 *
 *  1. Forced GPU rendering — SurfaceFlinger does less work per frame.
 *     (Window/transition/animator animation scales are deliberately left
 *     alone — Snazy does not change those system settings during boost.)
 *  2. The game's own process AND every render/GPU thread inside it moved
 *     into the "top-app" cpuset (the big-core cluster Android reserves for
 *     the foreground app) and given a real-time scheduling class — so the
 *     kernel scheduler stops timeslicing it against background work.
 *  3. A best-effort peak-refresh-rate request, silently ignored on devices
 *     that don't expose the setting.
 *
 * Nothing here claims to add GPU horsepower the chip doesn't have — it
 * makes sure the game actually gets the horsepower that exists, which is
 * where most "optimizer" apps stop short.
 */
object GameBoostManager {

    private const val BOOST_FLAG = "/data/local/tmp/.snazy_boost"

    // ---------------- One-shot system settings (GPU render only) ----------------
    //
    // Deliberately does NOT touch window_animation_scale,
    // transition_animation_scale, or animator_duration_scale — boosting
    // must never change the device's UI animation speed.

    /** Forces GPU rendering and (best-effort) requests a higher refresh rate. */
    fun buildApplyRenderBoostCommand(): String {
        val sb = StringBuilder()
        sb.append("settings put global force_gpu_rendering 1 2>/dev/null; ")
        // Best-effort: only takes effect on the handful of OEMs (mostly
        // Pixel) that expose this global key; silently no-ops elsewhere.
        sb.append("settings put system peak_refresh_rate 240 2>/dev/null; ")
        sb.append("settings put system min_refresh_rate 90 2>/dev/null; ")
        return sb.toString()
    }

    /** Restores exactly what boost changed above — nothing animation-related to restore. */
    fun buildRestoreRenderCommand(context: Context): String {
        val sb = StringBuilder()
        sb.append("settings put global force_gpu_rendering 0 2>/dev/null; ")
        sb.append("settings delete system peak_refresh_rate 2>/dev/null; ")
        sb.append("settings delete system min_refresh_rate 2>/dev/null; ")
        return sb.toString()
    }

    // ---------------- Thread-priority / cpuset boost loop ----------------

    /**
     * Builds the detached polling loop that repeatedly finds [pkg]'s
     * running process, then pushes its main PID and every thread under it
     * into the top-app cpuset (the cluster reserved for the foreground
     * app). Re-runs every 3s because game engines spawn new render/worker
     * threads throughout a session — a one-shot pass would miss threads
     * created after boost was applied.
     *
     * Mirrors the existing freeze-loop pattern in MainActivity: a flag
     * file gates a `nohup sh -c '...' &` loop detached from Snazy's own
     * process, so it keeps running while the game is foregrounded.
     *
     * Scheduling note (read this before changing priorities again):
     * `chrt -f` (SCHED_FIFO) is real-time — a FIFO thread only yields the
     * CPU when it blocks or a higher-priority RT thread preempts it, so it
     * can fully starve every normal-priority (SCHED_OTHER) thread sharing
     * that core, including `ksoftirqd` — the kernel thread that finishes
     * processing incoming network packets once the fast interrupt path is
     * saturated. A spinning RT render thread starving ksoftirqd shows up
     * exactly as **higher, jittery in-game ping while Boost is active** —
     * which is what real-world testing surfaced with the previous
     * `chrt -f -p 40` version below, even after it was narrowed from
     * "every thread" down to just render threads.
     *
     * Fix: no `chrt`/SCHED_FIFO anywhere in this loop anymore. Render
     * threads still get a strong scheduling edge via `renice` (nice
     * priority), which competes fairly for CPU time instead of hard-
     * blocking other work — it can't starve ksoftirqd or anything else,
     * so it can't reproduce the ping spike. Every thread also still moves
     * into the top-app cpuset (cheap, low-risk, real benefit, unrelated to
     * the scheduling class and not implicated in the ping issue).
     */
    fun buildBoostLoopCommand(pkg: String): String {
        val body = """
            while [ -f $BOOST_FLAG ]; do
              PID=${'$'}(pidof -s $pkg 2>/dev/null)
              if [ -z "${'$'}PID" ]; then
                PID=${'$'}(ps -A -o pid,args 2>/dev/null | grep $pkg | grep -v grep | awk '{print ${'$'}1}' | head -n1)
              fi
              if [ -n "${'$'}PID" ]; then
                echo ${'$'}PID > /dev/cpuset/top-app/tasks 2>/dev/null
                for t in /proc/${'$'}PID/task/*; do
                  tid=${'$'}(basename ${'$'}t)
                  echo ${'$'}tid > /dev/cpuset/top-app/tasks 2>/dev/null
                  name=${'$'}(cat /proc/${'$'}PID/task/${'$'}tid/comm 2>/dev/null)
                  case "${'$'}name" in
                    RenderThread|*GLThread*|*UnityMain*|mali-render*|*RenderEngine*)
                      renice -n -19 -p ${'$'}tid 2>/dev/null
                      ;;
                    *)
                      renice -n -5 -p ${'$'}tid 2>/dev/null
                      ;;
                  esac
                done
              fi
              sleep 3
            done
        """.trimIndent()
        return "echo 1 > $BOOST_FLAG; (nohup sh -c '$body' > /dev/null 2>&1 &) ; exit 0"
    }

    fun buildStopBoostLoopCommand(): String = "rm -f $BOOST_FLAG"
}
