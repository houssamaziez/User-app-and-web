import 'package:stackfood_multivendor/features/cart/controllers/cart_controller.dart';
import 'package:stackfood_multivendor/features/checkout/controllers/checkout_controller.dart';
import 'package:stackfood_multivendor/features/home/screens/home_screen.dart';
import 'package:stackfood_multivendor/features/location/domain/models/prediction_model.dart';
import 'package:stackfood_multivendor/features/splash/controllers/splash_controller.dart';
import 'package:stackfood_multivendor/features/favourite/controllers/favourite_controller.dart';
import 'package:stackfood_multivendor/features/location/domain/models/zone_response_model.dart';
import 'package:stackfood_multivendor/features/address/domain/models/address_model.dart';
import 'package:stackfood_multivendor/features/location/domain/services/location_service_interface.dart';
import 'package:stackfood_multivendor/helper/address_helper.dart';
import 'package:stackfood_multivendor/helper/auth_helper.dart';
import 'package:stackfood_multivendor/common/widgets/custom_snackbar_widget.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:stackfood_multivendor/helper/route_helper.dart';
import 'package:geocoding/geocoding.dart';

class LocationController extends GetxController implements GetxService {
  final LocationServiceInterface locationServiceInterface;

  LocationController({required this.locationServiceInterface});

  Position _position = Position(
      longitude: 0,
      latitude: 0,
      timestamp: DateTime.now(),
      accuracy: 1,
      altitude: 1,
      heading: 1,
      speed: 1,
      speedAccuracy: 1,
      altitudeAccuracy: 1,
      headingAccuracy: 1);
  Position get position => _position;

  Position _pickPosition = Position(
      longitude: 0,
      latitude: 0,
      timestamp: DateTime.now(),
      accuracy: 1,
      altitude: 1,
      heading: 1,
      speed: 1,
      speedAccuracy: 1,
      altitudeAccuracy: 1,
      headingAccuracy: 1);
  Position get pickPosition => _pickPosition;

  bool _loading = false;
  bool get loading => _loading;

  String? _address = '';
  String? get address => _address;

  String? _pickAddress = '';
  String? get pickAddress => _pickAddress;

  int _addressTypeIndex = 0;
  int get addressTypeIndex => _addressTypeIndex;

  final List<String?> _addressTypeList = ['home', 'office', 'others'];
  List<String?> get addressTypeList => _addressTypeList;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool _inZone = false;
  bool get inZone => _inZone;

  int _zoneID = 0;
  int get zoneID => _zoneID;

  bool _buttonDisabled = true;
  bool get buttonDisabled => _buttonDisabled;

  GoogleMapController? _mapController;
  GoogleMapController? get mapController => _mapController;

  List<PredictionModel> _predictionList = [];
  List<PredictionModel> get predictionList => _predictionList;

  bool _updateAddressData = true;
  bool _changeAddress = true;
  Future<AddressModel> getCurrentLocation(bool fromAddress,
      {GoogleMapController? mapController,
      LatLng? defaultLatLng,
      bool notify = true,
      bool showSnackBar = false}) async {
    _loading = true;
    if (notify) {
      update();
    }

    AddressModel addressModel;

    // 1. التأكد من صلاحيات الموقع
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (showSnackBar) {
        showCustomSnackBar('Location services are disabled.');
      }
      _loading = false;
      update();
      throw Exception('Location services are disabled.');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _loading = false;
        update();
        throw Exception('Location permissions are denied.');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      _loading = false;
      update();
      throw Exception('Location permissions are permanently denied.');
    }

    // 2. الحصول على الإحداثيات
    Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
    fromAddress ? _position = position : _pickPosition = position;

    // 3. تحريك الخريطة إن وُجدت
    if (mapController != null) {
      mapController.animateCamera(CameraUpdate.newLatLng(
        LatLng(position.latitude, position.longitude),
      ));
    }

    // 4. تحويل الإحداثيات إلى عنوان نصي باستخدام geocoding
    List<Placemark> placemarks =
        await placemarkFromCoordinates(position.latitude, position.longitude);
    Placemark place = placemarks.first;
    String address =
        '${place.street}, ${place.locality}, ${place.administrativeArea}, ${place.country}';
    fromAddress ? _address = address : _pickAddress = address;

    // 5. استخدام zoneResponse وهمي (أنت ممكن تبدل هذا بجلب بيانات من API إذا أردت)
    ZoneResponseModel responseModel = await getZone(
        position.latitude.toString(), position.longitude.toString(), true,
        showSnackBar: showSnackBar);
    _buttonDisabled = !responseModel.isSuccess;

