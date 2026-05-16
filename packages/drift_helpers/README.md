# drift_helpers

Small pure-Dart helpers reused across apps.

Currently exposes drift `TypeConverter` subclasses for common JSON / list
column shapes:

- `JsonConverter` — `Map<String, dynamic>?` ⇄ TEXT
- `JsonListConverter` — `List<Map<String, dynamic>>?` ⇄ TEXT
- `IntListConverter` — `List<int>` ⇄ TEXT
- `StringListConverter` — `List<String>` ⇄ TEXT

```dart
import 'package:drift_helpers/drift_helpers.dart';

class MyTable extends Table {
  TextColumn get tags => text()
      .map(const StringListConverter())
      .withDefault(const Constant('[]'))();
}
```

Pure Dart — no Flutter dependency.
