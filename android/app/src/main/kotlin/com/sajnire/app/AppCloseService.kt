package com.sajnire.app

import android.app.Service
import android.content.Intent
import android.os.IBinder
import android.util.Log
import com.google.firebase.database.FirebaseDatabase
import com.google.firebase.database.ServerValue

class AppCloseService : Service() {
    private var expertId: String? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val uid = intent?.getStringExtra("expertId")
        if (uid != null) {
            expertId = uid
            Log.d("AppCloseService", "Started for expertId: $expertId")
        }
        return START_NOT_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        expertId?.let { uid ->
            Log.d("AppCloseService", "onTaskRemoved triggered for expertId: $uid. Setting offline.")
            try {
                val db = FirebaseDatabase.getInstance("https://zegochat-c44b0.asia-southeast1.firebasedatabase.app")
                val updates = mapOf<String, Any>(
                    "isOnline" to false,
                    "status" to "offline",
                    "callStatus" to "offline",
                    "lastChanged" to ServerValue.TIMESTAMP
                )
                db.getReference("status/\$uid").updateChildren(updates)
            } catch (e: Exception) {
                Log.e("AppCloseService", "Error setting offline", e)
            }
        }
        stopSelf()
    }
}
