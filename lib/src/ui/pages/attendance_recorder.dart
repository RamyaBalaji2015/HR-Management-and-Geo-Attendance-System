import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geo_attendance_system/src/services/fetch_offices.dart';
import 'package:geo_attendance_system/src/ui/constants/geofence_controls.dart';
import 'package:geo_attendance_system/src/ui/constants/strings.dart';
import 'package:geofencing/geofencing.dart' as geofence_lib;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart' as location_lib;

class AttendanceRecorderWidget extends StatefulWidget {
  @override
  AttendanceRecorderWidgetState createState() =>
      AttendanceRecorderWidgetState();
}

class AttendanceRecorderWidgetState extends State<AttendanceRecorderWidget> {
  Completer<GoogleMapController> _controller = Completer();

  double zoomVal = 5.0;
  OfficeDatabase officeDatabase = new OfficeDatabase();

  // ignore: unused_field
  StreamSubscription<location_lib.LocationData> _locationSubscription;
  location_lib.LocationData _currentLocation;
  location_lib.LocationData _startLocation;
  Set<Marker> _markers = {};

  location_lib.Location _locationService = new location_lib.Location();
  bool _permission = false;
  String error;

  CameraPosition _currentCameraPosition;
  ReceivePort port = ReceivePort();
  String geofenceState = 'N/A';
  double latitude = 31.1471305;
  double longitude = 75.34121789999999;

  @override
  void initState() {
    super.initState();
    initPlatformState();
    IsolateNameServer.registerPortWithName(port.sendPort, geofence_port_name);
    port.listen((dynamic data) {
      print('Event: $data');
      setState(() {
        geofenceState = data;
      });
    });
  }

  static void callback(List<String> ids, geofence_lib.Location l,
      geofence_lib.GeofenceEvent e) async {
    print('Fences: $ids Location $l Event: $e');
    final SendPort send =
        IsolateNameServer.lookupPortByName(geofence_port_name);
    send?.send(e.toString());
  }

  Future<void> initGeoFencePlatformState() async {
    print('Initializing Geofencing');
    await geofence_lib.GeofencingManager.initialize();
    print('Initialization done');
  }

  @override
  void dispose() {
    super.dispose();
    _locationSubscription.cancel();
    geofence_lib.GeofencingManager.removeGeofenceById(fence_id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: <Widget>[
          googleMap(context),
          Padding(
            padding: const EdgeInsets.only(top: 40.0),
            child: FlatButton(
              shape: new RoundedRectangleBorder(
                  borderRadius: new BorderRadius.circular(100.0)),
              child: Icon(
                Icons.arrow_back,
                size: 30,
              ),
              onPressed: () {
                Navigator.pop(context);
              },
            ),
          ),
          Text(
            geofenceState,
            style: TextStyle(fontSize: 40.0, color: Colors.black),
          ),
          buildContainer(context),
        ],
      ),
    );
  }

  Widget googleMap(BuildContext context) {
    double _initialLat = 30.677515;
    double _initialLong = 76.743902;
    double _initialZoom = 15;
    return Container(
      height: MediaQuery.of(context).size.height,
      width: MediaQuery.of(context).size.width,
      child: GoogleMap(
        mapType: MapType.normal,
        initialCameraPosition: CameraPosition(
            target: LatLng(_initialLat, _initialLong), zoom: _initialZoom),
        markers: _markers,
        onMapCreated: (GoogleMapController controller) {
          _controller.complete(controller);
          _goToCurrentLocation();
          print("Reached Here");
          _registerForGeoFence();
        },
      ),
    );
  }

  buildContainer(BuildContext context) {
    TextStyle textStyle = TextStyle(
        fontSize: 22, color: Colors.blueGrey, fontWeight: FontWeight.w900);
    return Positioned(
      top: 5 * (MediaQuery.of(context).size.height) / 6,
      left: MediaQuery.of(context).size.width / 4,
      child: Container(
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30.0),
            boxShadow: <BoxShadow>[
              BoxShadow(offset: Offset(0, 3), blurRadius: 10, spreadRadius: 0.2)
            ]),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              FlatButton(
                child: Text(
                  "IN",
                  style: textStyle,
                ),
                onPressed: () {},
              ),
              Text(
                "|",
                style: textStyle,
              ),
              FlatButton(
                child: Text(
                  "OUT",
                  style: textStyle,
                ),
                onPressed: () {},
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _goToCurrentLocation() async {}

  Future<void> _gotoLocation(double lat, double long) async {
    final GoogleMapController controller = await _controller.future;
    controller.animateCamera(CameraUpdate.newCameraPosition(CameraPosition(
        target: LatLng(lat, long), zoom: 15, tilt: 50.0, bearing: 45.0)));
  }

  void _registerForGeoFence() {
    geofence_lib.GeofencingManager.registerGeofence(
        geofence_lib.GeofenceRegion(
            fence_id, latitude, longitude, radius_geofence, triggers,
            androidSettings: androidSettings),
        callback);
  }

  initPlatformState() async {
    await _locationService.changeSettings(
        accuracy: location_lib.LocationAccuracy.HIGH, interval: 1000);

    location_lib.LocationData location;
    // Platform messages may fail, so we use a try/catch PlatformException.
    try {
      bool serviceStatus = await _locationService.serviceEnabled();
      print("Service status: $serviceStatus");
      if (serviceStatus) {
        _permission = await _locationService.requestPermission();
        print("Permission: $_permission");
        if (_permission) {
          location = await _locationService.getLocation();

          _locationSubscription = _locationService
              .onLocationChanged()
              .listen((location_lib.LocationData result) async {
            _currentCameraPosition = CameraPosition(
                target: LatLng(result.latitude, result.longitude),
                zoom: 16,
                tilt: 50.0,
                bearing: 45.0);

            final GoogleMapController controller = await _controller.future;
            controller.animateCamera(
                CameraUpdate.newCameraPosition(_currentCameraPosition));
            if (mounted) {
              setState(() {
                _currentLocation = result;
                _markers.clear();
                _markers.add(Marker(
                    markerId: MarkerId("Current Location"),
                    position: LatLng(result.latitude, result.longitude)));
              });
            }
          });
        }
      } else {
        bool serviceStatusResult = await _locationService.requestService();
        print("Service status activated after request: $serviceStatusResult");
        if (serviceStatusResult) {
          initPlatformState();
        }
      }
    } on PlatformException catch (e) {
      print(e);
      if (e.code == 'PERMISSION_DENIED') {
        error = e.message;
      } else if (e.code == 'SERVICE_STATUS_ERROR') {
        error = e.message;
      }
      location = null;
    }

    setState(() {
      _startLocation = location;
    });
  }
}