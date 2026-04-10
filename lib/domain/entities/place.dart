class Place {
  final String id;
  final String name;
  final String category;
  final double latitude;
  final double longitude;
  final Map<String, String> tags; // tags OSM bruts
  final DateTime? discoveredAt;

  const Place({
    required this.id,
    required this.name,
    required this.category,
    required this.latitude,
    required this.longitude,
    required this.tags,
    this.discoveredAt,
  });
}
