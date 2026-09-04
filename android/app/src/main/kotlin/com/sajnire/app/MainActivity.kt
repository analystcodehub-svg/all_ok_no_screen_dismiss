package com.sajnire.app

import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.IntentSender
import android.os.Build
import com.google.android.gms.auth.api.identity.GetPhoneNumberHintIntentRequest
import com.google.android.gms.auth.api.identity.Identity
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.sajnire.app/auth"
    private val REQUEST_PHONE_HINT = 1001
    private var pendingResult: MethodChannel.Result? = null

    // Create notification channels natively so they exist even BEFORE Flutter code runs.
    // This is critical for showing FCM notifications in killed/terminated app state.
    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            // Messages channel — used for chat message notifications
            val messagesChannel = NotificationChannel(
                "messages_channel",
                "Messages",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Chat message notifications"
                enableVibration(true)
            }
            manager.createNotificationChannel(messagesChannel)

            // Calls channel — used for incoming call notifications
            val callsChannel = NotificationChannel(
                "calls_channel",
                "Incoming Calls",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Incoming call notifications"
                enableVibration(true)
            }
            manager.createNotificationChannel(callsChannel)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // Create channels FIRST before Flutter engine starts
        createNotificationChannels()
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "requestPhoneHint") {
                // Return immediately if there is already a pending request
                if (pendingResult != null) {
                    result.error("ALREADY_ACTIVE", "A phone hint request is already active", null)
                    return@setMethodCallHandler
                }
                
                pendingResult = result
                val request = GetPhoneNumberHintIntentRequest.builder().build()
                
                Identity.getSignInClient(this)
                    .getPhoneNumberHintIntent(request)
                    .addOnSuccessListener { pendingIntentResponse ->
                        try {
                            startIntentSenderForResult(
                                pendingIntentResponse.intentSender,
                                REQUEST_PHONE_HINT,
                                null, 0, 0, 0
                            )
                        } catch (e: IntentSender.SendIntentException) {
                            pendingResult?.error("HINT_FAILED", "Failed to start intent sender: ${e.message}", null)
                            pendingResult = null
                        }
                    }
                    .addOnFailureListener { e ->
                        pendingResult?.error("HINT_UNAVAILABLE", "Phone hint not available: ${e.message}", null)
                        pendingResult = null
                    }
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        
        if (requestCode == REQUEST_PHONE_HINT) {
            if (resultCode == Activity.RESULT_OK && data != null) {
                try {
                    val phoneNumber = Identity.getSignInClient(this).getPhoneNumberFromIntent(data)
                    pendingResult?.success(phoneNumber)
                } catch (e: Exception) {
                    pendingResult?.error("EXTRACT_FAILED", e.message, null)
                }
            } else {
                pendingResult?.error("CANCELLED", "User cancelled or failed", null)
            }
            pendingResult = null
        }
    }
}
