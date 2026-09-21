import 'dart:io';

/// Finds the address of this machine that a phone on the same Wi-Fi can reach.
typedef LanAddressResolver = Future<InternetAddress?> Function();

/// One IPv4 address on one network interface.
class LanCandidate {
  const LanCandidate({required this.interfaceName, required this.address});

  final String interfaceName;
  final InternetAddress address;
}

const List<String> _virtualMarkers = <String>[
  'vethernet',
  'virtualbox',
  'vmware',
  'vbox',
  'vmnet',
  'docker',
  'veth',
  'wsl',
  'hyper-v',
  'br-',
  'utun',
  'tun',
  'tap',
];

bool _looksVirtual(String interfaceName) {
  final name = interfaceName.toLowerCase();
  return _virtualMarkers.any(name.contains);
}

/// Higher is better; negative means "never use".
int _score(LanCandidate candidate) {
  final address = candidate.address;
  if (address.type != InternetAddressType.IPv4) return -1;
  final o = address.rawAddress;
  final int range;
  if (o[0] == 192 && o[1] == 168) {
    range = 30;
  } else if (o[0] == 10) {
    range = 20;
  } else if (o[0] == 172 && o[1] >= 16 && o[1] <= 31) {
    range = 10;
  } else {
    // Loopback, link-local, public and carrier-grade NAT addresses are not
    // somewhere a phone on the same Wi-Fi can be expected to reach.
    return -1;
  }
  return range + (_looksVirtual(candidate.interfaceName) ? 0 : 100);
}

/// Picks the best private IPv4 address, preferring physical interfaces over
/// virtual ones (VirtualBox, Docker, WSL, ...) and `192.168/16` over `10/8`
/// over `172.16/12`. Returns null when nothing qualifies.
InternetAddress? chooseLanAddress(Iterable<LanCandidate> candidates) {
  LanCandidate? best;
  var bestScore = -1;
  for (final candidate in candidates) {
    final score = _score(candidate);
    if (score > bestScore) {
      best = candidate;
      bestScore = score;
    }
  }
  return best?.address;
}

/// Every non-loopback IPv4 address on this machine.
Future<List<LanCandidate>> systemLanCandidates() async {
  final interfaces = await NetworkInterface.list(
    includeLoopback: false,
    type: InternetAddressType.IPv4,
  );
  return <LanCandidate>[
    for (final interface in interfaces)
      for (final address in interface.addresses)
        LanCandidate(interfaceName: interface.name, address: address),
  ];
}

/// The real [LanAddressResolver].
Future<InternetAddress?> resolveSystemLanAddress() async =>
    chooseLanAddress(await systemLanCandidates());
