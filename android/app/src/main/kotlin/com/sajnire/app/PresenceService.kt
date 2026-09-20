package com.sajnire.app

import android.app.Service
import android.content.Intent
import android.os.IBinder
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.database.FirebaseDatabase
import android.util.Log

class PresenceService : Service() {
    private val TAG = "PresenceService"

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "PresenceService started")
        return START_NOT_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        Log.d(TAG, "onTaskRemoved triggered: App swiped away")

        try {
            val user = FirebaseAuth.getInstance().currentUser
            if (user != null) {
                val uid = user.uid
                Log.d(TAG, "Marking user $uid as offline...")
                val ref = FirebaseDatabase.getInstance("https://zegochat-c44b0.asia-southeast1.firebasedatabase.app")
                    .getReference("status/$uid")
                
                val updates = mapOf(
                    "isOnline" to false,
                    "status" to "offline",
                    "callStatus" to "offline"
                )
                // We use setValue/updateChildren directly. It executes quickly.
                ref.updateChildren(updates)
                Log.d(TAG, "Update sent to RTDB.")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error in onTaskRemoved: ${e.message}")
        }
        
        stopSelf()
    }
}
