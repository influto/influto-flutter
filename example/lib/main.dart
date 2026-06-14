import 'package:flutter/material.dart';
import 'package:influto/influto.dart';

import 'purchase_manager.dart';
import 'referral_field.dart';
import 'sample_backend.dart';

/// The full InfluTo Flutter flow, top to bottom — a copy-paste reference:
/// 1 configure → 2 attribution → 3 referral input → 4 paywall (in_app_purchase
/// → reportPurchase) → 5 confirm it landed in InfluTo.
///
/// API key defaults from --dart-define=INFLUTO_API_KEY (never committed) but is
/// editable at runtime; defaults to the harmless `it_TEST_KEY` (backend rejects).
const _defaultApiKey =
    String.fromEnvironment('INFLUTO_API_KEY', defaultValue: 'it_TEST_KEY');
const _baseUrl = 'https://influ.to/api';

void main() => runApp(const InfluToSampleApp());

class InfluToSampleApp extends StatelessWidget {
  const InfluToSampleApp({super.key});

  @override
  Widget build(BuildContext context) =>
      const MaterialApp(title: 'InfluTo Sample', home: SampleScreen());
}

class SampleScreen extends StatefulWidget {
  const SampleScreen({super.key});

  @override
  State<SampleScreen> createState() => _SampleScreenState();
}

class _SampleScreenState extends State<SampleScreen> {
  final _apiKey = TextEditingController(text: _defaultApiKey);
  final _productId = TextEditingController(text: 'to.influ.sample.pro.monthly');
  final _appUserId = TextEditingController(text: 'sample-flutter');

  bool _initialized = false;
  String _status = 'Not initialized';
  String _attribution = '—';
  String? _appliedCode;
  String _result = '';
  String _landed = '';
  PurchaseManager? _purchases;

  Future<void> _initialize() async {
    try {
      await InfluTo.instance.initialize(InfluToConfig(
        apiKey: _apiKey.text,
        debug: true,
        apiUrl: _baseUrl,
        appVersion: 'sample-flutter-1.0',
      ));
      await InfluTo.instance.identifyUser(_appUserId.text);
      final a = await InfluTo.instance.checkAttribution();
      final code = await InfluTo.instance.getReferralCode();
      _purchases = PurchaseManager(
        appUserId: () => _appUserId.text,
        referralCode: () => _appliedCode,
        onResult: (s) => setState(() => _result = s),
      );
      await _purchases!.start();
      if (!mounted) return;
      setState(() {
        _initialized = true;
        _status = '✅ Initialized as ${_appUserId.text}';
        _attribution = a.attributed
            ? 'Attributed → ${a.referralCode}'
            : 'Organic (no attribution link)';
        _appliedCode = code;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initialized = false;
        _status = '❌ Init failed: $e';
      });
    }
  }

  Future<void> _checkLanded() async {
    final s = await SampleBackend.recentConversionsSummary(
      baseUrl: _baseUrl, apiKey: _apiKey.text, appUserId: _appUserId.text,
    );
    if (!mounted) return;
    setState(() => _landed = s);
  }

  @override
  void dispose() {
    _purchases?.dispose();
    _apiKey.dispose();
    _productId.dispose();
    _appUserId.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('InfluTo Sample')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const _Title('1 · Configuration'),
        TextField(controller: _apiKey, decoration: const InputDecoration(labelText: 'InfluTo API key')),
        TextField(controller: _productId, decoration: const InputDecoration(labelText: 'Product ID (SKU)')),
        TextField(controller: _appUserId, decoration: const InputDecoration(labelText: 'App user ID')),
        const SizedBox(height: 8),
        ElevatedButton(onPressed: _initialize, child: Text(_initialized ? 'Re-initialize' : 'Initialize SDK')),
        Text(_status),
        if (_initialized) ...[
          const _Title('2 · Attribution'),
          Text('Attribution: $_attribution'),
          if (_appliedCode != null) Text('Stored code: $_appliedCode'),
          const _Title('3 · Referral code (test attribution)'),
          ReferralCodeField(
            appUserId: _appUserId.text,
            onApplied: (c) => setState(() => _appliedCode = c),
          ),
          const _Title('4 · Paywall'),
          const Text('Buys via in_app_purchase, then calls reportPurchase with the store proof.'),
          ElevatedButton(
            onPressed: () => _purchases?.buy(_productId.text),
            child: Text('Buy ${_productId.text}'),
          ),
          const _Title('5 · Result'),
          if (_result.isNotEmpty) Text(_result),
          ElevatedButton(onPressed: _checkLanded, child: const Text('Did it land in InfluTo?')),
          if (_landed.isNotEmpty) Text(_landed),
        ],
        const SizedBox(height: 24),
      ]),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 4),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
      );
}
