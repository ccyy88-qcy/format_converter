import 'dart:typed_data';
import 'dart:io';

/// 文件格式魔数检测引擎
/// 通过读取文件头字节识别真实格式，不依赖扩展名
class FileFormatDetector {
  static const Map<String, List<int>> _magicBytes = {
    // === 图片 ===
    'image/png': [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
    'image/jpeg': [0xFF, 0xD8, 0xFF],
    'image/gif87a': [0x47, 0x49, 0x46, 0x38, 0x37, 0x61],
    'image/gif89a': [0x47, 0x49, 0x46, 0x38, 0x39, 0x61],
    'image/webp': [0x52, 0x49, 0x46, 0x46], // RIFF header, check further
    'image/bmp': [0x42, 0x4D],
    'image/tiff-le': [0x49, 0x49, 0x2A, 0x00],
    'image/tiff-be': [0x4D, 0x4D, 0x00, 0x2A],
    'image/svg': [0x3C, 0x3F, 0x78, 0x6D, 0x6C], // <?xml
    'image/heic': [0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63],
    'image/heif': [0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, 0x6D, 0x69, 0x66, 0x31],
    'image/avif': [0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70, 0x61, 0x76, 0x69, 0x66],
    'image/ico': [0x00, 0x00, 0x01, 0x00],
    'image/x-icon': [0x00, 0x00, 0x02, 0x00],

    // === 文档 ===
    'application/pdf': [0x25, 0x50, 0x44, 0x46],
    'application/zip': [0x50, 0x4B, 0x03, 0x04],
    'application/gzip': [0x1F, 0x8B],
    'application/x-7z-compressed': [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C],
    'application/x-rar-compressed': [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07],
    'application/x-tar': [0x75, 0x73, 0x74, 0x61, 0x72], // at offset 257
    'application/x-bzip2': [0x42, 0x5A, 0x68],

    // Office文档 (都是ZIP格式，需要进一步区分)
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document': [0x50, 0x4B, 0x03, 0x04],
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': [0x50, 0x4B, 0x03, 0x04],
    'application/vnd.openxmlformats-officedocument.presentationml.presentation': [0x50, 0x4B, 0x03, 0x04],

    // 旧版Office
    'application/msword': [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1],
    'application/vnd.ms-excel': [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1],
    'application/vnd.ms-powerpoint': [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1],

    // ODF格式
    'application/vnd.oasis.opendocument.text': [0x50, 0x4B, 0x03, 0x04],
    'application/vnd.oasis.opendocument.spreadsheet': [0x50, 0x4B, 0x03, 0x04],
    'application/vnd.oasis.opendocument.presentation': [0x50, 0x4B, 0x03, 0x04],

    // EPUB
    'application/epub+zip': [0x50, 0x4B, 0x03, 0x04],

    // RTF
    'application/rtf': [0x7B, 0x5C, 0x72, 0x74, 0x66],

    // === 音频 ===
    'audio/mpeg': [0xFF, 0xFB],
    'audio/mpeg3': [0xFF, 0xF3],
    'audio/mpeg4a': [0xFF, 0xF2],
    'audio/mp4': [0x66, 0x74, 0x79, 0x70], // at offset 4
    'audio/wav': [0x52, 0x49, 0x46, 0x46], // RIFF
    'audio/flac': [0x66, 0x4C, 0x61, 0x43],
    'audio/ogg': [0x4F, 0x67, 0x67, 0x53],
    'audio/aac': [0xFF, 0xF1],
    'audio/x-aac': [0xFF, 0xF9],
    'audio/x-aiff': [0x46, 0x4F, 0x52, 0x4D],

    // === 视频 ===
    'video/mp4': [0x66, 0x74, 0x79, 0x70], // at offset 4
    'video/avi': [0x52, 0x49, 0x46, 0x46], // RIFF
    'video/x-matroska': [0x1A, 0x45, 0xDF, 0xA3],
    'video/quicktime': [0x66, 0x74, 0x79, 0x70, 0x71, 0x74], // at offset 4
    'video/webm': [0x1A, 0x45, 0xDF, 0xA3],
    'video/x-flv': [0x46, 0x4C, 0x56, 0x01],
    'video/3gpp': [0x66, 0x74, 0x79, 0x70, 0x33, 0x67],

    // === 文本/代码 ===
    'text/plain': [], // 无固定魔数，需要启发式检测
    'text/html': [],
    'text/xml': [],
    'text/css': [],
    'text/javascript': [],
    'application/json': [],
    'application/xml': [],
    'application/javascript': [],
    'text/csv': [],
    'text/markdown': [],
    'text/yaml': [],
    'text/x-python': [],
    'text/x-java': [],
    'text/x-c': [],

    // === 其他 ===
    'application/x-executable': [0x7F, 0x45, 0x4C, 0x46], // ELF
    'application/x-mach-binary': [0xCF, 0xFA, 0xED, 0xFE], // Mach-O
    'application/x-dosexec': [0x4D, 0x5A], // PE/EXE
  };

  /// 通过文件路径检测格式 — 扩展名优先+魔数验证
  static Future<String> detect(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return 'unknown';

    final ext = filePath.toLowerCase().split('.').last;

    // 先根据扩展名快速判定（ZIP容器格式大文件扩展名最可靠）
    final extMime = _extensionMap[ext];
    if (extMime != null) {
      // 读少量字节做魔数验证
      final headBytes = await file.openRead(0, 64).first;
      final mime = _matchMagic(headBytes);
      if (mime == 'application/zip') {
        // ZIP容器：用扩展名区分子类型
        return _detectZipSubtype(headBytes, filePath);
      }
      if (mime != null && mime != 'application/zip') {
        return mime; // 魔数一致就返回魔数结果
      }
      return extMime; // 魔数不匹配但扩展名已知，用扩展名
    }

    // 扩展名未知，读完整文件做魔数检测
    final bytes = await file.readAsBytes();
    return detectFromBytes(bytes, filePath: filePath);
  }

  /// 通过字节数组检测格式 — 魔数优先
  static String detectFromBytes(Uint8List bytes, {String? filePath}) {
    if (bytes.isEmpty) return 'unknown';

    // 同时看扩展名和魔数
    String? extMime;
    if (filePath != null) {
      final ext = filePath.toLowerCase().split('.').last;
      extMime = _extensionMap[ext];
    }

    // 魔数匹配
    final mime = _matchMagic(bytes);
    if (mime != null && mime.isNotEmpty) {
      if (mime == 'application/zip') {
        return _detectZipSubtype(bytes, filePath);
      }
      return mime;
    }

    // RIFF变体
    if (bytes.length >= 12 && bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46) {
      if (bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50) return 'image/webp';
      if (bytes[8] == 0x41 && bytes[9] == 0x56 && bytes[10] == 0x49) return 'video/avi';
      if (bytes[8] == 0x57 && bytes[9] == 0x41 && bytes[10] == 0x56 && bytes[11] == 0x45) return 'audio/wav';
    }

    // MP4/MOV
    if (bytes.length >= 12 && bytes[4] == 0x66 && bytes[5] == 0x74 && bytes[6] == 0x79 && bytes[7] == 0x70) {
      if (bytes.length >= 12) {
        final brand = String.fromCharCodes(bytes.sublist(8, 12));
        if (brand.startsWith('qt')) return 'video/quicktime';
        return 'video/mp4';
      }
    }

    // 扩展名兜底
    if (extMime != null) return extMime;

    // 启发式文本检测
    if (_isText(bytes)) return _detectTextSubtype(String.fromCharCodes(bytes.take(1024)));

    return 'application/octet-stream';
  }

  static String? _matchMagic(Uint8List bytes) {
    for (final entry in _magicBytes.entries) {
      if (entry.value.isEmpty) continue;
      if (_startsWith(bytes, entry.value)) {
        return entry.key;
      }
    }
    return null;
  }

  static bool _startsWith(Uint8List bytes, List<int> magic) {
    if (bytes.length < magic.length) return false;
    for (int i = 0; i < magic.length; i++) {
      if (bytes[i] != magic[i]) return false;
    }
    return true;
  }

  /// 区分ZIP容器内的具体格式
  static String _detectZipSubtype(Uint8List bytes, String? filePath) {
    // 尝试读取ZIP内部文件名
    try {
      final content = String.fromCharCodes(bytes.take(4096));
      if (content.contains('[Content_Types].xml')) {
        if (content.contains('word/')) return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
        if (content.contains('xl/')) return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
        if (content.contains('ppt/')) return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
        return 'application/vnd.openxmlformats-officedocument.package';
      }
      if (content.contains('mimetypeapplication/epub')) return 'application/epub+zip';
      if (content.contains('META-INF/')) return 'application/java-archive';
      if (content.contains('AndroidManifest.xml')) return 'application/vnd.android.package-archive';
    } catch (_) {}

    // 根据扩展名区分
    if (filePath != null) {
      final ext = filePath.toLowerCase().split('.').last;
      if (ext == 'docx') return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      if (ext == 'xlsx') return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      if (ext == 'pptx') return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      if (ext == 'odt') return 'application/vnd.oasis.opendocument.text';
      if (ext == 'ods') return 'application/vnd.oasis.opendocument.spreadsheet';
      if (ext == 'odp') return 'application/vnd.oasis.opendocument.presentation';
      if (ext == 'epub') return 'application/epub+zip';
      if (ext == 'jar') return 'application/java-archive';
      if (ext == 'apk') return 'application/vnd.android.package-archive';
    }

    return 'application/zip';
  }

  static bool _isText(Uint8List bytes) {
    int textCount = 0;
    final checkLen = bytes.length > 4096 ? 4096 : bytes.length;
    for (int i = 0; i < checkLen; i++) {
      final b = bytes[i];
      if (b >= 0x20 && b <= 0x7E) {
        textCount++; // 可打印ASCII
      } else if (b == 0x0A || b == 0x0D || b == 0x09) {
        textCount++; // 换行、回车、制表
      } else if (b >= 0xC0 && b <= 0xFD) {
        textCount++; // UTF-8起始字节
      } else if (b >= 0x80 && b <= 0xBF) {
        textCount++; // UTF-8后续字节
      }
    }
    return textCount / checkLen > 0.85; // 85%以上可打印字符
  }

  static String _detectTextSubtype(String text) {
    final trimmed = text.trim();
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      try {
        // 简单JSON检测
        if (trimmed.contains(':') || trimmed.contains('[')) return 'application/json';
      } catch (_) {}
    }
    if (trimmed.startsWith('<')) {
      if (trimmed.contains('<html')) return 'text/html';
      if (trimmed.contains('<svg')) return 'image/svg+xml';
      return 'application/xml';
    }
    if (trimmed.startsWith('---') || trimmed.contains(': ') && !trimmed.contains('//')) {
      return 'text/yaml';
    }
    if (trimmed.contains('import ') || trimmed.contains('def ') || trimmed.contains('class ')) {
      if (trimmed.contains(':') && (trimmed.contains('  ') || trimmed.contains('\t'))) {
        return 'text/x-python';
      }
    }
    if (trimmed.contains('#include') || trimmed.contains('int main')) return 'text/x-c';
    return 'text/plain';
  }

