import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../../core/security/sync_crypto.dart';
import '../local/db/app_database.dart';
import 'file_sync_service.dart';

/// What the sync screen shows about the Wi-Fi sync.
class LanSyncStatus {
  const LanSyncStatus({
    this.state = 'off',
    this.peerName,
    this.peerAddress,
    this.lastSyncAt,
    this.error,
    this.lastSummary,
  });

  /// off | searching | syncing | connected | error
  final String state;
  final String? peerName;
  final String? peerAddress;
  final DateTime? lastSyncAt;
  final String? error;
  final String? lastSummary;

  LanSyncStatus copyWith({
    String? state,
    String? peerName,
    String? peerAddress,
    DateTime? lastSyncAt,
    String? error,
    bool clearError = false,
    String? lastSummary,
  }) {
    return LanSyncStatus(
      state: state ?? this.state,
      peerName: peerName ?? this.peerName,
      peerAddress: peerAddress ?? this.peerAddress,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      error: clearError ? null : error ?? this.error,
      lastSummary: lastSummary ?? this.lastSummary,
    );
  }
}

class _Peer {
  _Peer(this.id, this.name, this.address, this.port, this.isMain, this.seenAt);

  final String id;
  final String name;
  final String address;
  final int port;
  final bool isMain;
  final DateTime seenAt;
}

/// Automatic sync between the phones of one shop while they are on the same
/// Wi-Fi (or one phone's hotspot) and the app is open.
///
/// The owner's phone (main) runs a small server and announces itself with an
/// encrypted UDP beacon. Employee phones hear it, then every few seconds
/// when something changed (and at least once a minute) they receive the
/// main phone's changes and send their own. Everything on the wire is
/// AES-256-GCM encrypted with the shop code; a phone that does not know the
/// code cannot read, send or even be recognised.
class LanSyncService {
  LanSyncService(this._db, this._sync);

  final AppDatabase _db;
  final FileSyncService _sync;

  static const int tcpPort = 48484;
  static const int udpPort = 48485;
  static const int _maxBody = 64 * 1024 * 1024;

  final ValueNotifier<LanSyncStatus> status = ValueNotifier(const LanSyncStatus());

  /// Bumped whenever a sync changed local data (screens may reload).
  final ValueNotifier<int> dataVersion = ValueNotifier(0);

