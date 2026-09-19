## 0.2.0

- **Breaking:** the minimum Dart SDK is now 3.13 (was 3.7).
- Inherits the workspace's strict analysis options; raw `Map` types in
  `JsonListConverter` are now explicit (no behaviour change).
- Dependencies: `drift` ^2.35.0, `meta` ^1.19.0.

## 0.1.0

- Exposes `JsonConverter`, `JsonListConverter`, `IntListConverter`,
  and `StringListConverter`.
