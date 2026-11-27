package ru.komet.app

import android.annotation.TargetApi
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.util.Log

internal class IncomingCallRingtone(
    private val context: Context,
    private val audio: AudioManager,
    private val handler: Handler,
) {
    private val attributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
        .build()
    private var active = false
    private var monitoringDevices = false
    private var headsetId: Int? = null
    private var ringtone: Ringtone? = null
    private var player: MediaPlayer? = null
    private val deviceCallback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>) = updateRoute()
        override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>) = updateRoute()
    }

    @Synchronized
    fun start() {
        active = true
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            try {
                audio.registerAudioDeviceCallback(deviceCallback, handler)
                monitoringDevices = true
            } catch (error: Exception) {
                Log.w("KometFcm", "ringtone device monitoring failed: ${error.message}")
            }
        }
        updateRoute()
    }

    @Synchronized
    fun stop() {
        active = false
        if (monitoringDevices) {
            monitoringDevices = false
            runCatching { audio.unregisterAudioDeviceCallback(deviceCallback) }
        }
        releasePlayback()
    }

    @Synchronized
    private fun updateRoute() {
        if (!active) return
        try {
            if (audio.ringerMode != AudioManager.RINGER_MODE_NORMAL) {
                releasePlayback()
                return
            }
            val headset = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                connectedHeadset()
            } else {
                null
            }
            if (headsetId == headset?.id && (ringtone != null || player != null)) return
            releasePlayback()
            headsetId = headset?.id
            val defaultRingtone = RingtoneManager.getActualDefaultRingtoneUri(
                context, RingtoneManager.TYPE_RINGTONE,
            )
            val type = if (defaultRingtone != null) {
                RingtoneManager.TYPE_RINGTONE
            } else {
                RingtoneManager.TYPE_NOTIFICATION
            }
            val uri = defaultRingtone ?: RingtoneManager.getActualDefaultRingtoneUri(
                context, type,
            ) ?: return
            if (headset != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                playThroughHeadset(RingtoneManager.getDefaultUri(type), headset)
            } else {
                val sound = RingtoneManager.getRingtone(context, uri) ?: return
                ringtone = sound
                sound.audioAttributes = attributes
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) sound.isLooping = true
                sound.play()
            }
        } catch (error: Exception) {
            releasePlayback()
            Log.w("KometFcm", "ringtone failed: ${error.message}")
        }
    }

    private fun connectedHeadset(): AudioDeviceInfo? {
        val outputs = audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
        val headsetTypes = intArrayOf(
            AudioDeviceInfo.TYPE_WIRED_HEADSET,
            AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
            AudioDeviceInfo.TYPE_USB_HEADSET,
            AudioDeviceInfo.TYPE_BLE_HEADSET,
            AudioDeviceInfo.TYPE_HEARING_AID,
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
        )
        for (type in headsetTypes) {
            outputs.firstOrNull { it.type == type }?.let { return it }
        }
        return null
    }

    @TargetApi(Build.VERSION_CODES.P)
    private fun playThroughHeadset(uri: Uri, headset: AudioDeviceInfo) {
        val sound = MediaPlayer()
        player = sound
        sound.setAudioAttributes(attributes)
        sound.setDataSource(context, uri)
        sound.isLooping = true
        if (!sound.setPreferredDevice(headset)) {
            releasePlayback()
            return
        }
        sound.setOnPreparedListener(::onPrepared)
        sound.setOnErrorListener(::onPlaybackError)
        sound.prepareAsync()
    }

    @Synchronized
    private fun onPrepared(sound: MediaPlayer) {
        if (!active || player !== sound) return
        if (audio.ringerMode != AudioManager.RINGER_MODE_NORMAL) {
            releasePlayback()
            return
        }
        try {
            sound.start()
        } catch (error: IllegalStateException) {
            releasePlayback()
            Log.w("KometFcm", "ringtone start failed: ${error.message}")
        }
    }

    @Synchronized
    private fun onPlaybackError(sound: MediaPlayer, what: Int, extra: Int): Boolean {
        if (player === sound) {
            releasePlayback()
            Log.w("KometFcm", "ringtone playback failed: $what/$extra")
        }
        return true
    }

    private fun releasePlayback() {
        val systemRingtone = ringtone
        ringtone = null
        val headsetPlayer = player
        player = null
        runCatching { systemRingtone?.stop() }
        runCatching { headsetPlayer?.release() }
    }
}
