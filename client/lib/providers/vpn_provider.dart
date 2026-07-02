import 'dart:convert';
import 'dart:io';
import 'package:client/models/server_model.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_v2ray/flutter_v2ray.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class VpnProvider extends ChangeNotifier {
  late FlutterV2ray _v2ray;

  bool _initialized = false;
  bool _isLoading = false;
  String _vpnState = 'DISCONNECTED';
  String _vpnDuration = '00:00:00';

  List<ServerModel> _servers = [];
  ServerModel? _selectedServer;
  String? _deviceId;
  String? _userUuid;

  // Production API server (VDS)
  String get _apiUrl {
    return 'http://92.38.48.158:8080';
  }

  bool get isInitialized => _initialized;
  bool get isLoading => _isLoading;
  String get vpnState => _vpnState;
  String get vpnDuration => _vpnDuration;
  bool get isConnected => _vpnState == 'CONNECTED';
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

    try {
      await _v2ray.initializeV2Ray();
      _deviceId = await _getDeviceId();
      await _registerDevice();
      _initialized = true;
    } catch (e) {
      debugPrint("VPN Initialization Error: $e");
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

    try {
      final response = await http.post(
        Uri.parse('$_apiUrl/api/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'device_id': _deviceId}),
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _userUuid = data['uuid'];
        prefs.setString('user_uuid', _userUuid!);

        final List serverList = data['servers'];
        _servers = serverList.map((s) => ServerModel.fromJson(s)).toList();
        prefs.setString('cached_servers', jsonEncode(serverList));

        if (_servers.isNotEmpty) {
          if (_selectedServer == null || !_servers.any((s) => s.name == _selectedServer!.name)) {
            _selectedServer = _servers.first;
          }
        }
      }
    } catch (e) {
      debugPrint("Failed to reach API server. Active servers might be outdated. Error: $e");
    }
  }

  void selectServer(ServerModel server) {
    _selectedServer = server;
    notifyListeners();
  }

  Future<bool> requestVpnPermission() async {
    return await _v2ray.requestPermission();
  }

  Future<void> connect() async {
    if (_selectedServer == null) return;

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

      // Start V2Ray client tunnel
      await _v2ray.startV2Ray(
        remark: _selectedServer!.name,
        config: parser.getFullConfiguration(),
      );

      // Log connection to бэкенд
      _logConnection();
    } catch (e) {
      debugPrint("V2Ray Start Tunnel Error: $e");
      _vpnState = 'DISCONNECTED';
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    try {
      await _v2ray.stopV2Ray();
    } catch (e) {
      debugPrint("V2Ray Stop Tunnel Error: $e");
    }
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