  Timer? _timer;
  HttpServer? _server;
  RawDatagramSocket? _udp;
  Uint8List? _key;
  String? _keyCode;
  bool _busy = false;
  DateTime? _lastAttempt;
  String? _manualPeerId;
  final Map<String, _Peer> _peers = {};
  String _myId = '';
  String _myName = '';
  bool _myMain = false;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _tick());
    _tick();
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await _stopNetwork();
  }

  // ------------------------------------------------------------------- tick

  Future<void> _tick() async {
    if (_busy) return;
    try {
      final s = await _sync.settings();
      _myId = s.deviceId ?? '';
      _myName = s.storeName;
      _myMain = s.isMainDevice;
      final code = s.syncCode;
      if (code == null || code.isEmpty || !s.autoSync) {
        await _stopNetwork();
        _setStatus(const LanSyncStatus(state: 'off'));
        return;
      }
      if (_key == null || _keyCode != code) {
        _key = await SyncCrypto.deriveKey(code);
        _keyCode = code;
      }
      final key = _key!;

      await _ensureUdp(key);
      if (s.isMainDevice) {
        await _ensureServer();
      } else {
        await _stopServer();
      }
      _broadcast(key);

      if (s.isMainDevice) {
        final others = _livePeers().where((p) => p.isMain).toList();
        _setStatus(status.value.copyWith(
          state: 'connected',
          peerName: null,
          error: others.isEmpty
              ? null
              : 'two-main',
          clearError: others.isEmpty,
        ));
        return;
      }
      await _employeeTick(s, key);
    } catch (e) {
      _setStatus(status.value.copyWith(state: 'error', error: '$e'));
    }
  }

  List<_Peer> _livePeers() {
    final limit = DateTime.now().subtract(const Duration(seconds: 30));
    _peers.removeWhere((_, p) => p.seenAt.isBefore(limit));
    return _peers.values.toList();
  }

  Future<void> _employeeTick(AppSetting s, Uint8List key) async {
    _Peer? hub;
    for (final p in _livePeers()) {
      if (p.isMain && (hub == null || p.seenAt.isAfter(hub.seenAt))) hub = p;
    }
    final manual = (s.hubAddress ?? '').trim();
    final address = hub?.address ?? (manual.isEmpty ? null : manual);
    if (address == null) {
      _setStatus(status.value.copyWith(state: 'searching', clearError: true));
      return;
    }
    final port = hub?.port ?? tcpPort;
    final hubId = hub?.id ?? _manualPeerId;

    final peerRow = hubId == null
        ? null
        : await (_db.select(_db.syncPeers)..where((t) => t.deviceId.equals(hubId))).getSingleOrNull();

    final due = _lastAttempt == null ||
        DateTime.now().difference(_lastAttempt!) >= const Duration(seconds: 60) ||
        await _hasPendingChanges(peerRow?.lastPushAt);
    if (!due) {
      _setStatus(status.value.copyWith(
        state: 'connected',
        peerName: hub?.name ?? status.value.peerName,
        peerAddress: address,
        clearError: true,
      ));
      return;
    }
    await _syncWith(address, port, key, hubId, hub?.name);
  }

  Future<bool> _hasPendingChanges(DateTime? lastPush) async {
    if (lastPush == null) return true;
    final rows = await _db.customSelect(
      'SELECT (SELECT COUNT(*) FROM sales WHERE changed_at > ?1) + '
      '(SELECT COUNT(*) FROM stock_movements WHERE changed_at > ?1) + '
      '(SELECT COUNT(*) FROM products WHERE changed_at > ?1) AS c',
      variables: [Variable<DateTime>(lastPush)],
    ).get();
    return (rows.first.read<int>('c')) > 0;
  }

  void _setStatus(LanSyncStatus next) {
    status.value = next;
  }

  // ----------------------------------------------------------- employee side

  /// Runs a sync right now. Returns an error code or null on success.
  Future<String?> syncNow() async {
    if (_busy) return null;
    final s = await _sync.settings();
    if (s.syncCode == null || s.syncCode!.isEmpty) return 'NO_SYNC_CODE';
    if (s.isMainDevice) return 'IS_MAIN';
    final key = await _sync.key();
    _key = key;
    _keyCode = s.syncCode;
    _myId = s.deviceId ?? '';
    _Peer? hub;
    for (final p in _livePeers()) {
      if (p.isMain) hub = p;
    }
    final manual = (s.hubAddress ?? '').trim();
    final address = hub?.address ?? (manual.isEmpty ? null : manual);
    if (address == null) return 'NO_HUB';
    return _syncWith(address, hub?.port ?? tcpPort, key, hub?.id ?? _manualPeerId, hub?.name);
  }

  Future<String?> _syncWith(String address, int port, Uint8List key, String? hubId, String? hubName) async {
    _busy = true;
    _lastAttempt = DateTime.now();
    _setStatus(status.value.copyWith(state: 'syncing', peerAddress: address, clearError: true));
    try {
      var peerRow = hubId == null
          ? null
          : await (_db.select(_db.syncPeers)..where((t) => t.deviceId.equals(hubId))).getSingleOrNull();

      // 1) receive what the main phone has
      final pullAt = DateTime.now();
      final pulled = await _post(address, port, '/sync/pull', key, {
        'since': peerRow?.lastPullAt == null ? null : peerRow!.lastPullAt!.toUtc().toIso8601String(),
      });
      final package = pulled['package'] as Map<String, dynamic>;
      final serverTime = DateTime.tryParse('${pulled['serverTime']}')?.toLocal() ?? pullAt;
      final realHubId = '${package['deviceId'] ?? hubId ?? address}';
      _manualPeerId = realHubId;
      final name = '${package['storeName'] ?? hubName ?? ''}';
      peerRow ??= await (_db.select(_db.syncPeers)..where((t) => t.deviceId.equals(realHubId)))
          .getSingleOrNull();
      final result = await _sync.importPackage(package);
      await _savePeer(realHubId, name, lastPullAt: serverTime);

      // 2) send what this phone has (built after the import so that linked
      // products already carry the main phone's ids)
      final pushAt = DateTime.now();
      final outgoing = await _sync.buildPackage(since: peerRow?.lastPushAt);
      await _post(address, port, '/sync/push', key, {'package': outgoing});
      await _savePeer(realHubId, name, lastPushAt: pushAt, lastSyncAt: DateTime.now());

      if (result.changedAnything) dataVersion.value++;
      final summary = StringBuffer()
        ..write('${result.newSales}|${result.newProducts + result.updatedProducts}|${result.appliedMovements}');
      _setStatus(LanSyncStatus(
        state: 'connected',
        peerName: name,
        peerAddress: address,
        lastSyncAt: DateTime.now(),
        lastSummary: summary.toString(),
      ));
      return null;
    } on SocketException {
      _setStatus(status.value.copyWith(state: 'error', error: 'UNREACHABLE'));
      return 'UNREACHABLE';
    } on TimeoutException {
      _setStatus(status.value.copyWith(state: 'error', error: 'UNREACHABLE'));
      return 'UNREACHABLE';
    } on _SyncHttpError catch (e) {
      _setStatus(status.value.copyWith(state: 'error', error: e.code));
      return e.code;
    } catch (e) {
      _setStatus(status.value.copyWith(state: 'error', error: '$e'));
      return '$e';
    } finally {
      _busy = false;
    }
  }

  Future<void> _savePeer(
    String id,
    String name, {
    DateTime? lastPullAt,
    DateTime? lastPushAt,
    DateTime? lastSyncAt,
  }) async {
    final existing =
        await (_db.select(_db.syncPeers)..where((t) => t.deviceId.equals(id))).getSingleOrNull();
    if (existing == null) {
      await _db.into(_db.syncPeers).insert(
            SyncPeersCompanion.insert(
              deviceId: id,
              name: Value(name),
              lastPullAt: Value(lastPullAt),
              lastPushAt: Value(lastPushAt),
              lastSyncAt: Value(lastSyncAt),
            ),
          );
    } else {
      await (_db.update(_db.syncPeers)..where((t) => t.deviceId.equals(id))).write(
        SyncPeersCompanion(
          name: Value(name),
          lastPullAt: lastPullAt == null ? const Value.absent() : Value(lastPullAt),
          lastPushAt: lastPushAt == null ? const Value.absent() : Value(lastPushAt),
          lastSyncAt: lastSyncAt == null ? const Value.absent() : Value(lastSyncAt),
        ),
      );
    }
  }

  /// Forget what was exchanged with the main phone: the next sync sends and
  /// receives everything again (safe, nothing is duplicated).
  Future<void> resetPeers() async {
    await _db.delete(_db.syncPeers).go();
    _manualPeerId = null;
    _lastAttempt = null;
  }

  // ------------------------------------------------------------ wire format

  static Future<Uint8List> _seal(Map<String, dynamic> message, Uint8List key) {
    final json = utf8.encode(jsonEncode(message));
    return Isolate.run(
      () => SyncCrypto.encryptSync(Uint8List.fromList(gzip.encode(json)), key),
    );
  }

  static Future<Map<String, dynamic>> _open(Uint8List blob, Uint8List key) async {
    final plain = await Isolate.run(
      () => Uint8List.fromList(gzip.decode(SyncCrypto.decryptSync(blob, key))),
    );
    return jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _post(
    String address,
    int port,
    String path,
    Uint8List key,
    Map<String, dynamic> body,
  ) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final request = await client
          .postUrl(Uri.parse('http://$address:$port$path'))
          .timeout(const Duration(seconds: 8));
      request.headers.contentType = ContentType.binary;
      final payload = await _seal({
        ...body,
        'ts': DateTime.now().toUtc().toIso8601String(),
        'deviceId': _myId,
      }, key);
      request.contentLength = payload.length;
      request.add(payload);
      final response = await request.close().timeout(const Duration(seconds: 30));
      final bytes = BytesBuilder();
      await for (final chunk in response.timeout(const Duration(seconds: 120))) {
        bytes.add(chunk);
        if (bytes.length > _maxBody) throw const _SyncHttpError('TOO_BIG');
      }
      if (response.statusCode == 403) throw const _SyncHttpError('WRONG_CODE');
      if (response.statusCode == 408) throw const _SyncHttpError('CLOCK');
      if (response.statusCode != 200) throw _SyncHttpError('HTTP_${response.statusCode}');
      try {
        return await _open(bytes.toBytes(), key);
      } on SyncDecryptException {
        throw const _SyncHttpError('WRONG_CODE');
      }
    } finally {
      client.close(force: true);
    }
  }

  // ------------------------------------------------------------ main phone

  Future<void> _ensureServer() async {
    if (_server != null) return;
    try {
      final server = await HttpServer.bind(InternetAddress.anyIPv4, tcpPort, shared: true);
      _server = server;
      server.listen(
        _handle,
        onError: (_) => _server = null,
        onDone: () => _server = null,
      );
    } catch (_) {
      _server = null;
      rethrow;
    }
  }

  Future<void> _stopServer() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    Future<void> reply(int code, [Uint8List? body]) async {
      response.statusCode = code;
      if (body != null) {
        response.headers.contentType = ContentType.binary;
        response.contentLength = body.length;
        response.add(body);
      }
      await response.close();
    }

    try {
      final key = _key;
      if (key == null || request.method != 'POST') return reply(405);
      if (request.contentLength > _maxBody) return reply(413);

      final builder = BytesBuilder();
      await for (final chunk in request) {
        builder.add(chunk);
        if (builder.length > _maxBody) return reply(413);
      }

      final Map<String, dynamic> message;
      try {
        message = await _open(builder.toBytes(), key);
      } catch (_) {
        return reply(403);
      }
      final ts = DateTime.tryParse('${message['ts']}');
      if (ts == null || DateTime.now().toUtc().difference(ts.toUtc()).abs() > const Duration(minutes: 15)) {
        return reply(408);
      }

      switch (request.uri.path) {
        case '/sync/pull':
          final serverTime = DateTime.now();
          final sinceRaw = message['since'];
          final since = sinceRaw == null ? null : DateTime.tryParse('$sinceRaw')?.toLocal();
          final package = await _sync.buildPackage(since: since);
          return reply(
            200,
            await _seal({
              'ts': DateTime.now().toUtc().toIso8601String(),
              'serverTime': serverTime.toUtc().toIso8601String(),
              'package': package,
            }, key),
          );
        case '/sync/push':
          final result = await _sync.importPackage(message['package'] as Map<String, dynamic>);
          if (result.changedAnything) dataVersion.value++;
          return reply(
            200,
            await _seal({
              'ts': DateTime.now().toUtc().toIso8601String(),
              'ok': true,
            }, key),
          );
        default:
          return reply(404);
      }
    } catch (_) {
      try {
        await reply(500);
      } catch (_) {}
    }
  }

  // -------------------------------------------------------------- discovery

  Future<void> _ensureUdp(Uint8List key) async {
    if (_udp != null) return;
    try {
      RawDatagramSocket socket;
      try {
        socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, udpPort,
            reuseAddress: true, reusePort: true);
      } catch (_) {
        socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, udpPort, reuseAddress: true);
      }
      socket.broadcastEnabled = true;
      socket.listen(
        (event) {
          if (event != RawSocketEvent.read) return;
          final datagram = socket.receive();
          if (datagram == null) return;
          _onBeacon(datagram, key);
        },
        onError: (_) => _udp = null,
        onDone: () => _udp = null,
      );
      _udp = socket;
    } catch (_) {
      _udp = null;
    }
  }

  void _onBeacon(Datagram datagram, Uint8List key) {
    try {
      final plain = SyncCrypto.decryptSync(datagram.data, key);
      final msg = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
      final id = '${msg['id']}';
      if (id.isEmpty || id == _myId) return;
      _peers[id] = _Peer(
        id,
        '${msg['n'] ?? ''}',
        datagram.address.address,
        (msg['port'] as num?)?.toInt() ?? tcpPort,
        msg['main'] == true,
        DateTime.now(),
      );
    } catch (_) {
      // Not for us (other shop, other app, noise).
    }
  }

  Future<void> _broadcast(Uint8List key) async {
    final socket = _udp;
    if (socket == null) return;
    try {
      final payload = SyncCrypto.encryptSync(
        Uint8List.fromList(utf8.encode(jsonEncode({
          'id': _myId,
          'n': _myName,
          'main': _myMain,
          'port': tcpPort,
        }))),
        key,
      );
      final targets = <String>{'255.255.255.255'};
      for (final address in await localAddresses()) {
        final parts = address.split('.');
        if (parts.length == 4) targets.add('${parts[0]}.${parts[1]}.${parts[2]}.255');
      }
      for (final target in targets) {
        try {
          socket.send(payload, InternetAddress(target), udpPort);
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// This phone's address(es) on the local network.
  Future<List<String>> localAddresses() async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      return [
        for (final i in interfaces)
          for (final a in i.addresses)
            if (!a.isLoopback) a.address,
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _stopNetwork() async {
    await _stopServer();
    _udp?.close();
    _udp = null;
    _peers.clear();
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _udp?.close();
    _server?.close(force: true);
  }
}

class _SyncHttpError implements Exception {
  const _SyncHttpError(this.code);
  final String code;
}
