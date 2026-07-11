import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;

class MatchmakingService {
  final FirebaseDatabase _db;

  MatchmakingService()
      : _db = FirebaseDatabase.instanceFor(
          app: FirebaseDatabase.instance.app,
          databaseURL: 'https://zegochat-c44b0.asia-southeast1.firebasedatabase.app',
        ) {
    // Cache Optimization (keepSynced): Ensure the matchmaking pool is cached in RAM
    _db.ref('queues').keepSynced(true);
    initDemandListener();
  }

  int _currentActiveMales = 0;

  void initDemandListener() {
    _db.ref('stats/active_searching_males').onValue.listen((event) {
      if (event.snapshot.value != null) {
        _currentActiveMales = int.tryParse(event.snapshot.value.toString()) ?? 0;
      }
    });
  }

  int _getInstantPoolSize() {
    return (_currentActiveMales * 3).clamp(30, 2000);
  }

  /// Female Expert Logic (Joining/Leaving the Queue)
  Future<void> setExpertOnlineStatus({
    required String expertId,
    required bool isOnline,
    required String gender,
    required String language,
  }) async {
    try {
      final String bucketPath = 'queues/${gender.toLowerCase()}_${language.toLowerCase()}/$expertId';
      final docRef = _db.ref(bucketPath);
      final presenceRef = _db.ref('status/$expertId');
      
      if (isOnline) {
        int talkSeconds = 0;
        String nickname = 'Unknown';
        try {
          final doc = await FirebaseFirestore.instance.collection('experts').doc(expertId).get();
          if (doc.exists) {
            talkSeconds = (doc.data()?['totalTalkSeconds'] as num?)?.toInt() ?? 0;
            nickname = doc.data()?['name'] as String? ?? doc.data()?['nickname'] as String? ?? 'Expert';
          }
        } catch (e) {
          debugPrint('Error fetching expert data: $e');
        }

        // Set presence first, and set callStatus to available
        await presenceRef.update({
          'isOnline': true,
          'callStatus': 'available',
          'lastChanged': ServerValue.timestamp,
        });
        await presenceRef.onDisconnect().update({
          'isOnline': false,
          'callStatus': 'offline',
          'lastChanged': ServerValue.timestamp,
        });

        // Add to language queue with timestamp for ordering
        await docRef.update({
          'timestamp': ServerValue.timestamp,
          'totalTalkSeconds': talkSeconds,
          'nickname': nickname,
        });
        await docRef.onDisconnect().remove();
        debugPrint('Expert $expertId added to $bucketPath.');
      } else {
        await docRef.remove();
        await docRef.onDisconnect().cancel();
        
        await presenceRef.update({
          'isOnline': false,
          'callStatus': 'offline',
          'lastChanged': ServerValue.timestamp,
        });
        await presenceRef.onDisconnect().cancel();
        debugPrint('Expert $expertId removed from queue & status.');
      }
    } catch (e) {
      debugPrint('Error setting expert online status: $e');
      rethrow;
    }
  }

  /// Helper method to lock an expert for a call
  Future<bool> lockExpertForCall(String expertUid, String callerUid) async {
    try {
      final ref = _db.ref('active_calls/$expertUid');
      final result = await ref.runTransaction((Object? post) {
        if (post == null) {
          return Transaction.success({
            'callerUid': callerUid,
            'status': 'locked',
            'lockedAt': ServerValue.timestamp,
          });
        }
        
        // If there's already data (meaning someone else locked them), abort
        return Transaction.abort();
      });
      return result.committed;
    } catch (e) {
      debugPrint('Error locking expert $expertUid: $e');
      return false;
    }
  }

  /// Unlocks the expert instantly
  Future<void> unlockExpert(String expertUid) async {
    try {
      await _db.ref('active_calls/$expertUid').remove();
    } catch (e) {
      debugPrint('Error unlocking expert $expertUid: $e');
    }
  }

  /// Finds and locks an expert using the new 5-second polling algorithm
  Future<String?> findAndLockExpert(String callerUid, String preferredGender, String preferredLanguage) async {
    // Dynamic Bucket Path. Ensure these language buckets are created and indexed (.indexOn: .value) in RTDB.
    final String bucketPath = 'queues/${preferredGender.toLowerCase()}_${preferredLanguage.toLowerCase()}';
    
    int maxRetries = 2; // Do not loop infinitely
    int consecutiveFailures = 0;

    for (int retry = 0; retry < maxRetries; retry++) {
      if (retry > 0) {
        // Retry Delay
        await Future.delayed(const Duration(seconds: 1));
      }

      try {
        // Query & Pool Size: Fetch the longest-waiting experts using dynamic limit
        final DataSnapshot snapshot = await _db
            .ref(bucketPath)
            .orderByChild('timestamp')
            .limitToFirst(_getInstantPoolSize())
            .get();

        if (snapshot.exists && snapshot.value != null) {
          final Map<dynamic, dynamic> data = snapshot.value as Map<dynamic, dynamic>;
          
          // Greedy Shuffle
          List<String> expertIds = data.keys.map((e) => e.toString()).toList();
          expertIds.shuffle();

          // Locking: Loop through the shuffled list
          for (String expertUid in expertIds) {
            bool isLocked = await lockExpertForCall(expertUid, callerUid);
            
            if (isLocked) {
              bool isRinging = false;
              StreamSubscription? statusSub;
              
              try {
                final completer = Completer<bool>();
                
                // TARGETED LISTENERS (Critical): Listen strictly to the specific path
                statusSub = _db.ref('active_calls/$expertUid/status').onValue.listen((event) {
                  if (event.snapshot.value == 'ringing') {
                    if (!completer.isCompleted) completer.complete(true);
                  }
                });

                // The 5-Second Timeout
                isRinging = await completer.future.timeout(
                  const Duration(seconds: 5),
                  onTimeout: () => false,
                );
              } catch (e) {
                debugPrint('Error waiting for ringing status: $e');
              } finally {
                // Clean up StreamSubscriptions
                await statusSub?.cancel();
              }

              if (isRinging) {
                // HANDOVER TO UI: expert is alive. IMMEDIATELY return expertUid and completely break
                return expertUid;
              } else {
                // Fallback & Jump: timeout hits without 'ringing', unlock instantly
                await unlockExpert(expertUid);
                consecutiveFailures++;

                // Max Fails: If 2 consecutive locked experts fail, abort matchmaking completely
                if (consecutiveFailures >= 2) {
                  return null;
                }
                
                // Continue to the next expert in the list
                continue;
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Matchmaking query error: $e');
      }
    }

    return null; // All retries failed
  }
}
