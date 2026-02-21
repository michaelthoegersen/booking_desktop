import 'package:latlong2/latlong.dart';

class BusPosition {
  final String? place;
  final LatLng? livePos;
  final DateTime? startTime;
  final String? production;

  BusPosition({
    this.place,
    this.livePos,
    this.startTime,
    this.production,
  });
}