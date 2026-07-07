import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import '../models/download_item.dart';

class MagnetInfo {
  final String hash;
  final String? displayName;
  final List<String> trackers;

  MagnetInfo({
    required this.hash,
    this.displayName,
    this.trackers = const [],
  });
}

class TorrentMetaResult {
  final String name;
  final int totalSize;
  final int fileCount;
  final List<String> fileNames;
  final List<int> fileSizes;
  final Uint8List metadata;

  TorrentMetaResult({
    required this.name,
    required this.totalSize,
    required this.fileCount,
    required this.fileNames,
    required this.fileSizes,
    required this.metadata,
  });
}

class TorrentProgress {
  final double progress;
  final int downloadedBytes;
  final int totalBytes;
  final double downloadSpeed;
  final double uploadSpeed;
  final int etaSeconds;
  final int seeders;
  final int peers;

  TorrentProgress({
    required this.progress,
    required this.downloadedBytes,
    required this.totalBytes,
    required this.downloadSpeed,
    required this.uploadSpeed,
    required this.etaSeconds,
    required this.seeders,
    required this.peers,
  });
}

class TorrentDownloadService {
  static final TorrentDownloadService _instance = TorrentDownloadService._internal();
  factory TorrentDownloadService() => _instance;
  TorrentDownloadService._internal();

  final Map<String, TorrentTask> _tasks = {};
  final Map<String, Timer> _pollers = {};
  final Map<String, void Function(TorrentProgress)> _progressListeners = {};
  final Map<String, void Function()> _completionListeners = {};
  final Map<String, void Function(String)> _errorListeners = {};
  final Map<String, Uint8List> _metadataCache = {};

  // Proxy settings are stored for future use by the torrent engine
  // ignore: unused_field
  bool _proxyEnabled = false;
  // ignore: unused_field
  String? _proxyHost;
  // ignore: unused_field
  int? _proxyPort;
  // ignore: unused_field
  String? _proxyUser;
  // ignore: unused_field
  String? _proxyPass;

  void setProxySettings({
    required String host,
    required int port,
    String? username,
    String? password,
  }) {
    _proxyEnabled = true;
    _proxyHost = host;
    _proxyPort = port;
    _proxyUser = username;
    _proxyPass = password;
  }

  MagnetInfo parseMagnet(String magnet) {
    final magnetData = MagnetParser.parse(magnet);
    if (magnetData == null) {
      throw FormatException('Invalid magnet link');
    }
    final xtMatch = RegExp(r'xt=urn:btih:([^&]+)').firstMatch(magnet);
    final hash = xtMatch?.group(1) ?? '';
    final dnMatch = RegExp(r'dn=([^&]+)').firstMatch(magnet);
    final displayName = dnMatch != null ? Uri.decodeComponent(dnMatch.group(1)!) : null;
    final trMatches = RegExp(r'tr=([^&]+)').allMatches(magnet);
    final trackers = trMatches.map((m) => Uri.decodeComponent(m.group(1)!)).toList();
    debugPrint('[TorrentDownloadService] Parsed magnet: hash=$hash displayName=$displayName trackers=${trackers.length}');
    return MagnetInfo(
      hash: hash,
      displayName: displayName ?? magnetData.infoHashString,
      trackers: trackers,
    );
  }

  Future<TorrentMetaResult> fetchMetadata(
    String magnet, {
    void Function(String status)? onStatus,
  }) async {
    const int maxRetries = 3;
    const Duration perAttemptTimeout = Duration(seconds: 120);
    String? lastError;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      debugPrint('[TorrentDownloadService] Metadata attempt $attempt/$maxRetries');
      onStatus?.call('Initializing torrent engine (attempt $attempt/$maxRetries)...');

      try {
        final result = await _fetchMetadataSingle(magnet,
            onStatus: onStatus, timeout: perAttemptTimeout);

        debugPrint('[TorrentDownloadService] Metadata fetch succeeded on attempt $attempt');
        _metadataCache[magnet] = result.metadata;
        return result;
      } catch (e) {
        lastError = e.toString();
        debugPrint('[TorrentDownloadService] Metadata attempt $attempt failed: $e');

        if (attempt < maxRetries) {
          final wait = attempt * 3;
          debugPrint('[TorrentDownloadService] Waiting ${wait}s before retry...');
          onStatus?.call('Retrying in ${wait}s (attempt $attempt/$maxRetries)...');
          await Future.delayed(Duration(seconds: wait));
        }
      }
    }

