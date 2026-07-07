export 'dart:collection';

enum DownloadStatus { queued, downloading, paused, error, done }

enum DownloadType { http, torrent }

class DownloadItem {
  final String id;
  final String url;
  final String fileName;
  String savePath;
  String? batchId;
  String? batchName;
  DownloadStatus status;
  DownloadType downloadType;
  int totalBytes;
  int downloadedBytes;
  double speedBytesPerSec;
  int etaSeconds;
  int retryCount;
  String? errorMessage;
  DateTime addedAt;

  // Torrent-specific fields
  String? torrentHash;
  String? torrentDisplayName;
  String? torrentTrackers;
  int torrentSeeders;
  int torrentPeers;
  double uploadSpeedBytesPerSec;
  List<int> selectedFileIndices;

  DownloadItem({
    required this.id,
    required this.url,
    required this.fileName,
    required this.savePath,
    this.batchId,
    this.batchName,
    this.status = DownloadStatus.queued,
    this.downloadType = DownloadType.http,
    this.totalBytes = 0,
    this.downloadedBytes = 0,
    this.speedBytesPerSec = 0,
    this.etaSeconds = 0,
    this.retryCount = 0,
    this.errorMessage,
    this.torrentHash,
    this.torrentDisplayName,
    this.torrentTrackers,
    this.torrentSeeders = 0,
    this.torrentPeers = 0,
    this.uploadSpeedBytesPerSec = 0,
    this.selectedFileIndices = const [],
    DateTime? addedAt,
  }) : addedAt = addedAt ?? DateTime.now();

  double get progress =>
      totalBytes > 0 ? (downloadedBytes / totalBytes).clamp(0.0, 1.0) : 0.0;

  String get statusLabel {
    switch (status) {
      case DownloadStatus.queued:
        return 'Queued';
      case DownloadStatus.downloading:
        return 'Downloading';
      case DownloadStatus.paused:
        return 'Paused';
      case DownloadStatus.error:
        return 'Error';
      case DownloadStatus.done:
        return 'Done';
    }
  }

  bool get isTorrent => downloadType == DownloadType.torrent;

  DownloadItem copyWith({
    DownloadStatus? status,
    DownloadType? downloadType,
    int? totalBytes,
    int? downloadedBytes,
    double? speedBytesPerSec,
    int? etaSeconds,
    int? retryCount,
    String? errorMessage,
    String? torrentHash,
    String? torrentDisplayName,
    String? torrentTrackers,
    int? torrentSeeders,
    int? torrentPeers,
    double? uploadSpeedBytesPerSec,
    List<int>? selectedFileIndices,
  }) =>
      DownloadItem(
        id: id,
        url: url,
        fileName: fileName,
        savePath: savePath,
        batchId: batchId,
        batchName: batchName,
        status: status ?? this.status,
        downloadType: downloadType ?? this.downloadType,
        totalBytes: totalBytes ?? this.totalBytes,
        downloadedBytes: downloadedBytes ?? this.downloadedBytes,
        speedBytesPerSec: speedBytesPerSec ?? this.speedBytesPerSec,
        etaSeconds: etaSeconds ?? this.etaSeconds,
        retryCount: retryCount ?? this.retryCount,
        errorMessage: errorMessage ?? this.errorMessage,
        torrentHash: torrentHash ?? this.torrentHash,
        torrentDisplayName: torrentDisplayName ?? this.torrentDisplayName,
        torrentTrackers: torrentTrackers ?? this.torrentTrackers,
        torrentSeeders: torrentSeeders ?? this.torrentSeeders,
        torrentPeers: torrentPeers ?? this.torrentPeers,
        uploadSpeedBytesPerSec: uploadSpeedBytesPerSec ?? this.uploadSpeedBytesPerSec,
        selectedFileIndices: selectedFileIndices ?? this.selectedFileIndices,
        addedAt: addedAt,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'url': url,
    'fileName': fileName,
    'savePath': savePath,
    'batchId': batchId,
    'batchName': batchName,
    'status': status.index,
    'downloadType': downloadType.index,
    'totalBytes': totalBytes,
    'downloadedBytes': downloadedBytes,
    'retryCount': retryCount,
    'errorMessage': errorMessage,
    'addedAt': addedAt.toIso8601String(),
    'torrentHash': torrentHash,
    'torrentDisplayName': torrentDisplayName,
    'torrentTrackers': torrentTrackers,
    'torrentSeeders': torrentSeeders,
    'torrentPeers': torrentPeers,
    'uploadSpeedBytesPerSec': uploadSpeedBytesPerSec,
    'selectedFileIndices': selectedFileIndices.join(','),
  };

  factory DownloadItem.fromJson(Map<String, dynamic> json) {
    final selStr = json['selectedFileIndices'] as String?;
    return DownloadItem(
      id: json['id'],
      url: json['url'],
      fileName: json['fileName'],
      savePath: json['savePath'],
      batchId: json['batchId'],
      batchName: json['batchName'],
      status: DownloadStatus.values[json['status'] ?? 0],
      downloadType: json['downloadType'] != null
          ? DownloadType.values[json['downloadType']]
          : DownloadType.http,
      totalBytes: json['totalBytes'] ?? 0,
      downloadedBytes: json['downloadedBytes'] ?? 0,
      retryCount: json['retryCount'] ?? 0,
      errorMessage: json['errorMessage'],
      addedAt: json['addedAt'] != null ? DateTime.parse(json['addedAt']) : null,
      torrentHash: json['torrentHash'],
      torrentDisplayName: json['torrentDisplayName'],
      torrentTrackers: json['torrentTrackers'],
      torrentSeeders: json['torrentSeeders'] ?? 0,
      torrentPeers: json['torrentPeers'] ?? 0,
      uploadSpeedBytesPerSec: (json['uploadSpeedBytesPerSec'] ?? 0).toDouble(),
      selectedFileIndices: selStr != null && selStr.isNotEmpty
          ? selStr.split(',').map((e) => int.tryParse(e) ?? 0).toList()
          : [],
    );
  }
}
