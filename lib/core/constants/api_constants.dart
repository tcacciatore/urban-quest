class ApiConstants {
  static const String nominatimUrl = 'https://nominatim.openstreetmap.org/reverse';

  /// Mirrors Overpass testés dans l'ordre en cas de 504/timeout.
  static const List<String> overpassMirrors = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
    'https://overpass.private.coffee/api/interpreter',
    'https://overpass.openstreetmap.ru/api/interpreter',
    'https://overpass.nchc.org.tw/api/interpreter',
  ];
}
