import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'models.dart';

/// Talks to the monii backend. Adds the access token, and on a 401 silently
/// refreshes (rotating refresh token) and retries the failed request once.
class ApiClient {
  final Dio _dio;
  final FlutterSecureStorage _storage;
  final String baseUrl;

  ApiClient({required this.baseUrl, FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage(),
        _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        )) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.read(key: 'access');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (e, handler) async {
        if (e.response?.statusCode == 401 && await _tryRefresh()) {
          try {
            final req = e.requestOptions;
            final token = await _storage.read(key: 'access');
            req.headers['Authorization'] = 'Bearer $token';
            final response = await _dio.fetch<dynamic>(req);
            return handler.resolve(response);
          } catch (_) {
            // fall through to the original error
          }
        }
        handler.next(e);
      },
    ));
  }

  // ---- auth ----

  Future<AuthResult> login(String email, String password) async {
    final r = await _dio.post<dynamic>('/auth/login',
        data: {'email': email, 'password': password});
    return _persist(AuthResult.fromJson(r.data as Map<String, dynamic>));
  }

  Future<AuthResult> register(
      String email, String password, String? familyName) async {
    final r = await _dio.post<dynamic>('/auth/register', data: {
      'email': email,
      'password': password,
      if (familyName != null) 'familyName': familyName,
    });
    return _persist(AuthResult.fromJson(r.data as Map<String, dynamic>));
  }

  Future<void> logout() async {
    try {
      await _dio.post<dynamic>('/auth/logout');
    } catch (_) {
      // best effort
    }
    await _storage.deleteAll();
  }

  Future<bool> hasSession() async =>
      (await _storage.read(key: 'access')) != null;

  Future<String?> accessToken() => _storage.read(key: 'access');

  Future<AuthResult> _persist(AuthResult r) async {
    await _storage.write(key: 'access', value: r.accessToken);
    await _storage.write(key: 'refresh', value: r.refreshToken);
    return r;
  }

  Future<bool> _tryRefresh() async {
    final refresh = await _storage.read(key: 'refresh');
    if (refresh == null) return false;
    try {
      final r = await _dio
          .post<dynamic>('/auth/refresh', data: {'refreshToken': refresh});
      await _persist(AuthResult.fromJson(r.data as Map<String, dynamic>));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Register the parent device's FCM push token so alerts arrive instantly.
  /// Safe to call even when Firebase is not configured (silent 404/error).
  Future<void> setFcmToken(String token) async {
    try {
      await _dio.patch<dynamic>('/auth/fcm-token', data: {'fcmToken': token});
    } catch (_) {
      // Firebase not configured or network down — silent no-op
    }
  }

  // ---- devices ----

  Future<List<Device>> devices() async {
    final r = await _dio.get<dynamic>('/devices');
    return (r.data as List)
        .map((e) => Device.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ---- pairing ----

  Future<Pairing> createPairing() async {
    final r = await _dio.post<dynamic>('/pairings', data: <String, dynamic>{});
    return Pairing.fromJson(r.data as Map<String, dynamic>);
  }

  Future<String> pairingStatus(String id) async {
    final r = await _dio.get<dynamic>('/pairings/$id');
    return (r.data as Map<String, dynamic>)['status'] as String? ?? 'PENDING';
  }

  // ---- commands ----

  Future<void> sendCommand(String deviceId, String type,
      [Map<String, dynamic>? payload]) async {
    await _dio.post<dynamic>('/devices/$deviceId/commands', data: {
      'type': type,
      if (payload != null) 'payload': payload,
    });
  }

  // ---- policy ----

  Future<Map<String, dynamic>?> getPolicy() async {
    final r = await _dio.get<dynamic>('/policies');
    final data = r.data;
    if (data is Map<String, dynamic>) {
      return data['rules'] as Map<String, dynamic>?;
    }
    return null;
  }

  Future<void> updatePolicy(Map<String, dynamic> rules) async {
    await _dio.put<dynamic>('/policies', data: {'rules': rules});
  }

  // ---- alerts ----

  Future<List<AlertModel>> alerts() async {
    final r = await _dio.get<dynamic>('/alerts');
    return (r.data as List)
        .map((e) => AlertModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> markAlertRead(String id) async {
    await _dio.post<dynamic>('/alerts/$id/read');
  }

  // ---- location ----

  Future<DeviceLocation?> latestLocation(String deviceId) async {
    final r = await _dio.get<dynamic>('/devices/$deviceId/locations/latest');
    final data = r.data;
    if (data is Map<String, dynamic>) return DeviceLocation.fromJson(data);
    return null;
  }

  Future<List<DeviceLocation>> locationHistory(String deviceId,
      {int limit = 100}) async {
    final r = await _dio.get<dynamic>(
      '/devices/$deviceId/locations',
      queryParameters: {'limit': limit.toString()},
    );
    return (r.data as List)
        .map((e) => DeviceLocation.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<GeofencePlace>> listGeofences(String deviceId) async {
    final r = await _dio.get<dynamic>('/devices/$deviceId/geofences');
    return (r.data as List)
        .map((e) => GeofencePlace.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<GeofencePlace> createGeofence(
    String deviceId, {
    required String name,
    required double lat,
    required double lng,
    double radiusM = 200,
  }) async {
    final r = await _dio.post<dynamic>('/devices/$deviceId/geofences', data: {
      'name': name,
      'lat': lat,
      'lng': lng,
      'radiusM': radiusM,
    });
    return GeofencePlace.fromJson(r.data as Map<String, dynamic>);
  }

  Future<void> deleteGeofence(String deviceId, String geofenceId) async {
    await _dio.delete<dynamic>('/devices/$deviceId/geofences/$geofenceId');
  }

  // ---- content / keyword detection ----

  Future<List<PhotoFlag>> getPhotoFlags(String deviceId, {int limit = 100}) async {
    final r = await _dio.get<dynamic>(
      '/devices/$deviceId/photo-flags',
      queryParameters: {'limit': limit.toString()},
    );
    return (r.data as List)
        .map((e) => PhotoFlag.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<ContentItem>> getContent(String deviceId,
      {String? source}) async {
    final query = <String, dynamic>{};
    if (source != null) query['source'] = source;
    final r = await _dio.get<dynamic>(
      '/devices/$deviceId/content',
      queryParameters: query.isNotEmpty ? query : null,
    );
    return (r.data as List)
        .map((e) => ContentItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ---- usage logs / events ----

  Future<List<EventLog>> getEvents(String deviceId, {int limit = 100}) async {
    final r = await _dio.get<dynamic>(
      '/devices/$deviceId/events',
      queryParameters: {'limit': limit.toString()},
    );
    return (r.data as List)
        .map((e) => EventLog.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ---- live screen sessions ----

  /// [mode] = 'mirror' (continuous live stream) or 'screenshot' (one frame).
  Future<ScreenSession> createScreenSession(
    String deviceId, {
    String mode = 'mirror',
  }) async {
    final r = await _dio.post<dynamic>(
      '/devices/$deviceId/screen-sessions',
      data: {'mode': mode},
    );
    return ScreenSession.fromJson(r.data as Map<String, dynamic>);
  }

  /// On-demand screenshot: opens a session the device fills with a single frame.
  /// Join the returned session over the /screen socket to receive it.
  Future<ScreenSession> requestScreenshot(String deviceId) =>
      createScreenSession(deviceId, mode: 'screenshot');

  /// Remote-release Device Owner self-protection so the app can be removed.
  Future<void> releaseDeviceOwner(String deviceId) =>
      sendCommand(deviceId, 'RELEASE_OWNER');

  Future<ScreenSession> getScreenSession(String sessionId) async {
    final r = await _dio.get<dynamic>('/screen-sessions/$sessionId');
    return ScreenSession.fromJson(r.data as Map<String, dynamic>);
  }

  Future<ScreenSession> endScreenSession(String sessionId) async {
    final r = await _dio.post<dynamic>('/screen-sessions/$sessionId/end');
    return ScreenSession.fromJson(r.data as Map<String, dynamic>);
  }
}
