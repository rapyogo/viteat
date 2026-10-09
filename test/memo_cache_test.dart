import 'dart:async';

import 'package:customer/data/memo_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('un ecran qui vide la liste recue ne vide pas la memoire', () async {
    final MemoCache<String, List<int>> memo = MemoCache<String, List<int>>(const Duration(minutes: 2));
    final List<int> first = await memo.get('menu', (_) async => <int>[1, 2, 3]);
    first.clear();
    expect(await memo.get('menu', (_) async => <int>[]), <int>[1, 2, 3]);
  });

  test('deux demandes simultanees ne declenchent qu un chargement', () async {
    final MemoCache<String, String> memo = MemoCache<String, String>(const Duration(minutes: 2));
    int loads = 0;
    final Completer<String> gate = Completer<String>();
    Future<String> load(void Function(String) _) {
      loads++;
      return gate.future;
    }

    final Future<String> a = memo.get('v1', load);
    final Future<String> b = memo.get('v1', load);
    gate.complete('resto');
    expect(await a, 'resto');
    expect(await b, 'resto');
    expect(loads, 1);
  });

  test('la version serveur est transmise a tous les appelants en attente', () async {
    final MemoCache<String, String> memo = MemoCache<String, String>(const Duration(minutes: 2));
    final Completer<String> gate = Completer<String>();
    late void Function(String) serverArrived;
    Future<String> load(void Function(String) onFresh) {
      serverArrived = onFresh;
      return gate.future;
    }

    final List<String> seen = <String>[];
    final Future<String> a = memo.get('cat', load, onRefresh: (v) => seen.add('a:$v'));
    final Future<String> b = memo.get('cat', load, onRefresh: (v) => seen.add('b:$v'));
    gate.complete('disque');
    await Future.wait(<Future<String>>[a, b]);
    serverArrived('serveur');
    expect(seen, <String>['a:serveur', 'b:serveur']);
    expect(await memo.get('cat', load), 'serveur');
  });

  test('null et listes vides ne sont jamais memorises', () async {
    final MemoCache<String, List<int>?> memo = MemoCache<String, List<int>?>(const Duration(minutes: 2));
    int loads = 0;
    await memo.get('k', (_) async {
      loads++;
      return <int>[];
    });
    await memo.get('k', (_) async {
      loads++;
      return null;
    });
    expect(loads, 2);
    expect(memo.peek('k'), isNull);
  });

  test('valeur perimee rendue tout de suite puis revalidee', () async {
    final MemoCache<String, String> memo = MemoCache<String, String>(Duration.zero);
    memo.put('z', 'ancien');
    await Future<void>.delayed(const Duration(milliseconds: 2));
    int loads = 0;
    final String value = await memo.get('z', (_) async {
      loads++;
      return 'nouveau';
    });
    expect(value, 'ancien');
    await Future<void>.delayed(Duration.zero);
    expect(loads, 1);
    expect(memo.peek('z'), 'nouveau');
  });
}
