import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart' show calloc;
import 'package:libusb/libusb.dart';

abstract class USB {
  USB(
    this.device,
    this.descPtr,
    this.devHandlePtr,
    this.strDescPtr,
    this.strDescLength,
  );

  Pointer<libusb_device> device;
  Pointer<libusb_device_descriptor> descPtr;
  Pointer<Pointer<libusb_device_handle>> devHandlePtr;
  Pointer<UnsignedChar> strDescPtr;
  int strDescLength;
}

class USB3 extends USB {
  USB3(super.device, super.descPtr, super.devHandlePtr, super.strDescPtr,
      super.strDescLength);
}

class HID extends USB {
  HID(super.device, super.descPtr, super.devHandlePtr, super.strDescPtr,
      super.strDescLength);
}

extension LibsusbAPI on Libusb {
  static int _kMaxSmi64 = (1 << 62) - 1;
  static int _kMaxSmi32 = (1 << 30) - 1;
  static int _maxSize = sizeOf<IntPtr>() == 8 ? _kMaxSmi64 : _kMaxSmi32;

  static DynamicLibrary Function() loadLibrary = () {
    if (Platform.isWindows) {
      return DynamicLibrary.open(
          '${Directory.current.path}/libusb-1.0/libusb-1.0.dll');
    }
    if (Platform.isMacOS) {
      return DynamicLibrary.open(
          '${Directory.current.path}/libusb-1.0/libusb-1.0.dylib');
    } else if (Platform.isLinux) {
      return DynamicLibrary.open(
          '${Directory.current.path}/libusb-1.0/libusb-1.0.so');
    }
    throw 'libusb dynamic library not found';
  };

  String getError(int err) {
    var array = libusb_error_name(err);
    // FIXME array is Pointer<Char>, not Pointer<Uint8>
    var nativeString = array.cast<Uint8>().asTypedList(_maxSize);
    var strlen = nativeString.indexWhere((char) => char == 0);
    return utf8.decode(array.cast<Uint8>().asTypedList(strlen));
  }

  void init([Pointer<Pointer<libusb_context>>? ctx]) {
    var result = libusb_init(ctx ?? nullptr);

    if (result != libusb_error.LIBUSB_SUCCESS) {
      throw StateError(getError(result));
    }

    var cap =
        libusb_has_capability(libusb_capability.LIBUSB_CAP_HAS_CAPABILITY);
    if (cap == 0) {
      throw StateError('LIBUSB_CAP_NO_CAPABILITY');
    }

    cap = libusb_has_capability(libusb_capability.LIBUSB_CAP_HAS_HOTPLUG);
    if (cap == 0) {
      throw StateError('LIBUSB_CAP_NO_HOTPLUG');
    }

    cap = libusb_has_capability(libusb_capability.LIBUSB_CAP_HAS_HID_ACCESS);
    if (cap == 0) {
      throw StateError('LIBUSB_CAP_NO_HID_ACCESS');
    }

    cap = libusb_has_capability(
        libusb_capability.LIBUSB_CAP_SUPPORTS_DETACH_KERNEL_DRIVER);
    if (cap == 0) {
      throw StateError('LIBUSB_CAP_NO_DETACH_KERNEL_DRIVER');
    }
  }

  void exit([Pointer<libusb_context>? ctx]) {
    calloc.free(ctx ?? nullptr);
    libusb_exit(ctx ?? nullptr);
  }

  void open(USB usb) {
    var result = libusb_open(usb.device, usb.devHandlePtr);
  }
}
