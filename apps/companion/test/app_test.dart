import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glide_companion/app/app.dart';
import 'package:glide_companion/core/companion_client.dart';
import 'package:glide_companion/features/session/session_notifier.dart';
import 'package:glide_companion/features/session/session_screen.dart';
import 'package:glide_companion/features/session/session_view.dart';
import 'package:glide_protocol/glide_protocol.dart';

import 'support/fakes.dart';

Widget _app(FakeConnector connector) => ProviderScope(
      overrides: [
        companionClientProvider.overrideWithValue(
          CompanionClient(
            connect: connector.call,
            deviceId: 'companion-abc123',
          ),
        ),
        recentSessionsProvider.overrideWithValue(FakeRecentSessionsStore()),
      ],
      child: const GlideCompanionApp(),
    );

/// A notifier that starts from a fixed view and never touches the network.
class _SeededNotifier extends SessionNotifier {
  _SeededNotifier(this._seed);

  final SessionView _seed;

  @override
  SessionView build() => _seed;
}

Widget _sessionScreen(SessionView seed) => ProviderScope(
      overrides: [
        sessionProvider.overrideWith(() => _SeededNotifier(seed)),
      ],
      child: const MaterialApp(home: SessionScreen()),
    );

bool _enabled(WidgetTester tester, String label) {
  final button = tester.widget<ButtonStyleButton>(
    find.ancestor(
      of: find.text(label),
      matching: find.bySubtype<ButtonStyleButton>(),
    ),
  );
  return button.onPressed != null;
}

Future<void> _enterLinkAndContinue(WidgetTester tester, String link) async {
  await tester.enterText(find.byType(TextField), link);
  await tester.ensureVisible(find.text('Continue'));
  // `ensureVisible` jumps the scroll position instantly but does not lay
  // out/paint the new position itself, so the widget's on-screen offset is
  // still stale until a frame is pumped. Tapping immediately after
  // `ensureVisible` (as this used to) computes coordinates from that stale
  // position and can miss the button once the screen is tall enough to need
  // an actual scroll (it wasn't, before the glassmorphism redesign added a
  // taller header and card padding above this button).
  await tester.pump();
  await tester.tap(find.text('Continue'));
}

