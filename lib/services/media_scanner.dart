import 'dart:io';

enum MediaKind { video, audio }

class MediaEntry {
  final String name;
  final String relPath;
  final bool isFolder;
  final MediaKind? kind;
  final int size;

  MediaEntry({
    required this.name,
    required this.relPath,
    required this.isFolder,
    this.kind,
    this.size = 0,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'path': relPath,
        'kind': isFolder ? null : (kind == MediaKind.video ? 'video' : 'audio'),
        'size': size,
      };
}

class MediaScanner {
  static const Map<String, String> mimeTypes = {
    '.mp4': 'video/mp4',
    '.m4v': 'video/mp4',
    '.webm': 'video/webm',
    '.ogv': 'video/ogg',
    '.mov': 'video/quicktime',
    '.mkv': 'video/x-matroska',
    '.avi': 'video/x-msvideo',
    '.mp3': 'audio/mpeg',
    '.wav': 'audio/wav',
    '.flac': 'audio/flac',
    '.m4a': 'audio/mp4',
    '.aac': 'audio/aac',
    '.ogg': 'audio/ogg',
    '.opus': 'audio/opus',
    '.wma': 'audio/x-ms-wma',
  };

  static MediaKind? kindForExtension(String ext) {
    final mime = mimeTypes[ext.toLowerCase()];
    if (mime == null) return null;
    return mime.startsWith('video') ? MediaKind.video : MediaKind.audio;
  }

  static String mimeForExtension(String ext) {
    return mimeTypes[ext.toLowerCase()] ?? 'application/octet-stream';
  }

  final Directory mediaRoot;

  MediaScanner(this.mediaRoot);

  /// Resolves a client-supplied relative path against [mediaRoot], refusing
  /// anything that would escape it (path traversal protection). Returns
  /// null if the path is unsafe.
  FileSystemEntity? safeResolve(String relPath) {
    final cleaned = relPath.replaceFirst(RegExp(r'^[/\\]+'), '');
    final resolved = File('${mediaRoot.path}${Platform.pathSeparator}$cleaned');
    final normalizedRoot = mediaRoot.absolute.path;
    final normalizedTarget = resolved.absolute.path;
    if (normalizedTarget != normalizedRoot &&
        !normalizedTarget.startsWith('$normalizedRoot${Platform.pathSeparator}')) {
      return null;
    }
    return resolved;
  }

  List<MediaEntry> list(String relPath) {
    final cleaned = relPath.replaceFirst(RegExp(r'^[/\\]+'), '');
    final dirPath = cleaned.isEmpty
        ? mediaRoot
        : Directory('${mediaRoot.path}${Platform.pathSeparator}$cleaned');

    final normalizedRoot = mediaRoot.absolute.path;
    final normalizedTarget = dirPath.absolute.path;
    final isInsideRoot = normalizedTarget == normalizedRoot ||
        normalizedTarget.startsWith('$normalizedRoot${Platform.pathSeparator}');
    if (!isInsideRoot || !dirPath.existsSync()) {
      return [];
    }

    final entries = <MediaEntry>[];
    for (final entity in dirPath.listSync()) {
      final name = entity.uri.pathSegments.isNotEmpty
          ? (entity.uri.pathSegments.last.isEmpty
              ? entity.uri.pathSegments[entity.uri.pathSegments.length - 2]
              : entity.uri.pathSegments.last)
          : entity.path;

      if (name.startsWith('.')) continue;
      final entryRel = cleaned.isEmpty ? name : '$cleaned/$name';

      if (entity is Directory) {
        entries.add(MediaEntry(name: name, relPath: entryRel, isFolder: true));
      } else if (entity is File) {
        final ext = _extensionOf(name);
        final kind = kindForExtension(ext);
        if (kind == null) continue; // only expose playable media
        int size = 0;
        try {
          size = entity.lengthSync();
        } catch (_) {}
        entries.add(MediaEntry(
          name: name,
          relPath: entryRel,
          isFolder: false,
          kind: kind,
          size: size,
        ));
      }
    }

    entries.sort((a, b) {
      if (a.isFolder != b.isFolder) return a.isFolder ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }

  String _extensionOf(String name) {
    final idx = name.lastIndexOf('.');
    if (idx == -1) return '';
    return name.substring(idx);
  }
}
