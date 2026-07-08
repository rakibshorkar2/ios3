import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/torrent_task_model.dart';

class NativeTorrentUpdate {
  final String id;
  final String name;
  final String infoHash;
  final TorrentTaskState state;
  final double progress;
  final int downloadedBytes;
  final int totalBytes;
  final double downloadSpeed;
  final double uploadSpeed;
  final double averageDownloadSpeed;
  final double averageUploadSpeed;
  final int eta;
  final int peers;
  final int seeds;
  final int allPeers;
  final int piecesCompleted;
  final int totalPieces;
  final List<String> trackers;
  final List<int> selectedFileIndices;
  final bool isSequential;
  final String? errorMessage;
  final List<String> fileNames;
  final List<int> fileSizes;

  NativeTorrentUpdate({
    required this.id,
    required this.name,
    this.infoHash = '',
    required this.state,
    this.progress = 0,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.downloadSpeed = 0,
    this.uploadSpeed = 0,
    this.averageDownloadSpeed = 0,
    this.averageUploadSpeed = 0,
    this.eta = 0,
    this.peers = 0,
    this.seeds = 0,
    this.allPeers = 0,
    this.piecesCompleted = 0,
    this.totalPieces = 0,
    this.trackers = const [],
    this.selectedFileIndices = const [],
    this.isSequential = false,
    this.errorMessage,
    this.fileNames = const [],
    this.fileSizes = const [],
  });

  factory NativeTorrentUpdate.fromMap(Map<String, dynamic> map) {
    return NativeTorrentUpdate(
      id: map['id'] as String,
      name: map['name'] as String? ?? '',
      infoHash: map['infoHash'] as String? ?? '',
      state: TorrentTaskState.values[(map['state'] as int?) ?? 0],
      progress: (map['progress'] as num?)?.toDouble() ?? 0,
      downloadedBytes: (map['downloadedBytes'] as num?)?.toInt() ?? 0,
      totalBytes: (map['totalBytes'] as num?)?.toInt() ?? 0,
      downloadSpeed: (map['downloadSpeed'] as num?)?.toDouble() ?? 0,
      uploadSpeed: (map['uploadSpeed'] as num?)?.toDouble() ?? 0,
      averageDownloadSpeed: (map['averageDownloadSpeed'] as num?)?.toDouble() ?? 0,
      averageUploadSpeed: (map['averageUploadSpeed'] as num?)?.toDouble() ?? 0,
      eta: (map['eta'] as num?)?.toInt() ?? 0,
      peers: (map['peers'] as num?)?.toInt() ?? 0,
      seeds: (map['seeds'] as num?)?.toInt() ?? 0,
      allPeers: (map['allPeers'] as num?)?.toInt() ?? 0,
      piecesCompleted: (map['piecesCompleted'] as num?)?.toInt() ?? 0,
      totalPieces: (map['totalPieces'] as num?)?.toInt() ?? 0,
      trackers: (map['trackers'] as List<dynamic>?)?.cast<String>() ?? [],
      selectedFileIndices:
          (map['selectedFileIndices'] as List<dynamic>?)?.cast<int>() ?? [],
      isSequential: (map['isSequential'] as bool?) ?? false,
      errorMessage: map['errorMessage'] as String?,
      fileNames: (map['fileNames'] as List<dynamic>?)?.cast<String>() ?? [],
      fileSizes: (map['fileSizes'] as List<dynamic>?)?.cast<int>() ?? [],
    );
  }
}

class NativeTorrentEngineBridge {
  static const _methodChannel = MethodChannel('com.dirxplore/torrent');
  static const _eventChannel = EventChannel('com.dirxplore/torrent_events');

  static final NativeTorrentEngineBridge _instance =
      NativeTorrentEngineBridge._internal();
  factory NativeTorrentEngineBridge() => _instance;
  NativeTorrentEngineBridge._internal();

  bool _initialized = false;
  StreamSubscription? _eventSub;
  final StreamController<NativeTorrentUpdate> _updateController =
      StreamController<NativeTorrentUpdate>.broadcast();
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();

  Stream<NativeTorrentUpdate> get updates => _updateController.stream;
  Stream<String> get errors => _errorController.stream;

  bool get isAvailable => defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> initialize() async {
    if (!isAvailable || _initialized) return;
    try {
      await _methodChannel.invokeMethod('initializeEngine');
      _eventSub = _eventChannel.receiveBroadcastStream().listen(_handleEvent);
      _initialized = true;
      debugPrint('[NativeTorrent] Bridge initialized');
    } catch (e) {
      debugPrint('[NativeTorrent] Init failed: $e');
    }
  }

