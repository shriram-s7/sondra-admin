import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  final Dio dio = Dio();
  String? baseUrl;
  String? token;
  StreamController<Map<String, dynamic>> sseController = StreamController.broadcast();
  StreamSubscription? sseSubscription;

  // Android auto-login credentials (personal app — change these if your admin password changes)
  static const String _androidUsername = "admin";
  static const String _androidPassword = "admin";

  bool get _isAndroid => !kIsWeb && !Platform.isWindows;

  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal() {
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (token != null) {
          options.headers["Authorization"] = "Bearer $token";
        }
        return handler.next(options);
      },
      onError: (DioException e, handler) async {
        if (e.response?.statusCode == 401) {
          if (_isAndroid) {
            // Android: transparently re-login and retry
            final success = await _autoLogin();
            if (success) {
              e.requestOptions.headers["Authorization"] = "Bearer $token";
              try {
                final retryResponse = await dio.fetch(e.requestOptions);
                handler.resolve(retryResponse);
                return;
              } catch (_) {}
            }
          } else {
            // Windows: clear stored token on 401
            final prefs = await SharedPreferences.getInstance();
            await prefs.remove("sondra_token");
            token = null;
            sseSubscription?.cancel();
          }
        }
        return handler.next(e);
      },
    ));
  }

  Future<void> init() async {
    baseUrl = "https://sondra-backend-cxkc.onrender.com";
    dio.options.baseUrl = baseUrl!;

    if (_isAndroid) {
      // Android: auto-login silently — no user interaction, no SharedPreferences
      await _autoLogin();
    } else {
      // Windows: use stored token from previous session
      final prefs = await SharedPreferences.getInstance();
      token = prefs.getString("sondra_token");
      if (token != null) {
        startSseConnection();
      }
    }
  }

  /// Android transparent login — called silently on startup and on 401.
  Future<bool> _autoLogin() async {
    try {
      final response = await dio.post(
        "$baseUrl/auth/login",
        data: {"username": _androidUsername, "password": _androidPassword},
      );
      token = response.data["access_token"];
      startSseConnection();
      return true;
    } catch (e) {
      print("Android auto-login failed: $e");
      token = null;
      return false;
    }
  }

  /// Windows-only login with SharedPreferences storage.
  /// On Android this delegates to _autoLogin (no persistence).
  Future<bool> login(String username, String password) async {
    if (_isAndroid) {
      return _autoLogin();
    }
    String cleanUrl = "https://sondra-backend-cxkc.onrender.com";
    try {
      final response = await dio.post(
        "$cleanUrl/auth/login",
        data: {"username": username, "password": password},
      );
      final String jwtToken = response.data["access_token"];
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString("sondra_server_url", cleanUrl);
      await prefs.setString("sondra_token", jwtToken);
      baseUrl = cleanUrl;
      token = jwtToken;
      dio.options.baseUrl = cleanUrl;
      startSseConnection();
      return true;
    } catch (e) {
      print("Login failed: $e");
      return false;
    }
  }

  Future<void> logout() async {
    if (_isAndroid) {
      // Android: just clear in-memory — no persisted state
      token = null;
      sseSubscription?.cancel();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove("sondra_token");
    token = null;
    sseSubscription?.cancel();
  }

  void startSseConnection() {
    sseSubscription?.cancel();
    if (baseUrl == null || token == null) return;

    // Connect to backend SSE event stream
    // Because standard EventSource is not in Dart, we use Dio with responseType=stream
    final sseUrl = "$baseUrl/api/events?token=$token";
    
    StreamSubscription? sub;
    sub = dio.get<ResponseBody>(
      sseUrl,
      options: Options(responseType: ResponseType.stream),
    ).asStream().listen((response) {
      final stream = response.data?.stream;
      if (stream == null) return;
      
      sseSubscription = stream.map((event) => event as List<int>).transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        if (line.startsWith("data: ")) {
          try {
            final jsonStr = line.substring(6);
            final data = Map<String, dynamic>.from(jsonDecode(jsonStr));
            sseController.add(data);
          } catch (e) {
            print("Error parsing SSE line: $e");
          }
        }
      }, onError: (err) {
        print("SSE stream error: $err. Reconnecting in 5s...");
        Future.delayed(const Duration(seconds: 5), startSseConnection);
      }, onDone: () {
        print("SSE stream closed. Reconnecting in 5s...");
        Future.delayed(const Duration(seconds: 5), startSseConnection);
      });
    }, onError: (err) {
      print("Failed to open SSE: $err. Retrying in 10s...");
      Future.delayed(const Duration(seconds: 10), startSseConnection);
    });
    
    sseSubscription = sub;
  }

  // API wrappers
  Future<List<dynamic>> getSongs() async {
    final res = await dio.get("/api/songs");
    return res.data;
  }

  Future<List<dynamic>> getSongsSearch(String query) async {
    final res = await dio.get("/api/songs/search", queryParameters: {"q": query});
    return res.data;
  }

  Future<List<dynamic>> getPlaylists() async {
    final res = await dio.get("/api/playlists");
    return res.data;
  }

  Future<List<dynamic>> getHistoryRecent() async {
    final res = await dio.get("/api/history/recent", queryParameters: {"limit": 20});
    return res.data;
  }

  Future<List<dynamic>> getHistoryContinue() async {
    final res = await dio.get("/api/history/continue");
    return res.data;
  }

  Future<void> logHistory(int songId, int positionSeconds) async {
    await dio.post("/api/history", data: {
      "song_id": songId,
      "position_seconds": positionSeconds,
    });
  }

  Future<String> getDirectStreamUrl(int songId) async {
    final res = await dio.get("/api/stream/$songId");
    return res.data["stream_url"];
  }

  Future<String> getDownloadUrl(int songId) async {
    return "$baseUrl/api/stream/$songId/proxy?token=$token";
  }

  Future<void> triggerSync() async {
    await dio.post("/api/sync");
  }

  Future<Map<String, dynamic>> getSyncStatus() async {
    final res = await dio.get("/api/sync/status");
    return Map<String, dynamic>.from(res.data);
  }
}
