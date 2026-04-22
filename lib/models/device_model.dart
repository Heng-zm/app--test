/// Unified BT device model — works for both Classic and BLE devices.
class BTDevice {
  final String name;
  final String address;   // MAC for Classic / UUID string for BLE on iOS/macOS
  final String type;      // 'Classic' | 'BLE' | 'Dual' | 'Unknown'
  final int? rssi;
  final bool isPaired;
  final bool isBLE;       // true = flutter_blue_plus device

  const BTDevice({
    required this.name,
    required this.address,
    required this.type,
    this.rssi,
    this.isPaired = false,
    this.isBLE = false,
  });

  String get displayAddress {
    // Shorten UUID-style addresses shown on iOS/macOS BLE
    if (address.length > 17) return '${address.substring(0, 8)}…';
    return address;
  }

  String get signalLabel {
    if (rssi == null) return '';
    if (rssi! >= -60) return 'Strong';
    if (rssi! >= -70) return 'Good';
    if (rssi! >= -80) return 'Fair';
    return 'Weak';
  }

  int get signalBars {
    if (rssi == null) return 0;
    if (rssi! >= -60) return 4;
    if (rssi! >= -70) return 3;
    if (rssi! >= -80) return 2;
    return 1;
  }

  BTDevice copyWith({int? rssi, bool? isPaired}) => BTDevice(
        name: name,
        address: address,
        type: type,
        rssi: rssi ?? this.rssi,
        isPaired: isPaired ?? this.isPaired,
        isBLE: isBLE,
      );

  @override
  bool operator ==(Object other) =>
      other is BTDevice && other.address == address;

  @override
  int get hashCode => address.hashCode;
}