  /// 扩展名到MIME的映射兜底
  static const Map<String, String> _extensionMap = {
    'txt': 'text/plain', 'log': 'text/plain', 'ini': 'text/plain', 'cfg': 'text/plain',
    'md': 'text/markdown', 'markdown': 'text/markdown',
    'html': 'text/html', 'htm': 'text/html', 'xhtml': 'text/html',
    'xml': 'application/xml', 'svg': 'image/svg+xml', 'plist': 'application/xml',
    'json': 'application/json', 'jsonl': 'application/json',
    'yaml': 'text/yaml', 'yml': 'text/yaml',
    'css': 'text/css', 'scss': 'text/css', 'less': 'text/css',
    'js': 'text/javascript', 'mjs': 'text/javascript', 'ts': 'text/javascript',
    'py': 'text/x-python', 'pyw': 'text/x-python',
    'java': 'text/x-java', 'kt': 'text/x-kotlin', 'scala': 'text/x-scala',
    'c': 'text/x-c', 'h': 'text/x-c', 'cpp': 'text/x-c', 'hpp': 'text/x-c',
    'cs': 'text/x-csharp', 'go': 'text/x-go', 'rs': 'text/rust',
    'rb': 'text/x-ruby', 'php': 'text/x-php', 'sh': 'text/x-shellscript',
    'csv': 'text/csv', 'tsv': 'text/tab-separated-values',
    'sql': 'application/sql',
    'rtf': 'application/rtf',
    'doc': 'application/msword', 'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel', 'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt': 'application/vnd.ms-powerpoint', 'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'odt': 'application/vnd.oasis.opendocument.text',
    'ods': 'application/vnd.oasis.opendocument.spreadsheet',
    'odp': 'application/vnd.oasis.opendocument.presentation',
    'pdf': 'application/pdf',
    'epub': 'application/epub+zip',
    'zip': 'application/zip', 'gz': 'application/gzip', 'bz2': 'application/x-bzip2',
    'xz': 'application/x-xz', '7z': 'application/x-7z-compressed',
    'rar': 'application/x-rar-compressed', 'tar': 'application/x-tar',
    'png': 'image/png', 'jpg': 'image/jpeg', 'jpeg': 'image/jpeg',
    'gif': 'image/gif', 'bmp': 'image/bmp', 'webp': 'image/webp',
    'tiff': 'image/tiff', 'tif': 'image/tiff', 'ico': 'image/x-icon',
    'heic': 'image/heic', 'heif': 'image/heif', 'avif': 'image/avif',
    'mp3': 'audio/mpeg', 'mp4': 'video/mp4', 'm4a': 'audio/mp4',
    'wav': 'audio/wav', 'flac': 'audio/flac', 'ogg': 'audio/ogg',
    'aac': 'audio/aac', 'wma': 'audio/x-ms-wma', 'opus': 'audio/opus',
    'avi': 'video/avi', 'mkv': 'video/x-matroska', 'mov': 'video/quicktime',
    'webm': 'video/webm', 'flv': 'video/x-flv', 'wmv': 'video/x-ms-wmv',
    '3gp': 'video/3gpp',
    'exe': 'application/x-dosexec', 'dll': 'application/x-dosexec',
    'so': 'application/x-executable', 'elf': 'application/x-executable',
    'jar': 'application/java-war', 'apk': 'application/vnd.android.package-archive',
  };

