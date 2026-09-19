import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// A switch that makes this device behave as if it had no network.
///
/// The Sync lab needs a believable "airplane mode" that a reader can flip
/// from inside the app. Turning the backend off would not do: that is a
/// *server* outage (503), and the whole point of the experiment is that a
/// dead network and a dead server look different to the user and identical
/// to the retry budget — neither counts against the item.
class NetworkSwitch extends ChangeNotifier {
  bool _online = true;

  /// Whether requests are allowed to leave this device.
  bool get online => _online;

  set online(bool value) {
    if (_online == value) return;
    _online = value;
    notifyListeners();
  }
}

/// An [http.Client] that fails every request while [NetworkSwitch.online] is
/// false.
///
/// It throws `http.ClientException`, which is exactly what the browser and
/// `dart:io` raise when a host cannot be reached — so the sync engine
/// classifies it as environmental and does **not** count the attempt against
/// the operation.
class SwitchableClient extends http.BaseClient {
  SwitchableClient(this.networkSwitch, {http.Client? inner})
    : _inner = inner ?? http.Client();

  final NetworkSwitch networkSwitch;
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (!networkSwitch.online) {
      throw http.ClientException(
        'No connection (switched off in the Sync lab)',
        request.url,
      );
    }
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
