import sys

def patch_file(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    old_save = """  Future<void> _saveCallLog() async {
    try {
      final status = _duration > 0 ? 'ended' : 'missed';
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      // Use roomId to ensure consistent logId between caller and receiver, avoiding duplicate Firestore records
      final logId = 'log_${_roomId ?? timestamp}';
      
      final logData = {
        'logId': logId,
        'callerId': widget.callerId,
        'receiverId': widget.receiverId,
        'otherUserName': widget.nickname,
        'durationSeconds': _duration,
        'status': status,
        'timestamp': timestamp,
      };

      // 1. Save locally for instant Recents tab loading
      await LocalChatDatabase.instance.saveCallLogLocally(logData);

      // 2. Save to Firestore for cross-device sync (Only caller writes to avoid duplicate writes)
      if (widget.isCaller) {
        await FirebaseFirestore.instance.collection('call_logs').doc(logId).set(logData);
      }
    } catch (e) {
      debugPrint('Error saving call log: $e');
    }
  }"""

    new_save = """  Future<void> _saveCallLogIncremental() async {
    try {
      final status = _duration > 0 ? 'ended' : 'missed';
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final logId = 'log_${_roomId ?? timestamp}';
      
      final logData = {
        'logId': logId,
        'callerId': widget.callerId,
        'receiverId': widget.receiverId,
        'otherUserName': widget.nickname,
        'durationSeconds': _duration,
        'status': status,
        'timestamp': timestamp,
      };

      if (widget.isCaller) {
        // INCREMENTAL FIX: Continuously sync the exact duration to the database!
        await FirebaseFirestore.instance.collection('call_logs').doc(logId).set(logData, SetOptions(merge: true));
        
        // Only save to local SQLite at the very end of the call to avoid UI flickering
        if (_isHangingUp) {
          await LocalChatDatabase.instance.saveCallLogLocally(logData);
        }
      }
    } catch (e) {
      debugPrint('Error saving incremental call log: $e');
    }
  }

  Future<void> _verifyAndCreditExpertEarnings() async {
    final localDuration = _duration;
    final logId = 'log_${_roomId ?? DateTime.now().millisecondsSinceEpoch}';
    
    try {
      DocumentSnapshot<Map<String, dynamic>>? logDoc;
      // Wait up to 5 seconds for the caller to write the call log to Firestore
      for (int i = 0; i < 5; i++) {
        logDoc = await FirebaseFirestore.instance.collection('call_logs').doc(logId).get();
        if (logDoc.exists) break;
        await Future.delayed(const Duration(seconds: 1));
      }
      
      int actualDuration = localDuration;
      if (logDoc != null && logDoc.exists) {
        final data = logDoc.data()!;
        final callerDuration = (data['durationSeconds'] as num?)?.toInt() ?? 0;
        // Use the caller's duration if it's smaller, to give the exact figure
        if (callerDuration < actualDuration) {
          actualDuration = callerDuration;
        }
      } else {
        actualDuration = 0;
        debugPrint('Caller did not log the call (logDoc missing). Forcing actualDuration to 0 to prevent ghost earning.');
      }
      
      if (actualDuration >= 50) {
        int callMinutes = actualDuration ~/ 60;
        if (actualDuration % 60 >= 50) {
          callMinutes += 1;
        }
        final earned = _expertEarningRate * callMinutes;
        
        await _updateExpertStats(earned, actualDuration, 'hindi');
        debugPrint('Expert earned: ₹${earned.toStringAsFixed(2)} (${actualDuration}s at ₹$_expertEarningRate/min, billed as $callMinutes min)');
      } else {
        debugPrint('Call duration on Firestore was less than 50s. No earnings.');
      }
    } catch (e) {
      debugPrint('Error verifying earnings: $e');
      // Fallback to local duration if Firestore fails
      int callMinutes = localDuration ~/ 60;
      if (localDuration % 60 >= 50) {
        callMinutes += 1;
      }
      final earned = _expertEarningRate * callMinutes;
      await _updateExpertStats(earned, localDuration, 'hindi');
    }
  }"""

    if old_save in content:
        content = content.replace(old_save, new_save)
        with open(filepath, 'w') as f:
            f.write(content)
        print("Success")
    else:
        print("Failed to find old save")

patch_file("lib/screens/active_call_page.dart")
