import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:payu_checkoutpro_flutter/payu_checkoutpro_flutter.dart';
import 'package:payu_checkoutpro_flutter/PayUConstantKeys.dart';
import '../providers/app_state.dart';
import 'payment_history_screen.dart';

class RechargePackage {
  final double amount;
  final int coins;
  final int bonusCoins;
  final String? badge;
  final String? extraText;
  final Color? badgeColor;

  const RechargePackage({
    required this.amount,
    required this.coins,
    required this.bonusCoins,
    this.badge,
    this.extraText,
    this.badgeColor,
  });
}

class WalletRechargeScreen extends StatefulWidget {
  const WalletRechargeScreen({super.key});

  @override
  State<WalletRechargeScreen> createState() => _WalletRechargeScreenState();
}

class _WalletRechargeScreenState extends State<WalletRechargeScreen> implements PayUCheckoutProProtocol {
  late PayUCheckoutProFlutter _checkoutPro;
  
  final List<RechargePackage> _packages = const [
    RechargePackage(amount: 20.0, coins: 200, bonusCoins: 0),
    RechargePackage(amount: 50.0, coins: 500, bonusCoins: 30, extraText: "+6% Extra"),
    RechargePackage(amount: 100.0, coins: 1000, bonusCoins: 150, extraText: "+15% Extra"),
    RechargePackage(amount: 140.0, coins: 1400, bonusCoins: 280, extraText: "+20% Extra", badge: "Value Pack", badgeColor: Color(0xFFEF4444)),
    RechargePackage(amount: 200.0, coins: 2000, bonusCoins: 500, extraText: "+25% Extra"),
    RechargePackage(amount: 300.0, coins: 3000, bonusCoins: 1050, extraText: "+35% Extra", badge: "Popular", badgeColor: Color(0xFFEF4444)),
    RechargePackage(amount: 500.0, coins: 5000, bonusCoins: 1750, extraText: "+35% Extra"),
    RechargePackage(amount: 900.0, coins: 9000, bonusCoins: 3150, extraText: "+35% Extra"),
    RechargePackage(amount: 1900.0, coins: 19000, bonusCoins: 7600, extraText: "+40% Extra"),
    RechargePackage(amount: 9800.0, coins: 98000, bonusCoins: 39200, extraText: "+40% Extra"),
    RechargePackage(amount: 15000.0, coins: 150000, bonusCoins: 67500, extraText: "+45% Extra"),
  ];

  int _selectedPackageIndex = 0;
  bool _isLoading = false;
  String _lastSelectedGateway = 'Unknown';
  String _lastTxnId = '';

  final String _merchantKey = "8e0HBa";
  final String _merchantSalt = "vohCOn4XuJr0AHh2lojBj1WLv6euGVka";
  final String _environment = "0"; // "0" for Production, "1" for Test

  @override
  void initState() {
    super.initState();
    _checkoutPro = PayUCheckoutProFlutter(this);
  }

  double get _payableAmount => _packages[_selectedPackageIndex].amount;
  int get _totalCoinsCredited => _packages[_selectedPackageIndex].coins + _packages[_selectedPackageIndex].bonusCoins;

  @override
  generateHash(Map response) {
    var hashName = response[PayUHashConstantsKeys.hashName];
    var hashStringWithoutSalt = response[PayUHashConstantsKeys.hashString];
    var postSalt = response[PayUHashConstantsKeys.postSalt];
    var hashType = response[PayUHashConstantsKeys.hashType];
    
    String generatedHash = '';

    if (hashType == 'V2') {
      var hmac = Hmac(sha256, utf8.encode(_merchantSalt));
      var digest = hmac.convert(utf8.encode(hashStringWithoutSalt));
      generatedHash = digest.toString();
    } else {
      String hashDataWithSalt = hashStringWithoutSalt + _merchantSalt;
      if (postSalt != null && postSalt.toString().isNotEmpty) {
        hashDataWithSalt = hashDataWithSalt + postSalt.toString();
      }
      var bytes = utf8.encode(hashDataWithSalt);
      var digest = sha512.convert(bytes);
      generatedHash = digest.toString();
    }
    
    Map hashResponse = {hashName: generatedHash};
    _checkoutPro.hashGenerated(hash: hashResponse);
  }

