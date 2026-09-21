import 'dart:io';

import 'package:glide_cli/glide_cli.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await runGlide(arguments);
}
