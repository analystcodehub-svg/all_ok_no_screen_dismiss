package com.sajnire.app

import android.app.Service
import android.content.Intent
import android.os.IBinder
import android.util.Log
import com.google.firebase.database.FirebaseDatabase
import com.google.firebase.database.ServerValue

class AppCloseService : Service() {
    private var expertId: String? = null
    private var gender: String? = null
    private var language: String? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        intent?.let {
            expertId = it.getStringExtra("expertId")
            gender = it.getStringExtra("gender")
            language = it.getStringExtra("language")
            Log.d("AppCloseService", "Started for expertId: $expertId, gender: $gender, language: $language")
        }
        return START_NOT_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        
        val componentName = rootIntent?.component?.className ?: ""
        Log.d("AppCloseService", "onTaskRemoved triggered. componentName: $componentName")
        
        // Only proceed if the task removed is the main app task, NOT the CallKit activity.
        if (componentName.contains("CallkitIncomingActivity")) {
            Log.d("AppCloseService", "Ignoring onTaskRemoved because it is just CallKit finishing.")
            return
        }

        expertId?.let { uid ->
            Log.d("AppCloseService", "Setting offline and stopping service for expertId: $uid")
            try {
                val db = FirebaseDatabase.getInstance("https://zegochat-c44b0.asia-southeast1.firebasedatabase.app")
                
                // 1. Set status to offline
                val updates = mapOf<String, Any>(
                    "isOnline" to false,
                    "status" to "offline",
                    "callStatus" to "offline",
                    "lastChanged" to ServerValue.TIMESTAMP
                )
                db.getReference("status/$uid").updateChildren(updates)
                
                // 2. Explicitly remove from the matchmaking queue
                if (gender != null && language != null) {
                    val queueRef = db.getReference("queues/${gender}_${language}/$uid")
                    queueRef.removeValue()
                }

                // 3. Stop the flutter_background_service to ensure RTDB disconnects properly
                val backgroundServiceIntent = Intent()
                backgroundServiceIntent.setClassName(this, "id.flutter.flutter_background_service.BackgroundService")
                stopService(backgroundServiceIntent)

            } catch (e: Exception) {
                Log.e("AppCloseService", "Error setting offline", e)
            }
        }
        stopSelf()
    }
}
