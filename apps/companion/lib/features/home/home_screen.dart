import 'package:flutter/material.dart';
import 'package:glide_protocol/glide_protocol.dart';
import 'package:go_router/go_router.dart';

/// Start screen: scan the QR code, or paste the pairing link.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _link = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  void _connectWithLink() {
    try {
      final payload = PairingPayload.parse(_link.text);
      setState(() => _error = null);
      context.push('/pair', extra: payload);
    } on ProtocolException catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Glide')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: <Widget>[
            Text(
              'Flutter development, without friction.',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'On your computer, run "glide start" in your Flutter project, '
              'then scan the QR code it shows.',
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => context.push('/scan'),
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan QR code'),
            ),
            const SizedBox(height: 32),
            Text('No camera?', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            const Text(
              'Run "glide start --print-uri" and paste the pairing link. '
              'It is secret until used, so do not share it.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _link,
              decoration: InputDecoration(
                labelText: 'Pairing link',
                hintText: 'glide://pair?...',
                border: const OutlineInputBorder(),
                errorText: _error,
              ),
              autocorrect: false,
              enableSuggestions: false,
              onSubmitted: (_) => _connectWithLink(),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _connectWithLink,
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }
}
