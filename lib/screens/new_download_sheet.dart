import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:dio/dio.dart';
import 'dart:io';
import '../providers/download_provider.dart';
import '../providers/app_state.dart';
import '../services/dio_client.dart';
import '../services/haptic_service.dart';
import '../services/torrent_download_service.dart';

class NewDownloadSheet extends StatefulWidget {
  const NewDownloadSheet({super.key});

  @override
  State<NewDownloadSheet> createState() => _NewDownloadSheetState();
}

class _NewDownloadSheetState extends State<NewDownloadSheet> {
  final _urlController = TextEditingController();
  final _filenameController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  bool _infoFetched = false;
  int _fileSize = -1;
  String _fileType = '';
  bool _resumeSupported = false;
  String _detectedFileName = '';

  // Magnet-specific state
  bool _isMagnet = false;
  bool _fetchingMetadata = false;
  String _metadataStatus = '';
  TorrentMetaResult? _torrentMeta;
  String? _magnetHash;
  String? _magnetTrackers;
  final Set<int> _selectedFileIndices = {};

  @override
  void dispose() {
    _urlController.dispose();
    _filenameController.dispose();
    super.dispose();
  }

  bool _isMagnetLink(String url) {
    return url.trim().toLowerCase().startsWith('magnet:?');
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      _urlController.text = data.text!.trim();
      if (_infoFetched) {
        setState(() {
          _infoFetched = false;
          _error = null;
          _isMagnet = false;
          _torrentMeta = null;
          _metadataStatus = '';
        });
      }
    }
  }

  String? _validateUrl(String url) {
    if (url.isEmpty) return 'Please enter a URL';
    if (_isMagnetLink(url)) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      return 'Invalid URL format';
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return 'Only HTTP, HTTPS, and magnet links are supported';
    }
    return null;
  }

  String _fileNameFromUrl(String url) {
    final uri = Uri.parse(url);
    final path = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (path.isNotEmpty) {
      return path.last;
    }
    return 'download';
  }

  String _fileNameFromContentDisposition(String? disposition) {
    if (disposition == null) return '';
    final match = RegExp(
      r"filename\*?=(?:UTF-8''\s*)?([^;\s]+)",
    ).firstMatch(disposition);
    if (match != null) {
      return Uri.decodeComponent(
        match.group(1)!.trim().replaceAll(RegExp(r'^"|"$'), ''),
      );
    }
    return '';
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return 'Unknown';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }

  Future<bool> _tryHeadRequest(String url) async {
    try {
      final dio = DioClient().dio;
      final response = await dio.head(url);
      _parseHeaders(response.headers);
      return true;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.badResponse &&
          e.response?.statusCode == 405) {
        return false;
      }
      rethrow;
    }
  }

  Future<void> _tryGetFallback(String url) async {
    final dio = DioClient().dio;
    final response = await dio.get(
      url,
      options: Options(
        responseType: ResponseType.stream,
        followRedirects: true,
        headers: {'Range': 'bytes=0-0'},
      ),
    );
    _parseHeaders(response.headers);
    if (_fileSize <= 0) {
      final contentRange = response.headers.value(HttpHeaders.contentRangeHeader);
      if (contentRange != null) {
        final match = RegExp(r'/(\d+)$').firstMatch(contentRange);
        if (match != null) {
          _fileSize = int.tryParse(match.group(1)!) ?? -1;
        }
      }
    }
  }

  void _parseHeaders(Headers headers) {
    final contentLength = headers.value(HttpHeaders.contentLengthHeader);
    final contentType = headers.value(HttpHeaders.contentTypeHeader);
    final contentDisposition = headers.value('content-disposition');
    final acceptRanges = headers.value(HttpHeaders.acceptRangesHeader);

    _fileSize = int.tryParse(contentLength ?? '') ?? -1;
    _fileType = contentType?.split(';').first ?? 'Unknown';
    _resumeSupported = acceptRanges?.toLowerCase() == 'bytes';

    String fileName = _filenameController.text.trim();
    if (fileName.isEmpty) {
      fileName = _fileNameFromContentDisposition(contentDisposition);
    }
    if (fileName.isEmpty) {
      fileName = _fileNameFromUrl(_urlController.text.trim());
    }
    _detectedFileName = fileName;
  }

  Future<void> _fetchInfo() async {
    final url = _urlController.text.trim();
    final validationError = _validateUrl(url);
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }

    if (_isMagnetLink(url)) {
      await _handleMagnetLink(url);
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _infoFetched = false;
    });

    try {
      HapticService.medium();
      final headOk = await _tryHeadRequest(url);
      if (!headOk) {
        await _tryGetFallback(url);
      }

      if (_filenameController.text.trim().isNotEmpty) {
        _detectedFileName = _filenameController.text.trim();
      }
      if (_detectedFileName.isEmpty) {
        _detectedFileName = _fileNameFromUrl(url);
      }
      if (_filenameController.text.trim().isEmpty) {
        _filenameController.text = _detectedFileName;
      }

      if (!mounted) return;
      setState(() {
        _infoFetched = true;
        _isLoading = false;
      });
    } on DioException catch (e) {
      if (mounted) {
        setState(() {
          _error = _dioErrorToString(e);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to fetch file info: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleMagnetLink(String url) async {
    setState(() {
      _fetchingMetadata = true;
      _error = null;
      _isMagnet = true;
      _metadataStatus = 'Initializing torrent engine...';
    });

    try {
      HapticService.medium();
      final service = TorrentEngineService();
      final magnetInfo = service.parseMagnet(url);
      _magnetHash = magnetInfo.hash;
      _magnetTrackers = magnetInfo.trackers.join(', ');

      final meta = await service.fetchMetadata(url, onStatus: (status) {
        if (mounted) {
          setState(() => _metadataStatus = status);
        }
      });
      if (!mounted) return;

      setState(() {
        _torrentMeta = meta;
        _fetchingMetadata = false;
        _detectedFileName = meta.name;
        _filenameController.text = meta.name;
        _selectedFileIndices.clear();
        _selectedFileIndices.addAll(List.generate(meta.fileCount, (i) => i));
      });

      _showTorrentConfirmation();
    } on TorrentMetadataException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _fetchingMetadata = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to fetch torrent metadata: ${e.toString().length > 200 ? e.toString().substring(0, 200) : e}';
          _fetchingMetadata = false;
        });
      }
    }
  }

  bool _isSequential = false;

  void _showTorrentConfirmation() {
    final meta = _torrentMeta;
    if (meta == null) return;

    _isSequential = _isMediaTorrent(meta);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _TorrentConfirmSheet(
        meta: meta,
        magnetHash: _magnetHash ?? '',
        magnetTrackers: _magnetTrackers ?? '',
        selectedIndices: _selectedFileIndices.toList(),
        isSequential: _isSequential,
        onSelectionChanged: (indices) {
          _selectedFileIndices.clear();
          _selectedFileIndices.addAll(indices);
        },
        onSequentialChanged: (val) => _isSequential = val,
        onDownload: () => _startTorrentDownload(ctx),
      ),
    );
  }

  bool _isMediaTorrent(TorrentMetaResult meta) {
    const videoExts = ['mp4', 'mkv', 'avi', 'mov', 'webm', 'ts', 'm4v'];
    return meta.fileNames.any((f) {
      final ext = f.split('.').last.toLowerCase();
      return videoExts.contains(ext);
    });
  }

  Future<void> _startTorrentDownload(BuildContext dialogContext) async {
    final url = _urlController.text.trim();
    final fileName = _filenameController.text.trim();
    final meta = _torrentMeta;

    if (!mounted) return;
    final appState = context.read<AppState>();
    final dlProvider = context.read<DownloadProvider>();

    await dlProvider.addTorrentDownload(
      url,
      fileName,
      appState.defaultSavePath,
      torrentHash: _magnetHash,
      torrentDisplayName: meta?.name,
      torrentTrackers: _magnetTrackers,
      selectedFileIndices: _selectedFileIndices.isNotEmpty ? _selectedFileIndices.toList() : null,
      isSequential: _isSequential,
    );

    if (mounted) {
      Navigator.pop(dialogContext);
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added torrent: $fileName')),
      );
    }
  }

  Future<void> _startDownload() async {
    final url = _urlController.text.trim();
    final fileName = _filenameController.text.trim();

    if (!mounted) return;
    final appState = context.read<AppState>();
    final dlProvider = context.read<DownloadProvider>();
    await dlProvider.addDownload(url, fileName, appState.defaultSavePath);
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added: $fileName')),
      );
    }
  }

  String _dioErrorToString(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        return 'Connection timed out';
      case DioExceptionType.receiveTimeout:
        return 'Server is not responding';
      case DioExceptionType.badResponse:
        return 'Server error: ${e.response?.statusCode ?? 'Unknown'}';
      case DioExceptionType.connectionError:
        return 'Could not connect to server';
      default:
        return 'Network error: ${e.message ?? 'Unknown error'}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        color: cs.surface.withValues(alpha: 0.97),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('New Download',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    )),
            const SizedBox(height: 20),
            TextField(
              controller: _urlController,
              decoration: InputDecoration(
                labelText: 'URL or Magnet Link',
                hintText: 'https://... or magnet:?xt=...',
                prefixIcon: const Icon(Icons.link),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                errorText: _error,
              ),
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              onChanged: (_) {
                if (_infoFetched || _isMagnet) {
                  setState(() {
                    _infoFetched = false;
                    _isMagnet = false;
                    _error = null;
                    _torrentMeta = null;
                    _metadataStatus = '';
                  });
                }
              },
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.content_paste, size: 18),
                label: const Text('Paste from Clipboard'),
                onPressed: _pasteFromClipboard,
              ),
            ),
            const SizedBox(height: 12),
            if (!_isMagnet) ...[
              TextField(
                controller: _filenameController,
                decoration: InputDecoration(
                  labelText: 'Filename',
                  hintText: 'Auto-detected from URL',
                  prefixIcon: const Icon(Icons.description),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                textInputAction: TextInputAction.next,
                onChanged: (_) {
                  if (_infoFetched) {
                    setState(() => _infoFetched = false);
                  }
                },
              ),
            ],
            if (_infoFetched && !_isMagnet) ...[
              const SizedBox(height: 16),
              _buildFileInfoCard(cs),
            ],
            if (_fetchingMetadata) ...[
              const SizedBox(height: 16),
              _buildMetadataLoading(cs),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: _isLoading || _fetchingMetadata
                      ? FilledButton.icon(
                          onPressed: null,
                          icon: const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          ),
                          label: Text(_fetchingMetadata ? 'Fetching Torrent...' : 'Fetching...'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        )
                      : _infoFetched || _isMagnet
                          ? FilledButton.icon(
                              onPressed: _isMagnet ? () => _startTorrentDownload(context) : _startDownload,
                              icon: const Icon(Icons.download_rounded),
                              label: const Text('Download'),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.green,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            )
                          : FilledButton.icon(
                              onPressed: _fetchInfo,
                              icon: const Icon(Icons.search),
                              label: const Text('Fetch Info'),
                              style: FilledButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetadataLoading(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cs.primary.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _metadataStatus.isNotEmpty ? _metadataStatus : 'Downloading torrent metadata...',
              style: TextStyle(color: cs.onSurface, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileInfoCard(ColorScheme cs) {
    final icon = _resumeSupported ? Icons.replay : Icons.block;
    final iconColor = _resumeSupported ? Colors.green : cs.error;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cs.primary.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        children: [
          _infoRow(Icons.description, 'Filename', _detectedFileName, cs),
          const Divider(height: 16),
          _infoRow(
            Icons.storage,
            'Size',
            _fileSize > 0 ? _formatFileSize(_fileSize) : 'Unknown',
            cs,
          ),
          const Divider(height: 16),
          _infoRow(Icons.insert_drive_file, 'Type', _fileType, cs),
          const Divider(height: 16),
          _infoRow(
            icon,
            'Resume Support',
            _resumeSupported ? 'Yes' : 'No',
            cs,
            valueColor: iconColor,
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value, ColorScheme cs,
      {Color? valueColor}) {
    return Row(
      children: [
        Icon(icon, size: 18, color: cs.primary.withValues(alpha: 0.7)),
        const SizedBox(width: 10),
        Text(label,
            style: TextStyle(
                fontWeight: FontWeight.w600,
                color: cs.onSurface.withValues(alpha: 0.7),
                fontSize: 13)),
        const Spacer(),
        Flexible(
          child: Text(value,
              style: TextStyle(
                  color: valueColor ?? cs.onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w500),
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

class _TorrentConfirmSheet extends StatefulWidget {
  final TorrentMetaResult meta;
  final String magnetHash;
  final String magnetTrackers;
  final List<int> selectedIndices;
  final bool isSequential;
  final void Function(List<int>) onSelectionChanged;
  final void Function(bool) onSequentialChanged;
  final VoidCallback onDownload;

  const _TorrentConfirmSheet({
    required this.meta,
    required this.magnetHash,
    required this.magnetTrackers,
    required this.selectedIndices,
    required this.isSequential,
    required this.onSelectionChanged,
    required this.onSequentialChanged,
    required this.onDownload,
  });

  @override
  State<_TorrentConfirmSheet> createState() => _TorrentConfirmSheetState();
}

class _TorrentConfirmSheetState extends State<_TorrentConfirmSheet> {
  late List<bool> _selected;
  bool _selectAll = true;
  late bool _isSequential;

  @override
  void initState() {
    super.initState();
    _selected = List.generate(widget.meta.fileCount, (i) => widget.selectedIndices.contains(i));
    _selectAll = _selected.every((s) => s);
    _isSequential = widget.isSequential;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final meta = widget.meta;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        color: cs.surface.withValues(alpha: 0.97),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Torrent Details',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    )),
            const SizedBox(height: 16),
            _detailRow(Icons.movie, 'Name', meta.name, cs),
            const SizedBox(height: 8),
            _detailRow(Icons.storage, 'Total Size', _formatBytes(meta.totalSize), cs),
            const SizedBox(height: 8),
            _detailRow(Icons.description, 'Files', '${meta.fileCount} files', cs),
            if (widget.magnetHash.isNotEmpty) ...[
              const SizedBox(height: 8),
              _detailRow(Icons.tag, 'Info Hash', widget.magnetHash.length > 16
                  ? '${widget.magnetHash.substring(0, 16)}...'
                  : widget.magnetHash, cs),
            ],
            if (widget.magnetTrackers.isNotEmpty) ...[
              const SizedBox(height: 8),
              _detailRow(Icons.dns, 'Trackers', meta.fileCount > 0
                  ? '${widget.magnetTrackers.split(', ').length} trackers'
                  : 'None', cs),
            ],
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  Icon(Icons.sort, size: 18, color: cs.primary),
                  const SizedBox(width: 8),
                  Text('Sequential Download',
                      style: TextStyle(fontSize: 13, color: cs.onSurface)),
                  const Spacer(),
                  CupertinoSwitch(
                    value: _isSequential,
                    onChanged: (val) {
                      setState(() => _isSequential = val);
                      widget.onSequentialChanged(val);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text('Files',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface,
                        fontSize: 15)),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _selectAll = !_selectAll;
                      for (var i = 0; i < _selected.length; i++) {
                        _selected[i] = _selectAll;
                      }
                      widget.onSelectionChanged(
                        _selected.asMap().entries.where((e) => e.value).map((e) => e.key).toList(),
                      );
                    });
                  },
                  child: Text(_selectAll ? 'Deselect All' : 'Select All'),
                ),
              ],
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: meta.fileCount,
                itemBuilder: (context, index) {
                  return CheckboxListTile(
                    dense: true,
                    value: _selected[index],
                    title: Text(meta.fileNames[index],
                        style: const TextStyle(fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    subtitle: Text(_formatBytes(meta.fileSizes[index]),
                        style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.6))),
                    onChanged: (val) {
                      setState(() {
                        _selected[index] = val ?? false;
                        _selectAll = _selected.every((s) => s);
                      });
                      widget.onSelectionChanged(
                        _selected.asMap().entries.where((e) => e.value).map((e) => e.key).toList(),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: widget.onDownload,
              icon: const Icon(Icons.download_rounded),
              label: Text('Download ${_selected.where((s) => s).length} Files'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value, ColorScheme cs) {
    return Row(
      children: [
        Icon(icon, size: 16, color: cs.primary.withValues(alpha: 0.7)),
        const SizedBox(width: 8),
        Text('$label: ',
            style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.6),
                fontSize: 13)),
        Expanded(
          child: Text(value,
              style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }
}
