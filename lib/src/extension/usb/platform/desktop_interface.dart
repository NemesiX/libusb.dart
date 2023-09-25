import 'dart:ffi';
// import 'dart:math';
import 'dart:typed_data';
import 'dart:io';

import 'package:ffi/ffi.dart' as ffi;
import 'package:libusb/libusb.dart';
// import 'package:plugin_platform_interface/plugin_platform_interface.dart';
// import '../usb.dart';

// import '../platform_interface.dart';

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

  /// Initializes the LibUSB library.
  ///
  /// This method initializes the LibUSB library, preparing it for device
  /// communication. It must be called before any other LibUSB functions.
  ///
  /// Returns `true` if initialization succeeds, otherwise `false`.
  ///
  /// Throws a LibUSB exception if initialization fails.
  @override
  Future<bool> init() async {
    return _libusb.libusb_init(nullptr) == libusb_error.LIBUSB_SUCCESS;
  }

  /// Exits and releases resources used by the LibUSB library.
  ///
  /// This method should be called to gracefully exit and release resources
  /// used by the LibUSB library. It should be called when you're done using
  /// LibUSB, typically when your application is shutting down.
  ///
  /// Throws a LibUSB exception if there is an error during the exit process.
  @override
  Future<void> exit() async {
    _libusb.libusb_exit(nullptr);
  }

  /// Retrieves a list of available USB devices.
  ///
  /// This method retrieves a list of available USB devices using the LibUSB
  /// library. It returns a [Future] containing a list of [UsbDevice] objects
  /// representing the detected USB devices.
  ///
  /// Returns an empty list if no USB devices are detected.
  ///
  /// Throws a LibUSB exception if there is an error during device detection or
  /// memory allocation.
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

  /// Iterates through a list of LibUSB devices and yields corresponding [UsbDevice] objects.
  ///
  /// This function takes a pointer to a list of LibUSB devices and iterates through
  /// the list, yielding [UsbDevice] objects representing each device. It extracts
  /// information such as the device's identifier, vendor ID, product ID, and configuration
  /// count from the device descriptors.
  ///
  /// - [deviceList]: A pointer to a list of LibUSB devices.
  ///
  /// Yields [UsbDevice] objects for each detected device.
  ///
  /// Throws a LibUSB exception if there is an error while retrieving device information
  /// or memory allocation.
  ///
  /// Note: This function is used internally and is not intended to be called directly.
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

  /// Retrieves a list of USB devices along with their descriptions.
  ///
  /// This method retrieves a list of USB devices detected by the LibUSB library
  /// and, for each device, fetches its description using the [getDeviceDescription]
  /// method. It returns a [Future] containing a list of [UsbDeviceDescription] objects,
  /// which provide detailed information about each USB device.
  ///
  /// By default, this method requests permission to access each device, but you can
  /// disable this behavior by setting [requestPermission] to `false`.
  ///
  /// - [requestPermission]: Whether to request permission to access each device.
  ///   Defaults to `true`.
  ///
  /// Returns a list of [UsbDeviceDescription] objects representing the detected USB devices
  /// along with their descriptions.
  ///
  /// Throws a LibUSB exception if there is an error during device detection or description
  /// retrieval.
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

  /// Retrieves the description of a USB device.
  ///
  /// This method retrieves detailed information about a USB device, including its
  /// manufacturer, product name, and serial number (if available). It uses the provided
  /// [UsbDevice] object to identify and describe the target device.
  ///
  /// By default, this method requests permission to access the device, but you can
  /// disable this behavior by setting [requestPermission] to `false`.
  ///
  /// - [usbdevice]: The [UsbDevice] for which to retrieve the description.
  /// - [requestPermission]: Whether to request permission to access the device.
  ///   Defaults to `true`.
  ///
  /// Returns a [Future] containing a [UsbDeviceDescription] object that provides
  /// detailed information about the USB device.
  ///
  /// Throws a LibUSB exception if there is an error during device description retrieval
  /// or if the device cannot be accessed.
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
    } catch (e) {
      rethrow;
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

  /// Retrieves a UTF-8 encoded ASCII string descriptor from a USB device.
  ///
  /// This method retrieves a UTF-8 encoded ASCII string descriptor from a USB device
  /// associated with the provided device handle and descriptor index. It is typically
  /// used to obtain information such as manufacturer names, product names, or serial
  /// numbers from USB devices.
  ///
  /// - [handle]: The LibUSB device handle for the target USB device.
  /// - [descIndex]: The index of the descriptor to retrieve.
  ///
  /// Returns the UTF-8 encoded ASCII string descriptor if it is successfully retrieved,
  /// or `null` if an error occurs or the descriptor is not available.
  ///
  /// Throws any exception that occurs during the retrieval process.
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
    } catch (e) {
      rethrow;
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

  /// Opens a USB device for communication.
  ///
  /// This method attempts to open the specified USB device for communication. If
  /// successful, it sets the device handle for subsequent communication. It is
  /// important to note that only one device can be opened at a time. Attempting
  /// to open a device while another device is already open will result in an
  /// assertion error.
  ///
  /// - [usbDevice]: The [UsbDevice] to open for communication.
  ///
  /// Returns `true` if the device is successfully opened, otherwise `false`.
  ///
  /// Throws an assertion error if there is an attempt to open another device
  /// while a device is already open.
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

  /// Closes the currently open USB device.
  ///
  /// This method closes the USB device that is currently open for communication.
  /// If there is no open device, the method has no effect. It is important to
  /// close a device when communication is no longer needed to release system
  /// resources and allow other devices to be accessed.
  ///
  /// Note: Calling this method when no device is open has no effect.
  @override
  Future<void> closeDevice() async {
    if (_devHandle != null) {
      _libusb.libusb_close(_devHandle!);
      _devHandle = null;
    }
  }

  /// Retrieves the USB configuration with the specified index.
  ///
  /// This method retrieves the USB configuration information for the currently open
  /// device based on the provided configuration index. It returns a [UsbConfiguration]
  /// object containing details about the configuration, including its ID, index, and
  /// a list of associated interfaces.
  ///
  /// - [index]: The index of the USB configuration to retrieve.
  ///
  /// Throws an assertion error if no USB device is currently open.
  /// Throws an error if there is a problem retrieving the configuration information.
  ///
  /// Returns a [Future] containing the [UsbConfiguration] object.
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
    } catch (e) {
      rethrow;
    } finally {
      ffi.calloc.free(configDescPtrPtr);
    }
  }

  /// Iterates through USB interfaces and yields corresponding [UsbInterface] objects.
  ///
  /// This function takes a pointer to an array of LibUSB interfaces and the number
  /// of interfaces, and iterates through the interfaces and their alternate settings.
  /// For each interface, it yields a [UsbInterface] object representing the interface
  /// and its associated endpoints.
  ///
  /// - [interfacePtr]: A pointer to an array of LibUSB interfaces.
  /// - [interfaceCount]: The number of interfaces to iterate.
  ///
  /// Yields [UsbInterface] objects for each detected USB interface.
  ///
  /// Note: This function is used internally and is not intended to be called directly.
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

  /// Iterates through USB endpoints and yields corresponding [UsbEndpoint] objects.
  ///
  /// This function takes a pointer to an array of LibUSB endpoint descriptors and
  /// the number of endpoints, and iterates through the endpoints. For each endpoint,
  /// it yields a [UsbEndpoint] object representing the endpoint number and direction.
  ///
  /// - [endpointDescPtr]: A pointer to an array of LibUSB endpoint descriptors.
  /// - [endpointCount]: The number of endpoints to iterate.
  ///
  /// Yields [UsbEndpoint] objects for each detected USB endpoint.
  ///
  /// Note: This function is used internally and is not intended to be called directly.
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

  /// Sets the USB configuration for the currently open device.
  ///
  /// This method sets the USB configuration for the currently open device based
  /// on the provided [UsbConfiguration] object. It associates the device with the
  /// specified configuration, allowing communication with the device based on the
  /// selected configuration.
  ///
  /// - [config]: The [UsbConfiguration] object representing the desired configuration.
  ///
  /// Throws an assertion error if no USB device is currently open.
  ///
  /// Returns `true` if the configuration is successfully set, otherwise `false`.
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

  /// Detaches the kernel driver from a USB interface.
  ///
  /// This method detaches the kernel driver from a USB interface associated with
  /// the currently open USB device. This operation is necessary when you want to
  /// take control of the interface and communicate directly with it.
  ///
  /// - [intf]: The [UsbInterface] for which to detach the kernel driver.
  ///
  /// Throws an assertion error if no USB device is currently open.
  ///
  /// Returns `true` if the kernel driver is successfully detached, otherwise `false`.
  @override
  Future<bool> detachKernelDriver(UsbInterface intf) async {
    assert(_devHandle != null, 'Device not open');

    var result = _libusb.libusb_detach_kernel_driver(_devHandle!, intf.id);
    return result == libusb_error.LIBUSB_SUCCESS;
  }

  /// Claims control of a USB interface for communication.
  ///
  /// This method claims control of a USB interface associated with the currently
  /// open USB device. Claiming an interface is necessary before you can perform
  /// communication operations on it. If successful, it allows your application
  /// to use the interface for data transfer.
  ///
  /// - [intf]: The [UsbInterface] to claim control of.
  ///
  /// Throws an assertion error if no USB device is currently open.
  ///
  /// Returns `true` if the interface is successfully claimed, otherwise `false`.
  @override
  Future<bool> claimInterface(UsbInterface intf) async {
    assert(_devHandle != null, 'Device not open');

    var result = _libusb.libusb_claim_interface(_devHandle!, intf.id);
    print(_libusb.describeError(result));
    return result == libusb_error.LIBUSB_SUCCESS;
  }

  /// Releases control of a USB interface.
  ///
  /// This method releases control of a USB interface previously claimed by your
  /// application for communication. Releasing the interface allows other applications
  /// to potentially claim and use it.
  ///
  /// - [intf]: The [UsbInterface] to release control of.
  ///
  /// Throws an assertion error if no USB device is currently open.
  ///
  /// Returns `true` if the interface is successfully released, otherwise `false`.
  @override
  Future<bool> releaseInterface(UsbInterface intf) async {
    assert(_devHandle != null, 'Device not open');

    var result = _libusb.libusb_release_interface(_devHandle!, intf.id);
    return result == libusb_error.LIBUSB_SUCCESS;
  }

  /// Performs a USB bulk IN transfer to receive data from a USB endpoint.
  ///
  /// This method performs a USB bulk IN transfer to receive data from a USB
  /// endpoint associated with the currently open USB device. It allows you to
  /// retrieve data from the device up to the specified [maxLength] and within
  /// the given [timeout] duration.
  ///
  /// - [endpoint]: The [UsbEndpoint] representing the USB endpoint for the transfer.
  /// - [maxLength]: The maximum number of bytes to receive.
  /// - [timeout]: The maximum time in milliseconds to wait for the transfer to complete.
  ///
  /// Throws an assertion error if no USB device is currently open or if the endpoint's
  /// direction is not "in."
  /// Throws an error if there is a problem with the bulk transfer operation.
  ///
  /// Returns a [Uint8List] containing the received data.
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
      Uint8List test = Uint8List(maxLength);
      for (var i = 0; i < maxLength; i++) {
        test[i] = dataPtr[i];
      }
      // return Uint8List.fromList(dataPtr.asTypedList(acctualLengthPtr.value));
      return test;
    } catch (e) {
      rethrow;
    } finally {
      ffi.calloc.free(acctualLengthPtr);
      ffi.calloc.free(dataPtr);
    }
  }

  /// Performs a USB bulk OUT transfer to send data to a USB endpoint.
  ///
  /// This method performs a USB bulk OUT transfer to send data to a USB endpoint
  /// associated with the currently open USB device. It allows you to send the
  /// provided [data] to the device and specifies a [timeout] duration for the
  /// transfer to complete.
  ///
  /// - [endpoint]: The [UsbEndpoint] representing the USB endpoint for the transfer.
  /// - [data]: The [Uint8List] containing the data to be sent.
  /// - [timeout]: The maximum time in milliseconds to wait for the transfer to complete.
  ///
  /// Throws an assertion error if no USB device is currently open or if the endpoint's
  /// direction is not "out."
  /// Throws an error if there is a problem with the bulk transfer operation.
  ///
  /// Returns the number of bytes actually transferred (may be less than the length
  /// of the data if the transfer is incomplete or an error occurs).
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
    } catch (e) {
      rethrow;
    } finally {
      ffi.calloc.free(actualLengthPtr);
      ffi.calloc.free(dataPtr);
    }
  }

  /// Sets the auto-detach behavior of the kernel driver on Linux.
  ///
  /// This method allows you to control whether the kernel driver should be
  /// automatically detached from a USB device when it is opened for communication
  /// in a Linux environment. Enabling auto-detach can be useful to ensure that
  /// the application has full control over the device.
  ///
  /// - [enable]: A boolean value indicating whether to enable (true) or disable (false)
  ///   the auto-detach behavior.
  ///
  /// Throws an assertion error if no USB device is currently open.
  ///
  /// Note: This method is applicable only on Linux platforms. On other platforms,
  /// it has no effect.
  @override
  Future<void> setAutoDetachKernelDriver(bool enable) async {
    assert(_devHandle != null, 'Device not open');
    if (Platform.isLinux) {
      _libusb.libusb_set_auto_detach_kernel_driver(_devHandle!, enable ? 1 : 0);
    }
  }
}
