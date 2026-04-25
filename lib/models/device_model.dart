import 'package:flutter/foundation.dart';

enum BTType { classic, ble, dual, unknown }

/// Unified Bluetooth device model that bridges the gap between
/// Bluetooth Classic (Android-only) and BLE (Cross-platform).
@immutable
class BTDevice {
  final String name;

  /// Unique ID: MAC Address (Android) or UUID String (iOS/macOS).
  final String address;

  final BTType type;
  final int? rssi;
  final bool isPaired;
  final bool isBLE;

  const BTDevice({
    required this.name,
    required this.address,
    required this.type,
    this.rssi,
    this.isPaired = false,
    this.isBLE = false,
  });

  /// Shortens long iOS/macOS UUIDs or formats MAC addresses for cleaner UI.
  String get displayAddress {
    if (address.length > 17) {
      return '${address.substring(0, 8)}…${address.substring(address.length - 4)}';
    }
    return address.toUpperCase();
  }

  /// 🛠️ PERF: Single-pass signal evaluation
  /// Returns a record containing the label and bar count.
  ({String label, int bars}) get signalInfo {
    final val = rssi ?? -100;
    if (val >= -60) return (label: 'Strong', bars: 4);
    if (val >= -70) return (label: 'Good', bars: 3);
    if (val >= -80) return (label: 'Fair', bars: 2);
    if (val >= -90) return (label: 'Weak', bars: 1);
    return (label: 'Unknown', bars: 0);
  }

  /// Returns a new instance with updated fields.
  BTDevice copyWith({
    String? name,
    BTType? type,
    int? rssi,
    bool? isPaired,
  }) {
    return BTDevice(
      name: name ?? this.name,
      address: address, // Address is immutable as it is the Unique ID
      type: type ?? this.type,
      rssi: rssi ?? this.rssi,
      isPaired: isPaired ?? this.isPaired,
      isBLE: isBLE,
    );
  }

  /// 🛠️ PERF: Using address as the unique identifier for list diffing.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BTDevice &&
          runtimeType == other.runtimeType &&
          address == other.address &&
          rssi == other.rssi &&
          isPaired == other.isPaired;

  @override
  int get hashCode => address.hashCode ^ rssi.hashCode ^ isPaired.hashCode;

  @override
  String toString() => 'BTDevice($name, $address, $type, RSSI: $rssi)';
}
