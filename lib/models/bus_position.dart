import 'package:latlong2/latlong.dart';

class BusPosition {
  final String? place;
  final LatLng? livePos;
  final DateTime? startTime;

  BusPosition({
    this.place,
    this.livePos,
    this.startTime,
  });
}