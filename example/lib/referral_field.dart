import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:influto/influto.dart';

/// Best-practice referral-code input (per the cross-platform UX spec): a collapsed
/// "Have a referral code?" disclosure → field (auto-uppercase, no autocorrect,
/// charset-filtered) → debounced live validation → explicit Apply → applied chip.
class ReferralCodeField extends StatefulWidget {
  const ReferralCodeField({
    super.key,
    required this.appUserId,
    required this.onApplied,
  });

  final String appUserId;
  final ValueChanged<String?> onApplied;

  @override
  State<ReferralCodeField> createState() => _ReferralCodeFieldState();
}

class _ReferralCodeFieldState extends State<ReferralCodeField> {
  final _controller = TextEditingController();
  String? _applied;
  bool _expanded = false;
  String _state = 'idle'; // idle | validating | valid | invalid
  String _info = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String raw) {
    _debounce?.cancel();
    final code = _controller.text;
    setState(() => _info = '');
    if (code.length < 3) {
      setState(() => _state = 'idle');
      return;
    }
    setState(() => _state = 'validating');
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      final res = await InfluTo.instance.validateCode(code);
      if (!mounted) return;
      setState(() {
        if (res.valid) {
          _state = 'valid';
          _info = res.campaign?.name != null ? 'Valid — ${res.campaign!.name}' : 'Valid code';
        } else {
          _state = 'invalid';
          _info = res.errorCode == 'CODE_EXPIRED'
              ? 'This code has expired'
              : (res.error ?? "This code isn't valid");
        }
      });
    });
  }

  Future<void> _apply() async {
    final code = _controller.text;
    final res = await InfluTo.instance.applyCode(code, appUserId: widget.appUserId);
    if (!mounted) return;
    if (res.applied == true || res.valid) {
      setState(() {
        _applied = code;
        _expanded = false;
      });
      widget.onApplied(code);
    } else {
      setState(() {
        _state = 'invalid';
        _info = res.error ?? 'Could not apply code';
      });
    }
  }

  void _remove() {
    InfluTo.instance.clearAttribution();
    setState(() {
      _applied = null;
      _controller.clear();
      _state = 'idle';
      _info = '';
      _expanded = false;
    });
    widget.onApplied(null);
  }

  @override
  Widget build(BuildContext context) {
    if (_applied != null) {
      return Row(children: [
        const Icon(Icons.verified, color: Colors.green),
        const SizedBox(width: 8),
        Expanded(child: Text('Code $_applied applied')),
        TextButton(onPressed: _remove, child: const Text('Remove')),
      ]);
    }
    if (!_expanded) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: () => setState(() => _expanded = true),
          child: const Text('Have a referral code?'),
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextField(
        controller: _controller,
        onChanged: _onChanged,
        textCapitalization: TextCapitalization.characters,
        autocorrect: false,
        enableSuggestions: false,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9-]')),
          _UpperCaseFormatter(),
        ],
        decoration: InputDecoration(
          labelText: 'REFERRAL CODE',
          errorText: _state == 'invalid' ? _info : null,
          helperText: _state == 'valid' ? _info : null,
          suffixIcon: _state == 'validating'
              ? const SizedBox(
                  width: 18, height: 18,
                  child: Padding(padding: EdgeInsets.all(4), child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : null,
        ),
      ),
      const SizedBox(height: 8),
      ElevatedButton(
        onPressed: _state == 'valid' ? _apply : null,
        child: const Text('Apply'),
      ),
    ]);
  }
}

class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}
