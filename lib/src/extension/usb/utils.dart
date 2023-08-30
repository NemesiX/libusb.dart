// import 'dart:convert';
import 'dart:ffi';

import 'package:libusb/libusb.dart';

// import 'package:ffi/ffi.dart' as ffi;

// const int _kMaxSmi64 = (1 << 62) - 1;
// const int _kMaxSmi32 = (1 << 30) - 1;
// final int _maxSize = sizeOf<IntPtr>() == 8 ? _kMaxSmi64 : _kMaxSmi32;

extension LibusbExtension on Libusb {
  String describeError(int error) {
    String msg = "";

    Pointer<Char> array = libusb_error_name(error);

    final List<int> units = [];
    var len = 0;
    while (true) {
      final char = array.elementAt(len++).value;
      if (char == 0) break;
      units.add(char);
    }

    msg = String.fromCharCodes(units);

    array = libusb_strerror(error);
    final List<int> units2 = [];
    len = 0;
    while (true) {
      final char = array.elementAt(len++).value;
      if (char == 0) return msg + ": " + String.fromCharCodes(units2);
      units2.add(char);
    }
  }
}
