import 'dart:async';
import 'dart:collection';

/// Cache memoire partage entre les ecrans, avec duree de fraicheur et fusion
/// des appels identiques en cours.
///
/// Il se place AU-DESSUS des helpers cache-first de FireStoreUtils (qui lisent
/// le cache disque de Firestore puis revalident) :
/// - valeur fraiche (plus jeune que [ttl]) : rendue tout de suite, aucun appel ;
/// - valeur perimee : rendue tout de suite, revalidee en arriere-plan
///   (stale-while-revalidate) ;
/// - absente : chargee une seule fois, meme si dix widgets la demandent en meme
///   temps (avant, le meme vendeur pouvait etre lu en double).
///
/// Ne sont jamais memorises : null et les listes vides, que les helpers rendent
/// aussi bien pour « rien » que pour « erreur reseau ».
///
/// Les listes sont copiees a l'entree et a la sortie : un ecran qui vide ou
/// trie la liste recue (ex. la recherche du menu) ne touche pas la memoire
/// partagee.
class MemoCache<K, V> {
  MemoCache(this.ttl, {this.maxEntries = 300});

  final Duration ttl;
  final int maxEntries;

  final LinkedHashMap<K, _MemoEntry<V>> _entries = LinkedHashMap<K, _MemoEntry<V>>();
  final Map<K, Future<V>> _inFlight = <K, Future<V>>{};

  /// Rappels « version serveur arrivee » de tous les appelants d'un meme
  /// chargement (pas seulement du premier).
  final Map<K, List<void Function(V)>> _refreshWaiters = <K, List<void Function(V)>>{};

  /// [load] recoit un rappel a invoquer quand une valeur plus fraiche arrive
  /// apres coup (le onRefresh des helpers cache-first).
  Future<V> get(K key, Future<V> Function(void Function(V fresh) onFresh) load, {void Function(V)? onRefresh}) {
    final _MemoEntry<V>? entry = _entries[key];
    if (entry != null) {
      if (DateTime.now().difference(entry.at) > ttl) {
        // Revalidation : seule la version serveur (onFresh) est propagee a
        // l'ecran. Le resultat immediat du chargement vient du cache disque et
        // peut etre plus ancien que la valeur deja affichee.
        unawaited(_load(key, load, onRefresh: onRefresh).then((V _) {}, onError: (Object _) {}));
      }
      return Future<V>.value(_copy(entry.value));
    }
    return _load(key, load, onRefresh: onRefresh).then((V value) => _copy(value));
  }

  /// Valeur deja en memoire (fraiche ou non), sans aucun chargement.
  V? peek(K key) {
    final _MemoEntry<V>? entry = _entries[key];
    return entry == null ? null : _copy(entry.value);
  }

  void put(K key, V value) {
    if (!_cacheable(value)) return;
    _entries.remove(key);
    _entries[key] = _MemoEntry<V>(_copy(value), DateTime.now());
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  void invalidate(K key) => _entries.remove(key);

  void clear() => _entries.clear();

  Future<V> _load(K key, Future<V> Function(void Function(V fresh) onFresh) load, {void Function(V)? onRefresh}) {
    final Future<V>? pending = _inFlight[key];
    if (pending != null) {
      if (onRefresh != null) (_refreshWaiters[key] ??= <void Function(V)>[]).add(onRefresh);
      return pending;
    }
    // Nouveau chargement : les rappels d'un chargement precedent jamais servis
    // (aucune version serveur differente) sont abandonnes.
    _refreshWaiters[key] = <void Function(V)>[if (onRefresh != null) onRefresh];
    final Future<V> future = load((V fresh) {
      put(key, fresh);
      if (!_cacheable(fresh)) return;
      final List<void Function(V)> waiters = _refreshWaiters.remove(key) ?? const [];
      for (final void Function(V) callback in waiters) {
        callback(_copy(fresh));
      }
    }).then((V value) {
      put(key, value);
      return value;
    }).whenComplete(() {
      // Bloc, pas une fleche : remove() rend la future retiree (celle-ci), et
      // whenComplete attendrait alors sa propre fin, sans jamais se terminer.
      _inFlight.remove(key);
    });
    _inFlight[key] = future;
    return future;
  }

  /// Copie superficielle des listes ; les autres valeurs sont rendues telles
  /// quelles. toList() garde le type reel des elements (une liste de ProductModel reste typee).
  static V _copy<V>(V value) => value is List ? value.toList() as V : value;

  static bool _cacheable(Object? value) => value != null && !(value is Iterable && value.isEmpty);
}

class _MemoEntry<V> {
  _MemoEntry(this.value, this.at);

  final V value;
  final DateTime at;
}
