import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/clipboard_item.dart';
import 'database_helper.dart';

class ClipboardService {
  static final ClipboardService _instance = ClipboardService._internal();
  factory ClipboardService() => _instance;
  ClipboardService._internal();

  Timer? _monitorTimer;
  String _lastClipboardContent = '';
  final Set<String> _dismissedItems = {};
  final List<ClipboardItem> _items = [];
  bool _monitoring = false;
  bool _popupEnabled = true;
  bool _autoSave = false;
  int _maxHistorySize = 5000;

  bool get monitoring => _monitoring;
  bool get popupEnabled => _popupEnabled;
  bool get autoSave => _autoSave;
  int get maxHistorySize => _maxHistorySize;
  List<ClipboardItem> get items => List.unmodifiable(_items);

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _monitoring = prefs.getBool('clipboardMonitoring') ?? true;
    _popupEnabled = prefs.getBool('clipboardPopupEnabled') ?? true;
    _autoSave = prefs.getBool('clipboardAutoSave') ?? false;
    _maxHistorySize = prefs.getInt('clipboardMaxHistory') ?? 5000;

    final dismissed = prefs.getStringList('clipboardDismissed') ?? [];
    _dismissedItems.addAll(dismissed);

    final data = await DatabaseHelper().getClipboardItems();
    _items.clear();
    _items.addAll(data);

