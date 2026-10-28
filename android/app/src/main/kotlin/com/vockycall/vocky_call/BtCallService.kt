package com.vockycall.vocky_call

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothClass
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothServerSocket
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.EventChannel
import java.io.DataInputStream
import java.io.IOException
import java.io.OutputStream
import java.util.UUID

/**
 * Bluetooth call transport: one RFCOMM connection carrying framed
 * signaling JSON and raw PCM audio (8 kHz / 16-bit / mono).
 *
 * Frame: [type:1][length:4 big-endian][payload]
 *   0x5F = signaling JSON, 0xA0 = PCM audio.
 *
 * A server socket is always listening so the other phone can call us.
 * Insecure RFCOMM is used so the phones do not need to be paired first.
 *
 * A second "presence" server lets a phone that found us say hello, so we
 * list it too even when it is not discoverable (see [announce]).
 */
@SuppressLint("MissingPermission")
class BtCallService(private val context: Context) : EventChannel.StreamHandler {

    private val main = Handler(Looper.getMainLooper())
    private var events: EventChannel.EventSink? = null

    private val adapter: BluetoothAdapter?
        get() = (context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter

    @Volatile private var listening = false
    private val serverThreads = mutableListOf<Thread>()
    private val serverSockets = java.util.Collections.synchronizedSet(mutableSetOf<BluetoothServerSocket>())

    @Volatile private var conn: Connection? = null

    // Two RFCOMM connections opening between the same phones at once (a call
    // and a hello, or two hellos) can stall the Bluetooth link. So outgoing
    // connects take turns, and hellos keep away from calls.
    private val connectLock = Any()
    @Volatile private var callConnecting = false
    @Volatile private var lastCallEndMs = 0L

    @Volatile var muted = false

    // ── EventChannel ────────────────────────────────────────────────────

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) { events = sink }
    override fun onCancel(arguments: Any?) { events = null }

    private fun emit(map: Map<String, Any?>) = main.post { events?.success(map) }

