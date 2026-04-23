/// Unified Bluetooth device model that bridges the gap between
/// Bluetooth Classic (Android-only) and BLE (Cross-platform).
class BTDevice {
  final String name;

  /// MAC Address for Classic / UUID string for BLE on iOS/macOS.
  final String address;

  /// 'Classic' | 'BLE' | 'Dual' | 'Unknown'
  final String type;
  final int? rssi;
  final bool isPaired;

  /// Flag to identify if the device was found via flutter_blue_plus.
  final bool isBLE;

  const BTDevice({
    required this.name,
    required this.address,
    required this.type,
    this.rssi,
    this.isPaired = false,
    this.isBLE = false,
  });

  /// Shortens long iOS/macOS UUIDs for cleaner UI presentation.
  String get displayAddress {
    if (address.length > 17) {
      return '${address.substring(0, 8)}…';
    }
    return address;
  }

  /// Returns a human-readable text description of signal quality.
  String get signalLabel {
    if (rssi == null) {
      return 'Unknown';
    }
    if (rssi! >= -60) {
      return 'Strong';
    }
    if (rssi! >= -70) {
      return 'Good';
    }
    if (rssi! >= -80) {
      return 'Fair';
    }
    return 'Weak';
  }

  /// Calculates the number of bars (1-4) for the signal indicator widget.
  int get signalBars {
    if (rssi == null) {
      return 0;
    }
    if (rssi! >= -60) {
      return 4;
    }
    if (rssi! >= -70) {
      return 3;
    }
    if (rssi! >= -80) {
      return 2;
    }
    return 1;
  }

  /// Returns a new instance with updated volatile fields (like RSSI).
  BTDevice copyWith({
    int? rssi,
    bool? isPaired,
  }) {
    return BTDevice(
      name: name,
      address: address,
      type: type,
      rssi: rssi ?? this.rssi,
      isPaired: isPaired ?? this.isPaired,
      isBLE: isBLE,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is BTDevice && other.address == address;
  }

  @override
  int get hashCode => address.hashCode;
}
