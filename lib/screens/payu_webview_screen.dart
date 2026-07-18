import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../theme/app_colors.dart';

class PayUWebViewScreen extends StatefulWidget {
  final String merchantKey;
  final String hash;
  final String txnId;
  final String amount;
  final String productInfo;
  final String firstName;
  final String email;
  final String phone;
  final String surl;
  final String furl;

  const PayUWebViewScreen({
    super.key,
    required this.merchantKey,
    required this.hash,
    required this.txnId,
    required this.amount,
    required this.productInfo,
    required this.firstName,
    required this.email,
    required this.phone,
    required this.surl,
    required this.furl,
  });

  @override
  State<PayUWebViewScreen> createState() => _PayUWebViewScreenState();
}

class _PayUWebViewScreenState extends State<PayUWebViewScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (String url) {
            if (mounted) setState(() => _isLoading = false);
          },
          onNavigationRequest: (NavigationRequest request) {
            // INTERCEPT LOGIC
            if (request.url.startsWith(widget.surl)) {
              Navigator.pop(context, true); // true = success
              return NavigationDecision.prevent;
            } else if (request.url.startsWith(widget.furl)) {
              Navigator.pop(context, false); // false = failure
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      );

    _loadPaymentRequest();
  }

  void _loadPaymentRequest() {
    // Construct POST parameters
    final Map<String, String> params = {
      'key': widget.merchantKey,
      'txnid': widget.txnId,
      'amount': widget.amount,
      'productinfo': widget.productInfo,
      'firstname': widget.firstName,
      'email': widget.email,
      'phone': widget.phone,
      'surl': widget.surl,
      'furl': widget.furl,
      'hash': widget.hash,
      'udf1': '', // PayU requires these if part of hash, but typically not required unless hashed
      'udf2': '',
      'udf3': '',
      'udf4': '',
      'udf5': '',
    };

    final String postData = params.entries
        .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');

    _controller.loadRequest(
      Uri.parse('https://secure.payu.in/_payment'),
      method: LoadRequestMethod.post,
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: Uint8List.fromList(utf8.encode(postData)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Complete Payment', style: TextStyle(color: Colors.white)),
        backgroundColor: AppColors.primaryBlue,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(color: AppColors.primaryBlue),
            ),
        ],
      ),
    );
  }
}