    /** Separate event stream for presence hellos (used by discovery). */
    private var presenceEvents: EventChannel.EventSink? = null
    val presenceHandler = object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) { presenceEvents = sink }
        override fun onCancel(arguments: Any?) { presenceEvents = null }
    }

    // ── Public API (called from MethodChannel) ─────────────────────────

    /** Start accepting incoming connections. Retries until BT permission/adapter is ready. */
    fun listen() {
        if (listening) return
        listening = true
        serverThreads += startServer("bt-server", SERVICE_UUID) { socket ->
            if (conn != null) {
                Log.i(TAG, "Busy, rejecting ${socket.remoteDevice.address}")
                socket.close()
            } else {
                Log.i(TAG, "Incoming connection from ${socket.remoteDevice.address}")
                attach(socket)
            }
        }
        serverThreads += startServer("bt-presence", PRESENCE_UUID) { socket ->
            Thread({ readPresence(socket) }, "bt-presence-read").apply { isDaemon = true; start() }
        }
    }

    private fun startServer(name: String, uuid: UUID, onAccept: (BluetoothSocket) -> Unit): Thread =
        Thread({
            while (listening) {
                var server: BluetoothServerSocket? = null
                try {
                    val bt = adapter
                    if (bt == null || !bt.isEnabled) { Thread.sleep(2000); continue }
                    server = bt.listenUsingInsecureRfcommWithServiceRecord(SERVICE_NAME, uuid)
                    serverSockets += server
                    Log.i(TAG, "$name listening")
                    while (listening) onAccept(server.accept())
                } catch (e: SecurityException) {
                    Thread.sleep(2000) // permission not granted yet
                } catch (e: IOException) {
                    if (listening) Thread.sleep(1000)
                } catch (e: InterruptedException) {
                    return@Thread
                } finally {
                    server?.let { serverSockets -= it; try { it.close() } catch (_: IOException) {} }
                }
            }
        }, name).apply { isDaemon = true; start() }

    /**
     * Say hello to the VockyCall phone at [address] so it lists us, even if
     * we are not discoverable. [done] gets true if the phone answered.
     */
    fun announce(address: String, name: String, done: (Boolean) -> Unit) {
        if (!helloAllowed()) { done(false); return }
        Thread({
            var ok = false
            var socket: BluetoothSocket? = null
            val watchdog = Runnable { try { socket?.close() } catch (_: IOException) {} }
            try {
                synchronized(connectLock) {
                    if (!helloAllowed()) return@synchronized // a call started meanwhile
                    val bt = adapter ?: throw IOException("Bluetooth not available")
                    bt.cancelDiscovery()
                    val s = bt.getRemoteDevice(address).createInsecureRfcommSocketToServiceRecord(PRESENCE_UUID)
                    socket = s
                    main.postDelayed(watchdog, PRESENCE_TIMEOUT_MS)
                    s.connect()
                    val json = org.json.JSONObject().put("name", name).toString()
                    writeFrame(s.outputStream, TYPE_SIGNAL, json.toByteArray(Charsets.UTF_8))
                    ok = s.inputStream.read() == PRESENCE_ACK
                }
            } catch (e: Exception) {
                Log.d(TAG, "Announce to $address failed: $e")
            } finally {
                main.removeCallbacks(watchdog)
                try { socket?.close() } catch (_: IOException) {}
            }
            main.post { done(ok) }
        }, "bt-announce").start()
    }

    /** No hellos during a call, while one is connecting, or just after one ended. */
    private fun helloAllowed() = conn == null && !callConnecting &&
        System.currentTimeMillis() - lastCallEndMs > AFTER_CALL_QUIET_MS

    /** Read one hello from a phone that found us, then report it to Dart. */
    private fun readPresence(socket: BluetoothSocket) {
        val watchdog = Runnable { try { socket.close() } catch (_: IOException) {} }
        main.postDelayed(watchdog, PRESENCE_TIMEOUT_MS)
        try {
            val input = DataInputStream(socket.inputStream)
            val (type, payload) = readFrame(input, maxLen = 1024)
            if (type != TYPE_SIGNAL) return
            val name = org.json.JSONObject(String(payload, Charsets.UTF_8)).optString("name")
            socket.outputStream.apply { write(PRESENCE_ACK); flush() }
            val address = socket.remoteDevice.address
            Log.i(TAG, "Presence from $address ($name)")
            main.post { presenceEvents?.success(mapOf("address" to address, "name" to name)) }
            // Wait for the caller to close, so the ack is delivered. Closing is the normal end.
            try { input.read() } catch (_: IOException) {}
        } catch (e: Exception) {
            Log.d(TAG, "Presence read failed: $e")
        } finally {
            main.removeCallbacks(watchdog)
            try { socket.close() } catch (_: IOException) {}
        }
    }

    /** Connect to [address]. Calls [done] with null on success or an error message. */
    fun connect(address: String, done: (String?) -> Unit) {
        callConnecting = true
        Thread({
            var socket: BluetoothSocket? = null
            val watchdog = Runnable { try { socket?.close() } catch (_: IOException) {} }
            try {
                hangup()
                synchronized(connectLock) {
                    val bt = adapter ?: throw IOException("Bluetooth not available")
                    bt.cancelDiscovery() // discovery slows down connects a lot
                    val s = bt.getRemoteDevice(address).createInsecureRfcommSocketToServiceRecord(SERVICE_UUID)
                    socket = s
                    main.postDelayed(watchdog, CONNECT_TIMEOUT_MS) // don't hang on "Calling…"
                    s.connect()
                    main.removeCallbacks(watchdog)
                    Log.i(TAG, "Connected to $address")
                    attach(s)
                }
                main.post { done(null) }
            } catch (e: Exception) {
                main.removeCallbacks(watchdog)
                Log.w(TAG, "Connect to $address failed: $e")
                main.post { done(e.message ?: e.toString()) }
            } finally {
                callConnecting = false
            }
        }, "bt-connect").start()
    }

    /**
     * True if [address] could be a phone or tablet running VockyCall.
     * Headphones, speakers, watches, keyboards etc. are filtered out.
     * Devices with no class info are kept so no phone is ever hidden.
     */
    fun isCallCapable(address: String): Boolean {
        val major = try {
            adapter?.getRemoteDevice(address)?.bluetoothClass?.majorDeviceClass
        } catch (e: Exception) { null } ?: return true
        return major == BluetoothClass.Device.Major.PHONE ||
            major == BluetoothClass.Device.Major.COMPUTER ||
            major == BluetoothClass.Device.Major.UNCATEGORIZED
    }

    fun sendSignal(json: String) {
        conn?.write(TYPE_SIGNAL, json.toByteArray(Charsets.UTF_8))
    }

    fun startAudio() { conn?.startAudio() }

    /** Close the current call connection. The server keeps listening. */
    fun hangup() {
        val c = conn
        conn = null
        c?.close()
    }

    fun dispose() {
        listening = false
        synchronized(serverSockets) {
            serverSockets.forEach { try { it.close() } catch (_: IOException) {} }
        }
        serverThreads.forEach { it.interrupt() }
        hangup()
    }

    // ── Connection ──────────────────────────────────────────────────────

    /** True while a call connection is open (discovery must stay off then). */
    val isBusy: Boolean get() = conn != null

    private fun attach(socket: BluetoothSocket) {
        // Scanning during a call starves the RFCOMM link (and can crash the
        // emulator's BT stack), so stop any running discovery.
        try { adapter?.cancelDiscovery() } catch (_: SecurityException) {}
        val c = Connection(socket)
        conn = c
        c.startReading()
    }

    private inner class Connection(private val socket: BluetoothSocket) {
        val address: String = socket.remoteDevice.address
        private val out: OutputStream = socket.outputStream
        @Volatile private var closed = false
        private var recordThread: Thread? = null
        private var track: AudioTrack? = null
        private var framesIn = 0L
        private var framesOut = 0L

        fun write(type: Int, payload: ByteArray) {
            if (closed) return
            try {
                synchronized(out) { writeFrame(out, type, payload) }
            } catch (e: IOException) {
                onLost()
            }
        }

        fun startReading() {
            Thread({
                try {
                    val input = DataInputStream(socket.inputStream)
                    while (!closed) {
                        val (type, payload) = readFrame(input, MAX_FRAME)
                        when (type) {
                            TYPE_SIGNAL -> emit(mapOf(
                                "event" to "signal",
                                "address" to address,
                                "json" to String(payload, Charsets.UTF_8),
                            ))
                            TYPE_AUDIO -> {
                                track?.write(payload, 0, payload.size)
                                if (++framesIn % STATS_EVERY == 0L) {
                                    Log.d(TAG, "audio frames in=$framesIn out=$framesOut")
                                }
                            }
                        }
                    }
                } catch (e: IOException) {
                    onLost()
                }
            }, "bt-reader").apply { isDaemon = true; start() }
        }

        @SuppressLint("MissingPermission")
        fun startAudio() {
            if (closed || recordThread != null) return
            val minOut = AudioTrack.getMinBufferSize(SAMPLE_RATE, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT)
            track = AudioTrack.Builder()
                .setAudioAttributes(AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build())
                .setAudioFormat(AudioFormat.Builder()
                    .setSampleRate(SAMPLE_RATE)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .build())
                .setBufferSizeInBytes(maxOf(minOut, FRAME_BYTES * 8))
                .setTransferMode(AudioTrack.MODE_STREAM)
                .build()
                .also { it.play() }

            recordThread = Thread({
                val minIn = AudioRecord.getMinBufferSize(SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
                val rec = try {
                    AudioRecord(MediaRecorder.AudioSource.VOICE_COMMUNICATION, SAMPLE_RATE,
                        AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT,
                        maxOf(minIn, FRAME_BYTES * 4))
                } catch (e: SecurityException) {
                    Log.w(TAG, "Mic permission missing: $e"); return@Thread
                }
                if (rec.state != AudioRecord.STATE_INITIALIZED) {
                    Log.w(TAG, "AudioRecord init failed"); rec.release(); return@Thread
                }
                rec.startRecording()
                val buf = ByteArray(FRAME_BYTES)
                try {
                    while (!closed) {
                        val n = rec.read(buf, 0, buf.size)
                        if (n <= 0) continue
                        if (muted) java.util.Arrays.fill(buf, 0, n, 0)
                        write(TYPE_AUDIO, if (n == buf.size) buf else buf.copyOf(n))
                        framesOut++
                    }
                } finally {
                    rec.stop()
                    rec.release()
                }
            }, "bt-record").apply { isDaemon = true; start() }
            Log.i(TAG, "Audio started with $address")
        }

        private fun onLost() {
            if (closed) return
            val wasCurrent = conn === this
            close()
            if (wasCurrent) {
                conn = null
                emit(mapOf("event" to "disconnected", "address" to address))
            }
        }

        fun close() {
            if (closed) return
            closed = true
            lastCallEndMs = System.currentTimeMillis()
            try { socket.close() } catch (_: IOException) {}
            track?.let { try { it.stop() } catch (_: Exception) {}; it.release() }
            track = null
            Log.i(TAG, "Connection to $address closed (frames in=$framesIn out=$framesOut)")
        }
    }

    companion object {
        private fun writeFrame(out: OutputStream, type: Int, payload: ByteArray) {
            val len = payload.size
            out.write(byteArrayOf(type.toByte(), (len ushr 24).toByte(), (len ushr 16).toByte(),
                (len ushr 8).toByte(), len.toByte()))
            out.write(payload)
            out.flush()
        }

        private fun readFrame(input: DataInputStream, maxLen: Int): Pair<Int, ByteArray> {
            val type = input.readUnsignedByte()
            val len = input.readInt()
            if (len < 0 || len > maxLen) throw IOException("Bad frame length $len")
            val payload = ByteArray(len)
            input.readFully(payload)
            return type to payload
        }

        private const val TAG = "VockyBt"
        private const val SERVICE_NAME = "VockyCall"
        // App-specific UUID so we only ever connect to VockyCall, not other SPP devices.
        private val SERVICE_UUID: UUID = UUID.fromString("7d2c1f4e-8b3a-4c55-9a0e-5f1b6c3d2e10")
        private val PRESENCE_UUID: UUID = UUID.fromString("7d2c1f4e-8b3a-4c55-9a0e-5f1b6c3d2e11")
        private const val PRESENCE_ACK = 0x06
        private const val PRESENCE_TIMEOUT_MS = 8000L
        private const val CONNECT_TIMEOUT_MS = 15000L
        private const val AFTER_CALL_QUIET_MS = 15000L
        private const val TYPE_SIGNAL = 0x5F
        private const val TYPE_AUDIO = 0xA0
        private const val SAMPLE_RATE = 8000
        private const val FRAME_BYTES = 320 // 20 ms
        private const val MAX_FRAME = 64 * 1024
        private const val STATS_EVERY = 250L // ~5 s of audio
    }
}