  /// 获取文件分类
  static String getCategory(String mimeType) {
    if (mimeType.startsWith('image/')) return '图片';
    if (mimeType.startsWith('video/')) return '视频';
    if (mimeType.startsWith('audio/')) return '音频';
    if (mimeType.contains('word') || mimeType.contains('excel') || mimeType.contains('powerpoint') ||
        mimeType.contains('opendocument') || mimeType == 'application/pdf' ||
        mimeType == 'application/rtf' || mimeType.startsWith('text/')) return '文档';
    if (mimeType.contains('zip') || mimeType.contains('compressed') || mimeType.contains('archive')) return '压缩包';
    return '其他';
  }

  /// 获取可读格式名称
  static String getFormatName(String mimeType) {
    const names = {
      'image/png': 'PNG', 'image/jpeg': 'JPEG', 'image/gif': 'GIF',
      'image/webp': 'WebP', 'image/bmp': 'BMP', 'image/tiff': 'TIFF',
      'image/svg+xml': 'SVG', 'image/heic': 'HEIC', 'image/heif': 'HEIF',
      'image/avif': 'AVIF', 'image/x-icon': 'ICO',
      'application/pdf': 'PDF',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document': 'Word (DOCX)',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': 'Excel (XLSX)',
      'application/vnd.openxmlformats-officedocument.presentationml.presentation': 'PPT (PPTX)',
      'application/msword': 'Word (DOC)', 'application/vnd.ms-excel': 'Excel (XLS)',
      'application/vnd.ms-powerpoint': 'PPT (PPT)',
      'application/vnd.oasis.opendocument.text': 'ODT',
      'application/vnd.oasis.opendocument.spreadsheet': 'ODS',
      'application/vnd.oasis.opendocument.presentation': 'ODP',
      'application/rtf': 'RTF', 'application/epub+zip': 'EPUB',
      'application/zip': 'ZIP', 'application/gzip': 'GZIP',
      'application/x-7z-compressed': '7Z', 'application/x-rar-compressed': 'RAR',
      'application/x-tar': 'TAR', 'application/x-bzip2': 'BZIP2',
      'audio/mpeg': 'MP3', 'audio/wav': 'WAV', 'audio/flac': 'FLAC',
      'audio/ogg': 'OGG', 'audio/aac': 'AAC', 'audio/mp4': 'M4A',
      'audio/opus': 'Opus',
      'video/mp4': 'MP4', 'video/avi': 'AVI', 'video/x-matroska': 'MKV',
      'video/quicktime': 'MOV', 'video/webm': 'WebM', 'video/x-flv': 'FLV',
      'text/plain': '纯文本', 'text/html': 'HTML', 'text/css': 'CSS',
      'application/json': 'JSON', 'application/xml': 'XML', 'text/yaml': 'YAML',
      'text/markdown': 'Markdown', 'text/csv': 'CSV',
    };
    return names[mimeType] ?? mimeType;
  }

