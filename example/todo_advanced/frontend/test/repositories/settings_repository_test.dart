import 'package:flutter_test/flutter_test.dart';
import 'package:todo_advanced_frontend/database/database.dart';
import 'package:todo_advanced_frontend/repositories/settings_repository.dart';

import '../helpers/test_database.dart';

/// The sync panel's switches have to survive a reload, per device.
void main() {
  late AppDatabase db;
  late SettingsRepository settings;

  setUp(() {
    db = createTestDatabase();
    settings = SettingsRepository(db);
  });

  tearDown(() => db.close());

  test('an unknown key falls back to the default', () async {
    expect(await settings.read('nope'), isNull);
    expect(await settings.readBool('nope', orElse: true), isTrue);
    expect(await settings.readInt('nope', orElse: 60), 60);
  });

  test('values survive being read back', () async {
    await settings.writeBool(SettingKeys.autoSyncEnabled, value: true);
    await settings.writeInt(SettingKeys.autoSyncSeconds, 15);
    await settings.writeBool(SettingKeys.pushOnChange, value: false);

    expect(
      await settings.readBool(SettingKeys.autoSyncEnabled, orElse: false),
      isTrue,
    );
    expect(await settings.readInt(SettingKeys.autoSyncSeconds, orElse: 60), 15);
    expect(
      await settings.readBool(SettingKeys.pushOnChange, orElse: true),
      isFalse,
    );
  });

  test('writing the same key twice replaces it', () async {
    await settings.writeInt(SettingKeys.autoSyncSeconds, 15);
    await settings.writeInt(SettingKeys.autoSyncSeconds, 300);

    expect(
      await settings.readInt(SettingKeys.autoSyncSeconds, orElse: 60),
      300,
    );
    final rows = await db.select(db.appSettings).get();
    expect(rows, hasLength(1));
  });

  test('a value that is not a number falls back instead of throwing', () async {
    await settings.write(SettingKeys.autoSyncSeconds, 'soon');

    expect(await settings.readInt(SettingKeys.autoSyncSeconds, orElse: 60), 60);
  });

  test('a new device starts from the defaults', () async {
    final other = createTestDatabase();
    addTearDown(other.close);
    await settings.writeBool(SettingKeys.autoSyncEnabled, value: true);

    expect(
      await SettingsRepository(other)
          .readBool(SettingKeys.autoSyncEnabled, orElse: false),
      isFalse,
    );
  });
}
