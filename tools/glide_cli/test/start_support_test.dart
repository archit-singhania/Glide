import 'dart:io';

import 'package:glide_cli/glide_cli.dart';
import 'package:test/test.dart';

LanCandidate _c(String name, String address) => LanCandidate(
      interfaceName: name,
      address: InternetAddress(address),
    );

void main() {
  group('chooseLanAddress', () {
    test('prefers 192.168 over 10 over 172.16', () {
      final chosen = chooseLanAddress(<LanCandidate>[
        _c('eth0', '172.20.0.4'),
        _c('eth1', '10.0.0.7'),
        _c('wlan0', '192.168.1.20'),
      ]);
      expect(chosen?.address, '192.168.1.20');

      expect(
        chooseLanAddress(<LanCandidate>[
          _c('a', '172.20.0.4'),
          _c('b', '10.0.0.7'),
        ])?.address,
        '10.0.0.7',
      );
    });

    test('prefers a physical interface over a virtual one', () {
      final chosen = chooseLanAddress(<LanCandidate>[
        _c('vEthernet (WSL)', '192.168.56.1'),
        _c('Wi-Fi', '10.0.0.5'),
      ]);
      expect(chosen?.address, '10.0.0.5');
    });

    test('falls back to a virtual interface when it is the only option', () {
      final chosen = chooseLanAddress(<LanCandidate>[
        _c('docker0', '172.17.0.1'),
      ]);
      expect(chosen?.address, '172.17.0.1');
    });

    test('ignores loopback, link-local, public, CGNAT and IPv6 addresses', () {
      final chosen = chooseLanAddress(<LanCandidate>[
        _c('lo', '127.0.0.1'),
        _c('eth0', '169.254.10.2'),
        _c('eth1', '8.8.8.8'),
        _c('tailscale0', '100.64.1.1'),
        _c('eth2', '172.32.0.1'),
        _c('eth3', 'fe80::1'),
      ]);
      expect(chosen, isNull);
    });

    test('returns null when there are no candidates', () {
      expect(chooseLanAddress(const <LanCandidate>[]), isNull);
    });
  });

  group('QrRenderer', () {
    const data = 'glide://pair?version=1&host=192.168.1.20&port=49400';

    test('unicode output has equal-width lines and a blank quiet zone', () {
      final text = const QrRenderer().render(data);
      final lines = text.split('\n')..removeLast();

      expect(lines.length, greaterThan(5));
      expect(lines.map((l) => l.length).toSet(), hasLength(1));
      expect(lines.first.trim(), isEmpty);
      expect(text, anyOf(contains('█'), contains('▀'), contains('▄')));
    });

    test('colour output wraps each line in black-on-white', () {
      final text = const QrRenderer(color: true).render(data);
      final lines = text.split('\n')..removeLast();

      expect(lines, everyElement(startsWith('\x1B[30;47m')));
      expect(lines, everyElement(endsWith('\x1B[0m')));
    });

    test('ASCII output uses no block characters', () {
      final text = const QrRenderer(unicode: false).render(data);

      expect(text, contains('##'));
      expect(text, isNot(anyOf(contains('█'), contains('▀'), contains('▄'))));
    });

    test('is deterministic and depends on the data', () {
      const renderer = QrRenderer();
      expect(renderer.render(data), renderer.render(data));
      expect(renderer.render(data), isNot(renderer.render('$data&x=1')));
    });

    test('a realistic pairing link fits in a QR code', () {
      final link = 'glide://pair?version=1&host=192.168.100.200&port=49400'
          '&session=GLIDE-7X21-K94&token=${'A' * 43}&exp=1789965000000';
      expect(() => const QrRenderer().render(link), returnsNormally);
    });
  });
}
