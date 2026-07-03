import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:payu_checkoutpro_flutter/payu_checkoutpro_flutter.dart';
import 'package:payu_checkoutpro_flutter/PayUConstantKeys.dart';
import '../providers/app_state.dart';

class RechargePackage {
  final double amount;
  final String bonus;
  final String? badge;
  final double bonusPercentage;

  const RechargePackage({
    required this.amount,
    required this.bonus,
    required this.bonusPercentage,
    this.badge,
  });
}

class WalletRechargeScreen extends StatefulWidget {
  const WalletRechargeScreen({super.key});

  @override
  State<WalletRechargeScreen> createState() => _WalletRechargeScreenState();
}

class _WalletRechargeScreenState extends State<WalletRechargeScreen> implements PayUCheckoutProProtocol {
  late PayUCheckoutProFlutter _checkoutPro;
  
  // Package list from the screenshots
  final List<RechargePackage> _packages = const [
    RechargePackage(amount: 15.0, bonus: "+0% Extra", bonusPercentage: 0.0),
    RechargePackage(amount: 50.0, bonus: "+6% Extra", bonusPercentage: 6.0),
    RechargePackage(amount: 100.0, bonus: "+15% Extra", bonusPercentage: 15.0),
    RechargePackage(amount: 140.0, bonus: "+20% Extra", bonusPercentage: 20.0, badge: "Value Pack"),
    RechargePackage(amount: 200.0, bonus: "+25% Extra", bonusPercentage: 25.0),
    RechargePackage(amount: 300.0, bonus: "+35% Extra", bonusPercentage: 35.0, badge: "Popular"),
    RechargePackage(amount: 500.0, bonus: "+35% Extra", bonusPercentage: 35.0),
    RechargePackage(amount: 900.0, bonus: "+35% Extra", bonusPercentage: 35.0),
    RechargePackage(amount: 1900.0, bonus: "+40% Extra", bonusPercentage: 40.0),
    RechargePackage(amount: 9800.0, bonus: "+40% Extra", bonusPercentage: 40.0),
    RechargePackage(amount: 15000.0, bonus: "+45% Extra", bonusPercentage: 45.0),
  ];

  int _selectedPackageIndex = 3; // Default ₹140 package selected
  bool _couponApplied = false;
  bool _showConfettiDialog = false;

  // PayU Credentials — LIVE / Production
  final String _merchantKey = "8e0HBa";
  final String _merchantSalt = "vohCOn4XuJr0AHh2lojBj1WLv6euGVka";
  final String _environment = "0"; // "0" for Production, "1" for Test

  @override
  void initState() {
    super.initState();
    _checkoutPro = PayUCheckoutProFlutter(this);
  }

  // Calculate dynamic values
  double get _selectedAmount => _packages[_selectedPackageIndex].amount;
  double get _bonusPercentage => _packages[_selectedPackageIndex].bonusPercentage;
  double get _extraCashback => _selectedAmount * (_bonusPercentage / 100.0);
  
  // GST 18% + fixed 6.5 processing fee matching the screenshot calculations:
  // For ₹50 package, charges = 15.5 (50 * 0.18 + 6.5 = 9.0 + 6.5 = 15.5)
  // For ₹140 package, charges = 31.7 (140 * 0.18 + 6.5 = 25.2 + 6.5 = 31.7)
  double get _taxesAndCharges => double.parse((_selectedAmount * 0.18 + 6.5).toStringAsFixed(1));
  double get _payableAmount => _selectedAmount + _taxesAndCharges;
  
  // Coupon value: flat ₹3 extra cashback for package <= 50, otherwise flat ₹8 extra cashback
  double get _couponCashback => _selectedAmount <= 50.0 ? 3.0 : 8.0;
  
  // Total benefit amount (coins credited)
  double get _totalCoinsCredited => _selectedAmount + _extraCashback + (_couponApplied ? _couponCashback : 0.0);

