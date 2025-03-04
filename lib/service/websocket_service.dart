import 'dart:async';
import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../model/ship_model.dart';
import '../service/notification_service.dart';
import 'dart:convert';

// Debouncer class untuk menunda eksekusi fungsi
class Debouncer {
  final Duration delay;
  Timer? _timer;

  Debouncer(this.delay);

  void run(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  void dispose() {
    _timer?.cancel();
  }
}
class WebSocketService {
  static final WebSocketService _instance = WebSocketService._internal();
  
  factory WebSocketService(String url, String token, {Function(ShipData)? onMarkerTap}) {
    if (!_instance._isInitialized) {
      _instance._onMarkerTap = onMarkerTap;
      _instance._connect(url, token);
    }
    return _instance;
  }
  
  WebSocketService._internal();
  
  Function(ShipData)? _onMarkerTap;
  late final IO.Socket _socket;
  final StreamController<ShipData> _streamController = StreamController<ShipData>.broadcast();
  bool _isInitialized = false;
  int _reconnectAttempts = 0;
  final Debouncer _debouncer = Debouncer(const Duration(milliseconds: 200));
  
  void _connect(String url, String token) {
    _socket = IO.io(url, {
      'transports': ['websocket'],
      'autoConnect': false,
      'auth': {'token': token},
    });
  
    _socket.connect();
  
    _socket.onConnect((_) {
      print("WebSocket connected at ${DateTime.now()}");
      _reconnectAttempts = 0;
    });
  
    _socket.on('messageFromServer', (data) {
      _debouncer.run(() {
        try {
          // Handle both string and map data
          final Map<String, dynamic> jsonData = 
            data is String ? json.decode(data) : data as Map<String, dynamic>;
          
          // Extract ship data from the correct structure
          final message = jsonData['message'];
          final shipData = message?['data'];
          
          if (shipData != null && shipData['valid'] == true) {
            final parsedShip = ShipData(
              id: shipData['mmsi']?.toString() ?? '',
              latitude: double.tryParse(shipData['lat']?.toString() ?? '') ?? 0.0,
              longitude: double.tryParse(shipData['lon']?.toString() ?? '') ?? 0.0,
              speed: double.tryParse(shipData['sog']?.toString() ?? '') ?? 0.0,
              trueHeading: double.tryParse(shipData['hdg']?.toString() ?? '') ?? 0.0,
              cog: double.tryParse(shipData['cog']?.toString() ?? '') ?? 0.0,
              navStatus: shipData['navstatus']?.toString() ?? 'Unknown',
              engineStatus: 'Unknown',
              receivedOn: DateTime.now(),
            );
            
            if (_isValidShipData(parsedShip)) {
              _streamController.add(parsedShip);
            }
          }
        } catch (e) {
          print('WebSocket data processing error: $e');
        }
      });
    });
  
    _socket.onDisconnect((_) {
      print("WebSocket disconnected");
      _reconnect();
    });
  
    _socket.onConnectError((error) {
      print("WebSocket connection error: $error");
      _reconnect();
    });
  
    _socket.onError((error) {
      print("WebSocket error: $error");
      _reconnect();
    });
  
    _isInitialized = true;
  }
  
  void _reconnect() {
    if (_reconnectAttempts < 5) {
      _reconnectAttempts++;
      final delay = Duration(seconds: _reconnectAttempts * 2);
      print("Reconnecting in ${delay.inSeconds} seconds...");
      if (!_isDisposed) {  // Add this check
        Future.delayed(delay, () {
          if (!_isDisposed) {  // Add this check
            _socket.connect();
          }
        });
      }
    } else {
      print("Max reconnection attempts reached.");
      NotificationService().addDangerMessage("Gagal terhubung ke server. Silakan coba lagi nanti.");
    }
  }
  
  // Add proper disposal handling
  bool _isDisposed = false;
  
  void dispose() {
    _isDisposed = true;
    _socket.disconnect();
    _streamController.close();
    _debouncer.dispose();
  }
  bool _isValidShipData(ShipData ship) {
    return ship.id.isNotEmpty && 
           ship.latitude != 0.0 && 
           ship.longitude != 0.0 && 
           ship.latitude.abs() <= 90 && 
           ship.longitude.abs() <= 180;
  }
  Stream<ShipData> get shipDataStream => _streamController.stream;
  
  void updateToken(String newToken) {
    _socket.disconnect();
    _socket.io.options?['auth'] = {'token': newToken};
    _socket.connect();
    print("Updated WebSocket token to: $newToken");
  }
  
  void close() {
    _socket.disconnect();
    _streamController.close();
    _debouncer.dispose();
    print("WebSocket and StreamController closed.");
  }
  void handleMarkerTap(ShipData shipData) {
    if (_onMarkerTap != null) {
      _onMarkerTap!(shipData);
    }
  }
}