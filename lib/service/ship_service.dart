import 'dart:async';
import 'dart:convert';
import 'package:aisits_mobileapp/model/ship_model.dart';
import 'package:aisits_mobileapp/service/json_service.dart';
import 'package:aisits_mobileapp/service/notification_service.dart';
import 'package:aisits_mobileapp/service/websocket_service.dart';
import 'package:aisits_mobileapp/utils/log_utils.dart';
import 'package:aisits_mobileapp/widget/polygon_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

typedef OnMarkerTap = void Function(ShipData shipData);

class ShipService extends ChangeNotifier {
  static const int _maxReconnectAttempts = 5;
  static const Duration _reconnectDelay = Duration(seconds: 3);
  static const int _maxCachedShips = 1000;
  
  final WebSocketService _webSocketService;
  final JsonService _jsonService = JsonService();
  late final NotificationService _notificationService;  // Change to late final
  final Map<String, ShipData> ships = {};
  final ValueNotifier<Map<String, Marker>> markersNotifier = ValueNotifier({});
  final OnMarkerTap? onMarkerTap;
  
  StreamSubscription? _webSocketSubscription;
  Timer? _cleanupTimer;
  int _reconnectCount = 0;
  bool _isConnecting = false;
  bool _isDisposed = false;
  ShipService({
    required String url,
    required String token,
    required NotificationService notificationService,
    this.onMarkerTap,
  }) : _webSocketService = WebSocketService(url, token) {
    _notificationService = notificationService;  // Use provided instance
    _initService(url, token);
  }
  Future<void> _initService(String url, String token) async {
    try {
      await loadShipData();
      _connectWebSocket(url, token);
      _startCleanupTimer();
    } catch (e) {
      LogUtils.error('Service initialization error', e);
    }
  }
  void _startCleanupTimer() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _cleanupOldData();
    });
  }
  void _cleanupOldData() {
    if (ships.length > _maxCachedShips) {
      final keysToRemove = ships.keys.take(ships.length - _maxCachedShips);
      for (final key in keysToRemove) {
        ships.remove(key);
        markersNotifier.value.remove(key);
      }
      markersNotifier.notifyListeners();
    }
  }
  void _connectWebSocket(String url, String token) async {
    if (_isConnecting || _isDisposed) return;
    _isConnecting = true;
    
    try {
      await _webSocketSubscription?.cancel();
      _webSocketSubscription = _webSocketService.shipDataStream.listen(
        _handleWebSocketData,
        onError: (error) {
          LogUtils.error('WebSocket error', error);
          _handleReconnection(url, token);
        },
        onDone: () {
          if (!_isDisposed) {
            LogUtils.error('WebSocket connection closed');
            _handleReconnection(url, token);
          }
        },
      );
      _reconnectCount = 0;
    } catch (e) {
      LogUtils.error('WebSocket connection error', e);
      _handleReconnection(url, token);
    } finally {
      _isConnecting = false;
    }
  }
  Future<void> _handleWebSocketData(dynamic data) async {
    if (_isDisposed) return;

    try {
      Map<String, dynamic> messageData;
      if (data is String) {
        messageData = json.decode(data);
      } else if (data is Map) {
        messageData = Map<String, dynamic>.from(data);
      } else if (data is ShipData) {
        if (_isValidShipData(data)) {
          await _updateShipData(data);
        }
        return;
      } else {
        LogUtils.error('Unexpected data format', data.runtimeType);
        return;
      }

      final message = messageData['message'];
      if (message == null || message is! Map) {
        LogUtils.error('Invalid message format', message);
        return;
      }

      final aisData = message['data'];
      if (aisData == null || aisData is! Map || aisData['valid'] != true) {
        LogUtils.error('Invalid AIS data format', aisData);
        return;
      }

      final shipData = ShipData(
        id: (aisData['mmsi'] ?? '').toString(),
        latitude: _parseDouble(aisData['lat']),
        longitude: _parseDouble(aisData['lon']),
        speed: _parseDouble(aisData['sog']),
        trueHeading: _parseDouble(aisData['hdg']),
        cog: _parseDouble(aisData['cog']),
        navStatus: _getNavStatus(aisData['navstatus']),
        engineStatus: aisData['smi'] == 0 ? 'ON' : 'OFF',
        receivedOn: DateTime.now(),
      );

      if (_isValidShipData(shipData)) {
        await _updateShipData(shipData);
      }
    } catch (e, stackTrace) {
      LogUtils.error('Data parsing error', e);
      LogUtils.error('Stack trace', stackTrace);
    }
  }
  double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }
  String _getNavStatus(dynamic status) {
    switch(status) {
      case 0: return 'Under way using engine';
      case 1: return 'At anchor';
      case 2: return 'Not under command';
      case 3: return 'Restricted maneuverability';
      case 4: return 'Constrained by draught';
      case 5: return 'Moored';
      case 6: return 'Aground';
      case 7: return 'Engaged in fishing';
      case 8: return 'Under way sailing';
      default: return 'Unknown';
    }
  }
  bool _isValidShipData(ShipData shipData) {
    return shipData.id.isNotEmpty && _isValidCoordinates(shipData);
  }
  Future<void> _updateShipData(ShipData shipData) async {
    try {
      final mmsi = shipData.id.toString();
      final jsonData = await _jsonService.getShipData(mmsi);
      
      if (jsonData is Map<String, dynamic>) {
        // Perbaikan pengambilan data kapal
        shipData.name = jsonData['NAME']?.toString();
        shipData.type = jsonData['TYPENAME']?.toString();
        print("Ship data updated - MMSI: $mmsi, Name: ${shipData.name}, Type: ${shipData.type}"); // Debug log
      }

      ships[mmsi] = shipData;
      _updateMarkerWithShipData(shipData);
      checkShipLocation(shipData, getPolygons());
      notifyListeners();
    } catch (e) {
      LogUtils.error('Error updating ship data', e);
    }
  }
  void checkShipLocation(ShipData shipData, List<Polygon> polygons) {
    if (polygons.isEmpty || !_isValidCoordinates(shipData)) return;

    final LatLng latLng = LatLng(shipData.latitude, shipData.longitude);
    final String shipName = shipData.name ?? 'Unknown Ship';

    try {
      for (Polygon polygon in polygons) {
        if (isPointInPolygon(latLng, polygon.points)) {
          var color = polygon.color ?? Colors.blue;
          _handleShipInPolygon(shipName, color);
          LogUtils.info("Ship in polygon: $shipName");
          return;
        }
      }
    } catch (e) {
      LogUtils.error('Error checking ship location', e);
    }
  }
  void _handleShipInPolygon(String shipName, Color polygonColor) {
    try {
      // Menggunakan warna dasar untuk pengecekan
      final bool isDangerZone = polygonColor.withOpacity(1.0).value == Colors.red.value;
      final bool isRestrictedZone = polygonColor.withOpacity(1.0).value == Colors.blue.value;
      
      final String message = isDangerZone
        ? "Kapal $shipName memasuki AREA TERLARANG!"
        : "Kapal $shipName memasuki AREA TERBATAS!";

      if (isDangerZone) {
        _notificationService.addDangerMessage(message);
        LogUtils.info("Notifikasi bahaya ditambahkan untuk $shipName");
      } else if (isRestrictedZone) {
        _notificationService.addAlertMessage(message);
        LogUtils.info("Notifikasi peringatan ditambahkan untuk $shipName");
      }
      
      notifyListeners();
    } catch (e) {
      LogUtils.error('Error saat menangani kapal dalam polygon', e);
    }
  }
  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;

    try {
      _webSocketSubscription?.cancel();
      _cleanupTimer?.cancel();
      markersNotifier.dispose();
      ships.clear();
      // Don't close the WebSocket service here, as it's shared
      // close();  // Remove this line
    } catch (e) {
      LogUtils.error('Error disposing ShipService', e);
    }
    
    super.dispose();
  }
  // Add this method to properly cleanup resources
  void cleanup(bool _isInitialized) {
    _webSocketSubscription?.cancel();
    _cleanupTimer?.cancel();
    ships.clear();
    markersNotifier.value.clear();
    _isInitialized = false;
    _reconnectCount = 0;
  }
  // Modify _initService to handle reinitializations
  void _handleReconnection(String url, String token) {
    if (_reconnectCount < _maxReconnectAttempts) {
      _reconnectCount++;
      Future.delayed(_reconnectDelay, () => _connectWebSocket(url, token));
    } else {
      LogUtils.error('Max reconnection attempts reached');
    }
  }
  void _updateMarkerWithShipData(ShipData shipData) {
    if (!_isValidCoordinates(shipData)) {
      LogUtils.error('Invalid coordinates', 'MMSI=${shipData.id}');
      return;
    }

    final String mmsi = shipData.id.toString();
    final LatLng latLng = LatLng(shipData.latitude, shipData.longitude);

    try {
      markersNotifier.value = Map.from(markersNotifier.value)
        ..[mmsi] = _createMarker(shipData, latLng);
      LogUtils.shipData(mmsi, 
        name: shipData.name, 
        type: shipData.type, 
        action: 'marker_updated'
      );
    } catch (e) {
      LogUtils.error('Marker update error', e);
    }
  }
  bool _isValidCoordinates(ShipData shipData) {
    return shipData.latitude != 0.0 && 
           shipData.longitude != 0.0 && 
           shipData.latitude.abs() <= 90 && 
           shipData.longitude.abs() <= 180;
  }
  void _handleMarkerTap(ShipData shipData) {
    try {
      LogUtils.shipData(
        shipData.id, 
        name: shipData.name, 
        type: shipData.type,
        action: 'marker_tapped'
      );
      
      if (onMarkerTap != null) {
        onMarkerTap!(shipData);
      }
    } catch (e) {
      LogUtils.error('Error handling marker tap', e);
    }
  }
  Marker _createMarker(ShipData shipData, LatLng position) {
    // Pendekatan baru untuk rotasi ikon kapal
    final double rotationAngle;
  // Penyesuaian khusus untuk COG = 0
    if (shipData.cog == 0) {
      // Tidak perlu rotasi untuk COG 0, biarkan ikon dalam orientasi default
      rotationAngle = 0;
      print("Ship ${shipData.id} - COG 0 - Using default orientation");
    } else {
      // Untuk COG lainnya, gunakan rumus rotasi yang sudah ada
      rotationAngle = -shipData.cog * (3.14159265359 / 180.0);
      print("Ship ${shipData.id} - COG ${shipData.cog} - Rotation angle: $rotationAngle rad");
    }
  return Marker(
    point: position,
    width: 40,
    height: 40,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _handleMarkerTap(shipData),
        child: Hero(
          tag: "ship_${shipData.id}",
          child: Transform.rotate(
            angle: rotationAngle,
            child: shipData.getIcon(),
          ),
        ),
      ),
    ),
  );
}
  Future<void> loadShipData() async {
    try {
      final List<dynamic> jsonData = await _jsonService.loadShipData();
      if (jsonData.isEmpty) {
        LogUtils.info("Ship data not available");
        return;
      }
  
      int validShips = 0;
      for (var shipJson in jsonData) {
        if (_processShipJson(shipJson)) validShips++;
      }
      
      LogUtils.info("Initialized $validShips ships");
    } catch (e) {
      LogUtils.error('Ship data loading failed', e);
    }
  }
  bool _processShipJson(dynamic shipJson) {
    if (shipJson is! Map<String, dynamic>) return false;
  
    final String? mmsi = shipJson['MMSI']?.toString();
    if (mmsi == null || mmsi == "0" || mmsi.isEmpty) return false;
  
    ships[mmsi] = ShipData(
      id: mmsi,
      latitude: 0.0,
      longitude: 0.0,
      speed: 0.0,
      engineStatus: 'Unknown',
      name: shipJson['NAME']?.toString(),
      type: shipJson['TYPENAME']?.toString(),
      navStatus: 'Unknown',
      trueHeading: 0.0,
      cog: 0.0,
      receivedOn: DateTime.now(),
    );
    return true;
  }
  bool isPointInPolygon(LatLng point, List<LatLng> polygon) {
    if (polygon.isEmpty) return false;

    int n = polygon.length;
    bool inside = false;

    for (int i = 0, j = n - 1; i < n; j = i++) {
      final double xi = polygon[i].latitude;
      final double yi = polygon[i].longitude;
      final double xj = polygon[j].latitude;
      final double yj = polygon[j].longitude;

      final bool intersect =
          ((yi > point.longitude) != (yj > point.longitude)) &&
              (point.latitude <
                  (xj - xi) * (point.longitude - yi) / (yj - yi) + xi);

      if (intersect) inside = !inside;
    }

    return inside;
  }
  void close() {
    _webSocketService.close();
  }
  void listenToShipDataStream(void Function(ShipData data) onData) {
    _webSocketService.shipDataStream.listen(onData);
  }
}