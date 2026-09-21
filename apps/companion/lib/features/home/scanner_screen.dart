import 'package:flutter/material.dart';
import 'package:glide_protocol/glide_protocol.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Camera view that looks for a Glide pairing QR code.
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
  );
  bool _handled = false;
  String? _hint;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      try {
        final payload = PairingPayload.parse(raw);
        _handled = true;
        context.pushReplacement('/pair', extra: payload);
        return;
      } on ProtocolException catch (error) {
        setState(() => _hint = error.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Scan pairing code')),
        body: Stack(
          children: <Widget>[
            MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
              errorBuilder: (context, error, child) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'The camera is not available '
                    '(${error.errorCode.name}). Allow camera access in '
                    'Settings, or paste the pairing link on the start '
                    'screen.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
            if (_hint != null)
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: double.infinity,
                  color: Colors.black87,
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _hint!,
                    style: const TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
      );
}