  /// 获取该格式支持转换到的目标格式
  static List<String> getSupportedTargets(String mimeType) {
    final category = getCategory(mimeType);
    switch (category) {
      // ===== 图片 =====
      case '图片':
        return ['image/png', 'image/jpeg', 'image/bmp', 'image/webp', 'image/gif', 'image/tiff', 'application/pdf'];

      // ===== 文档 =====
      case '文档':
        // PDF
        if (mimeType == 'application/pdf') {
          return ['image/png', 'image/jpeg',
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
            'text/plain'];
        }
        // ODT
        if (mimeType == 'application/vnd.oasis.opendocument.text') {
          return ['application/pdf', 'text/plain',
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document'];
        }
        // ODS
        if (mimeType == 'application/vnd.oasis.opendocument.spreadsheet') {
          return ['application/pdf', 'text/csv', 'text/plain'];
        }
        // ODP
        if (mimeType == 'application/vnd.oasis.opendocument.presentation') {
          return ['application/pdf', 'text/plain'];
        }
        // Word/DOCX
        if (mimeType.contains('word') || mimeType == 'application/rtf') {
          return ['application/pdf', 'text/plain',
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document'];
        }
        // Excel/XLSX
        if (mimeType.contains('excel')) {
          return ['application/pdf', 'text/csv', 'text/plain'];
        }
        // PPT/PPTX
        if (mimeType.contains('powerpoint') || mimeType.contains('presentation')) {
          return ['application/pdf'];
        }
        // EPUB
        if (mimeType == 'application/epub+zip') {
          return ['application/pdf', 'text/plain',
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document'];
        }
        // HTML
        if (mimeType == 'text/html') {
          return ['application/pdf', 'text/plain',
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document'];
        }
        // JSON
        if (mimeType == 'application/json') {
          return ['text/csv', 'text/plain',
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document'];
        }
        // CSV
        if (mimeType == 'text/csv') {
          return ['application/pdf', 'text/plain',
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document'];
        }
        // 纯文本/代码/Markdown/XML/YAML/RTF
        if (mimeType == 'text/plain' || mimeType.startsWith('text/') || mimeType == 'application/xml' ||
            mimeType == 'application/rtf') {
          return ['application/pdf',
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document'];
        }
        // 兜底
        return ['application/pdf'];

      // ===== 压缩包 =====
      case '压缩包':
        return ['application/zip'];

      // ===== 音频/视频 =====
      case '音频':
      case '视频':
        return [];

      // ===== 其他 =====
      default:
        return [];
    }
  }
}
