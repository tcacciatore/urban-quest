import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../../data/repositories/personal_pin_repository.dart';
import '../../domain/entities/personal_pin.dart';

/// Chemin du dossier Documents de l'app, mis en cache une fois au démarrage.
/// Utilisé pour reconstruire les chemins de photos (on ne stocke que le nom de fichier).
final appDocsDirProvider = FutureProvider<String>((ref) async {
  final dir = await getApplicationDocumentsDirectory();
  return dir.path;
});

final personalPinRepositoryProvider = Provider<PersonalPinRepository>(
  (_) => PersonalPinRepository(),
);

class PersonalPinNotifier extends Notifier<List<PersonalPin>> {
  @override
  List<PersonalPin> build() {
    return ref.read(personalPinRepositoryProvider).loadAll();
  }

  Future<void> add(PersonalPin pin) async {
    state = [...state, pin];
    await ref.read(personalPinRepositoryProvider).saveAll(state);
  }

  Future<void> remove(String pinId) async {
    state = state.where((p) => p.id != pinId).toList();
    await ref.read(personalPinRepositoryProvider).saveAll(state);
  }
}

final personalPinProvider =
    NotifierProvider<PersonalPinNotifier, List<PersonalPin>>(
  PersonalPinNotifier.new,
);