    debugPrint('[TorrentDownloadService] All $maxRetries metadata attempts failed');
    final friendly = _friendlyError(lastError);
    throw TorrentMetadataException(friendly);
  }

  Future<TorrentMetaResult> _fetchMetadataSingle(
    String magnet, {
    void Function(String status)? onStatus,
    required Duration timeout,
  }) async {
    final metadataDownloader = MetadataDownloader.fromMagnet(magnet);
    final completer = Completer<Uint8List>();
    final statusTimer = _startStatusSimulator(onStatus);

    metadataDownloader.events.on<MetaDataDownloadComplete>((event) {
      debugPrint('[TorrentDownloadService] MetaDataDownloadComplete received: ${event.data.length} bytes');
      if (!completer.isCompleted) {
        completer.complete(Uint8List.fromList(event.data));
      }
    });

    metadataDownloader.events.on<MetaDataDownloadFailed>((event) {
      debugPrint('[TorrentDownloadService] MetaDataDownloadFailed: ${event.error}');
      if (!completer.isCompleted) {
        completer.completeError(event.error);
      }
    });

    try {
      debugPrint('[TorrentDownloadService] Starting MetadataDownloader...');
      onStatus?.call('Connecting to DHT...');
      await metadataDownloader.startDownload();

      onStatus?.call('Contacting trackers...');
      debugPrint('[TorrentDownloadService] Waiting for metadata (timeout: ${timeout.inSeconds}s)...');
      final data = await completer.future.timeout(
        timeout,
        onTimeout: () {
          debugPrint('[TorrentDownloadService] Timeout reached after ${timeout.inSeconds}s');
          metadataDownloader.stop();
          throw TimeoutException('No peers found. Metadata download timed out after ${timeout.inSeconds} seconds.');
        },
      );

      final model = TorrentParser.parseBytes(data);
      final fileNames = model.files.map((f) => f.name).toList();
      final fileSizes = model.files.map((f) => f.length).toList();
      final totalSize = model.files.fold<int>(0, (sum, f) => sum + f.length);

      debugPrint('[TorrentDownloadService] Metadata parsed: name="${model.name}" files=${model.files.length} totalSize=$totalSize');

      return TorrentMetaResult(
        name: model.name,
        totalSize: totalSize,
        fileCount: model.files.length,
        fileNames: fileNames,
        fileSizes: fileSizes,
        metadata: data,
      );
    } finally {
      statusTimer.cancel();
    }
  }

  Timer _startStatusSimulator(void Function(String status)? onStatus) {
    const messages = [
      'Connecting to DHT...',
      'Contacting trackers...',
      'Searching for peers...',
      'Downloading metadata...',
    ];
    int index = 0;
    onStatus?.call(messages[0]);
    return Timer.periodic(const Duration(seconds: 5), (timer) {
      index = (index + 1) % messages.length;
      onStatus?.call(messages[index]);
    });
  }

  String _friendlyError(String? raw) {
    if (raw == null) return 'Failed to fetch torrent metadata.';
    final lower = raw.toLowerCase();
    if (lower.contains('timeout') || lower.contains('timed out')) {
      return 'No peers found. Please try again later or use another magnet link.';
    }
    if (lower.contains('dht') || lower.contains('tracker')) {
      return 'Could not reach the torrent network. Check your internet connection and proxy settings.';
    }
    if (lower.contains('invalid') || lower.contains('parse') || lower.contains('format')) {
      return 'The magnet link appears to be invalid. Please check and try again.';
    }
    return 'Failed to fetch torrent metadata: ${raw.length > 100 ? raw.substring(0, 100) : raw}';
  }

  Uint8List? getCachedMetadata(String magnet) => _metadataCache[magnet];

  Future<void> startDownload(
    DownloadItem item, {
    Uint8List? metadata,
  }) async {
    if (item.downloadType != DownloadType.torrent) return;

    final magnet = item.url;
    final Uint8List metaBytes;
    if (metadata != null) {
      metaBytes = metadata;
    } else {
      metaBytes = _metadataCache[magnet] ?? await fetchMetadata(magnet).then((r) => r.metadata);
    }

    final model = TorrentParser.parseBytes(metaBytes);
    final task = TorrentTask.newTask(
      model,
      item.savePath,
      false,
    );

    _tasks[item.id] = task;

    task.events.on<TaskCompleted>((event) {
      _completionListeners[item.id]?.call();
    });

    await task.start();
    _startPolling(item.id);
  }

  void _startPolling(String id) {
    _pollers[id]?.cancel();
    _pollers[id] = Timer.periodic(const Duration(seconds: 1), (timer) {
      final task = _tasks[id];
      if (task == null) {
        timer.cancel();
        return;
      }

      final progress = task.progress;
      final dlSpeed = task.currentDownloadSpeed;
      final ulSpeed = task.uploadSpeed;
      final total = task.metaInfo.files.fold<int>(0, (s, f) => s + f.length);
      final downloaded = (progress * total).toInt();
      final remaining = total - downloaded;
      final eta = dlSpeed > 0 ? (remaining / dlSpeed).round() : 0;

      int seeders = 0;
      int peers = 0;
      try {
        final activePeers = task.activePeers;
        if (activePeers != null) {
          seeders = activePeers.length;
        }
      } catch (_) {}

      _progressListeners[id]?.call(TorrentProgress(
        progress: progress,
        downloadedBytes: downloaded,
        totalBytes: total,
        downloadSpeed: dlSpeed.toDouble(),
        uploadSpeed: ulSpeed.toDouble(),
        etaSeconds: eta,
        seeders: seeders,
        peers: peers,
      ));

      if (progress >= 1.0) {
        timer.cancel();
      }
    });
  }

  void onProgress(String id, void Function(TorrentProgress) callback) {
    _progressListeners[id] = callback;
  }

  void onComplete(String id, void Function() callback) {
    _completionListeners[id] = callback;
  }

  void onError(String id, void Function(String) callback) {
    _errorListeners[id] = callback;
  }

  void pause(String id) {
    _pollers[id]?.cancel();
    final task = _tasks[id];
    if (task != null) {
      task.pause();
    }
  }

  Future<void> resume(String id) async {
    final task = _tasks[id];
    if (task != null) {
      task.resume();
      _startPolling(id);
    }
  }

  void stop(String id) {
    _pollers[id]?.cancel();
    _pollers.remove(id);
    final task = _tasks[id];
    if (task != null) {
      task.stop();
      _tasks.remove(id);
    }
    _progressListeners.remove(id);
    _completionListeners.remove(id);
    _errorListeners.remove(id);
  }

  TorrentTask? getTask(String id) => _tasks[id];

  void dispose() {
    for (final timer in _pollers.values) {
      timer.cancel();
    }
    _pollers.clear();
    for (final task in _tasks.values) {
      task.stop();
    }
    _tasks.clear();
    _progressListeners.clear();
    _completionListeners.clear();
    _errorListeners.clear();
  }
}

class TorrentMetadataException implements Exception {
  final String message;
  TorrentMetadataException(this.message);

  @override
  String toString() => message;
}
