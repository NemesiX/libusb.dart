class UsbEndpoint {
  // Bits 0:3 are the endpoint number
  static const int MASK_NUMBER = 0x07;

  // Bits 4:6 are reserved

  // Bit 7 indicates direction
  static const int MASK_DIRECTION = 0x80;

  static const int DIRECTION_OUT = 0x00;
  static const int DIRECTION_IN = 0x80;

  final int endpointNumber;
  final int direction;

  UsbEndpoint({
    required this.endpointNumber,
    required this.direction,
  });

  factory UsbEndpoint.fromMap(Map<dynamic, dynamic> map) {
    return UsbEndpoint(
      endpointNumber: map['endpointNumber'],
      direction: map['direction'],
    );
  }

  int get endpointAddress => endpointNumber | direction;

  Map<String, dynamic> toMap() {
    return {
      'endpointNumber': endpointNumber,
      'direction': direction,
    };
  }

  @override
  String toString() => toMap().toString();
}
