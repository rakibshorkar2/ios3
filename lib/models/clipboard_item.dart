import 'dart:convert';

enum ClipboardContentType {
  text,
  url,
  image,
  richText,
  phone,
  email,
  json,
  code,
  color,
  filePath,
}

class ClipboardItem {
  final String id;
  final ClipboardContentType type;
  final String preview;
  final String content;
  final DateTime createdAt;
  bool isFavorite;
  bool isPinned;
  List<String> tags;
  int characterCount;
  int wordCount;
  int lineCount;
  String? domain;
  String? fileExtension;
  String? language;
  String? imagePath;

  ClipboardItem({
    required this.id,
    required this.type,
    required this.preview,
    required this.content,
    required this.createdAt,
    this.isFavorite = false,
    this.isPinned = false,
    this.tags = const [],
    int? characterCount,
    int? wordCount,
    int? lineCount,
    this.domain,
    this.fileExtension,
    this.language,
    this.imagePath,
  })  : characterCount = characterCount ?? content.length,
        wordCount = wordCount ?? content.split(RegExp(r'\s+')).length,
        lineCount = lineCount ?? '\n'.allMatches(content).length + 1;

  ClipboardItem copyWith({
    String? id,
    ClipboardContentType? type,
    String? preview,
    String? content,
    DateTime? createdAt,
    bool? isFavorite,
    bool? isPinned,
    List<String>? tags,
    int? characterCount,
    int? wordCount,
    int? lineCount,
    String? domain,
    String? fileExtension,
    String? language,
    String? imagePath,
  }) {
    return ClipboardItem(
      id: id ?? this.id,
      type: type ?? this.type,
      preview: preview ?? this.preview,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      isFavorite: isFavorite ?? this.isFavorite,
      isPinned: isPinned ?? this.isPinned,
      tags: tags ?? this.tags,
      characterCount: characterCount ?? this.characterCount,
      wordCount: wordCount ?? this.wordCount,
      lineCount: lineCount ?? this.lineCount,
      domain: domain ?? this.domain,
      fileExtension: fileExtension ?? this.fileExtension,
      language: language ?? this.language,
      imagePath: imagePath ?? this.imagePath,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.index,
      'preview': preview,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
      'isFavorite': isFavorite ? 1 : 0,
      'isPinned': isPinned ? 1 : 0,
      'tags': jsonEncode(tags),
      'characterCount': characterCount,
      'wordCount': wordCount,
      'domain': domain,
      'fileExtension': fileExtension,
      'language': language,
      'imagePath': imagePath,
    };
  }

  factory ClipboardItem.fromJson(Map<String, dynamic> json) {
    return ClipboardItem(
      id: json['id'],
      type: ClipboardContentType.values[json['type'] ?? 0],
      preview: json['preview'] ?? '',
      content: json['content'] ?? '',
      createdAt: DateTime.parse(json['createdAt']),
      isFavorite: (json['isFavorite'] ?? 0) == 1,
      isPinned: (json['isPinned'] ?? 0) == 1,
      tags: json['tags'] != null
          ? List<String>.from(jsonDecode(json['tags']))
          : [],
      characterCount: json['characterCount'],
      wordCount: json['wordCount'],
      domain: json['domain'],
      fileExtension: json['fileExtension'],
      language: json['language'],
      imagePath: json['imagePath'],
    );
  }

  static ClipboardContentType detectType(String text) {
    final trimmed = text.trim();

    if (trimmed.startsWith('http://') ||
        trimmed.startsWith('https://') ||
        trimmed.startsWith('ftp://') ||
        trimmed.startsWith('ftps://') ||
        trimmed.startsWith('magnet:')) {
      return ClipboardContentType.url;
    }

    if (RegExp(r'^[\w\.-]+@[\w\.-]+\.\w+$').hasMatch(trimmed)) {
      return ClipboardContentType.email;
    }

    if (RegExp(r'^\+?[\d\s\-\(\)]{7,15}$').hasMatch(trimmed)) {
      return ClipboardContentType.phone;
    }

    try {
      jsonDecode(text);
      return ClipboardContentType.json;
    } catch (_) {}

    if (RegExp(r'^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$').hasMatch(trimmed) ||
        RegExp(r'^rgb\(\d+,\s*\d+,\s*\d+\)$').hasMatch(trimmed) ||
        RegExp(r'^hsl\(\d+,\s*\d+%,\s*\d+%\)$').hasMatch(trimmed) ||
        RegExp(r'^rgba\(\d+,\s*\d+,\s*\d+,\s*[\d.]+\)$').hasMatch(trimmed)) {
      return ClipboardContentType.color;
    }

    if (trimmed.startsWith('/') ||
        trimmed.contains(RegExp(r'^[A-Za-z]:\\')) ||
        trimmed.contains(RegExp(r'^[A-Za-z]:/'))) {
      return ClipboardContentType.filePath;
    }

    if (text.contains('\n') || text.length > 200) {
      final codeIndicators = [
        RegExp(r'\bimport\b'),
        RegExp(r'\bdef \b'),
        RegExp(r'\bfunction\b'),
        RegExp(r'\bclass\b'),
        RegExp(r'\binterface\b'),
        RegExp(r'\benum\b'),
        RegExp(r'\bextends\b'),
        RegExp(r'\bimplements\b'),
        RegExp(r'\{[\s\S]*\}'),
        RegExp(r'^<[^>]+>'),
        RegExp(r'^</'),
        RegExp(r'<!DOCTYPE'),
        RegExp(r'\bSELECT\b|\bFROM\b|\bWHERE\b|\bJOIN\b|\bINSERT\b'),
        RegExp(r'\bpublic\b|\bprivate\b|\bprotected\b|\bstatic\b'),
        RegExp(r'\bvoid\b|\bint\b|\bstring\b|\bbool\b|\bdouble\b'),
        RegExp(r'^[{\[(]'),
      ];
      for (final indicator in codeIndicators) {
        if (indicator.hasMatch(text)) {
          return ClipboardContentType.code;
        }
      }
    }

    return ClipboardContentType.text;
  }

  static String detectLanguage(String text) {
    if (text.contains(RegExp(r'\bimport\b.*\bpackage\b'))) return 'dart';
    if (text.contains(RegExp(r'\bimport\b.*\bUIKit\b'))) return 'swift';
    if (text.contains(RegExp(r'\bdef \b|\bimport\b|\bfrom\b.*\bimport\b'))) return 'python';
    if (text.contains(RegExp(r'\bfunction\b|\bconst\b|\blet\b|\bvar\b|\b=>\b'))) return 'javascript';
    if (text.contains(RegExp(r'^<\!DOCTYPE html>'))) return 'html';
    if (text.contains(RegExp(r'\{[\s\S]*\}')) && text.contains(RegExp(r'@media'))) return 'css';
    if (text.contains(RegExp(r'\bSELECT\b|\bFROM\b|\bWHERE\b|\bJOIN\b'))) return 'sql';
    return 'code';
  }

  static String? extractDomain(String text) {
    final uri = Uri.tryParse(text);
    if (uri != null && uri.host.isNotEmpty) {
      return uri.host;
    }
    return null;
  }

  static String? extractFileExtension(String text) {
    final match = RegExp(r'\.([a-zA-Z0-9]+)$').firstMatch(text);
    return match?.group(1);
  }

  static String generatePreview(String content, {int maxLength = 120}) {
    if (content.length <= maxLength) return content;
    return '${content.substring(0, maxLength)}...';
  }
}
