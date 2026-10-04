import 'package:flutter/services.dart' show appFlavor;

/// Values compiled in from `config/tiers/<tier>.json` by `tool/build.sh`.
///
/// `String.fromEnvironment` is resolved at compile time, so these must stay
/// `const`. Nothing here is secret: every value can be read out of the binary.
abstract final class BuildEnv {
  static const String tier = String.fromEnvironment('APP_TIER');
  static const String apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// Call first in `main()`.
  ///
  /// Throws on the first launch of a build that skipped the tier config, or
  /// that paired one flavor (application id, bundle id) with another tier's
  /// config. Without this, both mistakes produce an app that starts normally
  /// and talks to the wrong backend.
  static void verify() {
    if (tier.isEmpty) {
      throw StateError(
        'APP_TIER is not set. Build with tool/build.sh, or pass '
        '--dart-define-from-file=config/tiers/<tier>.json',
      );
    }
    if (appFlavor != null && appFlavor != tier) {
      throw StateError('Flavor "$appFlavor" was built with the "$tier" config.');
    }
    if (apiBaseUrl.isEmpty) {
      throw StateError('API_BASE_URL is not set in config/tiers/$tier.json.');
    }
  }
}
