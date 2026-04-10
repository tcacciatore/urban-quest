import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../core/constants/app_constants.dart';
import '../../data/datasources/remote/overpass_remote_datasource.dart' show RandomPlaceDatasource;
import '../../domain/entities/quest.dart';
import '../../domain/usecases/generate_clues.dart';
import '../../core/extensions/latlng_extensions.dart';
import 'wallet_providers.dart';

final dioProvider = Provider<Dio>((ref) => Dio());

final randomPlaceDatasourceProvider = Provider<RandomPlaceDatasource>(
  (ref) => RandomPlaceDatasource(ref.read(dioProvider)),
);

final generateCluesProvider = Provider<GenerateClues>((ref) => GenerateClues());

class QuestNotifier extends Notifier<AsyncValue<Quest?>> {
  @override
  AsyncValue<Quest?> build() => const AsyncValue.data(null);

  Future<void> startQuest(LatLng userPosition, int radiusMeters, {String? direction}) async {
    state = const AsyncValue.loading();

    final cost = AppConstants.radiusCostMap[radiusMeters] ?? radiusMeters;
    final wallet = ref.read(walletProvider.notifier);
    final spent = await wallet.spendCredits(cost);

    if (!spent) {
      state = AsyncValue.error(
        ref.read(walletProvider).hasQuestsRemaining
            ? 'Crédits insuffisants. Marche pour en gagner !'
            : 'Tu as atteint la limite de 3 chasses aujourd\'hui.',
        StackTrace.current,
      );
      return;
    }

    try {
      final datasource = ref.read(randomPlaceDatasourceProvider);
      final generateClues = ref.read(generateCluesProvider);

      final place = await datasource.fetchRandomPlace(userPosition, radiusMeters, direction: direction);
      final clues = generateClues(place);

      final quest = Quest(
        id: '${DateTime.now().millisecondsSinceEpoch}',
        targetPlace: place,
        clues: clues,
        date: DateTime.now(),
        radiusMeters: radiusMeters,
        creditsCost: cost,
        status: QuestStatus.active,
        startedAt: DateTime.now(),
      );

      state = AsyncValue.data(quest);
    } catch (e, st) {
      // Rembourse les crédits en cas d'erreur réseau
      wallet.addCredits(cost);
      state = AsyncValue.error('Impossible de trouver un lieu. Réessaie.', st);
    }
  }

  /// Révèle l'indice suivant si les conditions sont remplies
  void tryRevealNextClue(LatLng currentPosition) {
    final quest = state.valueOrNull;
    if (quest == null || quest.status != QuestStatus.active) return;

    final target = LatLng(quest.targetPlace.latitude, quest.targetPlace.longitude);
    final distanceToTarget = currentPosition.distanceTo(target);
    final totalDistance = quest.radiusMeters.toDouble();

    final ratio = distanceToTarget / totalDistance;

    final updatedClues = quest.clues.map((clue) {
      if (!clue.isRevealed) {
        if (clue.index == 2 && ratio <= AppConstants.clue2UnlockDistanceRatio) {
          return clue.copyWith(isRevealed: true);
        }
        if (clue.index == 3 && distanceToTarget <= AppConstants.clue3UnlockDistanceMeters) {
          return clue.copyWith(isRevealed: true);
        }
      }
      return clue;
    }).toList();

    if (updatedClues != quest.clues) {
      state = AsyncValue.data(quest.copyWith(clues: updatedClues));
    }
  }

  void completeQuest(String userTag) {
    final quest = state.valueOrNull;
    if (quest == null) return;
    state = AsyncValue.data(
      quest.copyWith(
        status: QuestStatus.completed,
        completedAt: DateTime.now(),
        userTag: userTag,
      ),
    );
  }

  void abandonQuest() {
    final quest = state.valueOrNull;
    if (quest == null) return;
    state = AsyncValue.data(quest.copyWith(status: QuestStatus.abandoned));
  }
}

final questProvider = NotifierProvider<QuestNotifier, AsyncValue<Quest?>>(QuestNotifier.new);
