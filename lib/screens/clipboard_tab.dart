import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:ui';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/app_state.dart';
import '../providers/download_provider.dart';
import '../providers/clipboard_provider.dart';
import '../models/clipboard_item.dart';
import '../services/haptic_service.dart';

class ClipboardTab extends StatefulWidget {
  const ClipboardTab({super.key});

  @override
  State<ClipboardTab> createState() => _ClipboardTabState();
}

class _ClipboardTabState extends State<ClipboardTab> with WidgetsBindingObserver {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final provider = context.read<ClipboardProvider>();
      provider.checkForNewClipboard();
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final provider = context.watch<ClipboardProvider>();
    final isAmoled = appState.trueAmoledDark && Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          color: isAmoled ? Colors.black : null,
          gradient: isAmoled
              ? null
              : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Theme.of(context).colorScheme.surface,
                    Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.8),
                  ],
                ),
        ),
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) {
            return [
              SliverAppBar(
                expandedHeight: 120,
                floating: true,
                pinned: true,
                stretch: true,
                backgroundColor: Colors.transparent,
                elevation: 0,
                flexibleSpace: FlexibleSpaceBar(
                  title: Text(
                    'Clipboard',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                  centerTitle: false,
                  titlePadding: const EdgeInsetsDirectional.only(start: 16, bottom: 16),
                  background: ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Container(
                        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.15),
                      ),
                    ),
                  ),
                ),
                actions: [
                  if (provider.isMultiSelectMode)
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => provider.toggleMultiSelectMode(),
                    )
                  else ...[
                    IconButton(
                      icon: const Icon(Icons.star_border),
                      onPressed: () => provider.setShowFavoritesOnly(!provider.showFavoritesOnly),
                      tooltip: 'Favorites',
                    ),
                    IconButton(
                      icon: const Icon(Icons.bar_chart),
                      onPressed: () => _showStatistics(context),
                      tooltip: 'Statistics',
                    ),
                    PopupMenuButton(
                      icon: const Icon(Icons.more_vert),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(value: 'export', child: ListTile(
                          leading: Icon(Icons.file_upload_outlined),
                          title: Text('Export'),
                          contentPadding: EdgeInsets.zero,
                        )),
                        const PopupMenuItem(value: 'import', child: ListTile(
                          leading: Icon(Icons.file_download_outlined),
                          title: Text('Import'),
                          contentPadding: EdgeInsets.zero,
                        )),
                        const PopupMenuItem(value: 'clear', child: ListTile(
                          leading: Icon(Icons.delete_sweep_outlined, color: Colors.red),
                          title: Text('Clear All', style: TextStyle(color: Colors.red)),
                          contentPadding: EdgeInsets.zero,
                        )),
                      ],
                      onSelected: (val) {
                        if (val == 'export') _showExportDialog(context);
                        if (val == 'import') _showImportDialog(context);
                        if (val == 'clear') _confirmClearAll(context);
                      },
                    ),
                  ],
                ],
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _SliverAppBarDelegate(
                  _buildSearchAndCategories(context, provider),
                ),
              ),
            ];
          },
          body: Stack(
            children: [
              _buildBody(context, provider),
              if (provider.newlyDetectedItem != null)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _buildDetectionBanner(context, provider),
                ),
            ],
          ),
        ),
      ),
      floatingActionButton: !provider.isMultiSelectMode
          ? FloatingActionButton.small(
              onPressed: () async {
                HapticService.medium();
                await provider.captureCurrentClipboard();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Clipboard captured'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.9),
              child: Icon(Icons.content_paste, color: Theme.of(context).colorScheme.onPrimary),
              tooltip: 'Capture current clipboard',
            )
          : null,
    );
  }

  Widget _buildSearchAndCategories(BuildContext context, ClipboardProvider provider) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.15),
            width: 0.5,
          ),
        ),
      ),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.6),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: _buildSearchBar(context),
                ),
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      _categoryChip(context, 'All', ClipboardContentType.text, provider.selectedFilter.index == 0),
                      _categoryChip(context, 'Links', ClipboardContentType.url, provider.selectedFilter == ClipboardContentType.url),
                      _categoryChip(context, 'Code', ClipboardContentType.code, provider.selectedFilter == ClipboardContentType.code),
                      _categoryChip(context, 'JSON', ClipboardContentType.json, provider.selectedFilter == ClipboardContentType.json),
                      _categoryChip(context, 'Colors', ClipboardContentType.color, provider.selectedFilter == ClipboardContentType.color),
                      _categoryChip(context, 'Emails', ClipboardContentType.email, provider.selectedFilter == ClipboardContentType.email),
                      _categoryChip(context, 'Phones', ClipboardContentType.phone, provider.selectedFilter == ClipboardContentType.phone),
                      _categoryChip(context, 'Files', ClipboardContentType.filePath, provider.selectedFilter == ClipboardContentType.filePath),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _categoryChip(BuildContext context, String label, ClipboardContentType type, bool isSelected) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ChoiceChip(
        label: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? cs.onPrimary : cs.onSurface.withValues(alpha: 0.6),
          ),
        ),
        selected: isSelected,
        onSelected: (val) {
          if (val) {
            context.read<ClipboardProvider>().setFilter(type);
            HapticService.light();
          }
        },
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        selectedColor: cs.primary,
        backgroundColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isSelected
                ? cs.primary.withValues(alpha: 0.5)
                : cs.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        showCheckmark: false,
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.4),
            ),
          ),
          child: TextField(
            controller: _searchController,
            style: TextStyle(fontSize: 14, color: cs.onSurface),
            decoration: InputDecoration(
              hintText: 'Search clipboard...',
              hintStyle: TextStyle(color: cs.onSurface.withValues(alpha: 0.4), fontSize: 14),
              prefixIcon: Icon(Icons.search, color: cs.primary.withValues(alpha: 0.6), size: 20),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        context.read<ClipboardProvider>().setSearchQuery('');
                      },
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onChanged: (val) => context.read<ClipboardProvider>().setSearchQuery(val),
          ),
        ),
      ),
    );
  }

  Widget _buildDetectionBanner(BuildContext context, ClipboardProvider provider) {
    final cs = Theme.of(context).colorScheme;
    final item = provider.newlyDetectedItem!;
    return GestureDetector(
      onVerticalDragEnd: (_) => provider.dismissNewlyDetected(),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: cs.primaryContainer.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.primary.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.radar, size: 16, color: cs.primary),
                const SizedBox(width: 8),
                Text('New clipboard detected',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: cs.primary)),
                const Spacer(),
                GestureDetector(
                  onTap: provider.dismissNewlyDetected,
                  child: Icon(Icons.close, size: 16, color: cs.onSurface.withValues(alpha: 0.5)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              item.preview,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  icon: Icon(Icons.delete_outline, size: 14, color: cs.error),
                  label: Text('Dismiss', style: TextStyle(fontSize: 11, color: cs.error)),
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  onPressed: provider.dismissNewlyDetected,
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  icon: Icon(Icons.save, size: 14, color: Colors.green),
                  label: Text('Save', style: TextStyle(fontSize: 11, color: Colors.green)),
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  onPressed: provider.saveNewlyDetected,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, ClipboardProvider provider) {
    final items = provider.items;

    if (items.isEmpty) {
      return _buildEmptyState(
        provider.showFavoritesOnly
            ? 'No favorites yet'
            : provider.searchQuery.isNotEmpty
                ? 'No results found'
                : 'Your clipboard history is empty',
        provider.showFavoritesOnly
            ? Icons.star_outline
            : provider.searchQuery.isNotEmpty
                ? Icons.search_off
                : Icons.content_paste_rounded,
      );
    }

    return Column(
      children: [
        if (provider.isMultiSelectMode)
          _buildMultiSelectBar(context, provider),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: items.length,
            itemBuilder: (context, index) => _buildClipboardCard(context, items[index], provider),
          ),
        ),
      ],
    );
  }

  Widget _buildMultiSelectBar(BuildContext context, ClipboardProvider provider) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.1),
        border: Border(
          bottom: BorderSide(color: cs.primary.withValues(alpha: 0.2)),
        ),
      ),
      child: Row(
        children: [
          Text(
            '${provider.selectedIds.length} selected',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: cs.primary,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.select_all),
            onPressed: provider.selectAll,
            tooltip: 'Select All',
            iconSize: 20,
          ),
          IconButton(
            icon: const Icon(Icons.star_outline),
            onPressed: provider.toggleFavoriteSelected,
            tooltip: 'Toggle Favorite',
            iconSize: 20,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            onPressed: provider.selectedIds.isNotEmpty
                ? () => _confirmDeleteSelected(context, provider)
                : null,
            tooltip: 'Delete',
            iconSize: 20,
          ),
        ],
      ),
    );
  }

  Widget _buildClipboardCard(BuildContext context, ClipboardItem item, ClipboardProvider provider) {
    final cs = Theme.of(context).colorScheme;
    final isSelected = provider.selectedIds.contains(item.id);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dismissible(
      key: Key(item.id),
      direction: DismissDirection.horizontal,
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 24),
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Icon(Icons.copy, color: Colors.white),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.red),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          await Clipboard.setData(ClipboardData(text: item.content));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Copied to clipboard'),
                behavior: SnackBarBehavior.floating,
                backgroundColor: cs.inverseSurface,
              ),
            );
          }
          return false;
        } else {
          return true;
        }
      },
      onDismissed: (direction) {
        if (direction == DismissDirection.endToStart) {
          provider.deleteItem(item.id);
          HapticService.medium();
        }
      },
      child: GestureDetector(
        onTap: () {
          if (provider.isMultiSelectMode) {
            provider.toggleSelection(item.id);
            HapticService.light();
          } else {
            _showDetail(context, item);
          }
        },
        onLongPress: () {
          if (!provider.isMultiSelectMode) {
            provider.toggleMultiSelectMode();
            provider.toggleSelection(item.id);
            HapticService.medium();
          }
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? cs.primary.withValues(alpha: 0.5)
                  : isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.white.withValues(alpha: 0.3),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isSelected
                      ? cs.primary.withValues(alpha: 0.12)
                      : isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : Colors.white.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _typeIcon(item.type, cs),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _typeLabel(item.type),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _typeColor(item.type).withValues(alpha: 0.7),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        if (item.isPinned)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(Icons.push_pin, size: 14, color: Colors.orange.withValues(alpha: 0.7)),
                          ),
                        if (item.isFavorite)
                          Icon(Icons.star, size: 16, color: Colors.amber.withValues(alpha: 0.8)),
                        if (provider.isMultiSelectMode)
                          Checkbox(
                            value: isSelected,
                            onChanged: (_) => provider.toggleSelection(item.id),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      item.preview,
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurface.withValues(alpha: 0.85),
                        height: 1.3,
                      ),
                      maxLines: item.type == ClipboardContentType.url ? 2 : 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(Icons.access_time, size: 11, color: cs.onSurface.withValues(alpha: 0.35)),
                        const SizedBox(width: 4),
                        Text(
                          _formatTimestamp(item.createdAt),
                          style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.35)),
                        ),
                        const SizedBox(width: 16),
                        Icon(Icons.text_fields, size: 11, color: cs.onSurface.withValues(alpha: 0.35)),
                        const SizedBox(width: 4),
                        Text(
                          '${item.characterCount} chars',
                          style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.35)),
                        ),
                        if (item.domain != null) ...[
                          const SizedBox(width: 16),
                          Icon(Icons.language, size: 11, color: cs.onSurface.withValues(alpha: 0.35)),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              item.domain!,
                              style: TextStyle(fontSize: 10, color: cs.primary.withValues(alpha: 0.6)),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(String msg, IconData icon) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 48, color: cs.primary.withValues(alpha: 0.4)),
          ),
          const SizedBox(height: 24),
          Text(
            msg,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.5),
              fontSize: 15,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }

  void _showDetail(BuildContext context, ClipboardItem item) {
    HapticService.light();

    if (item.type == ClipboardContentType.image && item.imagePath != null) {
      _showImageViewer(context, item);
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _buildDetailSheet(context, item),
    );
  }

  Widget _buildDetailSheet(BuildContext context, ClipboardItem item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final provider = context.read<ClipboardProvider>();

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: BoxDecoration(
            color: isDark ? Colors.grey.shade900.withValues(alpha: 0.92) : Colors.white.withValues(alpha: 0.92),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(
              top: BorderSide(
                color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.5),
              ),
            ),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    _typeIcon(item.type, cs, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _typeLabel(item.type),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              letterSpacing: -0.5,
                              color: _typeColor(item.type),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _formatTimestamp(item.createdAt),
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurface.withValues(alpha: 0.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(item.isFavorite ? Icons.star : Icons.star_border,
                          color: item.isFavorite ? Colors.amber : null),
                      onPressed: () {
                        provider.toggleFavorite(item.id);
                      },
                    ),
                    IconButton(
                      icon: Icon(item.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                          color: item.isPinned ? Colors.orange : null),
                      onPressed: () {
                        provider.togglePin(item.id);
                        if (context.mounted) Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    if (item.type == ClipboardContentType.url)
                      _buildUrlPreview(context, item),
                    if (item.type == ClipboardContentType.code)
                      _buildCodePreview(context, item),
                    if (item.type == ClipboardContentType.json)
                      _buildCodePreview(context, item, isJson: true),
                    if (item.type == ClipboardContentType.color)
                      _buildColorPreview(context, item),
                    _buildContentSection(context, item),
                    const SizedBox(height: 20),
                    _buildMetadataSection(context, item),
                    if (item.tags.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildTagsSection(context, item),
                    ],
                  ],
                ),
              ),
              _buildDetailActions(context, item),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUrlPreview(BuildContext context, ClipboardItem item) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.domain != null) ...[
            Row(
              children: [
                Icon(Icons.language, size: 16, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  item.domain!,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: cs.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          if (item.fileExtension != null)
            Row(
              children: [
                Icon(Icons.insert_drive_file, size: 14, color: cs.onSurface.withValues(alpha: 0.5)),
                const SizedBox(width: 6),
                Text(
                  'File type: .${item.fileExtension}',
                  style: TextStyle(fontSize: 13, color: cs.onSurface.withValues(alpha: 0.6)),
                ),
              ],
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              _miniActionButton(Icons.open_in_new, 'Open', cs.primary, () async {
                final uri = Uri.tryParse(item.content);
                if (uri != null && await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              }),
              const SizedBox(width: 8),
              _miniActionButton(Icons.copy, 'Copy', cs.onSurface.withValues(alpha: 0.6), () async {
                await Clipboard.setData(ClipboardData(text: item.content));
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: const Text('Copied'), behavior: SnackBarBehavior.floating),
                  );
                }
              }),
              const SizedBox(width: 8),
              if (item.content.startsWith('http://') || item.content.startsWith('https://'))
                _miniActionButton(Icons.download_rounded, 'Download', Colors.green, () {
                  Navigator.pop(context);
                  _sendToDownloadManager(context, item.content);
                }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCodePreview(BuildContext context, ClipboardItem item, {bool isJson = false}) {
    final lang = isJson ? 'json' : (item.language ?? 'code');
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.code, size: 16, color: Colors.greenAccent),
              const SizedBox(width: 8),
              Text(
                lang.toUpperCase(),
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.copy, size: 16, color: Colors.white70),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: item.content));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: const Text('Copied'), behavior: SnackBarBehavior.floating),
                    );
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.share, size: 16, color: Colors.white70),
                onPressed: () => Share.share(item.content),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: SelectableText(
              item.content,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Colors.white,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColorPreview(BuildContext context, ClipboardItem item) {
    final cs = Theme.of(context).colorScheme;
    Color? swatch;
    try {
      final hex = item.content.trim();
      if (hex.startsWith('#')) {
        final h = hex.replaceFirst('#', '');
        if (h.length == 6) {
          swatch = Color(int.parse('FF$h', radix: 16));
        } else if (h.length == 3) {
          final r = h[0] * 2;
          final g = h[1] * 2;
          final b = h[2] * 2;
          swatch = Color(int.parse('FF$r$g$b', radix: 16));
        }
      } else if (hex.startsWith('rgb')) {
        final nums = RegExp(r'\d+').allMatches(hex).map((m) => int.parse(m.group(0)!)).toList();
        if (nums.length >= 3) {
          swatch = Color.fromARGB(255, nums[0], nums[1], nums[2]);
        }
      }
    } catch (_) {}

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Color Preview', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: cs.onSurface)),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 60, height: 60,
                decoration: BoxDecoration(
                  color: swatch ?? Colors.grey,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.content, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: cs.onSurface, fontFamily: 'monospace')),
                  if (swatch != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'R: ${(swatch.r * 255.0).round().clamp(0, 255)}  G: ${(swatch.g * 255.0).round().clamp(0, 255)}  B: ${(swatch.b * 255.0).round().clamp(0, 255)}',
                      style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.6)),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTagsSection(BuildContext context, ClipboardItem item) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.label, size: 16, color: cs.onSurface.withValues(alpha: 0.5)),
              const SizedBox(width: 8),
              Text('Tags', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: cs.onSurface)),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: item.tags.map((tag) => Chip(
              label: Text(tag, style: const TextStyle(fontSize: 11)),
              deleteIcon: const Icon(Icons.close, size: 14),
              onDeleted: () => context.read<ClipboardProvider>().removeTag(item.id, tag),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 4),
            )).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildContentSection(BuildContext context, ClipboardItem item) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: SelectableText(
        item.content,
        style: TextStyle(
          fontSize: 14,
          color: cs.onSurface,
          height: 1.5,
          fontFamily: item.type == ClipboardContentType.code ? 'monospace' : null,
        ),
      ),
    );
  }

  Widget _buildMetadataSection(BuildContext context, ClipboardItem item) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Details', style: TextStyle(
            fontWeight: FontWeight.bold, fontSize: 14, color: cs.onSurface,
          )),
          const SizedBox(height: 12),
          _metaRow(cs, 'Type', _typeLabel(item.type)),
          _metaRow(cs, 'Created', _formatDetailTimestamp(item.createdAt)),
          _metaRow(cs, 'Characters', item.characterCount.toString()),
          _metaRow(cs, 'Words', item.wordCount.toString()),
          _metaRow(cs, 'Lines', item.lineCount.toString()),
          if (item.domain != null) _metaRow(cs, 'Domain', item.domain!),
          if (item.language != null) _metaRow(cs, 'Language', item.language!.toUpperCase()),
          if (item.tags.isNotEmpty) _metaRow(cs, 'Tags', item.tags.join(', ')),
        ],
      ),
    );
  }

  Widget _metaRow(ColorScheme cs, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: TextStyle(
              fontSize: 12, color: cs.onSurface.withValues(alpha: 0.5),
            )),
          ),
          Expanded(
            child: Text(value, style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w500, color: cs.onSurface,
            )),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailActions(BuildContext context, ClipboardItem item) {
    final cs = Theme.of(context).colorScheme;
    final provider = context.read<ClipboardProvider>();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.2)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _detailAction(Icons.copy, 'Copy', () async {
            await Clipboard.setData(ClipboardData(text: item.content));
            if (context.mounted) {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: const Text('Copied'), behavior: SnackBarBehavior.floating),
              );
            }
          }),
          _detailAction(Icons.share, 'Share', () => Share.share(item.content)),
          _detailAction(Icons.edit, 'Edit', () {
            Navigator.pop(context);
            _showEditDialog(context, item);
          }),
          _detailAction(Icons.label_outline, 'Tag', () {
            Navigator.pop(context);
            _showAddTagDialog(context, item);
          }),
          _detailAction(item.isFavorite ? Icons.star : Icons.star_border,
              item.isFavorite ? 'Unfavorite' : 'Favorite', () {
            provider.toggleFavorite(item.id);
          }),
          _detailAction(Icons.delete_outline, 'Delete', () {
            Navigator.pop(context);
            provider.deleteItem(item.id);
          }, color: Colors.red),
        ],
      ),
    );
  }

  Widget _detailAction(IconData icon, String label, VoidCallback onPressed, {Color? color}) {
    return GestureDetector(
      onTap: onPressed,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _miniActionButton(IconData icon, String label, Color color, VoidCallback onPressed) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _typeIcon(ClipboardContentType type, ColorScheme cs, {double size = 20}) {
    IconData icon;
    Color color;
    switch (type) {
      case ClipboardContentType.url:
        icon = Icons.link_rounded; color = Colors.blue;
      case ClipboardContentType.image:
        icon = Icons.image_rounded; color = Colors.purple;
      case ClipboardContentType.email:
        icon = Icons.email_rounded; color = Colors.teal;
      case ClipboardContentType.phone:
        icon = Icons.phone_rounded; color = Colors.green;
      case ClipboardContentType.json:
        icon = Icons.data_object_rounded; color = Colors.orange;
      case ClipboardContentType.code:
        icon = Icons.code_rounded; color = Colors.greenAccent;
      case ClipboardContentType.color:
        icon = Icons.palette_rounded; color = Colors.pink;
      case ClipboardContentType.filePath:
        icon = Icons.folder_rounded; color = Colors.amber;
      case ClipboardContentType.richText:
        icon = Icons.text_format; color = Colors.indigo;
      case ClipboardContentType.text:
        icon = Icons.text_fields; color = cs.primary;
    }
    return Container(
      padding: EdgeInsets.all(size > 20 ? 8 : 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: size > 20 ? 22 : 16, color: color),
    );
  }

  Color _typeColor(ClipboardContentType type) {
    switch (type) {
      case ClipboardContentType.url: return Colors.blue;
      case ClipboardContentType.image: return Colors.purple;
      case ClipboardContentType.email: return Colors.teal;
      case ClipboardContentType.phone: return Colors.green;
      case ClipboardContentType.json: return Colors.orange;
      case ClipboardContentType.code: return Colors.greenAccent;
      case ClipboardContentType.color: return Colors.pink;
      case ClipboardContentType.filePath: return Colors.amber;
      case ClipboardContentType.richText: return Colors.indigo;
      case ClipboardContentType.text: return Colors.blueGrey;
    }
  }

  String _typeLabel(ClipboardContentType type) {
    switch (type) {
      case ClipboardContentType.text: return 'TEXT';
      case ClipboardContentType.url: return 'URL';
      case ClipboardContentType.image: return 'IMAGE';
      case ClipboardContentType.richText: return 'RICH TEXT';
      case ClipboardContentType.phone: return 'PHONE';
      case ClipboardContentType.email: return 'EMAIL';
      case ClipboardContentType.json: return 'JSON';
      case ClipboardContentType.code: return 'CODE';
      case ClipboardContentType.color: return 'COLOR';
      case ClipboardContentType.filePath: return 'FILE PATH';
    }
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.month}/${dt.day}/${dt.year}';
  }

  String _formatDetailTimestamp(DateTime dt) {
    return '${dt.month}/${dt.day}/${dt.year} at ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  void _showEditDialog(BuildContext context, ClipboardItem item) {
    final controller = TextEditingController(text: item.content);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Content'),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: controller,
            maxLines: 10,
            decoration: InputDecoration(
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final newContent = controller.text.trim();
              if (newContent.isNotEmpty && newContent != item.content) {
                await context.read<ClipboardProvider>().updateItemContent(item.id, newContent);
              }
              if (context.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showAddTagDialog(BuildContext context, ClipboardItem item) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Tag'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: 'Enter tag name...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.all(12),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final tag = controller.text.trim();
              if (tag.isNotEmpty) {
                await context.read<ClipboardProvider>().addTags(item.id, [tag]);
              }
              if (context.mounted) Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _sendToDownloadManager(BuildContext context, String url) {
    final appState = context.read<AppState>();
    final downloads = context.read<DownloadProvider>();
    final fileName = url.split('/').last.isNotEmpty ? url.split('/').last : 'download';
    downloads.addDownload(url, fileName, appState.defaultSavePath);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('URL sent to Download Manager'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showImageViewer(BuildContext context, ClipboardItem item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            leading: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.share, color: Colors.white),
                onPressed: () => Share.share(item.content),
              ),
            ],
          ),
          body: Center(
            child: InteractiveViewer(
              maxScale: 5,
              child: item.imagePath != null && File(item.imagePath!).existsSync()
                  ? Image.file(File(item.imagePath!), fit: BoxFit.contain)
                  : const Icon(Icons.image, size: 100, color: Colors.white30),
            ),
          ),
        ),
      ),
    );
  }

  void _showStatistics(BuildContext context) {
    final provider = context.read<ClipboardProvider>();
    final service = provider.service;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dist = provider.typeDistribution;
    final total = service.totalItems;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            padding: const EdgeInsets.all(24),
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey.shade900.withValues(alpha: 0.92) : Colors.white.withValues(alpha: 0.92),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border(
                top: BorderSide(
                  color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.5),
                ),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                Text('Clipboard Statistics',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: -0.5, color: cs.onSurface),
                ),
                const SizedBox(height: 20),
                Row(children: [
                  _statTile(cs, Icons.content_paste, '${service.totalItems}', 'Saved Items'),
                  _statTile(cs, Icons.image, '${service.imageCount}', 'Images'),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  _statTile(cs, Icons.link, '${service.linkCount}', 'Links'),
                  _statTile(cs, Icons.text_fields, '${service.textCount}', 'Text'),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  _statTile(cs, Icons.star, '${service.favoriteCount}', 'Favorites'),
                  _statTile(cs, Icons.storage, service.storageFormatted, 'Storage'),
                ]),
                if (dist.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Type Distribution', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: cs.onSurface)),
                        const SizedBox(height: 12),
                        ...dist.entries.map((e) {
                          final pct = total > 0 ? (e.value / total * 100) : 0.0;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 80,
                                  child: Text(
                                    e.key,
                                    style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.7)),
                                  ),
                                ),
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: pct / 100,
                                      minHeight: 8,
                                      backgroundColor: cs.surfaceContainerHighest,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 40,
                                  child: Text(
                                    '${pct.toInt()}%',
                                    textAlign: TextAlign.right,
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurface),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statTile(ColorScheme cs, IconData icon, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, color: cs.primary, size: 24),
            const SizedBox(height: 8),
            Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: cs.onSurface)),
            Text(label, style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.5))),
          ],
        ),
      ),
    );
  }

  void _showExportDialog(BuildContext context) {
    final provider = context.read<ClipboardProvider>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.transparent,
        contentPadding: EdgeInsets.zero,
        content: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.grey.shade900.withValues(alpha: 0.85)
                    : Colors.white.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.white.withValues(alpha: 0.5),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Export Clipboard', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 20),
                  ListTile(
                    leading: const Icon(Icons.text_snippet),
                    title: const Text('Plain Text (.txt)'),
                    onTap: () {
                      Navigator.pop(ctx);
                      Clipboard.setData(ClipboardData(text: provider.exportAsText));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: const Text('Copied as text'), behavior: SnackBarBehavior.floating),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.data_object),
                    title: const Text('JSON (.json)'),
                    onTap: () {
                      Navigator.pop(ctx);
                      Clipboard.setData(ClipboardData(text: provider.exportAsJson));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: const Text('Copied as JSON'), behavior: SnackBarBehavior.floating),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.table_chart),
                    title: const Text('CSV (.csv)'),
                    onTap: () {
                      Navigator.pop(ctx);
                      Clipboard.setData(ClipboardData(text: provider.exportAsCsv));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: const Text('Copied as CSV'), behavior: SnackBarBehavior.floating),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showImportDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.transparent,
        contentPadding: EdgeInsets.zero,
        content: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.grey.shade900.withValues(alpha: 0.85)
                    : Colors.white.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.white.withValues(alpha: 0.5),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Import Clipboard', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 20),
                  ListTile(
                    leading: const Icon(Icons.data_object),
                    title: const Text('Import from JSON'),
                    subtitle: const Text('Paste JSON data'),
                    onTap: () {
                      Navigator.pop(ctx);
                      _showImportTextField(context);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.text_snippet),
                    title: const Text('Import from TXT'),
                    subtitle: const Text('Paste formatted text'),
                    onTap: () {
                      Navigator.pop(ctx);
                      _showImportTextField(context, isJson: false);
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showImportTextField(BuildContext context, {bool isJson = true}) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isJson ? 'Import JSON' : 'Import Text'),
        content: TextField(
          controller: controller,
          maxLines: 10,
          decoration: InputDecoration(
            hintText: isJson ? 'Paste JSON data here...' : 'Paste text data here...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final provider = context.read<ClipboardProvider>();
              final count = isJson
                  ? await provider.importFromJson(controller.text)
                  : await provider.importFromText(controller.text);
              if (context.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Imported $count items'), behavior: SnackBarBehavior.floating),
                );
              }
            },
            child: const Text('Import'),
          ),
        ],
      ),
    );
  }

  void _confirmClearAll(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.transparent,
        contentPadding: EdgeInsets.zero,
        content: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.grey.shade900.withValues(alpha: 0.85)
                    : Colors.white.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.white.withValues(alpha: 0.5),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.delete_sweep, color: Colors.red, size: 22),
                      ),
                      const SizedBox(width: 14),
                      const Text('Clear All', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'This will permanently delete all clipboard items.',
                    style: TextStyle(fontSize: 14, color: cs.onSurface.withValues(alpha: 0.7)),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text('Cancel', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6))),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: () {
                          context.read<ClipboardProvider>().clearAll();
                          Navigator.pop(ctx);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.withValues(alpha: 0.2),
                          foregroundColor: Colors.red,
                        ),
                        child: const Text('Clear All'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _confirmDeleteSelected(BuildContext context, ClipboardProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Selected?'),
        content: Text('Delete ${provider.selectedIds.length} items?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              provider.deleteSelected();
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  _SliverAppBarDelegate(this.child);

  @override
  double get minExtent => 100;
  @override
  double get maxExtent => 100;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return child;
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) => child != oldDelegate.child;
}
