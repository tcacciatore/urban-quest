import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/api_constants.dart';
import 'quest_providers.dart' show dioProvider;

/// Paramètre : (id OSM de la relation, nom de la ville, lat, lon du centroïde).
typedef CityDescParam = (String cityId, String name, double lat, double lon);

/// Retourne l'extrait Wikipedia pour la ville.
/// Stratégie (par ordre de fiabilité) :
///   1. Tags OSM de la relation (wikipedia / wikidata) → article exact
///   2. Geosearch Wikipedia autour du centroïde, filtré par nom de ville
///   3. Recherche par nom (fallback)
final cityDescriptionProvider =
    FutureProvider.family<String?, CityDescParam>((ref, param) async {
  final (cityId, name, lat, lon) = param;
  final dio = ref.read(dioProvider);

  // ── Méthode 1 : tags OSM de la relation de la ville ──────────────────────
  try {
    final query = '[out:json][timeout:10]; relation($cityId); out tags;';
    final resp = await dio.get(
      ApiConstants.overpassMirrors.first,
      queryParameters: {'data': query},
      options: Options(receiveTimeout: const Duration(seconds: 15)),
    );
    final elements = resp.data['elements'] as List<dynamic>?;
    if (elements != null && elements.isNotEmpty) {
      final tags = elements.first['tags'] as Map<String, dynamic>? ?? {};

      // wikipedia tag direct (ex. "fr:Châtillon, Hauts-de-Seine")
      final wikiTag = tags['wikipedia'] as String?;
      if (wikiTag != null) {
        final desc = await _fetchFromWikipediaTag(dio, wikiTag);
        if (desc != null) return desc;
      }

      // wikidata tag (ex. "Q193660") → sitelink → article
      final wikidataTag = tags['wikidata'] as String?;
      if (wikidataTag != null) {
        final desc = await _fetchFromWikidata(dio, wikidataTag);
        if (desc != null) return desc;
      }
    }
  } catch (_) {}

  // ── Méthode 2 : geosearch filtré par nom ─────────────────────────────────
  for (final lang in ['fr', 'en']) {
    try {
      final geoResp = await dio.get(
        'https://$lang.wikipedia.org/w/api.php',
        queryParameters: {
          'action': 'query',
          'list': 'geosearch',
          'gscoord': '$lat|$lon',
          'gsradius': '10000',
          'gslimit': '10',
          'format': 'json',
          'formatversion': '2',
        },
        options: Options(receiveTimeout: const Duration(seconds: 8)),
      );
      final results =
          geoResp.data['query']?['geosearch'] as List<dynamic>?;
      if (results != null) {
        final norm = _normalize(name);
        final matching = results.where((r) {
          final title = r['title'] as String? ?? '';
          return _normalize(title).contains(norm);
        }).toList();
        for (final r in matching) {
          final title = r['title'] as String?;
          if (title == null || title.isEmpty) continue;
          final desc = await _fetchSummary(dio, lang, title);
          if (desc != null) return desc;
        }
      }
    } catch (_) {}
  }

  // ── Méthode 3 : recherche par nom (dernier recours) ───────────────────────
  for (final lang in ['fr', 'en']) {
    try {
      final searchResp = await dio.get(
        'https://$lang.wikipedia.org/w/api.php',
        queryParameters: {
          'action': 'query',
          'list': 'search',
          'srsearch': name,
          'srlimit': '3',
          'format': 'json',
          'formatversion': '2',
        },
        options: Options(receiveTimeout: const Duration(seconds: 8)),
      );
      final results =
          searchResp.data['query']?['search'] as List<dynamic>?;
      if (results == null || results.isEmpty) continue;
      final norm = _normalize(name);
      final sorted = List<dynamic>.from(results)
        ..sort((a, b) {
          final ta = _normalize(a['title'] as String? ?? '');
          final tb = _normalize(b['title'] as String? ?? '');
          return ta.startsWith(norm) ? -1 : (tb.startsWith(norm) ? 1 : 0);
        });
      for (final r in sorted) {
        final title = r['title'] as String?;
        if (title == null || title.isEmpty) continue;
        final desc = await _fetchSummary(dio, lang, title);
        if (desc != null) return desc;
      }
    } catch (_) {}
  }

  return null;
});

// ─── Helpers Wikipedia ────────────────────────────────────────────────────────

Future<String?> _fetchFromWikipediaTag(Dio dio, String tag) async {
  final colonIdx = tag.indexOf(':');
  if (colonIdx == -1) return null;
  final lang = tag.substring(0, colonIdx).trim();
  final title = tag.substring(colonIdx + 1).trim();
  if (lang.isEmpty || title.isEmpty) return null;
  return _fetchSummary(dio, lang, title);
}

Future<String?> _fetchFromWikidata(Dio dio, String qid) async {
  try {
    final resp = await dio.get(
      'https://www.wikidata.org/w/api.php',
      queryParameters: {
        'action': 'wbgetentities',
        'ids': qid,
        'props': 'sitelinks',
        'sitefilter': 'frwiki|enwiki',
        'format': 'json',
        'formatversion': '2',
      },
      options: Options(receiveTimeout: const Duration(seconds: 8)),
    );
    final entities = resp.data['entities'] as Map<String, dynamic>?;
    final links =
        (entities?[qid] as Map<String, dynamic>?)?['sitelinks']
            as Map<String, dynamic>?;
    if (links == null) return null;
    for (final (site, lang) in [('frwiki', 'fr'), ('enwiki', 'en')]) {
      final title =
          (links[site] as Map<String, dynamic>?)?['title'] as String?;
      if (title != null && title.isNotEmpty) {
        final desc = await _fetchSummary(dio, lang, title);
        if (desc != null) return desc;
      }
    }
  } catch (_) {}
  return null;
}

Future<String?> _fetchSummary(Dio dio, String lang, String title) async {
  try {
    final resp = await dio.get(
      'https://$lang.wikipedia.org/api/rest_v1/page/summary/${Uri.encodeComponent(title)}',
      options: Options(
        receiveTimeout: const Duration(seconds: 8),
        validateStatus: (s) => s != null && s < 500,
      ),
    );
    if (resp.statusCode != 200) return null;
    final extract = resp.data['extract'] as String?;
    if (extract == null || extract.isEmpty) return null;
    return extract.length > 600
        ? '${extract.substring(0, 600).trimRight()}…'
        : extract;
  } catch (_) {
    return null;
  }
}

String _normalize(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[àâä]'), 'a')
    .replaceAll(RegExp(r'[éèêë]'), 'e')
    .replaceAll(RegExp(r'[îï]'), 'i')
    .replaceAll(RegExp(r'[ôö]'), 'o')
    .replaceAll(RegExp(r'[ùûü]'), 'u')
    .replaceAll(RegExp(r'ç'), 'c')
    .replaceAll(RegExp(r'œ'), 'oe')
    .replaceAll(RegExp(r'æ'), 'ae');