void main() {
  group('start screen', () {
    testWidgets('offers scanning and pasting a link', (tester) async {
      await tester.pumpWidget(_app(FakeConnector()));

      expect(find.text('Scan QR code'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('rejects a link that is not a Glide pairing code', (
      tester,
    ) async {
      await tester.pumpWidget(_app(FakeConnector()));

      await _enterLinkAndContinue(tester, 'https://example.com');
      await tester.pump();

      expect(find.text('This is not a Glide pairing code.'), findsOneWidget);
      expect(find.text('Connect to computer'), findsNothing);
    });
  });

  group('pairing flow', () {
    testWidgets('a valid link shows the computer before connecting', (
      tester,
    ) async {
      final connector = FakeConnector(pairReply: acceptedReply());
      await tester.pumpWidget(_app(connector));

      await _enterLinkAndContinue(tester, testPayload().toUri().toString());
      await tester.pumpAndSettle();

      expect(find.text('Connect to computer'), findsOneWidget);
      expect(find.text('192.168.1.20:49400'), findsOneWidget);
      expect(find.text('GLIDE-7X21-K94'), findsOneWidget);
      // Nothing is sent until the person taps Connect.
      expect(connector.calls, isEmpty);
    });

    testWidgets('connecting opens the session dashboard', (tester) async {
      final connector = FakeConnector(pairReply: acceptedReply());
      await tester.pumpWidget(_app(connector));
      await _enterLinkAndContinue(tester, testPayload().toUri().toString());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(find.text('Connected'), findsOneWidget);
      expect(find.text('Run'), findsOneWidget);
      expect(_enabled(tester, 'Run'), isTrue);
      expect(_enabled(tester, 'Hot reload'), isFalse);
    });

    testWidgets('a rejected pairing stays on the confirmation screen', (
      tester,
    ) async {
      final connector = FakeConnector(
        pairReply: rejectedReply('The developer declined this device.'),
      );
      await tester.pumpWidget(_app(connector));
      await _enterLinkAndContinue(tester, testPayload().toUri().toString());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(
        find.text('The developer declined this device.'),
        findsOneWidget,
      );
      expect(find.text('Connect'), findsOneWidget);
    });

    testWidgets('the dashboard follows the host and sends reload', (
      tester,
    ) async {
      final connector = FakeConnector(pairReply: acceptedReply());
      await tester.pumpWidget(_app(connector));
      await _enterLinkAndContinue(tester, testPayload().toUri().toString());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      final session = connector.callsTo('/ws').single.channel;

      session.receive(status('running'));
      await tester.pumpAndSettle();

      // Separates "the state did not change" from "the screen did not
      // rebuild" if this ever fails.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SessionScreen)),
      );
      expect(container.read(sessionProvider).sessionState, 'running');

      expect(_enabled(tester, 'Hot reload'), isTrue);
      expect(_enabled(tester, 'Run'), isFalse);

      await tester.tap(find.text('Hot reload'));
      await tester.pumpAndSettle();

      expect(session.sent.last.type, 'app.reload');
    });
  });

  group('session dashboard', () {
    testWidgets('a failed build can be run again but not reloaded', (
      tester,
    ) async {
      await tester.pumpWidget(
        _sessionScreen(
          const SessionView(
            link: LinkStatus.connected,
            sessionState: 'failed',
          ),
        ),
      );

      expect(_enabled(tester, 'Run'), isTrue);
      expect(_enabled(tester, 'Hot reload'), isFalse);
      expect(_enabled(tester, 'Stop'), isFalse);
    });

    testWidgets('a running app can be reloaded, restarted and stopped', (
      tester,
    ) async {
      await tester.pumpWidget(
        _sessionScreen(
          const SessionView(
            link: LinkStatus.connected,
            sessionState: 'running',
          ),
        ),
      );

      expect(_enabled(tester, 'Run'), isFalse);
      expect(_enabled(tester, 'Hot reload'), isTrue);
      expect(_enabled(tester, 'Hot restart'), isTrue);
      expect(_enabled(tester, 'Full restart'), isTrue);
      expect(_enabled(tester, 'Stop'), isTrue);
    });

    testWidgets('a lost connection disables everything and says why', (
      tester,
    ) async {
      await tester.pumpWidget(
        _sessionScreen(
          const SessionView(
            link: LinkStatus.disconnected,
            linkMessage: 'The computer closed the connection.',
            sessionState: 'running',
          ),
        ),
      );

      expect(find.text('Disconnected'), findsOneWidget);
      expect(
        find.text('The computer closed the connection.'),
        findsOneWidget,
      );
      expect(_enabled(tester, 'Run'), isFalse);
      expect(_enabled(tester, 'Hot reload'), isFalse);
      // Nothing to reconnect with in this seeded state.
      expect(find.text('Reconnect'), findsNothing);
    });

    testWidgets('compiler errors show file, line and column', (tester) async {
      await tester.pumpWidget(
        _sessionScreen(
          const SessionView(
            link: LinkStatus.connected,
            sessionState: 'failed',
            errors: [
              DiagnosticEvent(
                severity: DiagnosticSeverity.error,
                category: DiagnosticCategory.dart,
                source: 'Dart compiler',
                message: "Undefined name 'userss'",
                file: 'lib/pages/home.dart',
                line: 82,
                column: 5,
              ),
            ],
          ),
        ),
      );

      expect(find.text('lib/pages/home.dart:82:5'), findsOneWidget);
      expect(find.text("Undefined name 'userss'"), findsOneWidget);
    });

    testWidgets('shows recent log output', (tester) async {
      await tester.pumpWidget(
        _sessionScreen(
          SessionView(
            link: LinkStatus.connected,
            sessionState: 'running',
            logs: [
              LogEntry(
                timestamp: DateTime.fromMillisecondsSinceEpoch(0),
                level: LogLevel.info,
                source: 'app',
                message: 'User fetched',
              ),
            ],
          ),
        ),
      );

      expect(find.text('User fetched'), findsOneWidget);
    });
  });
}
