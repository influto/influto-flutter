import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'influto_base.dart';
import 'models.dart';

class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}

enum _RefState { idle, validating, valid, invalid, applied }

/// Pre-built, configurable referral-code input.
///
/// Validates live (debounced) as the user types, applies on the button. By default
/// it shows ONLY the field + a valid/invalid state — the campaign name and the
/// influencer's personal name are hidden unless [showCampaignName] / [showReferrerName]
/// are set (both default `false`, consistent across the InfluTo SDKs). For full control
/// build your own UI and call `InfluTo.instance.validateCode` / `applyCode` directly.
class ReferralCodeInput extends StatefulWidget {
  const ReferralCodeInput({
    super.key,
    this.appUserId,
    this.autoPrefill = true,
    this.autoValidate = false,
    this.showCampaignName = false,
    this.showReferrerName = false,
    this.title,
    this.placeholder = 'Referral code',
    this.applyLabel = 'Apply',
    this.validMessage = 'Code applied',
    this.invalidMessage = "This code isn't valid",
    this.onValidated,
    this.onApplied,
  });

  /// Optional app user id passed to `applyCode` for attribution.
  final String? appUserId;

  /// Prefill from a stored attribution code on mount. @default true
  final bool autoPrefill;

  /// Validate a prefilled code immediately. @default false
  final bool autoValidate;

  /// Show `campaign.name` once applied. @default false
  final bool showCampaignName;

  /// Show "Referred by <influencer name>" once applied. @default false
  final bool showReferrerName;

  final String? title;
  final String placeholder;
  final String applyLabel;
  final String validMessage;
  final String invalidMessage;

  /// Fires after every validation (valid or not).
  final ValueChanged<CodeValidationResult>? onValidated;

  /// Fires only after the code is successfully applied.
  final ValueChanged<CodeValidationResult>? onApplied;

  @override
  State<ReferralCodeInput> createState() => _ReferralCodeInputState();
}

class _ReferralCodeInputState extends State<ReferralCodeInput> {
  final _controller = TextEditingController();
  _RefState _state = _RefState.idle;
  CodeValidationResult? _result;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    if (widget.autoPrefill) _prefill();
  }

  Future<void> _prefill() async {
    final c = await InfluTo.instance.getPrefilledCode();
    if (c != null && mounted) {
      _controller.text = c;
      if (widget.autoValidate) _validate(c);
    }
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    final code = _controller.text;
    if (code.length < 3) {
      setState(() => _state = _RefState.idle);
      return;
    }
    setState(() => _state = _RefState.validating);
    _debounce = Timer(const Duration(milliseconds: 450), () => _validate(code));
  }

  Future<void> _validate(String code) async {
    final res = await InfluTo.instance.validateCode(code);
    if (!mounted) return;
    _result = res;
    widget.onValidated?.call(res);
    setState(() => _state = res.valid ? _RefState.valid : _RefState.invalid);
  }

  Future<void> _apply() async {
    final res = await InfluTo.instance.applyCode(_controller.text, appUserId: widget.appUserId);
    if (!mounted) return;
    _result = res;
    if (res.applied == true || res.valid) {
      widget.onApplied?.call(res);
      setState(() => _state = _RefState.applied);
    } else {
      setState(() => _state = _RefState.invalid);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final applied = _state == _RefState.applied;
    final valid = _state == _RefState.valid || applied;
    final invalid = _state == _RefState.invalid;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (widget.title != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(widget.title!, style: theme.textTheme.titleMedium),
        ),
      TextField(
        controller: _controller,
        onChanged: _onChanged,
        enabled: !applied,
        textCapitalization: TextCapitalization.characters,
        autocorrect: false,
        enableSuggestions: false,
        maxLength: 20,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9-]')),
          _UpperCaseFormatter(),
        ],
        decoration: InputDecoration(
          labelText: widget.placeholder,
          border: const OutlineInputBorder(),
          counterText: '',
          errorText: invalid ? (_result?.error ?? widget.invalidMessage) : null,
          helperText: valid ? widget.validMessage : null,
          suffixIcon: _state == _RefState.validating
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : (valid ? const Icon(Icons.check_circle, color: Colors.green) : null),
        ),
      ),
      const SizedBox(height: 8),
      ElevatedButton(
        onPressed: _state == _RefState.valid ? _apply : null,
        child: Text(widget.applyLabel),
      ),
      if (applied && widget.showCampaignName && _result?.campaign != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(_result!.campaign!.name, style: theme.textTheme.bodyMedium),
        ),
      if (applied && widget.showReferrerName && _result?.influencer != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('Referred by ${_result!.influencer!.name}', style: theme.textTheme.bodySmall),
        ),
    ]);
  }
}
