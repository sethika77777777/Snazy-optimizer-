package com.sethikadv.snazy

/**
 * Runs INSIDE the privileged process Shizuku spawns (identity = shell/adb,
 * uid 2000, or root/uid 0 if the user runs Shizuku via Sui/root). This is
 * not part of Snazy's normal app process — it has no Context worth relying
 * on and no SDK restrictions, which is exactly why it's able to run the
 * same shell commands a rooted app would.
 *
 * Shizuku instantiates this class by reflection, so it MUST have a public
 * no-argument constructor. Do not add required constructor args.
 */
class UserService : IUserService.Stub() {

    override fun exec(command: String?): String {
        if (command.isNullOrBlank()) return ""
        return try {
            val process = ProcessBuilder("sh", "-c", command)
                .redirectErrorStream(true)
                .start()
            val output = process.inputStream.bufferedReader().use { it.readText() }
            process.waitFor()
            output
        } catch (e: Exception) {
            "ERROR:${e.message}"
        }
    }

    override fun execSilent(command: String?): Boolean {
        if (command.isNullOrBlank()) return false
        return try {
            val process = ProcessBuilder("sh", "-c", command)
                .redirectErrorStream(true)
                .start()
            process.inputStream.bufferedReader().use { it.readText() } // drain, avoid buffer stall
            process.waitFor() == 0
        } catch (e: Exception) {
            false
        }
    }

    /** Called by Shizuku itself (reserved transaction 16777114) on unbind. */
    override fun destroy() {
        System.exit(0)
    }
}
