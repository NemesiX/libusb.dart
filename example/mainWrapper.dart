import 'dart:io';

import 'package:libusb/src/extension/usb.dart';
import 'package:libusb/src/extension/usb/desktop_interface.dart';

void main() async {
  String productName = "CLS-ADV";

  if (Platform.isLinux) {
    UsbLinux.registerWith();
  } else {
    print("Unsupported platform!");
    exit(255);
  }

  if (!await Usb.init()) {
    print("Failed to initialize libusb!");
    exit(254);
  }

  // var deviceList = await Usb.getDeviceList();
  var deviceList = await Usb.getDevicesWithDescription();

  UsbDevice device;
  try {
    device = deviceList
        .firstWhere((element) => element.product == productName)
        .device;
  } catch (StateError) {
    print("Device not found!");
    exit(253);
  }

  if (!await Usb.hasPermission(device)) {
    if (!await Usb.requestPermission(device)) {
      print("Permission denied!");
      exit(252);
    }
  }

  if (!await Usb.openDevice(device)) {
    print("Failed to open device!");
    exit(251);
  } else {
    print("Device opened!");
  }

  var config = await Usb.getConfiguration(0);
  print("Configuration: $config");

  try {
    await Usb.closeDevice();
  } catch (e) {
    print("Failed to close device!");
    exit(250);
  } finally {
    print("Device closed!");
  }
}
