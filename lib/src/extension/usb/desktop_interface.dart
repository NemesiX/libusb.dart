import 'dart:ffi';
import 'dart:typed_data';
import 'dart:io';

import 'package:ffi/ffi.dart' as ffi;
import 'package:libusb/libusb.dart';
// import 'package:plugin_platform_interface/plugin_platform_interface.dart';
// import '../usb.dart';

import 'platform_interface.dart';

late Libusb _libusb;

class UsbLinux extends _UsbDesktop {
  static registerWith() {
    UsbPlatform.instance = UsbLinux();
    _libusb = Libusb(DynamicLibrary.open(
        '${Directory.current.path}/libusb-1.0/libusb-1.0.so'));
  }
}

class _UsbDesktop extends UsbPlatform {
  Pointer<libusb_device_handle>? _devHandle;

  @override
  Future<bool> init() async {
    return _libusb.libusb_init(nullptr) == libusb_error.LIBUSB_SUCCESS;
  }

  @override
  Future<void> exit() async {
    _libusb.libusb_exit(nullptr);
  }

  @override
  Future<List<UsbDevice>> getDeviceList() async {
    var deviceListPtr = ffi.calloc<Pointer<Pointer<libusb_device>>>();
    try {
      var count = _libusb.libusb_get_device_list(nullptr, deviceListPtr);
      if (count < 0) {
        return Future.value([]);
      }
      try {
        return Future.value(_iterateDevice(deviceListPtr.value).toList());
      } finally {
        _libusb.libusb_free_device_list(deviceListPtr.value, 1);
      }
    } finally {
      ffi.calloc.free(deviceListPtr);
    }
  }

  Iterable<UsbDevice> _iterateDevice(
      Pointer<Pointer<libusb_device>> deviceList) sync* {
    var descPtr = ffi.calloc<libusb_device_descriptor>();

    for (var i = 0; deviceList[i] != nullptr; i++) {
      var dev = deviceList[i];
      var addr = _libusb.libusb_get_device_address(dev);
      var getDesc = _libusb.libusb_get_device_descriptor(dev, descPtr) ==
          libusb_error.LIBUSB_SUCCESS;

      yield UsbDevice(
        identifier: addr.toString(),
        vendorId: getDesc ? descPtr.ref.idVendor : 0,
        productId: getDesc ? descPtr.ref.idProduct : 0,
        configurationCount: getDesc ? descPtr.ref.bNumConfigurations : 0,
      );
    }

    ffi.calloc.free(descPtr);
  }

  @override
  Future<List<UsbDeviceDescription>> getDevicesWithDescription(
      {bool requestPermission = true}) async {
    var devices = await getDeviceList();
    var result = <UsbDeviceDescription>[];
    for (var device in devices) {
      var desc = await getDeviceDescription(device);
      result.add(desc);
    }
    return result;
  }

  @override
  Future<UsbDeviceDescription> getDeviceDescription(UsbDevice usbdevice,
      {bool requestPermission = true}) async {
    String? manufacturer;
    String? product;
    String? serialNumber;

    var descPtr = ffi.calloc<libusb_device_descriptor>();
    try {
      var handle = _libusb.libusb_open_device_with_vid_pid(
          nullptr, usbdevice.vendorId, usbdevice.productId);
      if (handle != nullptr) {
        var device = _libusb.libusb_get_device(handle);
        if (device != nullptr) {
          var getDesc = _libusb.libusb_get_device_descriptor(device, descPtr) ==
              libusb_error.LIBUSB_SUCCESS;
          if (getDesc) {
            if (descPtr.ref.iManufacturer > 0) {
              manufacturer =
                  _getStringDescriptorASCII(handle, descPtr.ref.iManufacturer);
            }
            if (descPtr.ref.iProduct > 0) {
              product = _getStringDescriptorASCII(handle, descPtr.ref.iProduct);
            }
            if (descPtr.ref.iSerialNumber > 0) {
              serialNumber =
                  _getStringDescriptorASCII(handle, descPtr.ref.iSerialNumber);
            }
          }
        }
        _libusb.libusb_close(handle);
      }
    } finally {
      ffi.calloc.free(descPtr);
    }
    return UsbDeviceDescription(
      device: usbdevice,
      manufacturer: manufacturer,
      product: product,
      serialNumber: serialNumber,
    );
  }

