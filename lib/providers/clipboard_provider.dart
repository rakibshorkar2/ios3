import 'package:flutter/foundation.dart';
import 'dart:async';
import '../models/clipboard_item.dart';
import '../services/clipboard_service.dart';

class ClipboardProvider with ChangeNotifier {
  final ClipboardService _service = ClipboardService();
  List<ClipboardItem> _filteredItems = [];
  ClipboardContentType _selectedFilter = ClipboardContentType.text;
  String _searchQuery = '';
  bool _showFavoritesOnly = false;
  bool _isMultiSelectMode = false;
  final Set<String> _selectedIds = {};
  Timer? _detectionTimer;
  ClipboardItem? _newlyDetectedItem;

  ClipboardService get service => _service;
  List<ClipboardItem> get items => _filteredItems;
  ClipboardContentType get selectedFilter => _selectedFilter;
  String get searchQuery => _searchQuery;
  bool get showFavoritesOnly => _showFavoritesOnly;
  bool get isMultiSelectMode => _isMultiSelectMode;
  Set<String> get selectedIds => _selectedIds;
  ClipboardItem? get newlyDetectedItem => _newlyDetectedItem;

  Map<String, int> get typeDistribution {
    final counts = <String, int>{};
    for (final item in _service.items) {
      final label = item.type.name;
      counts[label] = (counts[label] ?? 0) + 1;
    }
    return counts;
  }

  Future<void> init() async {
    await _service.init();
    _applyFilters();
    notifyListeners();
    _startDetectionTimer();
  }

  void _startDetectionTimer() {
    _detectionTimer?.cancel();
    _detectionTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _checkForNewClipboard();
    });
  }

  Future<void> _checkForNewClipboard() async {
    final item = await _service.detectNewClipboardItem();
    if (item != null) {
      _newlyDetectedItem = item;
      _applyFilters();
      notifyListeners();
    }
  }

  Future<ClipboardItem?> checkForNewClipboard() async {
    final item = await _service.detectNewClipboardItem();
    if (item != null) {
      _newlyDetectedItem = item;
      _applyFilters();
      notifyListeners();
    }
    return item;
  }

  Future<void> captureCurrentClipboard() async {
    final item = await _service.getLatestClipboard();
    if (item != null) {
      await _service.saveItem(item);
      _newlyDetectedItem = null;
      _applyFilters();
      notifyListeners();
    }
  }

  void dismissNewlyDetected() {
    if (_newlyDetectedItem != null) {
      _service.dismissItem(_newlyDetectedItem!.content);
      _newlyDetectedItem = null;
      notifyListeners();
    }
  }

  Future<void> saveNewlyDetected() async {
    if (_newlyDetectedItem != null) {
      await _service.saveItem(_newlyDetectedItem!);
      _newlyDetectedItem = null;
      _applyFilters();
      notifyListeners();
    }
  }

  void _applyFilters() {
    var items = _service.items.toList();

    if (_selectedFilter.index > 0) {
      items = items.where((i) => i.type == _selectedFilter).toList();
    }

    if (_showFavoritesOnly) {
      items = items.where((i) => i.isFavorite).toList();
    }

    if (_searchQuery.isNotEmpty) {
      final lower = _searchQuery.toLowerCase();
      items = items.where((i) {
        return i.content.toLowerCase().contains(lower) ||
            (i.domain?.toLowerCase().contains(lower) ?? false);
      }).toList();
    }

    items.sort((a, b) {
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      return b.createdAt.compareTo(a.createdAt);
    });

    _filteredItems = items;
  }

  void setFilter(ClipboardContentType filter) {
    _selectedFilter = filter;
    _showFavoritesOnly = false;
    _applyFilters();
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    _applyFilters();
    notifyListeners();
  }

  void setShowFavoritesOnly(bool val) {
    _showFavoritesOnly = val;
    if (val) _selectedFilter = ClipboardContentType.text;
    _applyFilters();
    notifyListeners();
  }

  Future<void> saveItem(ClipboardItem item) async {
    await _service.saveItem(item);
    _applyFilters();
    notifyListeners();
  }

  Future<void> deleteItem(String id) async {
    await _service.deleteItem(id);
    _selectedIds.remove(id);
    _applyFilters();
    notifyListeners();
  }

  Future<void> toggleFavorite(String id) async {
    await _service.toggleFavorite(id);
    _applyFilters();
    notifyListeners();
  }

  Future<void> togglePin(String id) async {
    await _service.togglePin(id);
    _applyFilters();
    notifyListeners();
  }

  Future<void> updateItem(ClipboardItem item) async {
    await _service.updateItem(item);
    _applyFilters();
    notifyListeners();
  }

  Future<void> updateItemContent(String id, String newContent) async {
    await _service.updateItemContent(id, newContent);
    _applyFilters();
    notifyListeners();
  }

  Future<void> addTags(String id, List<String> tags) async {
    await _service.addTags(id, tags);
    _applyFilters();
    notifyListeners();
  }

  Future<void> removeTag(String id, String tag) async {
    await _service.removeTag(id, tag);
    _applyFilters();
    notifyListeners();
  }

  void toggleMultiSelectMode() {
    _isMultiSelectMode = !_isMultiSelectMode;
    if (!_isMultiSelectMode) _selectedIds.clear();
    notifyListeners();
  }

  void toggleSelection(String id) {
    if (_selectedIds.contains(id)) {
      _selectedIds.remove(id);
    } else {
      _selectedIds.add(id);
    }
    notifyListeners();
  }

  void selectAll() {
    _selectedIds.addAll(_filteredItems.map((i) => i.id));
    notifyListeners();
  }

  void clearSelection() {
    _selectedIds.clear();
    notifyListeners();
  }

  Future<void> deleteSelected() async {
    final ids = _selectedIds.toList();
    await _service.deleteMultiple(ids);
    _selectedIds.clear();
    _isMultiSelectMode = false;
    _applyFilters();
    notifyListeners();
  }

  Future<void> toggleFavoriteSelected() async {
    final ids = _selectedIds.toList();
    for (final id in ids) {
      await _service.toggleFavorite(id);
    }
    _selectedIds.clear();
    _isMultiSelectMode = false;
    _applyFilters();
    notifyListeners();
  }

  Future<void> clearAll() async {
    await _service.clearAll();
    _applyFilters();
    notifyListeners();
  }

  Future<void> clearByType(ClipboardContentType type) async {
    await _service.clearByType(type);
    _applyFilters();
    notifyListeners();
  }

  Future<void> dismissItem(String content) async {
    await _service.dismissItem(content);
  }

  String get exportAsText => _service.exportAsText();
  String get exportAsJson => _service.exportAsJson();
  String get exportAsCsv => _service.exportAsCsv();

  Future<int> importFromJson(String json) async {
    final count = await _service.importFromJson(json);
    _applyFilters();
    notifyListeners();
    return count;
  }

  Future<int> importFromText(String text) async {
    final count = await _service.importFromText(text);
    _applyFilters();
    notifyListeners();
    return count;
  }

  ClipboardItem? getItemById(String id) {
    try {
      return _service.items.firstWhere((i) => i.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _detectionTimer?.cancel();
    _service.dispose();
    super.dispose();
  }
}
