import 'project_model.dart';

/// Relative path (forward slashes) of the Android app manifest.
const String androidManifestPath = 'android/app/src/main/AndroidManifest.xml';

/// Relative path (forward slashes) of the iOS app's Info.plist.
const String iosInfoPlistPath = 'ios/Runner/Info.plist';

/// How a [PluginRequirement] is verified against the project's files.
enum RequirementCheck {
  /// A file must contain at least one of the given strings.
  fileContains,

  /// A file must exist.
  fileExists,

  /// Glide cannot verify this; it is shown as a reminder only.
  manual,
}

/// Something a plugin needs from the host app project, such as a permission
/// or a configuration file.
class PluginRequirement {
  const PluginRequirement.contains({
    required this.platform,
    required this.summary,
    required String this.file,
    required this.containsAny,
  }) : check = RequirementCheck.fileContains;

  const PluginRequirement.exists({
    required this.platform,
    required this.summary,
    required String this.file,
  })  : check = RequirementCheck.fileExists,
        containsAny = const <String>[];

  const PluginRequirement.manual({
    required this.platform,
    required this.summary,
  })  : check = RequirementCheck.manual,
        file = null,
        containsAny = const <String>[];

  final ProjectPlatform platform;

  /// What is required, in a sentence.
  final String summary;
  final RequirementCheck check;

  /// Project-relative path, or null for [RequirementCheck.manual].
  final String? file;
  final List<String> containsAny;
}

/// What Glide knows about one app-facing package.
class PluginKnowledge {
  const PluginKnowledge({
    required this.package,
    this.requirements = const <PluginRequirement>[],
  });

  /// The app-facing package name, for example `camera`.
  final String package;
  final List<PluginRequirement> requirements;
}

/// Requirements taken from each plugin's own documentation.
///
/// Deliberately small: an entry is only added when the requirement is
/// well established. A plugin missing from this table is not "fine"; Glide
/// simply has no information about it.
const List<PluginKnowledge> defaultPluginKnowledge = <PluginKnowledge>[
  PluginKnowledge(
    package: 'camera',
    requirements: <PluginRequirement>[
      PluginRequirement.contains(
        platform: ProjectPlatform.ios,
        summary: 'Camera usage description (NSCameraUsageDescription)',
        file: iosInfoPlistPath,
        containsAny: <String>['NSCameraUsageDescription'],
      ),
      PluginRequirement.contains(
        platform: ProjectPlatform.ios,
        summary: 'Microphone usage description (NSMicrophoneUsageDescription), '
            'needed when recording with audio',
        file: iosInfoPlistPath,
        containsAny: <String>['NSMicrophoneUsageDescription'],
      ),
    ],
  ),
  PluginKnowledge(
    package: 'image_picker',
    requirements: <PluginRequirement>[
      PluginRequirement.contains(
        platform: ProjectPlatform.ios,
        summary: 'Photo library usage description '
            '(NSPhotoLibraryUsageDescription), needed to pick from the gallery',
        file: iosInfoPlistPath,
        containsAny: <String>['NSPhotoLibraryUsageDescription'],
      ),
      PluginRequirement.contains(
        platform: ProjectPlatform.ios,
        summary: 'Camera usage description (NSCameraUsageDescription), '
            'needed to take photos',
        file: iosInfoPlistPath,
        containsAny: <String>['NSCameraUsageDescription'],
      ),
    ],
  ),
  PluginKnowledge(
    package: 'geolocator',
    requirements: <PluginRequirement>[
      PluginRequirement.contains(
        platform: ProjectPlatform.android,
        summary: 'A location permission (ACCESS_FINE_LOCATION or '
            'ACCESS_COARSE_LOCATION)',
        file: androidManifestPath,
        containsAny: <String>[
          'android.permission.ACCESS_FINE_LOCATION',
          'android.permission.ACCESS_COARSE_LOCATION',
        ],
      ),
      PluginRequirement.contains(
        platform: ProjectPlatform.ios,
        summary: 'Location usage description '
            '(NSLocationWhenInUseUsageDescription)',
        file: iosInfoPlistPath,
        containsAny: <String>['NSLocationWhenInUseUsageDescription'],
      ),
    ],
  ),
  PluginKnowledge(
    package: 'local_auth',
    requirements: <PluginRequirement>[
      PluginRequirement.contains(
        platform: ProjectPlatform.android,
        summary: 'The USE_BIOMETRIC permission',
        file: androidManifestPath,
        containsAny: <String>['android.permission.USE_BIOMETRIC'],
      ),
      PluginRequirement.contains(
        platform: ProjectPlatform.ios,
        summary: 'Face ID usage description (NSFaceIDUsageDescription)',
        file: iosInfoPlistPath,
        containsAny: <String>['NSFaceIDUsageDescription'],
      ),
    ],
  ),
  PluginKnowledge(
    package: 'google_maps_flutter',
    requirements: <PluginRequirement>[
      PluginRequirement.contains(
        platform: ProjectPlatform.android,
        summary: 'A Maps API key (com.google.android.geo.API_KEY meta-data)',
        file: androidManifestPath,
        containsAny: <String>['com.google.android.geo.API_KEY'],
      ),
      PluginRequirement.contains(
        platform: ProjectPlatform.ios,
        summary: 'A Maps API key provided in AppDelegate '
            '(GMSServices.provideAPIKey)',
        file: 'ios/Runner/AppDelegate.swift',
        containsAny: <String>['GMSServices'],
      ),
    ],
  ),
  PluginKnowledge(
    package: 'firebase_core',
    requirements: <PluginRequirement>[
      PluginRequirement.exists(
        platform: ProjectPlatform.android,
        summary: 'Firebase configuration file (google-services.json), not '
            'needed if you initialise Firebase only from firebase_options.dart',
        file: 'android/app/google-services.json',
      ),
      PluginRequirement.exists(
        platform: ProjectPlatform.ios,
        summary: 'Firebase configuration file (GoogleService-Info.plist), not '
            'needed if you initialise Firebase only from firebase_options.dart',
        file: 'ios/Runner/GoogleService-Info.plist',
      ),
    ],
  ),
  PluginKnowledge(
    package: 'permission_handler',
    requirements: <PluginRequirement>[
      PluginRequirement.manual(
        platform: ProjectPlatform.android,
        summary: 'Declare every permission you request in AndroidManifest.xml',
      ),
      PluginRequirement.manual(
        platform: ProjectPlatform.ios,
        summary: 'Enable each permission you use for iOS, following the '
            'permission_handler README, and add its usage description',
      ),
    ],
  ),
];
