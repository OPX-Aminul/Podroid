package com.opx.yourxdemon.engine

import android.util.Log
import java.io.BufferedReader
import java.io.InputStream
import java.io.InputStreamReader
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.Socket
import java.nio.charset.StandardCharsets

/**
 * Interactive PTY shell connection to the guest VM via TCP port 9051.
 *
 * Modeled after StrykerApp's port 1051 (socat TCP-LISTEN:1051 EXEC:'bash -il',pty).
 * The guest runs socat which bridges TCP to a PTY-backed bash/shell.
 *
 * This bypasses the Termux bridge + virtio-console path entirely:
 *   Host TCP → SLIRP → socat → PTY → bash
 *
 * Use this for interactive shell sessions where you need colors, cursor
 * movement, and escape sequences — but want lower latency than the
 * bridge→virtio-console→hvc0→getty→PTY path.
 */
object GuestTerminal {

    private const val TAG = "GuestTerminal"
    const val TERMINAL_PORT = 9051
    private const val CONNECT_TIMEOUT_MS = 4_000

    /**
     * Open an interactive shell session.
     * Returns a [Session] with raw input/output streams for bidirectional I/O.
     *
     * The caller is responsible for:
     * - Reading from session.inputStream (guest output)
     * - Writing to session.outputStream (user input)
     * - Closing the session when done
     */
    fun open(): Session {
        val socket = Socket()
        socket.connect(
            InetSocketAddress("127.0.0.1", TERMINAL_PORT),
            CONNECT_TIMEOUT_MS
        )
        socket.keepAlive = true
        socket.soTimeout = 0 // no read timeout for interactive session
        return Session(socket)
    }

    /**
     * Check if the interactive terminal port is reachable.
     */
    fun isReachable(timeoutMs: Int = 2000): Boolean {
        return try {
            Socket().use { sock ->
                sock.connect(
                    InetSocketAddress("127.0.0.1", TERMINAL_PORT),
                    timeoutMs
                )
                true
            }
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Represents an interactive shell session.
     * Read from [inputStream] for guest output, write to [outputStream] for user input.
     */
    class Session(private val socket: Socket) {
        val inputStream: InputStream get() = socket.inputStream
        val outputStream: OutputStream get() = socket.outputStream

        val reader: BufferedReader
            get() = BufferedReader(
                InputStreamReader(socket.inputStream, StandardCharsets.UTF_8)
            )

        val isConnected: Boolean
            get() = socket.isConnected && !socket.isClosed

        fun close() {
            try { socket.close() } catch (_: Exception) {}
        }

        /**
         * Send a string to the shell (raw, no newline appended).
         */
        fun send(data: String) {
            outputStream.write(data.toByteArray(StandardCharsets.UTF_8))
            outputStream.flush()
        }

        /**
         * Send a line to the shell (appends newline).
         */
        fun sendLine(line: String) {
            send(line + "\n")
        }

        /**
         * Send raw bytes to the shell.
         */
        fun sendBytes(data: ByteArray) {
            outputStream.write(data)
            outputStream.flush()
        }
    }
}
