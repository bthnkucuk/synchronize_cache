import '../database/database.dart';

/// Reads and writes this device's sync preferences.
///
/// Stored in the device's own database, so device A can have automatic sync
/// off while device B polls every 15 seconds — which is the whole point of
/// being able to watch them side by side.
class SettingsRepository {
  SettingsRepository(this._db);

  final AppDatabase _db;

  Future<String?> read(String key) async {
    final row = await (_db.select(
      _db.appSettings,
    )..where((s) => s.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> write(String key, String value) async {
    await _db
        .into(_db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(key: key, value: value),
        );
  }

  Future<bool> readBool(String key, {required bool orElse}) async =>
      switch (await read(key)) {
        'true' => true,
        'false' => false,
        _ => orElse,
      };

  Future<void> writeBool(String key, {required bool value}) =>
      write(key, value ? 'true' : 'false');

  Future<int> readInt(String key, {required int orElse}) async =>
      int.tryParse(await read(key) ?? '') ?? orElse;

  Future<void> writeInt(String key, int value) => write(key, '$value');
}

/// The keys the sync panel stores. Kept together so a typo cannot make a
/// setting silently fall back to its default forever.
abstract final class SettingKeys {
  static const autoSyncEnabled = 'sync.auto.enabled';
  static const autoSyncSeconds = 'sync.auto.seconds';
  static const pushOnChange = 'sync.push_on_change';
  static const liveUpdates = 'sync.live_updates';
}
