import 'package:libusb/libusb.dart';

void main() {
  var libusb = Libusb(LibsusbAPI.loadLibrary());
  libusb.init();
  libusb.exit();
}
