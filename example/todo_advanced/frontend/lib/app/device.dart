import 'package:flutter/foundation.dart' show kIsWeb, immutable;

/// Which device this app instance pretends to be.
///
/// Two browser tabs on `?device=A` and `?device=B` are two *devices*: each
/// gets its own local database but they talk to the same backend, which is
/// the only honest way to show what sync actually does. Without this the
/// second tab would share the first one's IndexedDB and nothing would ever
/// have to travel through the server.
@immutable
class Device {
  const Device(this.id);

  /// Reads the device from the URL on the web (`?device=B`) and from
  /// `--dart-define=DEVICE=B` natively, defaulting to `A`.
  factory Device.fromEnvironment() {
    if (kIsWeb) {
      // `Uri.base` is the page URL in a browser (and the working directory
      // on the VM, where it carries no `device` parameter).
      final fromUrl = Uri.base.queryParameters['device'];
      if (fromUrl != null && fromUrl.trim().isNotEmpty) {
        return Device(_normalize(fromUrl));
      }
    }
    const fromDefine = String.fromEnvironment('DEVICE');
    return Device(fromDefine.isEmpty ? 'A' : _normalize(fromDefine));
  }

  /// A short identifier such as `A` or `B`.
  final String id;

  /// What the app bar shows.
  String get label => 'Device $id';

  /// The name of this device's local database.
  ///
  /// Device A keeps the original name so an existing installation — the one
  /// in the reader's browser — keeps its todos when they first open `?device=A`.
  String get databaseName =>
      isPrimary ? 'todo_advanced' : 'todo_advanced_${id.toLowerCase()}';

  /// Whether this is the default device that owns the original database.
  bool get isPrimary => id == 'A';

  /// Keeps the id usable as part of a database name, and short enough to fit
  /// in an app bar.
  static String _normalize(String raw) {
    final cleaned = raw.trim().toUpperCase().replaceAll(
      RegExp('[^A-Z0-9_-]'),
      '',
    );
    if (cleaned.isEmpty) return 'A';
    return cleaned.length <= 8 ? cleaned : cleaned.substring(0, 8);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Device && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Device($id)';
}
