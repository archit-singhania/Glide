import 'package:flutter/material.dart';
import 'package:glide_protocol/glide_protocol.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../shared/glide_glass.dart';

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
  Widget build(BuildContext context) {
    final tokens = glideTokens(context);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: glassAppBar(context, title: 'Scan pairing code'),
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => ColoredBox(
              color: Colors.black,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: GlassSurface(
                    strong: true,
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
            ),
          ),
          // A dimmed frame with a bright cut-out square, so the reticle
          // reads as "aim here" without needing to know the camera preview
          // API's own overlay support.
          IgnorePointer(
            child: Center(
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: tokens.glowSecondary.withValues(alpha: 0.9),
                    width: 3,
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: tokens.glowSecondary.withValues(alpha: 0.35),
                      blurRadius: 40,
                      spreadRadius: 4,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: GlassSurface(
                  strong: true,
                  child: Text(
                    _hint ??
                        'Point the camera at the QR code shown by '
                            '"glide start".',
                    style: TextStyle(
                      color: _hint == null
                          ? Colors.white
                          : Theme.of(context).colorScheme.error,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
