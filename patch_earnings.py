import sys

def patch_file(filepath, replacement_map):
    with open(filepath, 'r') as f:
        content = f.read()
    
    for old, new in replacement_map.items():
        if old in content:
            content = content.replace(old, new)
        else:
            print(f"Warning: Not found in {filepath}: {old[:30]}")
            
    with open(filepath, 'w') as f:
        f.write(content)

filepath = "lib/screens/active_call_page.dart"

old_hangup = """    // Credit expert earnings and update talk time at end of call (only if >= 50 seconds)
    if (!widget.isCaller) {
      if (_duration >= 50) {
        int callMinutes = _duration ~/ 60;
        if (_duration % 60 >= 50) {
          callMinutes += 1;
        }
        final earned = _expertEarningRate * callMinutes;
        
        _updateExpertStats(earned, _duration, 'hindi');
        debugPrint('Expert earned: ₹${earned.toStringAsFixed(2)} (${_duration}s at ₹$_expertEarningRate/min, billed as $callMinutes min)');
      } else if (_duration > 0) {"""

new_hangup = """    // Credit expert earnings and update talk time at end of call (only if >= 50 seconds)
    if (!widget.isCaller) {
      if (_duration >= 50) {
        // Fetch caller's logged duration to prevent ghost call earnings
        _verifyAndCreditExpertEarnings();
      } else if (_duration > 0) {"""

old_update = """  Future<void> _updateExpertStats(double earned, int seconds, String language) async {"""

new_update = """  Future<void> _verifyAndCreditExpertEarnings() async {
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
  }

  Future<void> _updateExpertStats(double earned, int seconds, String language) async {"""

patch_file(filepath, {
    old_hangup: new_hangup,
    old_update: new_update
})

print("Patched earnings logic!")
