import 'package:flutter/material.dart';
import 'package:influto/influto.dart';

// API key from a build-time --dart-define so a REAL key is never committed.
// Default is a harmless placeholder → a real key can't ship by accident.
// To test:  flutter run --dart-define=INFLUTO_API_KEY=it_live_yourkey
const _apiKey = String.fromEnvironment('INFLUTO_API_KEY', defaultValue: 'it_TEST_KEY');

void main() => runApp(const DemoApp());

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});
  @override
  Widget build(BuildContext context) => const MaterialApp(home: DemoScreen());
}

class DemoScreen extends StatefulWidget {
  const DemoScreen({super.key});
  @override
  State<DemoScreen> createState() => _DemoScreenState();
}

class _DemoScreenState extends State<DemoScreen> {
  final _log = StringBuffer();
  void _line(String s) => setState(() => _log.writeln(s));

  Future<void> _run() async {
    try {
      // 1. initialize
      await InfluTo.instance.initialize(const InfluToConfig(
        apiKey: _apiKey,
        debug: true,
        // revenueCatHook: (attrs) => Purchases.setAttributes(attrs), // if RC installed
      ),);
      _line('init ok');

      // 2. checkAttribution (IP + fingerprint match)
      final attr = await InfluTo.instance.checkAttribution();
      _line('attributed=${attr.attributed} code=${attr.referralCode}');

      // 3. validateCode
      final v = await InfluTo.instance.validateCode('FITGURU30');
      _line('valid=${v.valid} ${v.campaign?.name ?? v.error}');

      // 4. identify + trackEvent
      await InfluTo.instance.identifyUser('user_123');
      await InfluTo.instance.trackEvent(
        const TrackEventOptions(
            eventType: 'paywall_viewed', appUserId: 'user_123',),
      );
      _line('identify + trackEvent sent');

      // 5. reportPurchase (store-direct): the host obtains the proof from
      //    in_app_purchase / purchases_flutter and passes it in.
      //    iOS:     signedTransaction = details.verificationData.serverVerificationData
      //    Android: purchaseToken     = details.verificationData.serverVerificationData
      // final r = await InfluTo.instance.reportPurchase(
      //   platform: 'android', purchaseToken: token, appUserId: 'user_123');
      // _line('purchase success=${r.success} validated=${r.validated}');
    } catch (e) {
      _line('ERR $e');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('InfluTo demo')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ElevatedButton(
                  onPressed: _run, child: const Text('Run InfluTo flow'),),
              const SizedBox(height: 12),
              Expanded(
                  child: SingleChildScrollView(child: Text(_log.toString())),),
            ],
          ),
        ),
      );
}
