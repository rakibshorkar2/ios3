import 'dart:math';
import 'dart:io' show File, Platform;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../providers/download_provider.dart';
import '../models/download_item.dart';
import '../services/thumbnail_service.dart';
import '../services/haptic_service.dart';
import 'package:share_plus/share_plus.dart';
import 'new_download_sheet.dart';

class DownloadTab extends StatefulWidget {
  const DownloadTab({super.key});

  @override
  State<DownloadTab> createState() => _DownloadTabState();
}

class _DownloadTabState extends State<DownloadTab> {
  final Set<String> _expandedBatchIds = {};

  @override
  Widget build(BuildContext context) {
    final dlProvider = context.watch<DownloadProvider>();
    final queue = dlProvider.queue;

    // Grouping logic
    final Map<String?, List<DownloadItem>> grouped = {};
    for (var item in queue) {
      grouped.putIfAbsent(item.batchId, () => []).add(item);
    }

    final batchIds = grouped.keys.toList();
    batchIds.sort((a, b) {
      if (a == null) return -1;
      if (b == null) return 1;
      return a.compareTo(b);
    });

    final isSelectionMode = dlProvider.isSelectionMode;

    return Scaffold(
      appBar: AppBar(
        title: isSelectionMode
            ? Text('${dlProvider.selectedIds.length} Selected')
            : const Text('Downloads'),
        leading: isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: dlProvider.clearSelection,
              )
            : null,
        actions: isSelectionMode
            ? [
                IconButton(
                  icon: const Icon(Icons.select_all),
                  tooltip: 'Select All',
                  onPressed: dlProvider.selectAll,
                ),
                IconButton(
                  icon: const Icon(Icons.delete),
                  tooltip: 'Delete Selected',
                  onPressed: () => _confirmDeleteSelected(context, dlProvider),
                ),
              ]
            : [
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'New Download',
                  onPressed: () {
                    HapticService.light();
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => const NewDownloadSheet(),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.checklist),
                  tooltip: 'Select Items',
                  onPressed: () { HapticService.light(); dlProvider.toggleSelectionMode(); },
                ),
                IconButton(
                  icon: const Icon(Icons.pause_circle_outline),
                  tooltip: 'Pause All',
                  onPressed: () { HapticService.medium(); dlProvider.pauseAll(); },
                ),
                IconButton(
                  icon: const Icon(Icons.play_circle_outline),
                  tooltip: 'Resume All',
                  onPressed: () { HapticService.medium(); dlProvider.resumeAll(); },
                ),
                IconButton(
                  icon: const Icon(Icons.clear_all),
                  tooltip: 'Clear Done',
                  onPressed: () { HapticService.light(); _confirmClearDone(context, dlProvider); },
                ),
                PopupMenuButton<String>(
                  onSelected: (value) async {
                    if (value == 'export') {
                      await dlProvider.exportQueue();
                    } else if (value == 'import') {
                      final success = await dlProvider.importQueue();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(success
                                  ? 'Queue imported successfully!'
                                  : 'Import cancelled or failed.')),
                        );
                      }
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'export',
                      child: Row(
                        children: [
                          Icon(Icons.upload_file, size: 20),
                          SizedBox(width: 8),
                          Text('Export Queue')
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'import',
                      child: Row(
                        children: [
                          Icon(Icons.download_rounded, size: 20),
                          SizedBox(width: 8),
                          Text('Import Queue')
                        ],
                      ),
                    ),
                  ],
                ),
              ],
      ),
      body: Column(
        children: [
          _buildStorageAnalyzer(),
          Expanded(
            child: queue.isEmpty
                ? const Center(child: Text('Download queue is empty.'))
                : ListView.builder(
                    itemCount: batchIds.length + 1,
                    itemBuilder: (context, index) {
                      if (index == batchIds.length) {
                        return const SizedBox(height: 140);
                      }
                      final bId = batchIds[index];
                      final items = grouped[bId]!;

                      if (bId == null) {
                        return Column(
                          children: items
                              .asMap()
                              .entries
                              .map((entry) => _buildDownloadCard(
                                  context, dlProvider, entry.value,
                                  index: entry.key + 1))
                              .toList(),
                        );
                      } else {
                        return _buildBatchTile(context, dlProvider, items,
                            index: index + 1);
                      }
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _showRefreshLinkDialog(BuildContext context, DownloadProvider dlProvider, DownloadItem item) {
    final controller = TextEditingController(text: item.originalUrl ?? item.url);
    bool isValidating = false;

    showCupertinoDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (context, setState) {
        return CupertinoAlertDialog(
          title: const Text('Refresh Download Link'),
          content: Column(
            children: [
              const Text('Enter a new URL for this download.\nProgress will be preserved if the server supports resume.',
                  style: TextStyle(fontSize: 12)),
              const SizedBox(height: 10),
              CupertinoTextField(
                controller: controller,
                placeholder: 'New URL',
                clearButtonMode: OverlayVisibilityMode.editing,
              ),
              if (isValidating) const SizedBox(height: 10),
              if (isValidating) const CupertinoActivityIndicator(),
            ],
          ),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: !isValidating ? false : true,
              onPressed: isValidating
                  ? null
                  : () async {
                      setState(() => isValidating = true);
                      final success = await dlProvider.refreshLink(item.id, controller.text.trim());
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(success ? 'Link updated successfully' : 'Failed to validate new link')),
                        );
                      }
                    },
              child: const Text('Update & Resume'),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildStorageAnalyzer() {
    final dlProvider = context.watch<DownloadProvider>();
    final appState = context.watch<AppState>();
    final totalBytes = dlProvider.totalStorage;
    final freeBytes = dlProvider.freeStorage;
    final cs = Theme.of(context).colorScheme;
    final isAmoled = appState.trueAmoledDark &&
        Theme.of(context).brightness == Brightness.dark;

    if (totalBytes <= 0) return const SizedBox.shrink();

    final usedBytes = totalBytes - freeBytes;
    final progress = totalBytes > 0 ? (usedBytes / totalBytes) : 0.0;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      color: isAmoled
          ? Colors.black
          : cs.surfaceContainerHighest.withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Device Storage',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: cs.onSurface)),
              Text(
                'Free: ${_formatStorageGB(freeBytes)} / ${_formatStorageGB(totalBytes)}',
                style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.7)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              color: progress > 0.9
                  ? Colors.red
                  : cs.primary,
              backgroundColor: cs.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }

  void _confirmClearDone(BuildContext context, DownloadProvider dlProvider) {
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Clear Finished Tasks?'),
        content: const Text('This will remove completed and failed tasks from the list.'),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () {
              dlProvider.clearDone();
              Navigator.pop(ctx);
            },
            child: const Text('Clear List'),
          ),
        ],
      ),
    );
  }

  Widget _buildBatchTile(BuildContext context, DownloadProvider dlProvider,
      List<DownloadItem> items,
      {int? index}) {
    final batchName = items.first.batchName ?? 'Folder Download';
    final String batchId = items.first.batchId!;
    final bool isExpanded = _expandedBatchIds.contains(batchId);
    final cs = Theme.of(context).colorScheme;

    final int totalItems = items.length;
    final int doneItems =
        items.where((i) => i.status == DownloadStatus.done).length;
    final double avgProgress =
        items.fold(0.0, (sum, i) => sum + i.progress) / totalItems;

    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: cs.primaryContainer.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: cs.primary.withValues(alpha: 0.15)),
        ),
        child: Column(
          children: [
            ListTile(
              onTap: () {
                HapticService.light();
                setState(() {
                  if (isExpanded) {
                    _expandedBatchIds.remove(batchId);
                  } else {
                    _expandedBatchIds.add(batchId);
                  }
                });
              },
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: CircleAvatar(
                backgroundColor: cs.primaryContainer,
                child: Icon(Icons.folder, color: cs.onPrimaryContainer, size: 20),
              ),
              title: Text('${index != null ? "$index. " : ""}$batchName',
                  style: TextStyle(fontWeight: FontWeight.bold, color: cs.onSurface)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      '$doneItems / $totalItems files complete (${(avgProgress * 100).toInt()}%)',
                      style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.7))),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: avgProgress,
                      minHeight: 6,
                      color: cs.primary,
                      backgroundColor: cs.surfaceContainerHighest,
                    ),
                  ),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(Icons.more_vert, color: cs.onSurface.withValues(alpha: 0.7)),
                    onPressed: () =>
                        _showBatchOptions(context, dlProvider, batchId, items),
                  ),
                  Icon(isExpanded ? Icons.expand_less : Icons.expand_more,
                      color: cs.onSurface.withValues(alpha: 0.6)),
                ],
              ),
            ),
            if (isExpanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Column(
                  children: items
                      .asMap()
                      .entries
                      .map((entry) => _buildDownloadCard(
                          context, dlProvider, entry.value,
                          isNested: true, index: entry.key + 1))
                      .toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showBatchOptions(BuildContext context, DownloadProvider dlProvider,
      String batchId, List<DownloadItem> items) {
    showCupertinoModalPopup(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('Batch Actions'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              HapticService.medium();
              dlProvider.resumeBatch(batchId);
              Navigator.pop(context);
            },
            child: const Row(
              children: [
                Icon(Icons.play_circle, color: CupertinoColors.activeGreen, size: 22),
                SizedBox(width: 12),
                Text('Resume All in Batch'),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              HapticService.medium();
              dlProvider.pauseBatch(batchId);
              Navigator.pop(context);
            },
            child: const Row(
              children: [
                Icon(Icons.pause_circle, color: CupertinoColors.systemOrange, size: 22),
                SizedBox(width: 12),
                Text('Pause All in Batch'),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              HapticService.heavy();
              Navigator.pop(context);
              _confirmRemoveBatch(context, dlProvider, batchId);
            },
            child: const Row(
              children: [
                Icon(Icons.delete_sweep, color: CupertinoColors.destructiveRed, size: 22),
                SizedBox(width: 12),
                Text('Remove Batch'),
              ],
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  void _confirmRemoveBatch(
      BuildContext context, DownloadProvider dlProvider, String batchId) {
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Remove Batch?'),
        content: const Text('Are you sure you want to remove all items in this batch?'),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () {
              dlProvider.stopBatch(batchId);
              Navigator.pop(ctx);
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadCard(
      BuildContext context, DownloadProvider dlProvider, DownloadItem item,
      {bool isNested = false, int? index}) {
    final bool isSelected = dlProvider.selectedIds.contains(item.id);
    final bool isSelectionMode = dlProvider.isSelectionMode;
    final cs = Theme.of(context).colorScheme;

    Widget card = Container(
      margin: isNested
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(isNested ? 10 : 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildThumbnail(item),
            SizedBox(width: isNested ? 10 : 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${index != null ? "$index. " : ""}${item.fileName}',
                          style: TextStyle(
                              fontWeight: isNested ? FontWeight.w600 : FontWeight.bold,
                              fontSize: isNested ? 13 : 15),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (item.category != DownloadCategory.other) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: cs.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(item.categoryLabel,
                              style: TextStyle(fontSize: 9, color: cs.primary, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: isNested ? 4 : 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: item.progress,
                      minHeight: 7,
                      backgroundColor: cs.surfaceContainerHighest,
                    ),
                  ),
                  SizedBox(height: isNested ? 6 : 10),
                  Row(
                    children: [
                      Expanded(
                        flex: 4,
                        child: Text(
                          item.status == DownloadStatus.downloading
                              ? '${_formatCompactBytes(item.downloadedBytes)}/${_formatCompactBytes(item.totalBytes)} (${(item.progress * 100).toInt()}%)'
                              : '${_formatBytes(item.downloadedBytes)} / ${_formatBytes(item.totalBytes)}',
                          style: TextStyle(
                              fontSize: isNested ? 10 : 11,
                              fontWeight: FontWeight.bold,
                              color: cs.onSurface.withValues(alpha: 0.8)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        flex: 4,
                        child: Text(
                          _formatSpeedAndETA(item),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: isNested ? 10 : 11,
                            color: cs.onSurface.withValues(alpha: 0.7),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        flex: 2,
                        child: Text(
                          item.statusLabel,
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            fontSize: isNested ? 10 : 11,
                            color: item.status == DownloadStatus.error
                                ? cs.error
                                : (item.status == DownloadStatus.done
                                    ? Colors.green
                                    : cs.primary),
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (item.errorMessage != null) ...[
                    const SizedBox(height: 4),
                    Text(item.errorMessage!,
                        style: TextStyle(color: cs.error, fontSize: 11)),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (item.status == DownloadStatus.done)
                        TextButton.icon(
                          icon: Icon(Icons.verified_user, size: 14,
                              color: cs.primary),
                          label: Text('Verify',
                              style: TextStyle(fontSize: 11, color: cs.primary)),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () {
                              HapticService.light();
                              _showVerifyHashDialog(context, dlProvider, item);
                            },
                        ),
                      _buildActionButtons(context, dlProvider, item),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (isSelectionMode) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            Checkbox(
              value: isSelected,
              onChanged: (val) => dlProvider.toggleSelection(item.id),
            ),
            Expanded(
                child: GestureDetector(
              onTap: () => dlProvider.toggleSelection(item.id),
              child: AbsorbPointer(child: card),
            )),
          ],
        ),
      );
    }

    return RepaintBoundary(
      child: GestureDetector(
        onLongPress: () {
          HapticService.medium();
          dlProvider.toggleSelection(item.id);
        },
        child: card,
      ),
    );
  }

  Widget _buildThumbnail(DownloadItem item) {
    return FutureBuilder<String?>(
      future: ThumbnailService().getThumbnail(item.savePath),
      builder: (context, snapshot) {
        final hasThumb = snapshot.hasData && snapshot.data != null;
        return Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            image: hasThumb
                ? DecorationImage(
                    image: FileImage(File(snapshot.data!)), fit: BoxFit.cover)
                : null,
          ),
          child: !hasThumb
              ? Icon(Icons.description,
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.5))
              : null,
        );
      },
    );
  }

  Widget _buildActionButtons(
      BuildContext context, DownloadProvider dlProvider, DownloadItem item) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (item.status == DownloadStatus.done)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(Icons.share, color: cs.primary, size: 20),
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                onPressed: () {
                  HapticService.light();
                  final file = File(item.savePath);
                  if (file.existsSync()) {
                    Share.shareXFiles([XFile(item.savePath)], text: item.fileName);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('File not found on disk.')),
                    );
                  }
                },
              ),
              if (Platform.isIOS)
                IconButton(
                  icon: Icon(Icons.folder_open, color: cs.secondary, size: 20),
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  onPressed: () {
                    HapticService.light();
                    final file = File(item.savePath);
                    if (file.existsSync()) {
                      dlProvider.revealFile(item.savePath);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('File not found on disk.')),
                      );
                    }
                  },
                ),
              if (Platform.isIOS)
                IconButton(
                  icon: Icon(Icons.save_alt, color: cs.tertiary, size: 20),
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  tooltip: 'Save to Files',
                  onPressed: () {
                    HapticService.light();
                    final file = File(item.savePath);
                    if (file.existsSync()) {
                      dlProvider.saveToFiles(item.savePath);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('File not found on disk.')),
                      );
                    }
                  },
                ),
            ],
          ),
        if (item.status == DownloadStatus.downloading ||
            item.status == DownloadStatus.queued)
          IconButton(
            icon: const Icon(Icons.pause_circle_outline, color: Colors.orange, size: 22),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: () { HapticService.light(); dlProvider.pause(item.id); },
          ),
        if (item.status == DownloadStatus.paused)
          IconButton(
            icon: const Icon(Icons.play_circle_outline, color: Colors.green, size: 22),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: () { HapticService.light(); dlProvider.resume(item.id); },
          ),
        if (item.status == DownloadStatus.error) ...[
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.orange, size: 20),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            tooltip: 'Refresh Link',
            onPressed: () { HapticService.light(); _showRefreshLinkDialog(context, dlProvider, item); },
          ),
          IconButton(
            icon: const Icon(Icons.play_circle_outline, color: Colors.green, size: 22),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: () { HapticService.light(); dlProvider.resume(item.id); },
          ),
        ],
        IconButton(
          icon: Icon(Icons.close_rounded, color: cs.error, size: 20),
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          onPressed: () { HapticService.heavy(); _confirmSafeDelete(context, dlProvider, item); },
        ),
      ],
    );
  }

  void _confirmSafeDelete(
      BuildContext context, DownloadProvider dlProvider, DownloadItem item) {
    bool deleteFile = false;
    showCupertinoDialog(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(builder: (context, setState) {
            return CupertinoAlertDialog(
                title: const Text('Delete Task?'),
                content: Column(
                  children: [
                    Text(
                        'Are you sure you want to remove "${item.fileName}" from the queue?'),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        CupertinoCheckbox(
                          value: deleteFile,
                          onChanged: (val) {
                            setState(() => deleteFile = val ?? false);
                          },
                        ),
                        const SizedBox(width: 8),
                        const Flexible(
                          child: Text('Delete file from storage as well',
                              style: TextStyle(fontSize: 13)),
                        ),
                      ],
                    ),
                  ],
                ),
                actions: [
                  CupertinoDialogAction(
                    isDefaultAction: true,
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel'),
                  ),
                  CupertinoDialogAction(
                    isDestructiveAction: true,
                    onPressed: () {
                      dlProvider.stop(item.id);
                      if (deleteFile) {
                        final f = File(item.savePath);
                        if (f.existsSync()) f.deleteSync();
                      }
                      Navigator.pop(ctx);
                    },
                    child: const Text('Delete'),
                  ),
                ]);
          });
        });
  }

  void _confirmDeleteSelected(
      BuildContext context, DownloadProvider dlProvider) {
    bool deleteFile = false;
    showCupertinoDialog(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(builder: (context, setState) {
            return CupertinoAlertDialog(
              title: const Text('Delete Selected?'),
              content: Column(
                children: [
                  Text(
                      'Are you sure you want to remove ${dlProvider.selectedIds.length} items?'),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      CupertinoCheckbox(
                        value: deleteFile,
                        onChanged: (val) {
                          setState(() => deleteFile = val ?? false);
                        },
                      ),
                      const SizedBox(width: 8),
                      const Flexible(
                        child: Text('Delete files from storage as well',
                            style: TextStyle(fontSize: 13)),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                CupertinoDialogAction(
                  isDefaultAction: true,
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                CupertinoDialogAction(
                  isDestructiveAction: true,
                  onPressed: () {
                    dlProvider.deleteSelected(deleteFiles: deleteFile);
                    Navigator.pop(ctx);
                  },
                  child: const Text('Delete'),
                ),
              ],
            );
          });
        });
  }

  void _showVerifyHashDialog(
      BuildContext context, DownloadProvider dlProvider, DownloadItem item) {
    final ctrl = TextEditingController();
    bool isVerifying = false;
    bool? isValid;
    String? algorithm;

    showCupertinoDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          return StatefulBuilder(builder: (context, setState) {
            return CupertinoAlertDialog(
              title: const Text('Verify File Hash'),
              content: Column(
                children: [
                  Text('Check hash for: ${item.fileName}',
                      style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _hashAlgoChip('MD5', setState, algorithm, (v) => algorithm = v),
                      const SizedBox(width: 4),
                      _hashAlgoChip('SHA1', setState, algorithm, (v) => algorithm = v),
                      const SizedBox(width: 4),
                      _hashAlgoChip('SHA256', setState, algorithm, (v) => algorithm = v),
                    ],
                    mainAxisAlignment: MainAxisAlignment.center,
                  ),
                  const SizedBox(height: 10),
                  CupertinoTextField(
                    controller: ctrl,
                    placeholder: 'Expected hash value',
                  ),
                  const SizedBox(height: 10),
                  if (isVerifying) const CupertinoActivityIndicator(),
                  if (!isVerifying && isValid != null)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(isValid! ? Icons.check_circle : Icons.cancel,
                            color: isValid! ? Colors.green : Colors.red),
                        const SizedBox(width: 8),
                        Text(isValid! ? 'Hash Matches!' : 'Hash Mismatch!',
                            style: TextStyle(
                                color: isValid! ? Colors.green : Colors.red,
                                fontWeight: FontWeight.bold))
                      ],
                    ),
                  if (item.calculatedMd5 != null || item.calculatedSha1 != null || item.calculatedSha256 != null) ...[
                    const SizedBox(height: 8),
                    Text('Auto-computed checksums:', style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
                    if (item.calculatedMd5 != null) Text('MD5: ${item.calculatedMd5}', style: const TextStyle(fontSize: 8)),
                    if (item.calculatedSha1 != null) Text('SHA1: ${item.calculatedSha1}', style: const TextStyle(fontSize: 8)),
                    if (item.calculatedSha256 != null) Text('SHA256: ${item.calculatedSha256}', style: const TextStyle(fontSize: 8)),
                  ],
                ],
              ),
              actions: [
                if (!isVerifying)
                  CupertinoDialogAction(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Close'),
                  ),
                if (!isVerifying)
                  CupertinoDialogAction(
                    isDefaultAction: true,
                    onPressed: () async {
                      if (ctrl.text.trim().isEmpty || algorithm == null) return;
                      setState(() {
                        isVerifying = true;
                        isValid = null;
                      });

                      final result = await dlProvider.verifyFileHash(
                          item.savePath, ctrl.text);

                      if (context.mounted) {
                        setState(() {
                          isVerifying = false;
                          isValid = result;
                        });
                      }
                    },
                    child: const Text('Verify'),
                  ),
              ],
            );
          });
        });
  }

  Widget _hashAlgoChip(String label, StateSetter setState, String? selected, Function(String) onSelected) {
    final isSelected = selected == label;
    return GestureDetector(
      onTap: () => setState(() => onSelected(label)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? CupertinoColors.activeBlue : CupertinoColors.systemGrey5,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.black)),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }

  String _formatCompactBytes(int bytes) {
    if (bytes <= 0) return '0B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = (log(bytes) / log(1024)).floor();
    var val = bytes / pow(1024, i);
    if (val >= 100) {
      return '${val.toStringAsFixed(0)}${suffixes[i]}';
    }
    return '${val.toStringAsFixed(1)}${suffixes[i]}';
  }

  String _formatStorageGB(dynamic mb) {
    final b = (mb is int ? mb.toDouble() : mb) as double;
    if (b <= 0) return '0 GB';
    // Plugin returns MiB (1024² bytes). Convert to decimal GB (1000³ bytes) to match iOS Settings.
    final decimalGB = b * 1024 * 1024 / (1000 * 1000 * 1000);
    return '${decimalGB.toStringAsFixed(1)} GB';
  }

  String _formatSpeedAndETA(DownloadItem item) {
    if (item.status == DownloadStatus.done) return 'Completed';
    if (item.status == DownloadStatus.error) return 'Failed';
    if (item.speedBytesPerSec <= 0) return '0 B/s';

    String speedStr = '';
    if (item.speedBytesPerSec > 1024 * 1024) {
      speedStr =
          '${(item.speedBytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    } else if (item.speedBytesPerSec > 1024) {
      speedStr = '${(item.speedBytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    } else {
      speedStr = '${item.speedBytesPerSec.toStringAsFixed(0)} B/s';
    }

    int mm = item.etaSeconds ~/ 60;
    int ss = item.etaSeconds % 60;
    int hh = mm ~/ 60;
    mm = mm % 60;

    String etaStr;
    if (hh > 0) {
      etaStr = '${hh}h ${mm}m';
    } else if (mm > 0) {
      etaStr = '${mm}m ${ss}s';
    } else {
      etaStr = '${ss}s';
    }

    return '$speedStr \u00b7 $etaStr';
  }
}