  // Hash generation
  @override
  generateHash(Map response) {
    debugPrint("PayU generateHash callback response: $response");
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
      // Concatenate hashString and salt
      String hashDataWithSalt = hashStringWithoutSalt + _merchantSalt;
      if (postSalt != null && postSalt.toString().isNotEmpty) {
        hashDataWithSalt = hashDataWithSalt + postSalt.toString();
      }
      
      // Compute SHA-512
      var bytes = utf8.encode(hashDataWithSalt);
      var digest = sha512.convert(bytes);
      generatedHash = digest.toString();
    }
    
    Map hashResponse = {hashName: generatedHash};
    
    debugPrint("PayU Hash Generated for $hashName: $generatedHash");
    _checkoutPro.hashGenerated(hash: hashResponse);
  }

  @override
  onPaymentSuccess(dynamic response) async {
    debugPrint("PayU Payment Success response: $response");
    await _syncWalletToFirestore(success: true);
  }

  @override
  onPaymentFailure(dynamic response) {
    debugPrint("PayU Payment Failure response: $response");
    _showSnackBar("Payment Failed or Cancelled.", isError: true);
  }

  @override
  onPaymentCancel(dynamic response) {
    debugPrint("PayU Payment Cancel response: $response");
    _showSnackBar("Payment Cancelled.", isError: true);
  }

  @override
  onError(dynamic response) {
    debugPrint("PayU Payment Error response: $response");
    _showSnackBar("Payment Error: ${response?.toString() ?? 'Unknown'}", isError: true);
  }

  Future<void> _syncWalletToFirestore({required bool success}) async {
    final appState = context.read<AppState>();
    final mobile = appState.mobileNumber.isNotEmpty ? appState.mobileNumber : "test_mobile";
    
    if (success) {
      try {
        final userDocRef = FirebaseFirestore.instance.collection('users').doc(mobile);
        
        await FirebaseFirestore.instance.runTransaction((transaction) async {
          final docSnapshot = await transaction.get(userDocRef);
          double currentBalance = 0.0;
          if (docSnapshot.exists) {
            currentBalance = (docSnapshot.data()?['walletBalance'] as num?)?.toDouble() ?? 0.0;
          }
          
          double newBalance = currentBalance + _totalCoinsCredited;
          transaction.set(userDocRef, {
            'mobileNumber': mobile,
            'walletBalance': newBalance,
            'lastRechargedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          
          // Update local AppState
          appState.setWalletBalance(newBalance);
        });

        _showSnackBar("Recharge Successful! ₹${_totalCoinsCredited.toStringAsFixed(2)} added to wallet.");
        
        // Dismiss bottom sheet and go back
        if (mounted) {
          Navigator.pop(context); // Close checkout bottom sheet if open
        }
      } catch (e) {
        debugPrint("Error syncing wallet to firestore: $e");
        _showSnackBar("Recharge succeeded but failed to sync balance: $e", isError: true);
      }
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

  void _startPayUPaymentFlow() {
    final appState = context.read<AppState>();
    final mobile = appState.mobileNumber.isNotEmpty ? appState.mobileNumber : "9876543210";
    final nickname = appState.nickname.isNotEmpty ? appState.nickname : "Guest";
    final txnid = "TXN${DateTime.now().millisecondsSinceEpoch}";

    // 1. Build Payment Parameters
    var payUPaymentParams = {
      PayUPaymentParamKey.key: _merchantKey,
      PayUPaymentParamKey.amount: _payableAmount.toStringAsFixed(2),
      PayUPaymentParamKey.productInfo: "Wallet Coins Recharge",
      PayUPaymentParamKey.firstName: nickname,
      PayUPaymentParamKey.email: "guest@sajnire.com",
      PayUPaymentParamKey.phone: mobile,
      PayUPaymentParamKey.transactionId: txnid,
      PayUPaymentParamKey.environment: _environment, // "0" for Production, "1" for Test
      PayUPaymentParamKey.userCredential: "$_merchantKey:$mobile",
      PayUPaymentParamKey.android_surl: "https://payu.in/merchant/postservice?form=2",
      PayUPaymentParamKey.android_furl: "https://payu.in/merchant/postservice?form=2",
      PayUPaymentParamKey.ios_surl: "https://payu.in/merchant/postservice?form=2",
      PayUPaymentParamKey.ios_furl: "https://payu.in/merchant/postservice?form=2",
      PayUPaymentParamKey.additionalParam: {
        "enforce_paymethod": "upi",
      },
    };

    // 2. Build Configuration
    var payUCheckoutProConfig = {
      PayUCheckoutProConfigKeys.merchantName: "SajniRe",
      PayUCheckoutProConfigKeys.primaryColor: "#3B82F6", // Blue primary
      PayUCheckoutProConfigKeys.secondaryColor: "#1E293B",
      PayUCheckoutProConfigKeys.autoSelectOtp: true,
      PayUCheckoutProConfigKeys.waitingTime: 30000,
      // Restrict payment modes to UPI only using configuration
      PayUCheckoutProConfigKeys.enforcePaymentList: [
        {"payment_type": "UPI"}
      ],
    };

    debugPrint("Opening PayU Checkout Screen for amount: ${_payableAmount.toStringAsFixed(2)}");
    try {
      _checkoutPro.openCheckoutScreen(
        payUPaymentParams: payUPaymentParams,
        payUCheckoutProConfig: payUCheckoutProConfig,
      );
    } catch (e) {
      debugPrint("Error launching PayU SDK: $e");
      _showSnackBar("Failed to open payment gateway: $e", isError: true);
    }
  }

  void _showCheckoutBottomSheet() {
    setState(() {
      _couponApplied = false;
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Container(
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(30),
                  topRight: Radius.circular(30),
                ),
              ),
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 24,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header Row with back/close and title
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: Color(0xFF0F172A)),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Text(
                        'Select Payment Method',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Recharge details card
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.02),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Recharge Amount',
                              style: TextStyle(
                                fontSize: 15,
                                color: Color(0xFF64748B),
                              ),
                            ),
                            Text(
                              '₹${_selectedAmount.toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            CustomPaint(
                              painter: DashedUnderlinePainter(color: const Color(0xFF64748B)),
                              child: const Text(
                                'Taxes and other charges',
                                style: TextStyle(
                                  fontSize: 15,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ),
                            Text(
                              '₹$_taxesAndCharges',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Divider(height: 1, color: Color(0xFFE2E8F0)),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Payable Amount',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            Text(
                              '₹${_payableAmount.toStringAsFixed(1)}',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF2563EB), // Sleek blue
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // View Coupons Card
                  GestureDetector(
                    onTap: () {
                      setModalState(() {
                        _showConfettiDialog = true;
                      });
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          const Icon(Icons.local_offer_outlined, color: Color(0xFF2563EB), size: 20),
                          const SizedBox(width: 12),
                          const Text(
                            'View All Coupons',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const Spacer(),
                          const Icon(Icons.arrow_forward_ios, size: 14, color: Color(0xFF64748B)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Confetti/Coupon Applied success Banner
                  if (_couponApplied)
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4), // Very light green
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFBBF7D0)),
                      ),
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Container(
                            decoration: const BoxDecoration(
                              color: Color(0xFF22C55E),
                              shape: BoxShape.circle,
                            ),
                            padding: const EdgeInsets.all(4),
                            child: const Icon(Icons.check, color: Colors.white, size: 14),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'You will get ₹${_totalCoinsCredited.toStringAsFixed(0)} in this recharge',
                              style: const TextStyle(
                                color: Color(0xFF15803D),
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 16),

                  // Simulated Payment Methods UI (as in screenshot)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Image.network(
                              'https://upload.wikimedia.org/wikipedia/commons/e/e1/UPI-Logo.png',
                              height: 18,
                              errorBuilder: (c, e, s) => const Icon(Icons.payment, size: 18),
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              'Pay by any UPI app',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF64748B),
                              ),
                            ),
                            const Spacer(),
                            const Text(
                              '⚡ Fastest',
                              style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFF2563EB),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Preferred by 95% Users',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF22C55E),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildUpiAppIcon('PhonePe', 'https://upload.wikimedia.org/wikipedia/commons/7/71/PhonePe_Logo.png'),
                            _buildUpiAppIcon('GPay', 'https://upload.wikimedia.org/wikipedia/commons/b/b2/Google_Pay_Logo.png'),
                            _buildUpiAppIcon('Paytm', 'https://upload.wikimedia.org/wikipedia/commons/4/42/Paytm_Logo.png'),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Bottom Action Button
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context); // Close bottom sheet
                      _startPayUPaymentFlow();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3B82F6),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      elevation: 0,
                    ),
                    child: Text(
                      'Pay ₹${_payableAmount.toStringAsFixed(1)}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  // Overlay coupon success dialog
                  if (_showConfettiDialog)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.5),
                        child: Center(
                          child: Container(
                            width: 280,
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'Extra',
                                  style: TextStyle(
                                    color: Color(0xFF22C55E),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '₹${_couponCashback.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    color: Color(0xFF22C55E),
                                    fontSize: 44,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Cashback applied!',
                                  style: TextStyle(
                                    color: Color(0xFF64748B),
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                ElevatedButton(
                                  onPressed: () {
                                    setModalState(() {
                                      _showConfettiDialog = false;
                                      _couponApplied = true;
                                    });
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF3B82F6),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                                    elevation: 0,
                                  ),
                                  child: const Text(
                                    'Okay',
                                    style: TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildUpiAppIcon(String name, String logoUrl) {
    return Column(
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: Image.network(
              logoUrl,
              fit: BoxFit.cover,
              errorBuilder: (c, e, s) => Center(
                child: Text(
                  name[0],
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          name,
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F6), // Warm background
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF0F172A), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Wallet',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.w800,
            fontSize: 22,
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16, top: 10, bottom: 10),
            child: OutlinedButton.icon(
              onPressed: () {
                _showSnackBar("No transactions found.");
              },
              icon: const Icon(Icons.swap_vert_rounded, size: 16, color: Color(0xFF2563EB)),
              label: const Text(
                'Transactions',
                style: TextStyle(
                  color: Color(0xFF2563EB),
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF2563EB)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Balance container card
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'My Balance',
                    style: TextStyle(
                      fontSize: 16,
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    '₹${appState.walletBalance.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2563EB),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
            child: Text(
              'Add Balance to Wallet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
          ),

          // Packages Grid
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 1.5,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: _packages.length,
              itemBuilder: (context, index) {
                final package = _packages[index];
                final isSelected = _selectedPackageIndex == index;

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedPackageIndex = index;
                    });
                  },
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFFEFF6FF) : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0),
                            width: isSelected ? 2.0 : 1.0,
                          ),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '₹${package.amount.toStringAsFixed(0)}',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected ? const Color(0xFF1E3A8A) : const Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                package.bonus,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF22C55E),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Overlay badge
                      if (package.badge != null)
                        Positioned(
                          top: -6,
                          right: 12,
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFF43F5E), // Coral Red
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            child: Text(
                              package.badge!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),

          // Safe icons indicators (Verified Experts, 100% Safe, Bank Approved)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            color: Colors.transparent,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildTrustIndicator(Icons.verified_user_outlined, 'Verified Experts'),
                Container(width: 1, height: 24, color: const Color(0xFFCBD5E1)),
                _buildTrustIndicator(Icons.security_outlined, '100% Safe'),
                Container(width: 1, height: 24, color: const Color(0xFFCBD5E1)),
                _buildTrustIndicator(Icons.account_balance_outlined, 'Bank Approved'),
              ],
            ),
          ),

          // Bottom Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Get ₹${_extraCashback.toStringAsFixed(0)} Extra cashback on this pack',
                  style: const TextStyle(
                    color: Color(0xFF22C55E),
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _showCheckoutBottomSheet,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3B82F6),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Add Balance',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrustIndicator(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: const Color(0xFF64748B)),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class DashedUnderlinePainter extends CustomPainter {
  final Color color;

  DashedUnderlinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    var paint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    
    double max = size.width;
    double dashWidth = 3.0;
    double dashSpace = 2.0;
    double startX = 0.0;
    
    while (startX < max) {
      canvas.drawLine(Offset(startX, size.height + 2), Offset(startX + dashWidth, size.height + 2), paint);
      startX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
