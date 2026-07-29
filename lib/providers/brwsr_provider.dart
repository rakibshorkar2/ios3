import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import 'dart:convert';

class GDriveItem {
  final String id;
  final String name;
  final String downloadUrl;
  final bool isFolder;
  bool isSelected;

  GDriveItem({
    required this.id,
    required this.name,
    required this.downloadUrl,
    this.isFolder = false,
    this.isSelected = true,
  });
}

class BRWSRTabData {
  final String id;
  String url;
  String title;
  InAppWebViewController? controller;
  FindInteractionController? findController;
  double progress;
  bool isLoading;
  bool isIncognito;
  bool isDesktopMode;
  bool canGoBack;
  bool canGoForward;
  int adsBlockedCount;
  String? faviconUrl;
  String? errorMessage;
  final List<String> detectedMediaLinks;

  BRWSRTabData({
    required this.id,
    this.url = 'https://www.google.com',
    this.title = 'New Tab',
    this.controller,
    FindInteractionController? findController,
    this.progress = 0.0,
    this.isLoading = false,
    this.isIncognito = false,
    this.isDesktopMode = false,
    this.canGoBack = false,
    this.canGoForward = false,
    this.adsBlockedCount = 0,
    this.faviconUrl,
    this.errorMessage,
    List<String>? detectedMediaLinks,
  })  : findController = findController ?? FindInteractionController(),
        detectedMediaLinks = detectedMediaLinks ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'title': title,
        'isIncognito': isIncognito,
        'isDesktopMode': isDesktopMode,
      };

  factory BRWSRTabData.fromJson(Map<String, dynamic> json) => BRWSRTabData(
        id: json['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
        url: json['url'] ?? 'https://www.google.com',
        title: json['title'] ?? 'New Tab',
        isIncognito: json['isIncognito'] ?? false,
        isDesktopMode: json['isDesktopMode'] ?? false,
      );
}

class BRWSRBookmarkItem {
  final String id;
  final String title;
  final String url;
  final DateTime createdAt;

  BRWSRBookmarkItem({
    required this.id,
    required this.title,
    required this.url,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'url': url,
        'createdAt': createdAt.toIso8601String(),
      };

  factory BRWSRBookmarkItem.fromJson(Map<String, dynamic> json) =>
      BRWSRBookmarkItem(
        id: json['id'] ?? '',
        title: json['title'] ?? '',
        url: json['url'] ?? '',
        createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      );
}

class BRWSRHistoryItem {
  final String id;
  final String title;
  final String url;
  final DateTime timestamp;

  BRWSRHistoryItem({
    required this.id,
    required this.title,
    required this.url,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'url': url,
        'timestamp': timestamp.toIso8601String(),
      };

  factory BRWSRHistoryItem.fromJson(Map<String, dynamic> json) =>
      BRWSRHistoryItem(
        id: json['id'] ?? '',
        title: json['title'] ?? '',
        url: json['url'] ?? '',
        timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
      );
}

class BRWSRProvider with ChangeNotifier {
  final List<BRWSRTabData> _tabs = [];
  int _activeTabIndex = 0;

  List<BRWSRBookmarkItem> _bookmarks = [];
  List<BRWSRHistoryItem> _history = [];

  bool _adBlockerEnabled = true;
  int _totalAdsBlockedSession = 0;

  // Find in page state
  bool _isFindInPageActive = false;
  String _findQuery = '';
  int _currentMatchIndex = 0;
  int _totalMatches = 0;

  BRWSRProvider() {
    _loadOpenTabs();
    _loadBookmarks();
    _loadHistory();
    _loadAdBlockerState();
  }

  // Getters
  List<BRWSRTabData> get tabs => List.unmodifiable(_tabs);
  int get activeTabIndex => _activeTabIndex;
  BRWSRTabData? get activeTab =>
      _tabs.isNotEmpty && _activeTabIndex < _tabs.length
          ? _tabs[_activeTabIndex]
          : null;

  List<BRWSRBookmarkItem> get bookmarks => List.unmodifiable(_bookmarks);
  List<BRWSRHistoryItem> get history => List.unmodifiable(_history);

  bool get adBlockerEnabled => _adBlockerEnabled;
  int get totalAdsBlockedSession => _totalAdsBlockedSession;

  bool get isFindInPageActive => _isFindInPageActive;
  String get findQuery => _findQuery;
  int get currentMatchIndex => _currentMatchIndex;
  int get totalMatches => _totalMatches;

  void _initDefaultTab() {
    if (_tabs.isEmpty) {
      _tabs.add(BRWSRTabData(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        url: 'https://www.google.com',
        title: 'Google',
      ));
      _activeTabIndex = 0;
    }
  }

