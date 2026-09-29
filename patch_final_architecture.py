import sys

def patch_file(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    # Block 1
    content = content.replace(
        "  Widget build(BuildContext context) {\n    return Scaffold(",
        "  Widget build(BuildContext context) {\n    return WillPopScope(\n      onWillPop: () async {\n        _triggerHangup();\n        return false;\n      },\n      child: Scaffold("
    )
    
    # Block 2 (hacky but works)
    content = content.replace(
        "          ),\n        ),\n      ),\n    );\n  }\n\n  @override",
        "          ),\n        ),\n      ),\n    ),\n    );\n  }\n\n  @override"
    )
    
    # Block 3
    content = content.replace(
        "          if (mounted) {\n            setState(() {\n              _roomId = generatedRoomId;\n              if (_callService.localStream != null) {\n                _localRenderer.srcObject = _callService.localStream;\n              }\n            });\n          }\n        } catch (e) {",
        "          if (mounted) {\n            setState(() {\n              _roomId = generatedRoomId;\n              if (_callService.localStream != null) {\n                _localRenderer.srcObject = _callService.localStream;\n              }\n            });\n          } else {\n            _callService.endCall(generatedRoomId);\n          }\n        } catch (e) {"
    )

    # Block 4
    old_timer = """      if (_duration > 0 && (_duration - 1) % 60 == 0) {
        if (widget.isCaller) {
          if (widget.isFirstFreeCall && _duration <= 120) {
            // First 2 minutes are free, do not deduct wallet
          } else {
            final requiredCoins = (widget.pricePerMin * 10).toInt();
            final currentBalance = context.read<AppState>().coinBalance;
            
            // Check if they have enough balance for this new minute
            if (currentBalance < requiredCoins) {
              _triggerHangup();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Call ended: Insufficient balance')),
              );
            } else {
              // Deduct for the upcoming minute
              context.read<AppState>().deductCoinBalance(requiredCoins);
            }
          }
        }
        // Expert earnings are credited at call end in _hangupLocal()
      }"""
    
    new_timer = """      if (_duration > 0 && (_duration - 1) % 60 == 0) {
        if (widget.isCaller) {
          bool isFreeMinute = widget.isFirstFreeCall && _duration <= 120;
          if (!isFreeMinute) {
            final requiredCoins = (widget.pricePerMin * 10).toInt();
            final currentBalance = context.read<AppState>().coinBalance;
            
            if (currentBalance < requiredCoins) {
              _triggerHangup();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Call ended: Insufficient balance')),
              );
              return;
            } else {
              context.read<AppState>().deductCoinBalance(requiredCoins);
              // Deduct Firestore instantly
              FirebaseFirestore.instance.collection('users').doc(widget.callerId).update({
                'coinBalance': FieldValue.increment(-requiredCoins),
              }).catchError((e) => debugPrint('Error syncing caller wallet deduction: $e'));
            }
          }
          
          // Male incrementally logs the duration!
          _saveCallLogIncremental();
        }
      }"""
    content = content.replace(old_timer, new_timer)

    # Block 5
    old_hangup = """    _saveCallLog();
    
    // Sync Caller's Wallet Deduction to Firestore exactly once at the end
    if (widget.isCaller && _duration > 0) {
      int callMinutes = (_duration / 60).ceil();
      if (widget.isFirstFreeCall) {
        callMinutes = (callMinutes >= 2) ? (callMinutes - 2) : 0;
      }
      if (callMinutes > 0) {
        final coinsToDeduct = callMinutes * (widget.pricePerMin * 10).toInt();
        
        // We can just query by callerId (which is the uid for users)
        final callerUid = widget.callerId; 
        
        FirebaseFirestore.instance.collection('users').doc(callerUid).update({
          'coinBalance': FieldValue.increment(-coinsToDeduct),
        }).catchError((e) => debugPrint('Error syncing caller wallet deduction: $e'));
        
        debugPrint('Caller billed for $callMinutes mins: -$coinsToDeduct coins synced to Firestore');
      }
    }

    // Credit expert earnings and update talk time at end of call (only if >= 50 seconds)
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

    new_hangup = """    // Final sync for any remaining seconds
    if (widget.isCaller) {
      _saveCallLogIncremental();
    }
    
    // Caller's Wallet is now safely deducted incrementally in the timer!

    // Credit expert earnings and update talk time at end of call (only if >= 50 seconds)
    if (!widget.isCaller) {
      if (_duration >= 50) {
        // Fetch caller's logged duration to prevent ghost call earnings
        _verifyAndCreditExpertEarnings();
      } else if (_duration > 0) {"""
    content = content.replace(old_hangup, new_hangup)

    # Block 6
    old_save = """  void _saveCallLog() async {
    try {
      final logId = 'log_${_roomId ?? DateTime.now().millisecondsSinceEpoch}';
      
      final logData = {
        'roomId': _roomId,
        'callerId': widget.callerId,
        'receiverId': widget.receiverId,
        'callerName': widget.callerName,
        'receiverName': widget.receiverName,
        'timestamp': FieldValue.serverTimestamp(),
        'durationSeconds': _duration,
        'isFreeCall': widget.isFirstFreeCall,
      };

      // 1. Save to local SQLite
      await DatabaseHelper.instance.insertCallLog(logData);

      // 2. Save to Firestore for cross-device sync (Only caller writes to avoid duplicate writes)
      if (widget.isCaller) {
        await FirebaseFirestore.instance.collection('call_logs').doc(logId).set(logData);
      }
    } catch (e) {
      debugPrint('Error saving call log: $e');
    }
  }"""
    
    new_save = """  void _saveCallLogIncremental() async {
    try {
      final logId = 'log_${_roomId ?? DateTime.now().millisecondsSinceEpoch}';
      
      final logData = {
        'roomId': _roomId,
        'callerId': widget.callerId,
        'receiverId': widget.receiverId,
        'callerName': widget.callerName,
        'receiverName': widget.receiverName,
        'timestamp': FieldValue.serverTimestamp(),
        'durationSeconds': _duration,
        'isFreeCall': widget.isFirstFreeCall,
      };

      // Only male (caller) writes to Firestore incrementally
      if (widget.isCaller) {
        await FirebaseFirestore.instance.collection('call_logs').doc(logId).set(logData, SetOptions(merge: true));
        // Update local sqlite only once at the end
        if (_isHangingUp) {
          await DatabaseHelper.instance.insertCallLog(logData);
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
    content = content.replace(old_save, new_save)

    with open(filepath, 'w') as f:
        f.write(content)

patch_file("lib/screens/active_call_page.dart")
