import sys

def patch_file(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    # 1. Replace the _startCallTimer logic
    old_timer = """    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        _duration++;
      });

      if (_duration == 1 && widget.isCaller && widget.isFirstFreeCall) {
        _markFreeCallUsed();
      }

      // At exactly 2 min (120s): free period ends, check balance immediately
      if (_duration == 120 && widget.isCaller && widget.isFirstFreeCall) {
        final balance = context.read<AppState>().coinBalance;
        if (balance < (widget.pricePerMin * 10).toInt()) {
          _triggerHangup();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Free 2 minutes over! Recharge to keep talking.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
          return;
        }
      }

      // Deduct balances at the start of every minute (1s, 61s, 121s) after free period
      // Deduct balances at the start of every minute (1s, 61s, 121s) after free period
      if (_duration > 0 && (_duration - 1) % 60 == 0) {
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
      }
    });"""

    new_timer = """    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        _duration++;
      });

      if (_duration == 1 && widget.isCaller && widget.isFirstFreeCall) {
        _markFreeCallUsed();
      }

      // At exactly 2 min (120s): free period ends, check balance immediately
      if (_duration == 120 && widget.isCaller && widget.isFirstFreeCall) {
        final balance = context.read<AppState>().coinBalance;
        if (balance < (widget.pricePerMin * 10).toInt()) {
          _triggerHangup();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Free 2 minutes over! Recharge to keep talking.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
          return;
        }
      }

      // INCREMENTAL BILLING: Sync exactly every 60 seconds (at 1s, 61s, 121s)
      if (_duration > 0 && (_duration - 1) % 60 == 0) {
        final currentMinute = ((_duration - 1) ~/ 60) + 1;
        
        if (widget.isCaller) {
          // MALE CALLER
          if (widget.isFirstFreeCall && _duration <= 120) {
            // First 2 minutes are free, do not deduct wallet, but sync minute!
            _syncMaleMinute(currentMinute, 0);
          } else {
            final requiredCoins = (widget.pricePerMin * 10).toInt();
            final currentBalance = context.read<AppState>().coinBalance;
            
            if (currentBalance < requiredCoins) {
              _triggerHangup();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Call ended: Insufficient balance')),
              );
            } else {
              context.read<AppState>().deductCoinBalance(requiredCoins);
              _syncMaleMinute(currentMinute, requiredCoins);
            }
          }
        } else {
          // FEMALE EXPERT
          // Wait 3 seconds to give the male's phone time to sync to the RTDB pipe
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) {
              _verifyAndSyncFemaleMinute(currentMinute);
            }
          });
        }
      }
    });"""

    # 2. Replace the end-of-call billing in _hangupLocal
    old_hangup = """    // Sync Caller's Wallet Deduction to Firestore exactly once at the end
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
        // Fetch caller's logged duration to prevent ghost call earnings
        _verifyAndCreditExpertEarnings();
      } else if (_duration > 0) {
        // Female talked for less than 50 seconds
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Aapko Rs 1 earn karne ke liye kam se kam 50 seconds baat karni hogi.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
      }
    }"""

    new_hangup = """    // The end-of-call mass billing has been entirely replaced by Incremental Billing!
    // Coins and Earnings were synced safely every 1 minute during the call."""


    # 3. Add the two new incremental functions
    old_verify = """  Future<void> _verifyAndCreditExpertEarnings() async {"""

    new_verify = """  Future<void> _syncMaleMinute(int minute, int coinsToDeduct) async {
    try {
      if (coinsToDeduct > 0) {
        await FirebaseFirestore.instance.collection('users').doc(widget.callerId).update({
          'coinBalance': FieldValue.increment(-coinsToDeduct)
        });
      }
      if (_roomId != null) {
        await FirebaseDatabase.instance.ref('calls/$_roomId/billedMinutes').set(minute);
      }
      debugPrint('Male synced minute $minute (Deducted $coinsToDeduct)');
    } catch (e) {
      debugPrint('Error syncing male minute: $e');
    }
  }

  Future<void> _verifyAndSyncFemaleMinute(int expectedMinute) async {
    try {
      if (_roomId == null) return;
      final snapshot = await FirebaseDatabase.instance.ref('calls/$_roomId/billedMinutes').get();
      final maleBilledMinute = (snapshot.value as num?)?.toInt() ?? 0;
      
      if (maleBilledMinute >= expectedMinute) {
        // Male successfully synced the pipe! Female earns this minute!
        await _updateExpertStats(_expertEarningRate, 60, 'hindi');
        debugPrint('Female successfully synced earnings for minute $expectedMinute');
      } else {
        // Male did NOT pay (disconnected, crashed, or ran out of money)
        debugPrint('Male failed to sync minute $expectedMinute! Hanging up.');
        _triggerHangup();
      }
    } catch (e) {
      debugPrint('Error verifying female earnings: $e');
    }
  }

  Future<void> _verifyAndCreditExpertEarnings() async {"""

    if old_timer in content:
        content = content.replace(old_timer, new_timer)
        print("Patched Timer")
    if old_hangup in content:
        content = content.replace(old_hangup, new_hangup)
        print("Patched Hangup")
    if old_verify in content:
        content = content.replace(old_verify, new_verify)
        print("Added new functions")

    with open(filepath, 'w') as f:
        f.write(content)

patch_file("lib/screens/active_call_page.dart")
