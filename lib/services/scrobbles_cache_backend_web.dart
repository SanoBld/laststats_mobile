// lib/services/scrobbles_cache_backend_web.dart
// ══════════════════════════════════════════════════════════════════════════
//  Backend Web — stockage via IndexedDB (illimité, persistant)
//
//  Réécrit avec package:web + dart:js_interop (dart:html déprécié depuis
//  Flutter 3.22).
//
//  Structure :
//    DB      : "laststats_scrobbles"  (version 1)
//    Store   : "cache"
//    Clés    : "meta", "year_2020", "year_2021", …
//    Valeurs : chaînes JSON
// ══════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

class CacheBackend {
  static const _dbName    = 'laststats_scrobbles';
  static const _storeName = 'cache';
  static const _version   = 1;

  static web.IDBDatabase?           _db;
  static Completer<web.IDBDatabase>? _opening;

  // ── Ouverture (singleton, thread-safe) ────────────────────────────────────

  static Future<web.IDBDatabase> _open() async {
    if (_db != null) return _db!;
    if (_opening != null) return _opening!.future;

    _opening = Completer<web.IDBDatabase>();
    final request = web.window.indexedDB.open(_dbName, _version);

    request.onupgradeneeded = ((web.IDBVersionChangeEvent event) {
      final db = request.result as web.IDBDatabase;
      if (!db.objectStoreNames.contains(_storeName)) {
        db.createObjectStore(_storeName);
      }
    }).toJS;

    request.onsuccess = ((web.Event event) {
      _db = request.result as web.IDBDatabase;
      _opening!.complete(_db!);
    }).toJS;

    request.onerror = ((web.Event event) {
      _opening!.completeError('IndexedDB open failed');
      _opening = null;
    }).toJS;

    return _opening!.future;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Enveloppe un [IDBRequest] dans un Future.
  static Future<JSAny?> _await(web.IDBRequest req) {
    final c = Completer<JSAny?>();
    req.onsuccess = ((web.Event _) => c.complete(req.result)).toJS;
    req.onerror   = ((web.Event _) => c.complete(null)).toJS;
    return c.future;
  }

  /// Attend la fin d'une transaction.
  static Future<void> _txnDone(web.IDBTransaction txn) {
    final c = Completer<void>();
    txn.oncomplete = ((web.Event _) => c.complete()).toJS;
    txn.onerror    = ((web.Event _) => c.complete()).toJS;
    txn.onabort    = ((web.Event _) => c.complete()).toJS;
    return c.future;
  }

  // ── API publique ───────────────────────────────────────────────────────────

  /// Lit la valeur JSON associée à [key], ou null si absente.
  static Future<String?> read(String key) async {
    try {
      final db    = await _open();
      final txn   = db.transaction(_storeName.toJS, 'readonly');
      final store = txn.objectStore(_storeName);
      final result = await _await(store.get(key.toJS));
      if (result == null || result.isUndefinedOrNull) return null;
      return (result as JSString).toDart;
    } catch (_) {
      return null;
    }
  }

  /// Stocke [value] (JSON) sous [key] dans IndexedDB.
  static Future<void> write(String key, String value) async {
    try {
      final db    = await _open();
      final txn   = db.transaction(_storeName.toJS, 'readwrite');
      final store = txn.objectStore(_storeName);
      store.put(value.toJS, key.toJS);
      await _txnDone(txn);
    } catch (_) {}
  }

  /// Supprime l'entrée [key].
  static Future<void> delete(String key) async {
    try {
      final db    = await _open();
      final txn   = db.transaction(_storeName.toJS, 'readwrite');
      final store = txn.objectStore(_storeName);
      store.delete(key.toJS);
      await _txnDone(txn);
    } catch (_) {}
  }

  /// Liste toutes les clés présentes dans le store.
  static Future<List<String>> listKeys() async {
    try {
      final db    = await _open();
      final txn   = db.transaction(_storeName.toJS, 'readonly');
      final store = txn.objectStore(_storeName);
      final result = await _await(store.getAllKeys());
      if (result == null || result.isUndefinedOrNull) return [];
      final list = (result as JSArray<JSAny?>).toDart;
      return list.whereType<JSString>().map((k) => k.toDart).toList();
    } catch (_) {
      return [];
    }
  }

  /// Estimation de la taille totale en octets (UTF-16 × 2).
  static Future<int> totalBytes() async {
    try {
      final db    = await _open();
      final txn   = db.transaction(_storeName.toJS, 'readonly');
      final store = txn.objectStore(_storeName);
      final result = await _await(store.getAll());
      if (result == null || result.isUndefinedOrNull) return 0;
      final list = (result as JSArray<JSAny?>).toDart;
      int total = 0;
      for (final v in list) {
        if (v is JSString) total += v.toDart.length * 2;
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// Vide entièrement le store.
  static Future<void> clearAll() async {
    try {
      final db    = await _open();
      final txn   = db.transaction(_storeName.toJS, 'readwrite');
      final store = txn.objectStore(_storeName);
      store.clear();
      await _txnDone(txn);
      _db      = null;
      _opening = null;
    } catch (_) {}
  }
}