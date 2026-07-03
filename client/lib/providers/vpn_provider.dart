import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:client/models/server_model.dart';
import 'package:client/services/singbox_config.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_v2ray/flutter_v2ray.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sing_box/sing_box.dart';

class VpnProvider extends ChangeNotifier {
  // Android VPN core.
  late FlutterV2ray _v2ray;
  // iOS VPN core (sing-box via Network Extension).
  final SingBox _singBox = SingBox.instance;
  StreamSubscription<SingBoxConnectionStatus>? _singBoxStatusSub;

  bool _initialized = false;
  bool _isLoading = false;
  String _vpnState = 'DISCONNECTED';
  String _vpnDuration = '00:00:00';
  String? _lastConnectError;

  List<ServerModel> _servers = [];
  ServerModel? _selectedServer;
  String? _deviceId;
  String? _userUuid;

  // Production API server (VDS). Served over HTTPS by reusing the existing
  // calktalk.rudnowski.dev certificate: a reverse proxy maps the `/vpn` path
  // prefix to the Go control plane on 127.0.0.1:8080 (the `/vpn` prefix is
  // stripped by the proxy, so requests hit /api/... on the backend).
  String get _apiUrl {
    return 'https://calktalk.rudnowski.dev/vpn';
  }

  bool get isInitialized => _initialized;
  bool get isLoading => _isLoading;
  String get vpnState => _vpnState;
  String get vpnDuration => _vpnDuration;
  bool get isConnected => _vpnState == 'CONNECTED';
  String? get lastConnectError => _lastConnectError;
  List<ServerModel> get servers => _servers;
  ServerModel? get selectedServer => _selectedServer;

  VpnProvider() {
    _v2ray = FlutterV2ray(
      onStatusChanged: (status) {
        _vpnState = status.state;
        _vpnDuration = status.duration;
        notifyListeners();
      },
    );
  }

  Future<void> init() async {
    if (_initialized) return;
    _isLoading = true;
    notifyListeners();

    // Get the device id first, independently of the native VPN plugin.
    // On iOS the VPN plugin has no implementation and throws, which must not
    // prevent us from obtaining the device id / registering.
    try {
      _deviceId = await _getDeviceId();
    } catch (e) {
      debugPrint("Device ID error: $e");
    }

    try {
      if (Platform.isIOS) {
        await _singBox.initialize();
        _singBoxStatusSub ??= _singBox.watchSingBoxConnectionStatus().listen((status) {
          _vpnState = _mapSingBoxStatus(status);
          notifyListeners();
        });
      } else {
        await _v2ray.initializeV2Ray();
      }
    } catch (e) {
      debugPrint("VPN Initialization Error: $e");
    }

    _initialized = true;

    // Fetch servers separately so a network failure here doesn't block the
    // ability to retry later via refreshServers().
    await _registerDevice();

    _isLoading = false;
    notifyListeners();
  }