  String? _getStringDescriptorASCII(
      Pointer<libusb_device_handle> handle, int descIndex) {
    String? result;
    Pointer<ffi.Utf8> string = ffi.calloc<Uint8>(256).cast();
    try {
      var ret = _libusb.libusb_get_string_descriptor_ascii(
          handle, descIndex, string.cast(), 256);
      if (ret > 0) {
        result = string.toDartString();
      }
    } finally {
      ffi.calloc.free(string);
    }
    return result;
  }

  @override
  Future<bool> hasPermission(UsbDevice usbDevice) async {
    return true;
  }

  @override
  Future<bool> requestPermission(UsbDevice usbDevice) async {
    return true;
  }

  @override
  Future<bool> openDevice(UsbDevice usbDevice) async {
    assert(_devHandle == null, 'Last device not closed');

    var handle = _libusb.libusb_open_device_with_vid_pid(
        nullptr, usbDevice.vendorId, usbDevice.productId);
    if (handle == nullptr) {
      return false;
    }
    _devHandle = handle;
    return true;
  }

  @override
  Future<void> closeDevice() async {
    if (_devHandle != null) {
      _libusb.libusb_close(_devHandle!);
      _devHandle = null;
    }
  }

  @override
  Future<UsbConfiguration> getConfiguration(int index) async {
    assert(_devHandle != null, 'Device not open');

    var configDescPtrPtr = ffi.calloc<Pointer<libusb_config_descriptor>>();
    try {
      var device = _libusb.libusb_get_device(_devHandle!);
      var getConfigDesc =
          _libusb.libusb_get_config_descriptor(device, index, configDescPtrPtr);
      if (getConfigDesc != libusb_error.LIBUSB_SUCCESS) {
        throw 'getConfigDesc error: ${_libusb.describeError(getConfigDesc)}';
      }

      var configDescPtr = configDescPtrPtr.value;
      var usbConfiguration = UsbConfiguration(
        id: configDescPtr.ref.bConfigurationValue,
        index: configDescPtr.ref.iConfiguration,
        interfaces: _iterateInterface(
                configDescPtr.ref.interface1, configDescPtr.ref.bNumInterfaces)
            .toList(),
      );
      _libusb.libusb_free_config_descriptor(configDescPtr);

      return usbConfiguration;
    } finally {
      ffi.calloc.free(configDescPtrPtr);
    }
  }

  Iterable<UsbInterface> _iterateInterface(
      Pointer<libusb_interface> interfacePtr, int interfaceCount) sync* {
    for (var i = 0; i < interfaceCount; i++) {
      var interface = interfacePtr[i];
      for (var j = 0; j < interface.num_altsetting; j++) {
        var intfDesc = interface.altsetting[j];
        yield UsbInterface(
          id: intfDesc.bInterfaceNumber,
          alternateSetting: intfDesc.bAlternateSetting,
          endpoints: _iterateEndpoint(intfDesc.endpoint, intfDesc.bNumEndpoints)
              .toList(),
        );
      }
    }
  }

  Iterable<UsbEndpoint> _iterateEndpoint(
      Pointer<libusb_endpoint_descriptor> endpointDescPtr,
      int endpointCount) sync* {
    for (var i = 0; i < endpointCount; i++) {
      var endpointDesc = endpointDescPtr[i];
      yield UsbEndpoint(
        endpointNumber: endpointDesc.bEndpointAddress & UsbEndpoint.MASK_NUMBER,
        direction: endpointDesc.bEndpointAddress & UsbEndpoint.MASK_DIRECTION,
      );
    }
  }