  @override
  onPaymentSuccess(dynamic response) async {
    await _syncWalletToFirestore(success: true, gateway: _lastSelectedGateway, txnId: _lastTxnId);
  }

  @override
  onPaymentFailure(dynamic response) {
    _showSnackBar("Payment Failed or Cancelled.", isError: true);
  }

  @override
  onPaymentCancel(dynamic response) {
    _showSnackBar("Payment Cancelled.", isError: true);
  }

  @override
  onError(dynamic response) {
    _showSnackBar("Payment Error: ${response?.toString() ?? 'Unknown'}", isError: true);
  }

  Future<void> _syncWalletToFirestore({required bool success, required String gateway, required String txnId}) async {
    if (!success) return;
    
    setState(() => _isLoading = true);
    final appState = context.read<AppState>();
    final mobile = appState.mobileNumber.isNotEmpty ? appState.mobileNumber : "test_mobile";
    
    try {
      final userDocRef = FirebaseFirestore.instance.collection('users').doc(mobile);
      final rechargeDocRef = FirebaseFirestore.instance.collection('recharge_history').doc(txnId);
      
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final docSnapshot = await transaction.get(userDocRef);
        int currentBalance = 0;
        if (docSnapshot.exists) {
          currentBalance = (docSnapshot.data()?['coinBalance'] as num?)?.toInt() ?? 0;
        }
        
        int newBalance = currentBalance + _totalCoinsCredited;
        transaction.set(userDocRef, {
          'mobileNumber': mobile,
          'coinBalance': newBalance,
          'lastRechargedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        
        transaction.set(rechargeDocRef, {
          'userId': mobile,
          'amount': _payableAmount,
          'coinsCredited': _totalCoinsCredited,
          'gateway': gateway,
          'status': 'success',
          'timestamp': FieldValue.serverTimestamp(),
          'txnId': txnId,
        });

        appState.setCoinBalance(newBalance);
      });

      _showSnackBar("Recharge Successful! ₹${(_totalCoinsCredited / 10).toStringAsFixed(0)} added.");
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _showSnackBar("Recharge succeeded but failed to sync balance: $e", isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _startPhonePePaymentFlow() {
    final appState = context.read<AppState>();
    final mobile = appState.mobileNumber.isNotEmpty ? appState.mobileNumber : "9876543210";
    final nickname = appState.nickname.isNotEmpty ? appState.nickname : "Guest";
    final txnid = "TXN${DateTime.now().millisecondsSinceEpoch}";
    
    _lastSelectedGateway = 'PhonePe';
    _lastTxnId = txnid;

    var payUPaymentParams = {
      PayUPaymentParamKey.key: _merchantKey,
      PayUPaymentParamKey.amount: _payableAmount.toStringAsFixed(2),
      PayUPaymentParamKey.productInfo: "Wallet Recharge",
      PayUPaymentParamKey.firstName: nickname,
      PayUPaymentParamKey.email: "guest@sajnire.com",
      PayUPaymentParamKey.phone: mobile,
      PayUPaymentParamKey.transactionId: txnid,
      PayUPaymentParamKey.environment: _environment,
      PayUPaymentParamKey.userCredential: "$_merchantKey:$mobile",
      PayUPaymentParamKey.android_surl: "https://payu.herokuapp.com/ios_success",
      PayUPaymentParamKey.android_furl: "https://payu.herokuapp.com/ios_failure",
      PayUPaymentParamKey.ios_surl: "https://payu.herokuapp.com/ios_success",
      PayUPaymentParamKey.ios_furl: "https://payu.herokuapp.com/ios_failure",
      PayUPaymentParamKey.additionalParam: {
        "enforce_paymethod": "upi",
      },
    };

    var payUCheckoutProConfig = {
      PayUCheckoutProConfigKeys.merchantName: "SajniRe",
      PayUCheckoutProConfigKeys.primaryColor: "#5E35B1", // PhonePe Purple Theme
      PayUCheckoutProConfigKeys.secondaryColor: "#1E293B",
      PayUCheckoutProConfigKeys.autoSelectOtp: true,
      PayUCheckoutProConfigKeys.waitingTime: 30000,
      PayUCheckoutProConfigKeys.enforcePaymentList: [
        {
          "payment_type": "UPI",
          "enforce_ibiboCode": "PHONEPE"
        }
      ],
    };

    try {
      _checkoutPro.openCheckoutScreen(
        payUPaymentParams: payUPaymentParams,
        payUCheckoutProConfig: payUCheckoutProConfig,
      );
    } catch (e) {
      _showSnackBar("Failed to open payment gateway: $e", isError: true);
    }
  }

  void _startPayUPaymentFlow() {
    final appState = context.read<AppState>();
    final mobile = appState.mobileNumber.isNotEmpty ? appState.mobileNumber : "9876543210";
    final nickname = appState.nickname.isNotEmpty ? appState.nickname : "Guest";
    final txnid = "TXN${DateTime.now().millisecondsSinceEpoch}";

    _lastSelectedGateway = 'PayU';
    _lastTxnId = txnid;

    var payUPaymentParams = {
      PayUPaymentParamKey.key: _merchantKey,
      PayUPaymentParamKey.amount: _payableAmount.toStringAsFixed(2),
      PayUPaymentParamKey.productInfo: "Wallet Recharge",
      PayUPaymentParamKey.firstName: nickname,
      PayUPaymentParamKey.email: "guest@sajnire.com",
      PayUPaymentParamKey.phone: mobile,
      PayUPaymentParamKey.transactionId: txnid,
      PayUPaymentParamKey.environment: _environment,
      PayUPaymentParamKey.userCredential: "$_merchantKey:$mobile",
      PayUPaymentParamKey.android_surl: "https://payu.herokuapp.com/ios_success",
      PayUPaymentParamKey.android_furl: "https://payu.herokuapp.com/ios_failure",
      PayUPaymentParamKey.ios_surl: "https://payu.herokuapp.com/ios_success",
      PayUPaymentParamKey.ios_furl: "https://payu.herokuapp.com/ios_failure",
      PayUPaymentParamKey.additionalParam: {
        "enforce_paymethod": "upi",
      },
    };

    var payUCheckoutProConfig = {
      PayUCheckoutProConfigKeys.merchantName: "SajniRe",
      PayUCheckoutProConfigKeys.primaryColor: "#3B82F6",
      PayUCheckoutProConfigKeys.secondaryColor: "#1E293B",
      PayUCheckoutProConfigKeys.autoSelectOtp: true,
      PayUCheckoutProConfigKeys.waitingTime: 30000,
      PayUCheckoutProConfigKeys.enforcePaymentList: [
        {"payment_type": "UPI"}
      ],
    };

    try {
      _checkoutPro.openCheckoutScreen(
        payUPaymentParams: payUPaymentParams,
        payUCheckoutProConfig: payUCheckoutProConfig,
      );
    } catch (e) {
      _showSnackBar("Failed to open payment gateway: $e", isError: true);
    }
  }

  void _startGooglePlayPaymentFlow() {
    _lastSelectedGateway = 'Google Play';
    _showSnackBar("Google Play payment integration is coming soon.", isError: true);
  }

  void _showPaymentOptionsBottomSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Select Payment Method',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.play_arrow_rounded, color: Colors.green, size: 28),
                ),
                title: const Text('Google Play', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Pay securely via Google', style: TextStyle(fontSize: 12)),
                tileColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _startGooglePlayPaymentFlow();
                },
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.purple.withOpacity(0.05),
                    shape: BoxShape.circle,
                  ),
                  child: ClipOval(
                    child: Image.network(
                      'https://uxwing.com/wp-content/themes/uxwing/download/brands-and-social-media/phonepe-icon.png',
                      width: 36,
                      height: 36,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => const Icon(Icons.payment, color: Colors.purple, size: 28),
                    ),
                  ),
                ),
                title: const Text('PhonePe', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Secure payment via PayU', style: TextStyle(fontSize: 12)),
                tileColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _startPhonePePaymentFlow();
                },
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.account_balance_wallet_rounded, color: Colors.blue, size: 28),
                ),
                title: const Text('Other UPI Options', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('GPay, Paytm, etc. (via PayU)', style: TextStyle(fontSize: 12)),
                tileColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _startPayUPaymentFlow();
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  Widget _buildVerticalDivider() {
    return Container(
      height: 24,
      width: 1,
      color: const Color(0xFFCBD5E1),
      margin: const EdgeInsets.symmetric(horizontal: 16),
    );
  }

  Widget _buildTrustBadge(IconData icon, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 24, color: const Color(0xFF475569)),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF475569), fontWeight: FontWeight.w500)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final coinBalance = context.watch<AppState>().coinBalance;
    final Color bgColor = const Color(0xFFF9F5FA);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF312E81), Color(0xFF1E1B4B)], // Midnight Blue gradient
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Wallet', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0, top: 10.0, bottom: 10.0),
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PaymentHistoryScreen()),
                );
              },
              icon: const Icon(Icons.swap_vert_rounded, size: 16, color: Colors.white),
              label: const Text('Transactions', style: TextStyle(color: Colors.white)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.white),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12), // Sharper corners
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
          )
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Balance Card
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.02),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('My Balance', style: TextStyle(color: Color(0xFF64748B), fontSize: 16, fontWeight: FontWeight.w600)),
                      Text(
                        '₹${(coinBalance / 10).toStringAsFixed(2)}',
                        style: const TextStyle(color: Color(0xFF3B82F6), fontSize: 26, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                const Text('Add Balance to Wallet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                const SizedBox(height: 16),

                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _packages.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final package = _packages[index];
                    final isSelected = _selectedPackageIndex == index;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedPackageIndex = index),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFFEFF6FF) : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected ? const Color(0xFF3B82F6) : Colors.grey.shade200,
                            width: isSelected ? 2.0 : 1.0,
                          ),
                          boxShadow: isSelected ? [] : [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.02),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: isSelected ? const Color(0xFF3B82F6).withOpacity(0.1) : Colors.grey.shade100,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.account_balance_wallet_rounded,
                                    color: isSelected ? const Color(0xFF3B82F6) : Colors.grey.shade600,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '₹${package.amount.toStringAsFixed(0)}',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800,
                                        color: isSelected ? const Color(0xFF1E3A8A) : const Color(0xFF0F172A),
                                      ),
                                    ),
                                    if (package.extraText != null) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        package.extraText!,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF10B981),
                                        ),
                                      ),
                                    ]
                                  ],
                                ),
                              ],
                            ),
                            if (package.badge != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: package.badgeColor ?? const Color(0xFFEF4444),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  package.badge!,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 32),
                
                // Trust badges row
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildTrustBadge(Icons.shield_outlined, '100% Safe'),
                      _buildVerticalDivider(),
                      _buildTrustBadge(Icons.account_balance_outlined, 'Bank Approved'),
                    ],
                  ),
                ),
                
                const SizedBox(height: 140), // padding for CTA
              ],
            ),
          ),
          
          // Bottom CTA
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.only(top: 16, bottom: 20, left: 20, right: 20),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if ((_packages[_selectedPackageIndex].bonusCoins / 10) > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Get ₹${(_packages[_selectedPackageIndex].bonusCoins / 10).toStringAsFixed(0)} Extra cashback on this pack',
                        style: const TextStyle(
                          color: Color(0xFF10B981),
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _showPaymentOptionsBottomSheet,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF97316), // Sunset Orange
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), // Sharper corners
                      ),
                      child: _isLoading 
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white))
                        : const Text(
                            'Add Balance',
                            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