  /// Re-fetches the server list from the control plane. Safe to call any number
  /// of times (e.g. from the "Refresh" button) even after init() has run.
  Future<void> refreshServers() async {
    _isLoading = true;
    notifyListeners();
    try {
      _deviceId ??= await _getDeviceId();
      await _registerDevice();
    } catch (e) {
      debugPrint("Refresh servers error: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<String> _getDeviceId() async {
    var deviceInfo = DeviceInfoPlugin();
    if (Platform.isIOS) {
      var ios = await deviceInfo.iosInfo;
      return ios.identifierForVendor ?? 'ios_temp_${DateTime.now().millisecondsSinceEpoch}';
    } else {
      var android = await deviceInfo.androidInfo;
      return android.id;
    }
  }

  Future<void> _registerDevice() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedServers = prefs.getString('cached_servers');
    _userUuid = prefs.getString('user_uuid');

    // Load cached servers first for instant availability
    if (cachedServers != null) {
      try {
        final List decoded = jsonDecode(cachedServers);
        _servers = decoded.map((s) => ServerModel.fromJson(s)).toList();
        if (_servers.isNotEmpty) {
          _selectedServer = _servers.first;
        }
      } catch (e) {
        debugPrint("Error parsing cached servers: $e");
      }
    }

    // Retry a couple of times: mobile networks can drop the first request,
    // and non-standard ports (8080) sometimes need a moment on flaky links.
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await http.post(
          Uri.parse('$_apiUrl/api/register'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'device_id': _deviceId}),
        ).timeout(const Duration(seconds: 12));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          _userUuid = data['uuid'];
          if (_userUuid != null) {
            prefs.setString('user_uuid', _userUuid!);
          }

          final List serverList = data['servers'] ?? [];
          _servers = serverList.map((s) => ServerModel.fromJson(s)).toList();
          prefs.setString('cached_servers', jsonEncode(serverList));

          if (_servers.isNotEmpty) {
            if (_selectedServer == null || !_servers.any((s) => s.name == _selectedServer!.name)) {
              _selectedServer = _servers.first;
            }
          }
          return;
        }
        debugPrint("Register returned status ${response.statusCode}");
      } catch (e) {
        debugPrint("Register attempt ${attempt + 1} failed: $e");
      }
      await Future.delayed(const Duration(seconds: 2));
    }
    debugPrint("Failed to reach API server after retries. Using cached servers if any.");
  }

  void selectServer(ServerModel server) {
    _selectedServer = server;
    notifyListeners();
  }

  Future<bool> requestVpnPermission() async {
    // On iOS the sing_box plugin installs the tunnel profile and triggers the
    // system "Allow VPN configuration" prompt during connect(), so there is no
    // separate permission step here.
    if (Platform.isIOS) return true;
    return await _v2ray.requestPermission();
  }

  Future<void> connect() async {
    if (_selectedServer == null) return;
    if (Platform.isIOS) {
      await _connectIOS();
    } else {
      await _connectAndroid();
    }
  }

  Future<void> _connectAndroid() async {
    final hasPermission = await requestVpnPermission();
    if (!hasPermission) {
      _vpnState = 'DENIED';
      notifyListeners();
      return;
    }

    try {
      _vpnState = 'CONNECTING';
      notifyListeners();

      // The API returns a VLESS share link (vless://...), but the plugin needs a
      // full V2Ray JSON config. Parse the link into a proper configuration first.
      final V2RayURL parser = FlutterV2ray.parseFromURL(_selectedServer!.link);

      await _v2ray.startV2Ray(
        remark: _selectedServer!.name,
        config: parser.getFullConfiguration(),
      );

      _logConnection();
    } catch (e) {
      debugPrint("V2Ray Start Tunnel Error: $e");
      _vpnState = 'DISCONNECTED';
      notifyListeners();
    }
  }

  Future<void> _connectIOS() async {
    try {
      _lastConnectError = null;
      _vpnState = 'CONNECTING';
      notifyListeners();

      // sing-box wants a full JSON config; build it from the VLESS link.
      final config = SingBoxConfig.fromVlessLink(_selectedServer!.link);
      final ok = await _singBox.connect(config);
      if (!ok) {
        await _reportIOSConnectError();
        _vpnState = 'DISCONNECTED';
        notifyListeners();
        return;
      }
      // The tunnel can still fail asynchronously inside the Network Extension
      // (e.g. bad config). Give it a few seconds and, if it didn't reach the
      // connected state, surface the real error from the extension.
      _logConnection();
      Future.delayed(const Duration(seconds: 6), () async {
        if (_vpnState != 'CONNECTED') {
          await _reportIOSConnectError();
          notifyListeners();
        }
      });
    } catch (e) {
      debugPrint("sing-box start error: $e");
      _vpnState = 'DISCONNECTED';
      notifyListeners();
    }
  }

  Future<void> _reportIOSConnectError() async {
    try {
      final err = await _singBox.getLastError();
      if (err != null && err.isNotEmpty) {
        _lastConnectError = err;
        debugPrint("sing-box connect failed: $err");
      }
    } catch (e) {
      debugPrint("Failed to fetch sing-box last error: $e");
    }
  }

  Future<void> disconnect() async {
    try {
      if (Platform.isIOS) {
        await _singBox.disconnect();
      } else {
        await _v2ray.stopV2Ray();
      }
    } catch (e) {
      debugPrint("Stop Tunnel Error: $e");
    }
  }

  String _mapSingBoxStatus(SingBoxConnectionStatus status) {
    switch (status) {
      case SingBoxConnectionStatus.connected:
        return 'CONNECTED';
      case SingBoxConnectionStatus.connecting:
        return 'CONNECTING';
      case SingBoxConnectionStatus.disconnecting:
        return 'CONNECTING';
      case SingBoxConnectionStatus.disconnected:
      case SingBoxConnectionStatus.disconnectedByUser:
      case SingBoxConnectionStatus.connectionLost:
      case SingBoxConnectionStatus.error:
        return 'DISCONNECTED';
    }
  }

  @override
  void dispose() {
    _singBoxStatusSub?.cancel();
    super.dispose();
  }

  Future<void> _logConnection() async {
    try {
      await http.post(
        Uri.parse('$_apiUrl/api/connect'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'device_id': _deviceId}),
      );
    } catch (_) {}
  }
}
