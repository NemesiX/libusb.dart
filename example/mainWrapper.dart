import 'dart:io';
import 'dart:typed_data';

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

  if (!await Usb.detachKernelDriver(config.interfaces[0])) {
    print("Failed to detach kernel driver!");
    exit(250);
  } else {
    print("Kernel driver detached!");
  }

  if (!await Usb.claimInterface(config.interfaces[0])) {
    print("Failed to claim interface!");
    exit(250);
  } else {
    print("Interface claimed!");
  }

  var inn = config.interfaces[0].endpoints[0];
  var out = config.interfaces[0].endpoints[1];

  List<int> pkt = List<int>.filled(64, 0x00);
  pkt[0] = 0x02;
  pkt[1] = 0x00;
  pkt[2] = 0x01;
  pkt[3] = 0xFE;
  // pkt[3] = 0x01;
  pkt[4] = 0xFF;

  var pkt1 = Uint8List.fromList(pkt);
  await Usb.bulkTransferOut(
    inn,
    pkt1,
  );

  await Usb.bulkTransferOut(
    inn,
    Uint8List.fromList(List<int>.filled(64, 0x00)),
  );

  var result = await Usb.bulkTransferIn(out, 128);
  print(result);

  try {
    await Usb.releaseInterface(config.interfaces[0]);

    await Usb.closeDevice();
  } catch (e) {
    print("Failed to close device!");
    exit(250);
  } finally {
    print("Device closed!");
  }
}