    // 6. إنشاء AddressModel
    addressModel = AddressModel(
      latitude: position.latitude.toString(),
      longitude: position.longitude.toString(),
      addressType: 'others',
      zoneId: responseModel.isSuccess ? responseModel.zoneIds[0] : 0,
      zoneIds: responseModel.zoneIds,
      address: address,
      zoneData: responseModel.zoneData,
    );

    _loading = false;
    update();
    return addressModel;
  }

  Future<ZoneResponseModel> getZone(String? lat, String? long, bool markerLoad,
      {bool updateInAddress = false, bool showSnackBar = false}) async {
    if (markerLoad) {
      _loading = true;
    } else {
      _isLoading = true;
    }
    if (!updateInAddress) {
      Future.delayed(Duration(seconds: 10), () {
        update();
      });
    }
    ZoneResponseModel responseModel =
        await locationServiceInterface.getZone(lat, long);
    _inZone = responseModel.isSuccess;
    _zoneID = responseModel.zoneIds.isNotEmpty ? responseModel.zoneIds[0] : 0;
    if (updateInAddress && responseModel.isSuccess) {
      AddressModel address = AddressHelper.getAddressFromSharedPref()!;
      address.zoneData = responseModel.zoneData;
      AddressHelper.saveAddressInSharedPref(address);
    }

    if (markerLoad) {
      _loading = false;
    } else {
      _isLoading = false;
    }
    update();
    return responseModel;
  }

  void makeLoadingOff() {
    _isLoading = false;
  }

  void updatePosition(CameraPosition? position, bool fromAddress) async {
    if (_updateAddressData) {
      _loading = true;
      update();
      if (fromAddress) {
        _position = Position(
          latitude: position!.target.latitude,
          longitude: position.target.longitude,
          timestamp: DateTime.now(),
          heading: 1,
          accuracy: 1,
          altitude: 1,
          speedAccuracy: 1,
          speed: 1,
          altitudeAccuracy: 1,
          headingAccuracy: 1,
        );
      } else {
        _pickPosition = Position(
          latitude: position!.target.latitude,
          longitude: position.target.longitude,
          timestamp: DateTime.now(),
          heading: 1,
          accuracy: 1,
          altitude: 1,
          speedAccuracy: 1,
          speed: 1,
          altitudeAccuracy: 1,
          headingAccuracy: 1,
        );
      }
      ZoneResponseModel responseModel = await getZone(
          position.target.latitude.toString(),
          position.target.longitude.toString(),
          true);
      _buttonDisabled = !responseModel.isSuccess;
      if (_changeAddress) {
        String addressFromGeocode = await getAddressFromGeocode(
            LatLng(position.target.latitude, position.target.longitude));
        fromAddress
            ? _address = addressFromGeocode
            : _pickAddress = addressFromGeocode;
      } else {
        _changeAddress = true;
      }
      _loading = false;
      update();
    } else {
      _updateAddressData = true;
    }
  }

  void setAddressTypeIndex(int index, {bool notify = true}) {
    _addressTypeIndex = index;
    if (notify) {
      update();
    }
  }

  void saveAddressAndNavigate(AddressModel address, bool fromSignUp,
      String? route, bool canRoute, bool isDesktop) {
    _prepareZoneData(address, fromSignUp, route, canRoute, isDesktop);
  }

  void _prepareZoneData(AddressModel address, bool fromSignUp, String? route,
      bool canRoute, bool isDesktop) {
    getZone(address.latitude, address.longitude, false).then((response) async {
      if (response.isSuccess) {
        Get.find<CartController>().getCartDataOnline();
        address.zoneId = response.zoneIds[0];
        address.zoneIds = [];
        address.zoneIds!.addAll(response.zoneIds);
        address.zoneData = [];
        address.zoneData!.addAll(response.zoneData);
        autoNavigate(address, fromSignUp, route, canRoute, isDesktop);
      } else {
        Get.back();
        showCustomSnackBar(response.message);
        if (route == 'splash') {
          Get.toNamed(RouteHelper.getPickMapRoute(route, false));
        }
      }
    });
  }

  void autoNavigate(AddressModel? address, bool fromSignUp, String? route,
      bool canRoute, bool isDesktop) async {
    locationServiceInterface.handleTopicSubscription(
        AddressHelper.getAddressFromSharedPref(), address);
    await AddressHelper.saveAddressInSharedPref(address!);
    if (AuthHelper.isLoggedIn() && !AuthHelper.isGuestLoggedIn()) {
      await Get.find<FavouriteController>().getFavouriteList();
      updateZone();
    }
    if (route == 'splash' && Get.isDialogOpen!) {
      Get.back();
    }
    HomeScreen.loadData(true);
    Get.find<CheckoutController>().clearPrevData();
    locationServiceInterface.handleRoute(fromSignUp, route, canRoute);
  }

  Future<Position> setLocation(
      String address, GoogleMapController? mapController) async {
    _loading = true;
    update();

    // 🔍 الحصول على lat/lng من العنوان النصي
    List<Location> locations = await locationFromAddress(address);
    Location loc = locations.first;
    LatLng latLng = LatLng(loc.latitude, loc.longitude);

    // تحويل latLng إلى Position
    _pickPosition = Position(
      latitude: latLng.latitude,
      longitude: latLng.longitude,
      timestamp: DateTime.now(),
      accuracy: 1,
      altitude: 1,
      heading: 1,
      speed: 1,
      speedAccuracy: 1,
      altitudeAccuracy: 1,
      headingAccuracy: 1,
    );

    // ✅ استخدام geocoding للحصول على العنوان البشري
    List<Placemark> placemarks =
        await placemarkFromCoordinates(latLng.latitude, latLng.longitude);
    Placemark placemark = placemarks.first;

    _pickAddress =
        "${placemark.name}, ${placemark.street}, ${placemark.locality}, ${placemark.country}";
    _changeAddress = false;

    // تحريك الكاميرا على الموقع الجديد
    if (mapController != null) {
      mapController.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(target: latLng, zoom: 16),
      ));
    }

    _loading = false;
    update();
    return _pickPosition;
  }

  void disableButton() {
    _buttonDisabled = true;
    _inZone = true;
    update();
  }

  void addAddressData() {
    _position = _pickPosition;
    _address = _pickAddress;
    _updateAddressData = false;
    update();
  }

  void updateAddress(AddressModel address) {
    _position = Position(
      latitude: double.parse(address.latitude!),
      longitude: double.parse(address.longitude!),
      timestamp: DateTime.now(),
      altitude: 1,
      heading: 1,
      speed: 1,
      speedAccuracy: 1,
      floor: 1,
      accuracy: 1,
      altitudeAccuracy: 1,
      headingAccuracy: 1,
    );
    _address = address.address;
    _addressTypeIndex = _addressTypeList.indexOf(address.addressType);
  }

  void setPickData() {
    _pickPosition = _position;
    _pickAddress = _address;
  }

  void setMapController(GoogleMapController mapController) {
    _mapController = mapController;
  }

  Future<String> getAddressFromGeocode(LatLng latLng) async {
    List<Placemark> placemarks =
        await placemarkFromCoordinates(latLng.latitude, latLng.longitude);
    Placemark place = placemarks.first;
    return '${place.street}, ${place.locality}, ${place.administrativeArea}, ${place.country}';
  }

  Future<List<PredictionModel>> searchLocation(String text) async {
    List<PredictionModel> _predictionList = [];

    if (text.isNotEmpty) {
      try {
        // نحصل على الإحداثيات من النص
        List<Location> locations = await locationFromAddress(text);

        for (var location in locations) {
          // نحول الإحداثيات إلى اسم مكان
          List<Placemark> placemarks = await placemarkFromCoordinates(
            location.latitude,
            location.longitude,
          );

          // نأخذ أول نتيجة ونعرض اسم المكان
          if (placemarks.isNotEmpty) {
            Placemark place = placemarks[0];
            String fullAddress =
                '${place.name}, ${place.street}, ${place.locality}, ${place.administrativeArea}, ${place.country}';

            _predictionList.add(
              PredictionModel(
                description: fullAddress,
                id: '', // حسب الحاجة
                distanceMeters: 0,
                placeId: '',
                reference: '',
              ),
            );
          }
          _position = Position(
            latitude: location.latitude,
            longitude: location.longitude,
            timestamp: DateTime.now(),
            accuracy: 1,
            altitude: 1,
            heading: 1,
            speed: 1,
            speedAccuracy: 1,
            altitudeAccuracy: 1,
            headingAccuracy: 1,
          );
        }
      } catch (e) {
        print('خطأ في البحث: $e');
      }
    }

    return _predictionList;
  }

  void setPlaceMark(String address) {
    _address = address;
  }

  void checkPermission(Function onTap) {
    locationServiceInterface.checkLocationPermission(onTap);
  }

  Future<void> updateZone() async {
    await locationServiceInterface.updateZone();
  }
}
