package com.sethikadv.snazy

/**
 * Reads a real, current FPS value for [pkg] from Android's own per-frame
 * timing data. [exec] must be a privileged (root/Shizuku) shell call — this
 * is all gated behind the DUMP permission, same as `adb shell`.
 *
 * Two data sources, tried in order:
 *
 * 1. **SurfaceFlinger** (`dumpsys SurfaceFlinger --latency <layer>`) — the
 *    compositor's own per-frame present timestamps for [pkg]'s actual
 *    rendering surface. This is the one that matters for games: almost
 *    every game draws through a SurfaceView / GLSurfaceView / Vulkan
 *    swapchain, which is composited straight to the display by
 *    SurfaceFlinger *outside* the normal View hierarchy. That means the
 *    real gameplay frames never reach source (2) below at all — checking
 *    SurfaceFlinger is the only way to see them.
 *
 * 2. **HWUI gfxinfo** (`dumpsys gfxinfo <pkg> framestats`) — kept as a
 *    fallback for apps/screens that render through ordinary Views (menus,
 *    non-game apps), where there's no separate compositor layer to read.
 *
 * No synthetic or interpolated numbers from either path: if a command
 * fails, the target app isn't running/drawing, or fewer than 2 valid frame
 * timestamps are available, this returns null and the overlay shows "--"
 * rather than guessing.
 */
object FpsReader {

    // Package -> last-known-good SurfaceFlinger layer name, so we don't
    // have to re-list every layer on every 800ms poll. Dropped automatically
    // if a read against it ever comes back empty (app restarted, layer
    // recreated with a different id, etc.) so the next poll re-resolves it.
    private val layerCache = mutableMapOf<String, String>()

    fun readFps(pkg: String, exec: (String) -> String?): Int? {
        if (pkg.isEmpty()) return null
        readFpsFromSurfaceFlinger(pkg, exec)?.let { return it }
        return readFpsFromGfxInfo(pkg, exec)
    }

    // ---------------- SurfaceFlinger (real game frames) ----------------

    private fun readFpsFromSurfaceFlinger(pkg: String, exec: (String) -> String?): Int? {
        val layer = layerCache[pkg] ?: resolveLayer(pkg, exec) ?: return null
        val escaped = layer.replace("'", "'\\''")
        val output = exec("dumpsys SurfaceFlinger --latency '$escaped'") ?: return null
        val fps = parseSurfaceFlingerLatency(output)
        if (fps == null) {
            // Cached layer no longer producing data (game closed, or the
            // layer got torn down/recreated) — re-resolve fresh next poll.
            layerCache.remove(pkg)
        }
        return fps
    }

    private fun resolveLayer(pkg: String, exec: (String) -> String?): String? {
        val output = exec("dumpsys SurfaceFlinger --list") ?: return null
        val layers = output.lineSequence().map { it.trim() }.filter { it.isNotEmpty() }.toList()
        // Prefer the SurfaceView layer — that's where the actual game
        // content is drawn. Fall back to any layer for the package (covers
        // games that render straight into the main window surface).
        val found = layers.firstOrNull { it.contains("SurfaceView", ignoreCase = true) && it.contains(pkg) }
            ?: layers.firstOrNull { it.contains(pkg) }
        if (found != null) layerCache[pkg] = found
        return found
    }

    /** Package-visible for testing without a device. */
    fun parseSurfaceFlingerLatency(output: String): Int? {
        val lines = output.lineSequence().map { it.trim() }.filter { it.isNotEmpty() }.toList()
        if (lines.size < 3) return null // only the refresh-period line (or nothing) — no frame rows yet

        // Line 0 is the display's refresh period in ns — not a frame, skip it.
        // Each remaining line is "desiredPresentTime actualPresentTime frameReadyTime".
        val timestamps = lines.drop(1)
            .mapNotNull { line ->
                val parts = line.split(Regex("\\s+"))
                if (parts.size < 2) null else parts[1].toLongOrNull()
            }
            // Pending/not-yet-composited slots are reported as 0 or Long.MAX_VALUE — not real frames.
            .filter { it > 0L && it != Long.MAX_VALUE }
            .distinct()
            .sorted()

        if (timestamps.size < 2) return null

        val newest = timestamps.last()
        val windowStartNs = newest - 1_000_000_000L
        val inWindow = timestamps.count { it >= windowStartNs }

        return if (inWindow >= 2) inWindow else null
    }

    // ---------------- HWUI gfxinfo (fallback for View-based screens) ----------------

    private fun readFpsFromGfxInfo(pkg: String, exec: (String) -> String?): Int? {
        val output = exec("dumpsys gfxinfo $pkg framestats") ?: return null
        return parseGfxInfoFps(output)
    }

    /** Package-visible for testing without a device. */
    fun parseGfxInfoFps(output: String): Int? {
        val lines = output.lineSequence().iterator()
        var header: List<String>? = null
        val rows = mutableListOf<List<Long>>()
        var inBlock = false

        while (lines.hasNext()) {
            val line = lines.next().trim()
            if (line == "---PROFILEDATA---") {
                if (!inBlock) {
                    inBlock = true
                    continue
                } else {
                    break // second marker closes the block
                }
            }
            if (!inBlock || line.isEmpty()) continue
            if (header == null) {
                header = line.split(",")
                continue
            }
            val values = line.split(",").mapNotNull { it.trim().toLongOrNull() }
            if (values.size == header.size) rows.add(values)
        }

        val h = header ?: return null
        if (rows.isEmpty()) return null

        val flagsIdx = h.indexOf("Flags")
        val frameCompletedIdx = h.indexOf("FrameCompleted").let { if (it >= 0) it else h.indexOf("Vsync") }
        if (frameCompletedIdx < 0) return null

        val timestamps = rows
            .filter { flagsIdx < 0 || (it[flagsIdx] and 1L) == 0L } // drop marked-invalid frames
            .map { it[frameCompletedIdx] }
            .filter { it > 0L }
            .distinct()
            .sorted()

        if (timestamps.size < 2) return null

        // Rolling 1-second window ending at the newest frame — a real,
        // stable instantaneous rate rather than an average since app start.
        val newest = timestamps.last()
        val windowStartNs = newest - 1_000_000_000L
        val inWindow = timestamps.count { it >= windowStartNs }

        return if (inWindow >= 2) inWindow else null
    }
}