  Future<void> shutdown() async {
    if (!isAvailable || !_initialized) return;
    try {
      await _methodChannel.invokeMethod('shutdownEngine');
      await _eventSub?.cancel();
      _initialized = false;
      debugPrint('[NativeTorrent] Bridge shut down');
    } catch (e) {
      debugPrint('[NativeTorrent] Shutdown error: $e');
    }
  }

  Future<String?> addMagnet(String magnet, String savePath) async {
    if (!isAvailable) return null;
    try {
      final id = await _methodChannel.invokeMethod<String>('addMagnet', {
        'magnet': magnet,
        'savePath': savePath,
      });
      debugPrint('[NativeTorrent] Added magnet: $id');
      return id;
    } catch (e) {
      debugPrint('[NativeTorrent] addMagnet error: $e');
      return null;
    }
  }

  Future<String?> addTorrentFile(String path, String savePath) async {
    if (!isAvailable) return null;
    try {
      final id = await _methodChannel.invokeMethod<String>('addTorrentFile', {
        'path': path,
        'savePath': savePath,
      });
      debugPrint('[NativeTorrent] Added torrent file: $id');
      return id;
    } catch (e) {
      debugPrint('[NativeTorrent] addTorrentFile error: $e');
      return null;
    }
  }

  Future<void> pauseTorrent(String id) async {
    if (!isAvailable) return;
    try {
      await _methodChannel.invokeMethod('pauseTorrent', {'id': id});
    } catch (e) {
      debugPrint('[NativeTorrent] pauseTorrent error: $e');
    }
  }

  Future<void> resumeTorrent(String id) async {
    if (!isAvailable) return;
    try {
      await _methodChannel.invokeMethod('resumeTorrent', {'id': id});
    } catch (e) {
      debugPrint('[NativeTorrent] resumeTorrent error: $e');
    }
  }

  Future<void> removeTorrent(String id, {bool deleteFiles = false}) async {
    if (!isAvailable) return;
    try {
      await _methodChannel.invokeMethod('removeTorrent', {
        'id': id,
        'deleteFiles': deleteFiles,
      });
    } catch (e) {
      debugPrint('[NativeTorrent] removeTorrent error: $e');
    }
  }

  Future<List<Map<String, dynamic>>?> getTorrentList() async {
    if (!isAvailable) return null;
    try {
      final list =
          await _methodChannel.invokeMethod<List<dynamic>>('getTorrentList');
      return list?.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('[NativeTorrent] getTorrentList error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> getTorrentDetails(String id) async {
    if (!isAvailable) return null;
    try {
      return await _methodChannel
          .invokeMethod<Map<dynamic, dynamic>>('getTorrentDetails', {'id': id})
          .then((m) => m?.cast<String, dynamic>());
    } catch (e) {
      debugPrint('[NativeTorrent] getTorrentDetails error: $e');
      return null;
    }
  }

  Future<void> runDiagnostics() async {
    if (!isAvailable) return;
    try {
      debugPrint('[NativeTorrent] Starting integration diagnostics...');
      final result = await _methodChannel.invokeMethod<String>('runDiagnostics');
      debugPrint('[NativeTorrent] Diagnostics result: $result');
    } catch (e) {
      debugPrint('[NativeTorrent] Diagnostics error: $e');
    }
  }

  void _handleEvent(dynamic event) {
    if (event is! Map) return;
    final type = event['event'] as String?;

    switch (type) {
      case 'torrentUpdate':
        final torrent =
            NativeTorrentUpdate.fromMap(event['torrent'] as Map<String, dynamic>);
        _updateController.add(torrent);
        break;
      case 'error':
        final message = event['message'] as String? ?? 'Unknown native error';
        _errorController.add(message);
        break;
      case 'metadataProgress':
        debugPrint('[NativeTorrent] Metadata progress: ${event['progress']}');
        break;
      case 'metadataComplete':
        final torrent =
            NativeTorrentUpdate.fromMap(event['torrent'] as Map<String, dynamic>);
        _updateController.add(torrent);
        break;
      case 'debugLog':
        final data = event['data'] as Map<String, dynamic>?;
        if (data != null) {
          debugPrint('[NativeTorrent][Diagnostic] $data');
        }
        break;
    }
  }

  void dispose() {
    _eventSub?.cancel();
    _updateController.close();
    _errorController.close();
  }
}
