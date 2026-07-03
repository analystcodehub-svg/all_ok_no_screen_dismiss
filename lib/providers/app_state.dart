import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AppState extends ChangeNotifier {
  // Authentication state
  String _mobileNumber = '';
  String get mobileNumber => _mobileNumber;

  // Gender / Role selection state
  String _selectedGender = ''; // 'Male' or 'Female' or ''
  String get selectedGender => _selectedGender;

  // Female Onboarding flow state
  String _nickname = '';
  String get nickname => _nickname;

  String _uid = '';
  String get uid {
    if (_uid.isNotEmpty) return _uid;
    return FirebaseAuth.instance.currentUser?.uid ?? '';
  }

  int _birthYear = 2001;
  int get birthYear => _birthYear;

  String _primaryLanguage = 'Hindi';
  String get primaryLanguage => _primaryLanguage;

  final List<String> _otherLanguages = [];
  List<String> get otherLanguages => List.unmodifiable(_otherLanguages);

  bool _isAudioVerified = false;
  bool get isAudioVerified => _isAudioVerified;

  // Female Expert Dashboard state
  bool _isOnline = false;
  bool get isOnline => _isOnline;

  double _totalEarnings = 0.0;
  double get totalEarnings => _totalEarnings;

  // Male Caller Dashboard state
  double _walletBalance = 0.0;
  double get walletBalance => _walletBalance;

  bool _hasUsedFreeCall = false;
  bool get hasUsedFreeCall => _hasUsedFreeCall;

  // Setters
  void setMobileNumber(String number) {
    _mobileNumber = number;
    notifyListeners();
  }

  void setSelectedGender(String gender) {
    _selectedGender = gender;
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

  void setOnlineStatus(bool online) {
    _isOnline = online;
    notifyListeners();
  }

  void addEarnings(double amount) {
    _totalEarnings += amount;
    notifyListeners();
  }

  void setWalletBalance(double balance) {
    _walletBalance = balance;
    notifyListeners();
  }

  void setHasUsedFreeCall(bool used) {
    _hasUsedFreeCall = used;
    notifyListeners();
  }

  void addWalletBalance(double amount) {
    _walletBalance += amount;
    notifyListeners();
  }

  void deductWalletBalance(double amount) {
    if (_walletBalance >= amount) {
      _walletBalance -= amount;
    } else {
      _walletBalance = 0;
    }
    notifyListeners();
  }

  void reset() {
    _mobileNumber = '';
    _selectedGender = '';
    _nickname = '';
    _birthYear = 2001;
    _primaryLanguage = 'Hindi';
    _otherLanguages.clear();
    _isAudioVerified = false;
    _isOnline = false;
    _totalEarnings = 0.0;
    _walletBalance = 0.0;
    _hasUsedFreeCall = false;
    notifyListeners();
  }
}
