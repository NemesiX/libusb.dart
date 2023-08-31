import 'dart:typed_data';

import 'package:libusb/src/extension/usb/platform_interface.dart';

import 'usb/data/configuration.dart';
import 'usb/data/descriptor.dart';
import 'usb/data/device.dart';
import 'usb/data/endpoint.dart';
import 'usb/data/interface.dart';

export 'usb/data/configuration.dart';
export 'usb/data/descriptor.dart';
export 'usb/data/device.dart';
export 'usb/data/endpoint.dart';
export 'usb/data/interface.dart';
export 'usb/utils.dart';
export 'usb/platform_interface.dart';

UsbPlatform get _platform => UsbPlatform.instance;

class Usb {
  static Future<bool> init() => _platform.init();

  static Future<void> exit() => _platform.exit();

  static Future<List<UsbDevice>> getDeviceList() => _platform.getDeviceList();

  /// [requestPermission] If true, Android will ask permission for each USB
  /// device if required. Only required to retrieve the serial number.
  static Future<List<UsbDeviceDescription>> getDevicesWithDescription({
    bool requestPermission = true,
  }) =>
      _platform.getDevicesWithDescription(requestPermission: requestPermission);

  /// [requestPermission] If true, Android will ask permission for the USB device
  /// if required. Only required to retrieve the serial number.
  static Future<UsbDeviceDescription> getDeviceDescription(
    UsbDevice usbDevice, {
    bool requestPermission = true,
  }) =>
      _platform.getDeviceDescription(
        usbDevice,
        requestPermission: requestPermission,
      );

  static Future<bool> hasPermission(UsbDevice usbDevice) =>
      _platform.hasPermission(usbDevice);

  static Future<bool> requestPermission(UsbDevice usbDevice) =>
      _platform.requestPermission(usbDevice);

  static Future<bool> openDevice(UsbDevice usbDevice) =>
      _platform.openDevice(usbDevice);

  static Future<void> closeDevice() => _platform.closeDevice();

  static Future<UsbConfiguration> getConfiguration(int index) =>
      _platform.getConfiguration(index);

  static Future<bool> setConfiguration(UsbConfiguration config) =>
      _platform.setConfiguration(config);

  static Future<bool> detachKernelDriver(UsbInterface intf) =>
      _platform.detachKernelDriver(intf);

  static Future<bool> claimInterface(UsbInterface intf) =>
      _platform.claimInterface(intf);

  static Future<bool> releaseInterface(UsbInterface intf) =>
      _platform.releaseInterface(intf);

  static Future<Uint8List> bulkTransferIn(UsbEndpoint endpoint, int maxLength,
          {int timeout = 1000}) =>
      _platform.bulkTransferIn(endpoint, maxLength, timeout);

  static Future<int> bulkTransferOut(UsbEndpoint endpoint, Uint8List data,
          {int timeout = 1000}) =>
      _platform.bulkTransferOut(endpoint, data, timeout);

  static Future<void> setAutoDetachKernelDriver(bool enable) =>
      _platform.setAutoDetachKernelDriver(enable);
}
