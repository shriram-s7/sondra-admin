import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';

class ApiService {
  final Dio dio = Dio();
  String? baseUrl;
  String? token;
  StreamController<Map<String, dynamic>> sseController = StreamController.broadcast();
  StreamSubscription? sseSubscription;

  // Hardcoded admin credentials for auto-login (Android + Windows).
  // Change these if your backend admin password changes, then rebuild.
  static const String _adminUsername = "shriram";
  static const String _adminPassword = "nopassword";

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
        // Don't retry the login endpoint itself — that would cause an infinite
        // loop if the hardcoded credentials happen to be wrong or change.
        if (e.response?.statusCode == 401 && !e.requestOptions.path.contains('/auth/login')) {
          // Transparently re-login and retry (Android + Windows)
          final success = await _autoLogin();
          if (success) {
            e.requestOptions.headers["Authorization"] = "Bearer $token";
            try {
              final retryResponse = await dio.fetch(e.requestOptions);
              handler.resolve(retryResponse);
              return;
            } catch (_) {}
          }
        }
        return handler.next(e);
      },
    ));
  }

  Future<void> init() async {
    baseUrl = "https://sondra-backend-cxkc.onrender.com";
    dio.options.baseUrl = baseUrl!;

    // Both Android and Windows: auto-login silently with hardcoded credentials
    // No SharedPreferences token storage, no user-facing auth
    await _autoLogin();
  }

  /// Silently authenticates on startup and on 401 — both platforms.
  Future<bool> _autoLogin() async {
    try {
      final response = await dio.post(
        "/auth/login/form",
        data: {"username": _adminUsername, "password": _adminPassword},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      token = response.data["access_token"];
      startSseConnection();
      return true;
    } catch (e) {
      print("Auto-login failed: $e");
      token = null;
      return false;
    }
  }

  Future<void> logout() async {
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

  Future<List<dynamic>> getPlaylists() async {
    final res = await dio.get("/api/playlists");
    return res.data;
  }

  Future<List<dynamic>> getHistoryRecent() async {
    final res = await dio.get("/api/history/recent", queryParameters: {"limit": 20});
    return res.data;
  }

  Future<void> logHistory(int songId, int positionSeconds) async {
    await dio.post("/api/history", data: {
      "song_id": songId,
      "position_seconds": positionSeconds,
    });
  }

  Future<String> getDirectStreamUrl(int songId) async {
    try {
      final res = await dio.get("/api/stream/$songId/direct");
      print('[DIRECT-API] response for song $songId: status=${res.statusCode} body=${res.data}');
      return res.data["url"] as String;
    } catch (e) {
      print('[DIRECT-API] threw for song $songId: $e');
      rethrow;
    }
  }

  String getProxyStreamUrl(int songId) {
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