    if (_monitoring) startMonitoring();
  }

  Future<void> setMonitoring(bool val) async {
    _monitoring = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('clipboardMonitoring', val);
    if (val) {
      startMonitoring();
    } else {
      stopMonitoring();
    }
  }

  Future<void> setPopupEnabled(bool val) async {
    _popupEnabled = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('clipboardPopupEnabled', val);
  }

  Future<void> setAutoSave(bool val) async {
    _autoSave = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('clipboardAutoSave', val);
  }

  Future<void> setMaxHistorySize(int val) async {
    _maxHistorySize = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('clipboardMaxHistory', val);
    if (_items.length > _maxHistorySize) {
      _items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      while (_items.length > _maxHistorySize) {
        final removed = _items.removeLast();
        DatabaseHelper().deleteClipboardItem(removed.id);
      }
    }
  }

  void startMonitoring() {
    _monitorTimer?.cancel();
    _monitorTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _checkClipboard();
    });
  }

  void stopMonitoring() {
    _monitorTimer?.cancel();
    _monitorTimer = null;
  }

  Future<ClipboardItem?> _checkClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text ?? '';
      if (text.isEmpty || text == _lastClipboardContent) return null;
      _lastClipboardContent = text;

      final existingIndex = _items.indexWhere(
        (item) => item.content == text,
      );
      if (existingIndex != -1) return null;

      if (_dismissedItems.contains(text)) return null;

      final item = _createItem(text);

      if (_autoSave) {
        await saveItem(item);
        return null;
      }

      return item;
    } catch (_) {
      return null;
    }
  }

  Future<ClipboardItem?> detectNewClipboardItem() async {
    return _checkClipboard();
  }

  String _generateId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final rand = Random().nextInt(99999);
    return '$now$rand';
  }

  ClipboardItem _createItem(String text) {
    final type = ClipboardItem.detectType(text);
    final id = _generateId();
    return ClipboardItem(
      id: id,
      type: type,
      preview: ClipboardItem.generatePreview(text),
      content: text,
      createdAt: DateTime.now(),
      domain: type == ClipboardContentType.url ? ClipboardItem.extractDomain(text) : null,
      fileExtension: type == ClipboardContentType.filePath ? ClipboardItem.extractFileExtension(text) : null,
      language: type == ClipboardContentType.code ? ClipboardItem.detectLanguage(text) : null,
    );
  }

  Future<void> saveItem(ClipboardItem item) async {
    _items.insert(0, item);
    await DatabaseHelper().insertClipboardItem(item);
    if (_items.length > _maxHistorySize) {
      final removed = _items.removeLast();
      DatabaseHelper().deleteClipboardItem(removed.id);
    }
  }

  Future<void> dismissItem(String content) async {
    _dismissedItems.add(content);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('clipboardDismissed', _dismissedItems.toList());
  }

  Future<void> deleteItem(String id) async {
    _items.removeWhere((item) => item.id == id);
    await DatabaseHelper().deleteClipboardItem(id);
  }

  Future<void> toggleFavorite(String id) async {
    final index = _items.indexWhere((item) => item.id == id);
    if (index == -1) return;
    _items[index].isFavorite = !_items[index].isFavorite;
    await DatabaseHelper().updateClipboardItem(_items[index]);
  }

  Future<void> togglePin(String id) async {
    final index = _items.indexWhere((item) => item.id == id);
    if (index == -1) return;
    _items[index].isPinned = !_items[index].isPinned;
    await DatabaseHelper().updateClipboardItem(_items[index]);
  }

  Future<void> updateItem(ClipboardItem item) async {
    final index = _items.indexWhere((i) => i.id == item.id);
    if (index != -1) {
      _items[index] = item;
    }
    await DatabaseHelper().updateClipboardItem(item);
  }

  Future<void> updateItemContent(String id, String newContent) async {
    final index = _items.indexWhere((i) => i.id == id);
    if (index == -1) return;
    final updated = _items[index].copyWith(
      content: newContent,
      preview: ClipboardItem.generatePreview(newContent),
      type: ClipboardItem.detectType(newContent),
      characterCount: newContent.length,
      wordCount: newContent.split(RegExp(r'\s+')).length,
      lineCount: '\n'.allMatches(newContent).length + 1,
      domain: ClipboardItem.detectType(newContent) == ClipboardContentType.url
          ? ClipboardItem.extractDomain(newContent)
          : null,
      language: ClipboardItem.detectType(newContent) == ClipboardContentType.code
          ? ClipboardItem.detectLanguage(newContent)
          : _items[index].language,
    );
    _items[index] = updated;
    await DatabaseHelper().updateClipboardItem(updated);
  }

  Future<void> addTags(String id, List<String> newTags) async {
    final index = _items.indexWhere((i) => i.id == id);
    if (index == -1) return;
    final existing = Set<String>.from(_items[index].tags);
    existing.addAll(newTags.map((t) => t.trim()).where((t) => t.isNotEmpty));
    _items[index].tags = existing.toList();
    await DatabaseHelper().updateClipboardItem(_items[index]);
  }

  Future<void> removeTag(String id, String tag) async {
    final index = _items.indexWhere((i) => i.id == id);
    if (index == -1) return;
    _items[index].tags = _items[index].tags.where((t) => t != tag).toList();
    await DatabaseHelper().updateClipboardItem(_items[index]);
  }

  Future<ClipboardItem?> getLatestClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (text.isEmpty) return null;
    final exists = _items.any((i) => i.content == text);
    if (exists) return null;
    return _createItem(text);
  }

  List<ClipboardItem> search(String query) {
    if (query.isEmpty) return List.unmodifiable(_items);
    final lower = query.toLowerCase();
    return _items.where((item) {
      return item.content.toLowerCase().contains(lower) ||
          (item.domain?.toLowerCase().contains(lower) ?? false) ||
          item.type.name.toLowerCase().contains(lower) ||
          item.tags.any((t) => t.toLowerCase().contains(lower));
    }).toList();
  }

  List<ClipboardItem> filterByType(ClipboardContentType type) {
    if (type == ClipboardContentType.text) return _items.where((i) => i.type == type).toList();
    return _items.where((i) => i.type == type).toList();
  }

  List<ClipboardItem> getFavorites() {
    return _items.where((i) => i.isFavorite).toList();
  }

  List<ClipboardItem> getPinned() {
    return _items.where((i) => i.isPinned).toList();
  }

  Future<void> deleteMultiple(List<String> ids) async {
    _items.removeWhere((item) => ids.contains(item.id));
    for (final id in ids) {
      await DatabaseHelper().deleteClipboardItem(id);
    }
  }

  Future<void> toggleFavoriteMultiple(List<String> ids) async {
    for (final id in ids) {
      await toggleFavorite(id);
    }
  }

  Future<void> clearAll() async {
    _items.clear();
    await DatabaseHelper().clearClipboardItems();
  }

  Future<void> clearByType(ClipboardContentType type) async {
    final ids = _items.where((i) => i.type == type).map((i) => i.id).toList();
    for (final id in ids) {
      await deleteItem(id);
    }
  }

  String exportAsText() {
    return _items
        .map((item) =>
            '[${item.type.name.toUpperCase()}] ${item.createdAt.toIso8601String()}\n${item.content}\n---')
        .join('\n');
  }

  String exportAsJson() {
    return jsonEncode(_items.map((item) => item.toJson()).toList());
  }

  String exportAsCsv() {
    final buffer = StringBuffer();
    buffer.writeln('Type,Preview,Content,Created At,Favorite,Pinned');
    for (final item in _items) {
      final escaped = item.content.replaceAll('"', '""');
      buffer.writeln(
          '${item.type.name},"${item.preview.replaceAll('"', '""')}","$escaped",${item.createdAt.toIso8601String()},${item.isFavorite},${item.isPinned}');
    }
    return buffer.toString();
  }

  Future<int> importFromJson(String json) async {
    try {
      final List<dynamic> data = jsonDecode(json);
      int count = 0;
      for (final d in data) {
        final item = ClipboardItem.fromJson(d);
        final exists = _items.any((i) => i.content == item.content);
        if (!exists) {
          await saveItem(item);
          count++;
        }
      }
      return count;
    } catch (_) {
      return 0;
    }
  }

  Future<int> importFromText(String text) async {
    final lines = text.split('\n');
    int count = 0;
    String currentContent = '';
    for (final line in lines) {
      if (line == '---') {
        if (currentContent.isNotEmpty) {
          final item = _createItem(currentContent);
          final exists = _items.any((i) => i.content == item.content);
          if (!exists) {
            await saveItem(item);
            count++;
          }
          currentContent = '';
        }
      } else if (!line.startsWith('[')) {
        currentContent += '$line\n';
      }
    }
    return count;
  }

  int get totalItems => _items.length;
  int get imageCount => _items.where((i) => i.type == ClipboardContentType.image).length;
  int get linkCount => _items.where((i) => i.type == ClipboardContentType.url).length;
  int get textCount => _items.where((i) => i.type == ClipboardContentType.text).length;
  int get favoriteCount => _items.where((i) => i.isFavorite).length;
  int get storageBytes => _items.fold(0, (sum, item) => sum + item.content.length);
  String get storageFormatted {
    final bytes = storageBytes;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void dispose() {
    _monitorTimer?.cancel();
  }
}