  // --- Open Tabs Persistence ---
  Future<void> _loadOpenTabs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = prefs.getString('brwsr_open_tabs_v2');
      final idx = prefs.getInt('brwsr_active_index_v2') ?? 0;
      if (str != null) {
        final List<dynamic> list = jsonDecode(str);
        if (list.isNotEmpty) {
          _tabs.clear();
          _tabs.addAll(list.map((e) => BRWSRTabData.fromJson(e)).toList());
          _activeTabIndex = (idx >= 0 && idx < _tabs.length) ? idx : 0;
        }
      }
    } catch (e) {
      debugPrint('Error loading open tabs: $e');
    }
    if (_tabs.isEmpty) {
      _initDefaultTab();
    }
    notifyListeners();
  }

  Future<void> saveOpenTabs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = jsonEncode(_tabs.map((t) => t.toJson()).toList());
      await prefs.setString('brwsr_open_tabs_v2', str);
      await prefs.setInt('brwsr_active_index_v2', _activeTabIndex);
    } catch (e) {
      debugPrint('Error saving open tabs: $e');
    }
  }

  // --- Tab Management ---
  void addNewTab({String? url, bool isIncognito = false}) {
    final newTab = BRWSRTabData(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      url: url ?? 'https://www.google.com',
      title: isIncognito ? 'Private Tab' : 'New Tab',
      isIncognito: isIncognito,
    );
    _tabs.add(newTab);
    _activeTabIndex = _tabs.length - 1;
    saveOpenTabs();
    notifyListeners();
  }

  void closeTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    _tabs.removeAt(index);
    if (_tabs.isEmpty) {
      addNewTab();
    } else if (_activeTabIndex >= _tabs.length) {
      _activeTabIndex = _tabs.length - 1;
    }
    saveOpenTabs();
    notifyListeners();
  }

  void switchTab(int index) {
    if (index >= 0 && index < _tabs.length) {
      _activeTabIndex = index;
      saveOpenTabs();
      notifyListeners();
    }
  }

  void updateActiveTabUrl(String newUrl) {
    if (activeTab != null) {
      activeTab!.url = newUrl;
      activeTab!.errorMessage = null;
      saveOpenTabs();
      notifyListeners();
    }
  }

  void updateActiveTabTitle(String title) {
    if (activeTab != null && title.isNotEmpty) {
      activeTab!.title = title;
      saveOpenTabs();
      notifyListeners();
    }
  }

  void addDetectedMediaLink(String mediaUrl) {
    if (activeTab != null && !activeTab!.detectedMediaLinks.contains(mediaUrl)) {
      activeTab!.detectedMediaLinks.add(mediaUrl);
      notifyListeners();
    }
  }

  void updateActiveTabProgress(double progress) {
    if (activeTab != null) {
      activeTab!.progress = progress;
      activeTab!.isLoading = progress < 1.0;
      notifyListeners();
    }
  }

  void updateActiveTabNavigationState({bool? canGoBack, bool? canGoForward}) {
    if (activeTab != null) {
      if (canGoBack != null) activeTab!.canGoBack = canGoBack;
      if (canGoForward != null) activeTab!.canGoForward = canGoForward;
      notifyListeners();
    }
  }

  void setTabController(int index, InAppWebViewController controller) {
    if (index >= 0 && index < _tabs.length) {
      _tabs[index].controller = controller;
    }
  }

  void clearActiveTabError() {
    if (activeTab != null) {
      activeTab!.errorMessage = null;
      notifyListeners();
    }
  }

  void toggleDesktopMode() {
    if (activeTab != null) {
      activeTab!.isDesktopMode = !activeTab!.isDesktopMode;
      activeTab!.controller?.reload();
      saveOpenTabs();
      notifyListeners();
    }
  }

  // --- Bookmarks ---
  Future<void> _loadBookmarks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = prefs.getString('brwsr_bookmarks');
      if (str != null) {
        final List<dynamic> list = jsonDecode(str);
        _bookmarks = list.map((e) => BRWSRBookmarkItem.fromJson(e)).toList();
      }
    } catch (e) {
      debugPrint('Error loading BRWSR bookmarks: $e');
    }
    notifyListeners();
  }

  Future<void> _saveBookmarks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = jsonEncode(_bookmarks.map((e) => e.toJson()).toList());
      await prefs.setString('brwsr_bookmarks', str);
    } catch (e) {
      debugPrint('Error saving BRWSR bookmarks: $e');
    }
  }

  bool isBookmarked(String url) {
    return _bookmarks.any((b) => b.url == url);
  }

  void toggleBookmark({String? url, String? title}) {
    final targetUrl = url ?? activeTab?.url;
    if (targetUrl == null || targetUrl.isEmpty) return;

    final targetTitle = title ?? activeTab?.title ?? targetUrl;
    final index = _bookmarks.indexWhere((b) => b.url == targetUrl);

    if (index >= 0) {
      _bookmarks.removeAt(index);
    } else {
      _bookmarks.add(BRWSRBookmarkItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: targetTitle,
        url: targetUrl,
        createdAt: DateTime.now(),
      ));
    }
    _saveBookmarks();
    notifyListeners();
  }

  void removeBookmark(String id) {
    _bookmarks.removeWhere((b) => b.id == id);
    _saveBookmarks();
    notifyListeners();
  }

  // --- History ---
  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = prefs.getString('brwsr_history');
      if (str != null) {
        final List<dynamic> list = jsonDecode(str);
        _history = list.map((e) => BRWSRHistoryItem.fromJson(e)).toList();
      }
    } catch (e) {
      debugPrint('Error loading BRWSR history: $e');
    }
    notifyListeners();
  }

  Future<void> _saveHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = jsonEncode(_history.map((e) => e.toJson()).toList());
      await prefs.setString('brwsr_history', str);
    } catch (e) {
      debugPrint('Error saving BRWSR history: $e');
    }
  }

  void recordHistory(String url, String title) {
    // Avoid saving history in Incognito Mode or empty URLs
    if (activeTab?.isIncognito == true) return;
    if (url.isEmpty || url == 'about:blank') return;

    // Avoid duplicate contiguous history
    if (_history.isNotEmpty && _history.first.url == url) return;

    _history.insert(
      0,
      BRWSRHistoryItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: title.isNotEmpty ? title : url,
        url: url,
        timestamp: DateTime.now(),
      ),
    );

    // Keep history size reasonable (max 1000 items)
    if (_history.length > 1000) {
      _history = _history.sublist(0, 1000);
    }

    _saveHistory();
    notifyListeners();
  }

  void removeHistoryItem(String id) {
    _history.removeWhere((h) => h.id == id);
    _saveHistory();
    notifyListeners();
  }

  void clearHistory() {
    _history.clear();
    _saveHistory();
    notifyListeners();
  }

  // --- Ad Blocker System ---
  Future<void> _loadAdBlockerState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _adBlockerEnabled = prefs.getBool('brwsr_adblocker_enabled') ?? true;
    } catch (_) {}
    notifyListeners();
  }

  void toggleAdBlocker() {
    _adBlockerEnabled = !_adBlockerEnabled;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool('brwsr_adblocker_enabled', _adBlockerEnabled);
    });
    // Reload active tab to apply changes
    activeTab?.controller?.reload();
    notifyListeners();
  }

  void registerAdBlockedOnPage() {
    if (activeTab != null) {
      activeTab!.adsBlockedCount++;
    }
    _totalAdsBlockedSession++;
    notifyListeners();
  }

  List<ContentBlocker> getAdBlockerRules({String? customDomains}) {
    if (!_adBlockerEnabled) return [];

    final rules = <ContentBlocker>[
      ContentBlocker(
        trigger: ContentBlockerTrigger(
          urlFilter: ".*(doubleclick\\.net|googlesyndication\\.com|adservice\\.google\\.com|pagead2|adsystem|adnxs\\.com|popads\\.net|taboola\\.com|outbrain\\.com|rubiconproject\\.com|scorecardresearch\\.com|analytics\\.google\\.com|googletagmanager\\.com|adform\\.net|smartadserver\\.com|openx\\.net|criteo\\.com|pubmatic\\.com).*",
          resourceType: [
            ContentBlockerTriggerResourceType.SCRIPT,
            ContentBlockerTriggerResourceType.IMAGE,
            ContentBlockerTriggerResourceType.RAW,
            ContentBlockerTriggerResourceType.SVG_DOCUMENT,
            ContentBlockerTriggerResourceType.STYLE_SHEET,
          ],
        ),
        action: ContentBlockerAction(
          type: ContentBlockerActionType.BLOCK,
        ),
      ),
      ContentBlocker(
        trigger: ContentBlockerTrigger(
          urlFilter: ".*(banner|popup|adserver|adwrapper|adframe|ad_box|adsales|telemetry).*",
          resourceType: [
            ContentBlockerTriggerResourceType.IMAGE,
            ContentBlockerTriggerResourceType.SCRIPT,
            ContentBlockerTriggerResourceType.RAW,
            ContentBlockerTriggerResourceType.SVG_DOCUMENT,
          ],
        ),
        action: ContentBlockerAction(
          type: ContentBlockerActionType.BLOCK,
        ),
      ),
    ];

    if (customDomains != null && customDomains.trim().isNotEmpty) {
      final domains = customDomains
          .split(RegExp(r'[,\n\s]+'))
          .map((d) => d.trim())
          .where((d) => d.isNotEmpty)
          .map((d) => RegExp.escape(d))
          .join('|');
      if (domains.isNotEmpty) {
        rules.add(
          ContentBlocker(
            trigger: ContentBlockerTrigger(
              urlFilter: ".*($domains).*",
              resourceType: [
                ContentBlockerTriggerResourceType.SCRIPT,
                ContentBlockerTriggerResourceType.IMAGE,
                ContentBlockerTriggerResourceType.RAW,
                ContentBlockerTriggerResourceType.SVG_DOCUMENT,
                ContentBlockerTriggerResourceType.STYLE_SHEET,
              ],
            ),
            action: ContentBlockerAction(
              type: ContentBlockerActionType.BLOCK,
            ),
          ),
        );
      }
    }

    return rules;
  }

  // --- Google Drive Shared Folder & File Extractor ---
  Future<List<GDriveItem>> extractGoogleDriveFolder(
      String url, InAppWebViewController? controller) async {
    final items = <GDriveItem>[];
    final seenIds = <String>{};

    // Attempt 1: JS Evaluation in WebView DOM
    if (controller != null) {
      try {
        final jsCode = '''
          (function() {
            var results = [];
            var els = document.querySelectorAll('div[data-id], a[href*="/file/d/"], div[role="row"]');
            els.forEach(function(el) {
              var id = el.getAttribute('data-id') || '';
              var href = el.getAttribute('href') || '';
              var text = el.innerText || el.getAttribute('aria-label') || '';
              if (!id && href.includes('/file/d/')) {
                var m = href.match(/\\/file\\/d\\/([^\\/\\?]+)/);
                if (m) id = m[1];
              }
              if (id && id.length > 10) {
                var name = text.split('\\n')[0].trim();
                if (!name || name.length < 2) name = 'Google_Drive_File_' + id.substring(0, 6);
                results.push({id: id, name: name});
              }
            });
            return JSON.stringify(results);
          })()
        ''';
        final res = await controller.evaluateJavascript(source: jsCode);
        if (res != null) {
          final List<dynamic> list = jsonDecode(res.toString());
          for (var obj in list) {
            final id = obj['id'].toString();
            final name = obj['name'].toString();
            if (seenIds.add(id)) {
              items.add(GDriveItem(
                id: id,
                name: name,
                downloadUrl: 'https://drive.google.com/uc?export=download&id=$id',
              ));
            }
          }
        }
      } catch (e) {
        debugPrint('JS GDrive Extraction error: $e');
      }
    }

    // Attempt 2: Direct HTTP parse fallback if items empty
    if (items.isEmpty) {
      try {
        final dio = Dio();
        final response = await dio.get(url);
        final html = response.data.toString();

        // Match all file IDs in HTML source
        final reg = RegExp(r'\/file\/d\/([a-zA-Z0-9_-]{25,})|data-id="([a-zA-Z0-9_-]{25,})"');
        final matches = reg.allMatches(html);
        for (var m in matches) {
          final id = m.group(1) ?? m.group(2);
          if (id != null && seenIds.add(id)) {
            items.add(GDriveItem(
              id: id,
              name: 'Google_Drive_File_${id.substring(0, 6)}',
              downloadUrl: 'https://drive.google.com/uc?export=download&id=$id',
            ));
          }
        }
      } catch (e) {
        debugPrint('HTTP GDrive parse fallback error: $e');
      }
    }

    return items;
  }

  // --- Find In Page ---
  void openFindInPage() {
    _isFindInPageActive = true;
    _findQuery = '';
    _currentMatchIndex = 0;
    _totalMatches = 0;
    notifyListeners();
  }

  void closeFindInPage() {
    _isFindInPageActive = false;
    _findQuery = '';
    _currentMatchIndex = 0;
    _totalMatches = 0;
    activeTab?.findController?.clearMatches();
    notifyListeners();
  }

  void updateFindQuery(String query) {
    _findQuery = query;
    if (query.isNotEmpty) {
      activeTab?.findController?.findAll(find: query);
    } else {
      activeTab?.findController?.clearMatches();
      _currentMatchIndex = 0;
      _totalMatches = 0;
    }
    notifyListeners();
  }

  void findNext() {
    if (_findQuery.isNotEmpty) {
      activeTab?.findController?.findNext(forward: true);
    }
  }

  void findPrevious() {
    if (_findQuery.isNotEmpty) {
      activeTab?.findController?.findNext(forward: false);
    }
  }

  void updateFindResult(int activeMatchIndex, int numberOfMatches) {
    _currentMatchIndex = activeMatchIndex;
    _totalMatches = numberOfMatches;
    notifyListeners();
  }
}
