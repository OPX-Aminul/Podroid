package com.opx.yourxdemon.engine

import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.Socket
import java.nio.charset.StandardCharsets

/**
 * Fast TCP command execution against the guest VM.
 *
 * Modeled after StrykerApp's GuestExec: connects to yourxdemon-agentd
 * on TCP port 9050 (SLIRP hostfwd → guest:9050), sends a wrapped shell
 * command, and reads stdout+stderr over the same socket.
 *
 * This bypasses the PTY/virtio-console bridge path entirely:
 *   Host TCP → SLIRP → agentd → sh -c → stdout back over TCP
 *
 * The existing Termux-based terminal (virtio-console) is still the
 * interactive shell. GuestExec is for fast non-interactive commands
 * (package installs, service queries, file operations).
 */
object GuestExec {

    private const val TAG = "GuestExec"
    private const val AGENT_PORT = 9050
    private const val CONNECT_TIMEOUT_MS = 4_000
    private const val READ_TIMEOUT_MS = 90_000
    private const val EXIT_SENTINEL = "__EXIT__"
    private const val PING_SENTINEL = "__YOURXDEMON_PONG__"

    /**
     * Execute a command on the guest and return stdout lines + exit code.
     *
     * @param command Shell command to execute (e.g. "ls -la /")
     * @param timeoutMs Maximum time to wait for completion
     * @return [Result] with (exitCode, output lines)
     */
    suspend fun run(
        command: String,
        timeoutMs: Long = READ_TIMEOUT_MS,
    ): Pair<Int, List<String>> = withContext(Dispatchers.IO) {
        val socket = Socket()
        try {
            socket.connect(
                InetSocketAddress("127.0.0.1", AGENT_PORT),
                CONNECT_TIMEOUT_MS
            )
            socket.soTimeout = timeoutMs.toInt()
            socket.keepAlive = true

            val os: OutputStream = socket.getOutputStream()

            // Wrap command with PATH/HOME setup (same as StrykerApp)
            val payload = buildString {
                append("export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\$\{PATH:+:\$PATH\}; ")
                append("export HOME=/root LANG=C.UTF-8; ")
                append(command)
                append("\nprintf '\\n${EXIT_SENTINEL}%s\\n' \"\$?\"\n")
            }

            os.write(payload.toByteArray(StandardCharsets.UTF_8))
            os.flush()

            val reader = BufferedReader(
                InputStreamReader(socket.inputStream, StandardCharsets.UTF_8)
            )

            val output = mutableListOf<String>()
            var exitCode = -1

            var line: String?
            while (reader.readLine().also { line = it } != null) {
                val l = line ?: break
                if (l.startsWith(EXIT_SENTINEL)) {
                    exitCode = try {
                        l.substring(EXIT_SENTINEL.length).trim().toInt()
                    } catch (_: NumberFormatException) {
                        -1
                    }
                    break
                }
                output.add(l)
            }

            Pair(exitCode, output)
        } catch (e: Exception) {
            Log.e(TAG, "GuestExec.run failed: ${e.message}")
            Pair(-1, emptyList())
        } finally {
            try { socket.close() } catch (_: Exception) {}
        }
    }

    /**
     * Execute a command and return only the output (ignore exit code).
     */
    suspend fun runOrEmpty(command: String, timeoutMs: Long = READ_TIMEOUT_MS): List<String> {
        val (_, output) = run(command, timeoutMs)
        return output
    }

    /**
     * Ping the agent to check if it's alive and responsive.
     * A bare TCP connect proves nothing (SLIRP accepts before guest listens),
     * so we do a round-trip through the guest shell.
     */
    suspend fun ping(timeoutMs: Int = 4_000): Boolean = withContext(Dispatchers.IO) {
        try {
            Socket().use { sock ->
                sock.connect(
                    InetSocketAddress("127.0.0.1", AGENT_PORT),
                    timeoutMs
                )
                sock.soTimeout = timeoutMs

                val os = sock.getOutputStream()
                os.write("echo $PING_SENTINEL\nexit\n".toByteArray(StandardCharsets.UTF_8))
                os.flush()

                val br = BufferedReader(
                    InputStreamReader(sock.inputStream, StandardCharsets.UTF_8)
                )
                var line: String?
                while (br.readLine().also { line = it } != null) {
                    if (line?.contains(PING_SENTINEL) == true) return@withContext true
                }
                false
            }
        } catch (e: Exception) {
            Log.d(TAG, "Agent ping failed: ${e.message}")
            false
        }
    }

    /**
     * Blocking version of run() for use from non-coroutine contexts.
     * Use with caution — blocks the calling thread.
     */
    fun runBlocking(command: String, timeoutMs: Long = READ_TIMEOUT_MS): Pair<Int, List<String>> {
        val socket = Socket()
        return try {
            socket.connect(
                InetSocketAddress("127.0.0.1", AGENT_PORT),
                CONNECT_TIMEOUT_MS
            )
            socket.soTimeout = timeoutMs.toInt()

            val os = socket.getOutputStream()
            val payload = buildString {
                append("export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\$\{PATH:+:\$PATH\}; ")
                append("export HOME=/root LANG=C.UTF-8; ")
                append(command)
                append("\nprintf '\\n${EXIT_SENTINEL}%s\\n' \"\$?\"\n")
            }
            os.write(payload.toByteArray(StandardCharsets.UTF_8))
            os.flush()

            val reader = BufferedReader(
                InputStreamReader(socket.inputStream, StandardCharsets.UTF_8)
            )

            val output = mutableListOf<String>()
            var exitCode = -1

            var line: String?
            while (reader.readLine().also { line = it } != null) {
                val l = line ?: break
                if (l.startsWith(EXIT_SENTINEL)) {
                    exitCode = try {
                        l.substring(EXIT_SENTINEL.length).trim().toInt()
                    } catch (_: NumberFormatException) {
                        -1
                    }
                    break
                }
                output.add(l)
            }

            Pair(exitCode, output)
        } catch (e: Exception) {
            Log.e(TAG, "GuestExec.runBlocking failed: ${e.message}")
            Pair(-1, emptyList())
        } finally {
            try { socket.close() } catch (_: Exception) {}
        }
    }
}
