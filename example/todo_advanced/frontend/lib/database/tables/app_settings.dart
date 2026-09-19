import 'package:drift/drift.dart';

/// A tiny key/value table for this device's sync preferences.
///
/// The sync panel's switches (automatic sync on/off, its interval, send
/// right after every change) have to survive a reload, and they belong to
/// *this* device — device B may sync every 15 seconds while device A is off.
/// Since every device already has its own database, one table here is all it
/// takes; no extra package, no platform channel.
class AppSettings extends Table {
  TextColumn get key => text()();

  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
