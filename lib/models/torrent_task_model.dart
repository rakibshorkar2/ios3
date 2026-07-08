import 'dart:typed_data';

enum TorrentTaskState { metadata, downloading, paused, seeding, completed, error }

class TorrentTaskModel {
  final String id;
  final String magnetLink;
  final String savePath;
  String name;
  String infoHash;
  TorrentTaskState state;
  double progress;
  int totalBytes;
  int downloadedBytes;
  double downloadSpeed;
  double uploadSpeed;
  double averageDownloadSpeed;
  double averageUploadSpeed;
  int etaSeconds;
  int seeders;
  int peers;
  int allPeers;
  int piecesCompleted;
  int totalPieces;
  List<String> trackers;
  List<int> selectedFileIndices;
  bool isSequential;
  String? errorMessage;
  DateTime addedAt;
  Uint8List? metadataBytes;
  List<String> filesCompleted;

  TorrentTaskModel({
    required this.id,
    required this.magnetLink,
    required this.savePath,
    this.name = '',
    this.infoHash = '',
    this.state = TorrentTaskState.metadata,
    this.progress = 0.0,
    this.totalBytes = 0,
    this.downloadedBytes = 0,
    this.downloadSpeed = 0,
    this.uploadSpeed = 0,
    this.averageDownloadSpeed = 0,
    this.averageUploadSpeed = 0,
    this.etaSeconds = 0,
    this.seeders = 0,
    this.peers = 0,
    this.allPeers = 0,
    this.piecesCompleted = 0,
    this.totalPieces = 0,
    this.trackers = const [],
    this.selectedFileIndices = const [],
    this.isSequential = false,
    this.errorMessage,
    DateTime? addedAt,
    this.metadataBytes,
    this.filesCompleted = const [],
  }) : addedAt = addedAt ?? DateTime.now();

  String get stateLabel {
    switch (state) {
      case TorrentTaskState.metadata:
        return 'Metadata';
      case TorrentTaskState.downloading:
        return 'Downloading';
      case TorrentTaskState.paused:
        return 'Paused';
      case TorrentTaskState.seeding:
        return 'Seeding';
      case TorrentTaskState.completed:
        return 'Completed';
      case TorrentTaskState.error:
        return 'Error';
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'magnetLink': magnetLink,
    'savePath': savePath,
    'name': name,
    'infoHash': infoHash,
    'state': state.index,
    'progress': progress,
    'totalBytes': totalBytes,
    'downloadedBytes': downloadedBytes,
    'downloadSpeed': downloadSpeed,
    'uploadSpeed': uploadSpeed,
    'averageDownloadSpeed': averageDownloadSpeed,
    'averageUploadSpeed': averageUploadSpeed,
    'etaSeconds': etaSeconds,
    'seeders': seeders,
    'peers': peers,
    'allPeers': allPeers,
    'piecesCompleted': piecesCompleted,
    'totalPieces': totalPieces,
    'trackers': trackers.join('||'),
    'selectedFileIndices': selectedFileIndices.join(','),
    'isSequential': isSequential ? 1 : 0,
    'errorMessage': errorMessage,
    'addedAt': addedAt.toIso8601String(),
    'filesCompleted': filesCompleted.join('||'),
  };

  factory TorrentTaskModel.fromJson(Map<String, dynamic> json) {
    final trStr = json['trackers'] as String?;
    final selStr = json['selectedFileIndices'] as String?;
    final fcStr = json['filesCompleted'] as String?;
    return TorrentTaskModel(
      id: json['id'],
      magnetLink: json['magnetLink'],
      savePath: json['savePath'],
      name: json['name'] ?? '',
      infoHash: json['infoHash'] ?? '',
      state: TorrentTaskState.values[json['state'] ?? 0],
      progress: (json['progress'] ?? 0.0).toDouble(),
      totalBytes: json['totalBytes'] ?? 0,
      downloadedBytes: json['downloadedBytes'] ?? 0,
      downloadSpeed: (json['downloadSpeed'] ?? 0).toDouble(),
      uploadSpeed: (json['uploadSpeed'] ?? 0).toDouble(),
      averageDownloadSpeed: (json['averageDownloadSpeed'] ?? 0).toDouble(),
      averageUploadSpeed: (json['averageUploadSpeed'] ?? 0).toDouble(),
      etaSeconds: json['etaSeconds'] ?? 0,
      seeders: json['seeders'] ?? 0,
      peers: json['peers'] ?? 0,
      allPeers: json['allPeers'] ?? 0,
      piecesCompleted: json['piecesCompleted'] ?? 0,
      totalPieces: json['totalPieces'] ?? 0,
      trackers: trStr != null && trStr.isNotEmpty ? trStr.split('||') : [],
      selectedFileIndices: selStr != null && selStr.isNotEmpty
          ? selStr.split(',').map((e) => int.tryParse(e) ?? 0).toList()
          : [],
      isSequential: (json['isSequential'] ?? 0) == 1,
      errorMessage: json['errorMessage'],
      addedAt: json['addedAt'] != null ? DateTime.parse(json['addedAt']) : null,
      filesCompleted: fcStr != null && fcStr.isNotEmpty ? fcStr.split('||') : [],
    );
  }
}
