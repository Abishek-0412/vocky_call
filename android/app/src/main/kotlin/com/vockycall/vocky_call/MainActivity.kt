package com.vockycall.vocky_call

import android.content.Context
import android.media.AudioManager
import android.net.wifi.WifiManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * MainActivity
 *
 * Responsibilities (SRP):
 *  1. Acquire/release WiFi multicast lock so UDP broadcasts are received.
 *  2. Expose audio output routing (earpiece ↔ speaker) via MethodChannel.
 *  3. Bridge the native Bluetooth call transport ([BtCallService]).
 *
 * All other logic lives in Dart/Flutter.
 */
class MainActivity : FlutterActivity() {

    private var multicastLock: WifiManager.MulticastLock? = null
    private lateinit var audioManager: AudioManager
    private var btCall: BtCallService? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager

        // ── Multicast Lock Channel ─────────────────────────────────────────
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MULTICAST_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "acquireMulticastLock" -> {
                    acquireMulticastLock()
                    result.success(null)
                }
                "releaseMulticastLock" -> {
                    releaseMulticastLock()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // ── Bluetooth Call Channel ─────────────────────────────────────────
        val bt = BtCallService(applicationContext).also { btCall = it }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, BT_EVENTS_CHANNEL)
            .setStreamHandler(bt)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, BT_PRESENCE_CHANNEL)
            .setStreamHandler(bt.presenceHandler)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BT_CALL_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "listen" -> { bt.listen(); result.success(null) }
                "connect" -> bt.connect(call.argument<String>("address")!!) { error ->
                    if (error == null) result.success(null)
                    else result.error("BT_CONNECT", error, null)
                }
                "isBusy" -> result.success(bt.isBusy)
                "announce" -> bt.announce(
                    call.argument<String>("address")!!,
                    call.argument<String>("name")!!,
                ) { ok -> result.success(ok) }
                "isCallCapable" -> result.success(bt.isCallCapable(call.argument<String>("address")!!))
                "sendSignal" -> { bt.sendSignal(call.argument<String>("json")!!); result.success(null) }
                "startAudio" -> { bt.startAudio(); result.success(null) }
                "setMuted" -> { bt.muted = call.argument<Boolean>("muted") == true; result.success(null) }
                "hangup" -> { bt.hangup(); result.success(null) }
                else -> result.notImplemented()
            }
        }

        // ── Audio Routing Channel ──────────────────────────────────────────
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            AUDIO_ROUTING_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setEarpiece" -> {
                    audioManager.isSpeakerphoneOn = false
                    audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
                    result.success(null)
                }
                "setSpeaker" -> {
                    audioManager.isSpeakerphoneOn = true
                    audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        releaseMulticastLock()
        btCall?.dispose()
        super.onDestroy()
    }

    // ── Private Helpers ────────────────────────────────────────────────────

    private fun acquireMulticastLock() {
        if (multicastLock?.isHeld == true) return
        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        multicastLock = wifiManager.createMulticastLock("VockyCallMulticastLock").apply {
            setReferenceCounted(true)
            acquire()
        }
    }

    private fun releaseMulticastLock() {
        if (multicastLock?.isHeld == true) {
            multicastLock?.release()
        }
    }

    companion object {
        private const val MULTICAST_CHANNEL = "com.vockycall/multicast_lock"
        private const val AUDIO_ROUTING_CHANNEL = "com.vockycall/audio_routing"
        private const val BT_CALL_CHANNEL = "com.vockycall/bt_call"
        private const val BT_EVENTS_CHANNEL = "com.vockycall/bt_call_events"
        private const val BT_PRESENCE_CHANNEL = "com.vockycall/bt_presence_events"
    }
}
