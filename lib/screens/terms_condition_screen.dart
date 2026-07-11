import 'package:flutter/material.dart';

class TermsConditionScreen extends StatelessWidget {
  const TermsConditionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Terms & Conditions', style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Terms & Conditions', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            SizedBox(height: 16),
            Text('Welcome to SajniRe. By using our application, you agree to comply with and be bound by the following terms and conditions of use.', style: TextStyle(fontSize: 16)),
            SizedBox(height: 16),
            Text('1. Usage Policy', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('Users must be 18 years or older to use this service. You agree to use the app for lawful purposes only and in a way that does not infringe the rights of others.', style: TextStyle(fontSize: 16)),
            SizedBox(height: 16),
            Text('2. User Accounts', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('You are responsible for maintaining the confidentiality of your account and password. We reserve the right to refuse service, terminate accounts, or remove content in our sole discretion.', style: TextStyle(fontSize: 16)),
            SizedBox(height: 16),
            Text('3. Communication', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('All calls and interactions with experts are subject to our community guidelines. Any form of harassment, abuse, or inappropriate behavior will result in immediate account suspension.', style: TextStyle(fontSize: 16)),
            SizedBox(height: 16),
            Text('4. Modifications', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('We may revise these terms of service at any time without notice. By using this application you are agreeing to be bound by the then current version of these terms.', style: TextStyle(fontSize: 16)),
          ],
        ),
      ),
    );
  }
}
