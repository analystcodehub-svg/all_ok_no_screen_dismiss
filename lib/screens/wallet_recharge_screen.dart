import 'dart:async';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../providers/app_state.dart';
import 'payment_history_screen.dart';
import 'payment_success_screen.dart';
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

class _WalletRechargeScreenState extends State<WalletRechargeScreen> {
  late StreamSubscription<List<PurchaseDetails>> _subscription;
  
  final List<RechargePackage> _packages = const [
    RechargePackage(amount: 3.0, coins: 30, bonusCoins: 0, badge: "Starter", badgeColor: Color(0xFF6366F1)),
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

  @override
  void initState() {
    super.initState();
    final Stream<List<PurchaseDetails>> purchaseUpdated = InAppPurchase.instance.purchaseStream;
    _subscription = purchaseUpdated.listen((purchaseDetailsList) {
      _listenToPurchaseUpdated(purchaseDetailsList);
    }, onDone: () {
      _subscription.cancel();
    }, onError: (error) {
      _showSnackBar("Purchase Stream Error: $error", isError: true);
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  double get _payableAmount => _packages[_selectedPackageIndex].amount;
  int get _totalCoinsCredited => _packages[_selectedPackageIndex].coins + _packages[_selectedPackageIndex].bonusCoins;

  void _listenToPurchaseUpdated(List<PurchaseDetails> purchaseDetailsList) async {
    for (var purchaseDetails in purchaseDetailsList) {
      if (purchaseDetails.status == PurchaseStatus.pending) {
        setState(() => _isLoading = true);
      } else {
        if (purchaseDetails.status == PurchaseStatus.error) {
          setState(() => _isLoading = false);
          _showSnackBar("Purchase Error: ${purchaseDetails.error?.message}", isError: true);
        } else if (purchaseDetails.status == PurchaseStatus.purchased ||
                   purchaseDetails.status == PurchaseStatus.restored) {
          bool valid = await _verifyPurchase(purchaseDetails);
          if (valid) {
            await _syncWalletToFirestore(
              success: true, 
              gateway: 'Google Play', 
              txnId: purchaseDetails.purchaseID ?? 'txn_${DateTime.now().millisecondsSinceEpoch}',
            );
          } else {
            _showSnackBar("Invalid Purchase.", isError: true);
            setState(() => _isLoading = false);
          }
        }
        if (purchaseDetails.pendingCompletePurchase) {
          await InAppPurchase.instance.completePurchase(purchaseDetails);
        }
      }
    }
  }

  Future<bool> _verifyPurchase(PurchaseDetails purchaseDetails) async {
    // In a real app, verify the receipt on your server.
    // For this simple implementation, we assume it's valid if Google says it's purchased.
    return true; 
  }

  Future<void> _syncWalletToFirestore({required bool success, required String gateway, required String txnId}) async {
    if (!success) return;
    
    setState(() => _isLoading = true);
    final appState = context.read<AppState>();
    final myUid = appState.uid.isNotEmpty ? appState.uid : "test_uid";
    
    try {
      final userDocRef = FirebaseFirestore.instance.collection('users').doc(myUid);
      final rechargeDocRef = FirebaseFirestore.instance.collection('recharge_history').doc(txnId);
      
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final docSnapshot = await transaction.get(userDocRef);
        int currentBalance = 0;
        if (docSnapshot.exists) {
          currentBalance = (docSnapshot.data()?['coinBalance'] as num?)?.toInt() ?? 0;
        }
        
        int newBalance = currentBalance + _totalCoinsCredited;
        transaction.set(userDocRef, {
          'uid': myUid,
          'coinBalance': newBalance,
          'lastRechargedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        
        transaction.set(rechargeDocRef, {
          'buyer_name': myUid,
          'userId': myUid,
          'amount': _payableAmount,
          'coinsCredited': _totalCoinsCredited,
          'gateway': gateway,
          'status': 'success',
          'timestamp': FieldValue.serverTimestamp(),
          'txnId': txnId,
        });

        appState.setCoinBalance(newBalance);
      });

      if (mounted) {
        // Direct redirect to Home screen (skipping any success screens)
        Navigator.popUntil(context, (route) => route.isFirst);
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Recharge Successful! ₹${(_totalCoinsCredited / 10).toStringAsFixed(0)} added to wallet."),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e) {
      _showSnackBar("Recharge succeeded but failed to sync balance: $e", isError: true);
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

  Future<void> _buyProduct() async {
    setState(() => _isLoading = true);
    
    // Identify which Product ID maps to the selected amount
    final amount = _packages[_selectedPackageIndex].amount.toInt();
    final productId = 'sajnire_coins_$amount';

    final bool available = await InAppPurchase.instance.isAvailable();
    if (!available) {
      setState(() => _isLoading = false);
      _showSnackBar("Store not available.", isError: true);
      return;
    }

    final ProductDetailsResponse response = await InAppPurchase.instance.queryProductDetails({productId});
    
    if (response.notFoundIDs.isNotEmpty || response.productDetails.isEmpty) {
      setState(() => _isLoading = false);
      _showSnackBar("Product $productId not configured in Play Console yet.", isError: true);
      return;
    }

    final ProductDetails productDetails = response.productDetails.first;
    final PurchaseParam purchaseParam = PurchaseParam(productDetails: productDetails);
    
    InAppPurchase.instance.buyConsumable(purchaseParam: purchaseParam, autoConsume: true);
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
                        color: Colors.black.withValues(alpha: 0.02),
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
                              color: Colors.black.withValues(alpha: 0.02),
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
                                    color: isSelected ? const Color(0xFF3B82F6).withValues(alpha: 0.1) : Colors.grey.shade100,
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
                    color: Colors.black.withValues(alpha: 0.05),
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
                      onPressed: _isLoading ? null : _buyProduct,
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
