import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';


class ShipData {
  String id;
  double latitude;
  double longitude;
  double speed;
  String? engineStatus; // Nullable
  String? name; // Nullable
  String? type; // Nullable
  String? navStatus; // Nullable
  double trueHeading;
  double cog;
  DateTime receivedOn;
  
  ShipData({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.speed,
    this.engineStatus, // Nullable
    this.name, // Nullable
    this.type, // Nullable
    this.navStatus, // Nullable
    required this.trueHeading,
    required this.cog,
    required this.receivedOn,
  });
  
  // Fungsi untuk mendapatkan ikon SVG berdasarkan tipe kapal
  Widget getIcon() {
    // Normalisasi tipe kapal dengan menghapus spasi dan mengubah ke lowercase
    final String normalizedType = type?.toLowerCase().replaceAll(' ', '') ?? '';
    print('Ship type before normalization: $type'); // Debug log
    print('Ship type after normalization: $normalizedType'); // Debug log
    
    if (normalizedType.contains('cargo') || normalizedType.contains('general')) {
      return SvgPicture.asset('assets/icons/cargo.svg', width: 20, height: 20);
    } else if (normalizedType.contains('cruise') || 
              normalizedType.contains('passenger') || 
              normalizedType.contains('ferry')) {
      return SvgPicture.asset('assets/icons/cruise.svg', width: 20, height: 20);
    } else if (normalizedType.contains('special') || 
              normalizedType.contains('other') ||
              normalizedType.contains('misc')) {
      return SvgPicture.asset('assets/icons/special.svg', width: 20, height: 20);
    } else if (normalizedType.contains('support') || 
              normalizedType.contains('service') ||
              normalizedType.contains('supply')) {
      return SvgPicture.asset('assets/icons/support.svg', width: 20, height: 20);
    } else if (normalizedType.contains('tanker') || 
              normalizedType.contains('oil') ||
              normalizedType.contains('gas')) {
      return SvgPicture.asset('assets/icons/tanker.svg', width: 20, height: 20);
    }
    
    print('Using unknown icon for type: $normalizedType'); // Debug log
    return SvgPicture.asset('assets/icons/unknown.svg', width: 20, height: 20);
  }
  
  Map<String, dynamic> toJson() {
    return {
      'mmsi': id,
      'lat': latitude,
      'lon': longitude,
      'sog': speed,
      'smi': engineStatus,
      'NAME': name,
      'TYPENAME': type,
      'navstatus': navStatus,
      'hdg': trueHeading,
      'cog': cog,
      'timestamp': receivedOn.toIso8601String(),
    };
  }
  
factory ShipData.fromJson(Map<String, dynamic> json) {
    try {
      // Extract nested data from WebSocket message
      final message = json['message'] as Map<String, dynamic>?;
      final data = message?['data'] as Map<String, dynamic>?;
      
      if (data == null || data['valid'] != true) {
        throw Exception('Invalid data structure or data not valid');
      }

      return ShipData(
        id: data['mmsi']?.toString() ?? '',
        latitude: data['lat']?.toDouble() ?? 0.0,
        longitude: data['lon']?.toDouble() ?? 0.0,
        speed: data['sog']?.toDouble() ?? 0.0,
        engineStatus: data['smi'] == 0 ? 'ON' : 'OFF',
        name: data['NAME']?.toString(),
        type: data['TYPENAME']?.toString(),
        navStatus: _getNavStatus(data['navstatus']),
        trueHeading: data['hdg']?.toDouble() ?? 0.0,
        cog: data['cog']?.toDouble() ?? 0.0,
        receivedOn: DateTime.tryParse(json['timestamp']?.toString() ?? '') ?? DateTime.now(),
      );
    } catch (e) {
      print('Error parsing ship data: $e');
      rethrow;
    }
  }
  
  void updateFromJson(Map<String, dynamic> json) {
    try {
      final message = json['message'] as Map<String, dynamic>?;
      final data = message?['data'] as Map<String, dynamic>?;
      
      if (data == null || data['valid'] != true) return;

      latitude = data['lat']?.toDouble() ?? latitude;
      longitude = data['lon']?.toDouble() ?? longitude;
      speed = data['sog']?.toDouble() ?? speed;
      engineStatus = data['smi'] == 0 ? 'ON' : 'OFF';
      navStatus = _getNavStatus(data['navstatus']);
      trueHeading = data['hdg']?.toDouble() ?? trueHeading;
      cog = data['cog']?.toDouble() ?? cog;
    } catch (e) {
      print('Error updating ship data: $e');
    }
  }
  
  static String _getNavStatus(dynamic status) {
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
}