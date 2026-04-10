import '../entities/clue.dart';
import '../entities/place.dart';

/// Génère 3 indices progressifs à partir de l'adresse du lieu.
/// Indice 1 : quartier / code postal (très vague)
/// Indice 2 : nom de la rue (sans le numéro)
/// Indice 3 : distance en temps réel (calculée dynamiquement dans le widget)
class GenerateClues {
  List<Clue> call(Place place) {
    final tags = place.tags;
    final suburb = tags['suburb'];
    final city = tags['city'];
    final postcode = tags['postcode'];
    final road = tags['road'];

    final nearbyPoi = tags['nearby_poi'];

    return [
      Clue(
        index: 1,
        text: _clue1(suburb, city, postcode),
        type: ClueType.text,
        isRevealed: true,
      ),
      Clue(
        index: 2,
        text: _clue2(nearbyPoi, road),
        type: ClueType.text,
        isRevealed: false,
      ),
      Clue(
        index: 3,
        text: _clue3(nearbyPoi),
        type: ClueType.text,
        isRevealed: false,
      ),
    ];
  }

  String _clue3(String? poi) {
    if (poi != null && poi.isNotEmpty) {
      return 'Sur ton chemin, tu passeras devant : $poi.';
    }
    return 'Tu approches du but, cherche bien autour de toi.';
  }

  String _clue1(String? suburb, String? city, String? postcode) {
    if (suburb != null) return 'Le lieu se trouve dans le quartier : $suburb.';
    if (postcode != null && city != null) return 'Le lieu se trouve à $city ($postcode).';
    if (city != null) return 'Le lieu se trouve à $city.';
    return 'Le lieu se trouve quelque part dans ta ville.';
  }

  String _clue2(String? poi, String? road) {
    if (road != null && road.length >= 3) {
      final lastThree = road.substring(road.length - 3);
      return 'Les 3 dernières lettres de la rue sont "$lastThree".';
    }
    if (road != null) return 'La rue s\'appelle "$road".';
    return 'Continue à marcher, tu approches...';
  }
}
