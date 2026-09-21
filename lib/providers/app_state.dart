import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppState extends ChangeNotifier {
  // Authentication state
  String _mobileNumber = '';
  String get mobileNumber => _mobileNumber;

  // Gender / Role selection state
  String _selectedGender = ''; // 'Male' or 'Female' or ''
  String get selectedGender => _selectedGender;

  // Auto-retrieved SMS code (for visible filling)
  String? _autoRetrievedSmsCode;
  String? get autoRetrievedSmsCode => _autoRetrievedSmsCode;

  // Female Onboarding flow state
  String _nickname = '';
  String get nickname => _nickname;

  final String _uid = '';
  String get uid {
    if (_uid.isNotEmpty) return _uid;
    return FirebaseAuth.instance.currentUser?.uid ?? '';
  }

  int _birthYear = 2001;
  int get birthYear => _birthYear;

  int _avatarIndex = 1;
  int get avatarIndex => _avatarIndex;

  String _primaryLanguage = 'Hindi';
  String get primaryLanguage => _primaryLanguage;

  final List<String> _otherLanguages = [];
  List<String> get otherLanguages => List.unmodifiable(_otherLanguages);

  bool _isAudioVerified = false;
  bool get isAudioVerified => _isAudioVerified;

  String _enteredReferralCode = '';
  String get enteredReferralCode => _enteredReferralCode;

  // Female Expert Dashboard state
  bool _isOnline = false;
  bool get isOnline => _isOnline;

  double _totalEarnings = 0.0;
  double get totalEarnings => _totalEarnings;

  // Male Caller Dashboard state
  int _coinBalance = 0;
  int get coinBalance => _coinBalance;

  bool _hasUsedFreeCall = false;
  bool get hasUsedFreeCall => _hasUsedFreeCall;

  int _freeMessagesUsed = 0;
  int get freeMessagesUsed => _freeMessagesUsed;

  // Setters
  void setMobileNumber(String number) {
    _mobileNumber = number;
    notifyListeners();
  }

  void setSelectedGender(String gender) {
    _selectedGender = gender;
    SharedPreferences.getInstance().then((prefs) => prefs.setString('userRole', gender.toLowerCase()));
    notifyListeners();
  }

  void setAutoRetrievedSmsCode(String? code) {
    _autoRetrievedSmsCode = code;
    notifyListeners();
  }

  void setNickname(String name) {
    _nickname = name;
    notifyListeners();
  }

  void setBirthYear(int year) {
    _birthYear = year;
    notifyListeners();
  }

  void setAvatarIndex(int index) {
    _avatarIndex = index;
    notifyListeners();
  }

  void setPrimaryLanguage(String lang) {
    _primaryLanguage = lang;
    notifyListeners();
  }

  void toggleOtherLanguage(String lang) {
    if (_otherLanguages.contains(lang)) {
      _otherLanguages.remove(lang);
    } else {
      _otherLanguages.add(lang);
    }
    notifyListeners();
  }

  void clearOtherLanguages() {
    _otherLanguages.clear();
    notifyListeners();
  }

  void setAudioVerified(bool verified) {
    _isAudioVerified = verified;
    notifyListeners();
  }

  void setEnteredReferralCode(String code) {
    _enteredReferralCode = code;
    notifyListeners();
  }

  void setOnlineStatus(bool online) {
    _isOnline = online;
    SharedPreferences.getInstance().then((prefs) => prefs.setBool('isExpertOnline', online));
    notifyListeners();
  }

  void addEarnings(double amount) {
    _totalEarnings += amount;
    notifyListeners();
  }

  void setCoinBalance(int balance) {
    _coinBalance = balance;
    notifyListeners();
  }

  void setHasUsedFreeCall(bool used) {
    _hasUsedFreeCall = used;
    notifyListeners();
  }

  void setFreeMessagesUsed(int count) {
    _freeMessagesUsed = count;
    notifyListeners();
  }

  void incrementFreeMessagesUsed() {
    _freeMessagesUsed++;
    notifyListeners();
  }

  void addCoinBalance(int amount) {
    _coinBalance += amount;
    notifyListeners();
  }

  void deductCoinBalance(int amount) {
    if (_coinBalance >= amount) {
      _coinBalance -= amount;
    } else {
      _coinBalance = 0;
    }
    notifyListeners();
  }

  // --- SharedPreferences Chat Billing Optimization ---
  int _pendingChatCoins = 0;
  int _pendingChatFreeMsgs = 0;

  int get pendingChatCoins => _pendingChatCoins;
  int get pendingChatFreeMsgs => _pendingChatFreeMsgs;

  Future<void> addPendingChatDeduction({required int coins, required int freeMsgs}) async {
    final prefs = await SharedPreferences.getInstance();
    
    if (coins > 0) {
      _pendingChatCoins += coins;
      await prefs.setInt('pendingChatCoins', _pendingChatCoins);
      deductCoinBalance(coins); // instant UI update
    }
    if (freeMsgs > 0) {
      _pendingChatFreeMsgs += freeMsgs;
      await prefs.setInt('pendingChatFreeMsgs', _pendingChatFreeMsgs);
      incrementFreeMessagesUsed(); // instant UI update
    }
    
    final myUid = uid.isNotEmpty ? uid : "test_uid";
    await prefs.setString('pendingChatUid', myUid);
  }

  void clearPendingChatDeductionsLocally() {
    _pendingChatCoins = 0;
    _pendingChatFreeMsgs = 0;
  }

  static Future<void> syncPendingChatDeductions() async {
    final prefs = await SharedPreferences.getInstance();
    final coinsToDeduct = prefs.getInt('pendingChatCoins') ?? 0;
    final freeMsgsToSync = prefs.getInt('pendingChatFreeMsgs') ?? 0;
    
    if (coinsToDeduct == 0 && freeMsgsToSync == 0) return;
    
    final myUid = prefs.getString('pendingChatUid') ?? '';
    if (myUid.isEmpty) return;

    final Map<String, dynamic> updates = {};
    if (freeMsgsToSync > 0) {
      updates['freeMessagesUsed'] = FieldValue.increment(freeMsgsToSync);
    }
    if (coinsToDeduct > 0) {
      updates['coinBalance'] = FieldValue.increment(-coinsToDeduct);
    }

    await prefs.remove('pendingChatCoins');
    await prefs.remove('pendingChatFreeMsgs');
    await prefs.remove('pendingChatUid');

    if (updates.isNotEmpty) {
      FirebaseFirestore.instance.collection('users').doc(myUid).update(updates).catchError((e) {
        debugPrint('Failed to sync chat deductions: $e');
      });
    }
  }

  void reset() {
    _mobileNumber = '';
    _selectedGender = '';
    _nickname = '';
    _birthYear = 2001;
    _avatarIndex = 1;
    _primaryLanguage = 'Hindi';
    _otherLanguages.clear();
    _isAudioVerified = false;
    _isOnline = false;
    _totalEarnings = 0.0;
    _coinBalance = 0;
    _hasUsedFreeCall = false;
    _freeMessagesUsed = 0;
    _autoRetrievedSmsCode = null;
    notifyListeners();
  }
}