  @override
  Future<bool> setConfiguration(UsbConfiguration config) async {
    assert(_devHandle != null, 'Device not open');

    var setConfig = _libusb.libusb_set_configuration(_devHandle!, config.id);
    if (setConfig != libusb_error.LIBUSB_SUCCESS) {
      // debugPrint('setConfig error: ${_libusb.describeError(setConfig)}');
      print('setConfig error: ${_libusb.describeError(setConfig)}');
      return false;
    }
    return true;
  }

  @override
  Future<bool> detachKernelDriver(UsbInterface intf) async {
    assert(_devHandle != null, 'Device not open');

    var result = _libusb.libusb_detach_kernel_driver(_devHandle!, intf.id);
    return result == libusb_error.LIBUSB_SUCCESS;
  }

  @override
  Future<bool> claimInterface(UsbInterface intf) async {
    assert(_devHandle != null, 'Device not open');

    var result = _libusb.libusb_claim_interface(_devHandle!, intf.id);
    print(_libusb.describeError(result));
    return result == libusb_error.LIBUSB_SUCCESS;
  }

  @override
  Future<bool> releaseInterface(UsbInterface intf) async {
    assert(_devHandle != null, 'Device not open');

    var result = _libusb.libusb_release_interface(_devHandle!, intf.id);
    return result == libusb_error.LIBUSB_SUCCESS;
  }

  @override
  Future<Uint8List> bulkTransferIn(
      UsbEndpoint endpoint, int maxLength, int timeout) async {
    assert(_devHandle != null, 'Device not open');
    assert(endpoint.direction == UsbEndpoint.DIRECTION_IN,
        'Endpoint\'s direction should be in');

    Pointer<Int> acctualLengthPtr = ffi.calloc<Int>();
    Pointer<UnsignedChar> dataPtr = ffi.calloc<UnsignedChar>(maxLength);

    try {
      var result = _libusb.libusb_bulk_transfer(
        _devHandle!,
        endpoint.endpointAddress,
        dataPtr,
        maxLength,
        acctualLengthPtr,
        timeout,
      );

      if (result != libusb_error.LIBUSB_SUCCESS) {
        throw 'bulkTransferIn error: ${_libusb.describeError(result)}';
      }
      Uint8List test = Uint8List(0);
      for (var i = 0; i < maxLength; i++) {
        print(dataPtr[i]);
      }
      // return Uint8List.fromList(dataPtr.asTypedList(acctualLengthPtr.value));
      return test;
    } finally {
      ffi.calloc.free(acctualLengthPtr);
      ffi.calloc.free(dataPtr);
    }
  }

  @override
  Future<int> bulkTransferOut(
      UsbEndpoint endpoint, Uint8List data, int timemout) async {
    assert(_devHandle != null, 'Device not open');
    assert(endpoint.direction == UsbEndpoint.DIRECTION_OUT,
        'Endpoint\'s direction should be out');

    Pointer<Int> actualLengthPtr = ffi.calloc<Int>();
    // Pointer<Uint8> dataPtr = ffi.calloc<Uint8>(data.length);
    // dataPtr.asTypedList(data.length).setAll(0, data);
    Pointer<UnsignedChar> dataPtr = ffi.calloc<UnsignedChar>(data.length);
    for (var i = 0; i < data.length; i++) {
      dataPtr[i] = data[i];
    }

    try {
      var result = _libusb.libusb_bulk_transfer(
        _devHandle!,
        endpoint.endpointAddress,
        dataPtr,
        data.length,
        actualLengthPtr,
        timemout,
      );

      if (result != libusb_error.LIBUSB_SUCCESS) {
        // debugPrint('bulkTransferOut error: ${_libusb.describeError(result)}');
        print('bulkTransferOut error: ${_libusb.describeError(result)}');
        return result;
      }
      return actualLengthPtr.value;
    } finally {
      ffi.calloc.free(actualLengthPtr);
      ffi.calloc.free(dataPtr);
    }
  }

  @override
  Future<void> setAutoDetachKernelDriver(bool enable) async {
    assert(_devHandle != null, 'Device not open');
    if (Platform.isLinux) {
      _libusb.libusb_set_auto_detach_kernel_driver(_devHandle!, enable ? 1 : 0);
    }
  }
}
