import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  final qs = await FirebaseFirestore.instance.collection('experts').limit(5).get();
  for (var doc in qs.docs) {
    print(doc.data());
  }
}
