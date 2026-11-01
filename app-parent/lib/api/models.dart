class AuthResult {
  final String accessToken;
  final String refreshToken;
  final String userId;
  final String email;
  final String familyId;

  AuthResult({
    required this.accessToken,
    required this.refreshToken,
    required this.userId,
    required this.email,
    required this.familyId,
  });

  factory AuthResult.fromJson(Map<String, dynamic> j) {
    final user = j['user'] as Map<String, dynamic>;
    return AuthResult(
      accessToken: j['accessToken'] as String,
      refreshToken: j['refreshToken'] as String,
      userId: user['id'] as String,
      email: user['email'] as String,
      familyId: user['familyId'] as String,
    );
  }
}

class Device {
  final String id;
  final String name;
  final String status;
  final int? batteryPct;
  final String? model;
  final String? manufacturer;
  final DateTime? lastSeenAt;

  Device({
    required this.id,
    required this.name,
    required this.status,
    this.batteryPct,
    this.model,
    this.manufacturer,
    this.lastSeenAt,
  });

  factory Device.fromJson(Map<String, dynamic> j) => Device(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? 'Device',
        status: (j['status'] as String?) ?? 'UNKNOWN',
        batteryPct: j['batteryPct'] as int?,
        model: j['model'] as String?,
        manufacturer: j['manufacturer'] as String?,
        lastSeenAt: j['lastSeenAt'] != null
            ? DateTime.tryParse(j['lastSeenAt'] as String)
            : null,
      );
}

class AlertModel {
  final String id;
  final String type;
  final String title;
  final String body;
  final DateTime? createdAt;
  final bool read;

  AlertModel({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.createdAt,
    required this.read,
  });

  factory AlertModel.fromJson(Map<String, dynamic> j) => AlertModel(
        id: j['id'] as String,
        type: (j['type'] as String?) ?? 'SYSTEM',
        title: (j['title'] as String?) ?? '',
        body: (j['body'] as String?) ?? '',
        createdAt: j['createdAt'] != null
            ? DateTime.tryParse(j['createdAt'] as String)
            : null,
        read: j['readAt'] != null,
      );
}

class Pairing {
  final String id;
  final String code;
  final String qrToken;
  final String status;

  Pairing({
    required this.id,
    required this.code,
    required this.qrToken,
    required this.status,
  });

  factory Pairing.fromJson(Map<String, dynamic> j) => Pairing(
        id: j['id'] as String,
        code: (j['code'] as String?) ?? '',
        qrToken: (j['qrToken'] as String?) ?? '',
        status: (j['status'] as String?) ?? 'PENDING',
      );
}

class DeviceLocation {
  final String? id;
  final double lat;
  final double lng;
  final double? accuracyM;
  final DateTime? occurredAt;

  DeviceLocation({
    this.id,
    required this.lat,
    required this.lng,
    this.accuracyM,
    this.occurredAt,
  });

  factory DeviceLocation.fromJson(Map<String, dynamic> j) => DeviceLocation(
        id: j['id'] as String?,
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        accuracyM: (j['accuracyM'] as num?)?.toDouble(),
        occurredAt: j['occurredAt'] != null
            ? DateTime.tryParse(j['occurredAt'] as String)
            : null,
      );
}

class GeofencePlace {
  final String id;
  final String name;
  final double lat;
  final double lng;
  final double radiusM;
  final bool active;

  GeofencePlace({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    required this.radiusM,
    required this.active,
  });

  factory GeofencePlace.fromJson(Map<String, dynamic> j) => GeofencePlace(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? 'Place',
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        radiusM: (j['radiusM'] as num?)?.toDouble() ?? 200,
        active: j['active'] as bool? ?? true,
      );
}

class PhotoFlag {
  final String id;
  final String category;
  final double confidence;
  final DateTime occurredAt;

  PhotoFlag({
    required this.id,
    required this.category,
    required this.confidence,
    required this.occurredAt,
  });

  factory PhotoFlag.fromJson(Map<String, dynamic> j) => PhotoFlag(
        id: j['id'] as String,
        category: (j['category'] as String?) ?? 'unknown',
        confidence: (j['confidence'] as num?)?.toDouble() ?? 0,
        occurredAt: j['occurredAt'] != null
            ? DateTime.parse(j['occurredAt'] as String)
            : DateTime.now(),
      );
}

class ContentItem {
  final String id;
  final String source;
  final String body;
  final String? matched;
  final String? counterparty;
  final DateTime? occurredAt;

  ContentItem({
    required this.id,
    required this.source,
    required this.body,
    this.matched,
    this.counterparty,
    this.occurredAt,
  });

  factory ContentItem.fromJson(Map<String, dynamic> j) => ContentItem(
        id: j['id'] as String,
        source: (j['source'] as String?) ?? '',
        body: (j['body'] as String?) ?? '',
        matched: j['matched'] as String?,
        counterparty: j['counterparty'] as String?,
        occurredAt: j['occurredAt'] != null
            ? DateTime.tryParse(j['occurredAt'] as String)
            : null,
      );
}

class EventLog {
  final String id;
  final String type;
  final Map<String, dynamic> data;
  final DateTime occurredAt;

  EventLog({
    required this.id,
    required this.type,
    required this.data,
    required this.occurredAt,
  });

  factory EventLog.fromJson(Map<String, dynamic> j) => EventLog(
        id: j['id'] as String,
        type: (j['type'] as String?) ?? '',
        data: (j['data'] as Map<String, dynamic>?) ?? <String, dynamic>{},
        occurredAt: j['occurredAt'] != null
            ? DateTime.parse(j['occurredAt'] as String)
            : DateTime.now(),
      );
}

class ScreenSession {
  final String id;
  final String deviceId;
  final bool consented;
  final String transport;
  final String status;
  final DateTime startedAt;
  final DateTime? endedAt;

  ScreenSession({
    required this.id,
    required this.deviceId,
    required this.consented,
    required this.transport,
    required this.status,
    required this.startedAt,
    this.endedAt,
  });

  factory ScreenSession.fromJson(Map<String, dynamic> j) => ScreenSession(
        id: j['id'] as String,
        deviceId: j['deviceId'] as String,
        consented: j['consented'] as bool? ?? false,
        transport: (j['transport'] as String?) ?? 'clip',
        status: (j['status'] as String?) ?? 'pending',
        startedAt: j['startedAt'] != null
            ? DateTime.parse(j['startedAt'] as String)
            : DateTime.now(),
        endedAt: j['endedAt'] != null
            ? DateTime.tryParse(j['endedAt'] as String)
            : null,
      );
}
