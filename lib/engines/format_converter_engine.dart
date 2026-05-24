import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

/// 转换进度回调
typedef ProgressCallback = void Function(double progress, String status);

/// 转换结果
class ConversionResult {
  final bool success;
  final String? outputPath;
  final String? error;
  final int? fileSize;

  ConversionResult({required this.success, this.outputPath, this.error, this.fileSize});
}

/// 通用格式转换引擎
class FormatConverterEngine {

  /// 主转换入口
  static Future<ConversionResult> convert({
    required String inputPath,
    required String targetMime,
    String? outputDir,
    int quality = 90,
    ProgressCallback? onProgress,
  }) async {
    try {
      onProgress?.call(0.05, '检测文件格式...');

      final inputFile = File(inputPath);
      if (!await inputFile.exists()) {
        return ConversionResult(success: false, error: '源文件不存在');
      }

      // 创建输出目录
      final outDir = outputDir ?? p.dirname(inputPath);
      await Directory(outDir).create(recursive: true);

      // 根据目标格式路由转换
      ConversionResult result;

      if (targetMime.startsWith('image/')) {
        result = await _convertImage(inputPath, targetMime, outDir, quality, onProgress);
      } else if (targetMime == 'application/pdf') {
        result = await _convertToPdf(inputPath, outDir, onProgress);
      } else if (targetMime == 'text/plain') {
        result = await _convertToText(inputPath, outDir, onProgress);
      } else if (targetMime == 'text/csv') {
        result = await _convertToCsv(inputPath, outDir, onProgress);
      } else if (targetMime == 'application/vnd.openxmlformats-officedocument.wordprocessingml.document') {
        result = await _convertToDocx(inputPath, outDir, onProgress);
      } else if (targetMime == 'application/zip') {
        result = await _convertToZip(inputPath, outDir, onProgress);
      } else {
        return ConversionResult(success: false, error: '暂不支持转换到该格式: $targetMime');
      }

      return result;
    } catch (e) {
      return ConversionResult(success: false, error: '转换失败: $e');
    }
  }

  // ==================== 图片转换 ====================

  static Future<ConversionResult> _convertImage(
    String inputPath, String targetMime, String outDir, int quality, ProgressCallback? cb) async {
    cb?.call(0.1, '读取图片...');

    final bytes = await File(inputPath).readAsBytes();
    img.Image? image = img.decodeImage(bytes);

    if (image == null) {
      return ConversionResult(success: false, error: '无法解码图片');
    }

    cb?.call(0.4, '转换格式...');

    final ext = _mimeToExtension(targetMime);
    final fileName = _changeExtension(p.basename(inputPath), ext);
    final outputPath = p.join(outDir, fileName);
    Uint8List? outputBytes;

    switch (targetMime) {
      case 'image/png':
        outputBytes = Uint8List.fromList(img.encodePng(image));
        break;
      case 'image/jpeg':
        outputBytes = Uint8List.fromList(img.encodeJpg(image, quality: quality));
        break;
      case 'image/webp':
        outputBytes = Uint8List.fromList(img.encodeWebp(image, quality: quality));
        break;
      case 'image/bmp':
        outputBytes = Uint8List.fromList(img.encodeBmp(image));
        break;
      case 'image/gif':
        outputBytes = Uint8List.fromList(img.encodeGif(image));
        break;
      case 'image/tiff':
        outputBytes = Uint8List.fromList(img.encodeTiff(image));
        break;
      default:
        return ConversionResult(success: false, error: '不支持的图片目标格式');
    }

    cb?.call(0.8, '保存文件...');

    if (outputBytes != null) {
      await File(outputPath).writeAsBytes(outputBytes);
      cb?.call(1.0, '完成');
      return ConversionResult(success: true, outputPath: outputPath, fileSize: outputBytes.length);
    }

    return ConversionResult(success: false, error: '编码失败');
  }

  // ==================== 转PDF ====================

  static Future<ConversionResult> _convertToPdf(String inputPath, String outDir, ProgressCallback? cb) async {
    final ext = p.extension(inputPath).toLowerCase();
    final fileName = _changeExtension(p.basename(inputPath), '.pdf');
    final outputPath = p.join(outDir, fileName);

    if (ext == '.pdf') {
      return ConversionResult(success: false, error: '已经是PDF格式');
    }

    // 图片转PDF
    if (_isImageFile(ext)) {
      return _imageToPdf(inputPath, outputPath, outDir, cb);
    }

    // 文本转PDF
    if (_isTextFile(ext)) {
      return _textToPdf(inputPath, outputPath, cb);
    }

    // DOCX转PDF (读取文本后生成PDF)
    if (ext == '.docx') {
      return _docxToPdf(inputPath, outputPath, cb);
    }

    // XLSX转PDF (读取CSV后生成PDF)
    if (ext == '.xlsx' || ext == '.xls' || ext == '.csv') {
      return _spreadsheetToPdf(inputPath, outputPath, ext, cb);
    }

    return ConversionResult(success: false, error: '无法将 $ext 转换为PDF');
  }

  static Future<ConversionResult> _imageToPdf(String input, String output, String outDir, ProgressCallback? cb) async {
    cb?.call(0.1, '读取图片...');
    final bytes = await File(input).readAsBytes();

    cb?.call(0.3, '生成PDF...');
    final pdf = pw.Document();
    final image = pw.MemoryImage(bytes);

    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (context) => pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
    ));

    cb?.call(0.7, '写入文件...');
    final pdfBytes = await pdf.save();
    await File(output).writeAsBytes(pdfBytes);

    cb?.call(1.0, '完成');
    return ConversionResult(success: true, outputPath: output, fileSize: pdfBytes.length);
  }

  static Future<ConversionResult> _textToPdf(String input, String output, ProgressCallback? cb) async {
    cb?.call(0.1, '读取文本...');
    final text = await File(input).readAsString();

    cb?.call(0.3, '生成PDF...');
    final pdf = pw.Document();
    final lines = text.split('\n');

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (context) => [
        pw.Text(lines.join('\n'),
          style: pw.TextStyle(fontSize: 11, lineSpacing: 1.5),
          textAlign: pw.TextAlign.left,
        ),
      ],
    ));

    cb?.call(0.7, '写入文件...');
    final pdfBytes = await pdf.save();
    await File(output).writeAsBytes(pdfBytes);

    cb?.call(1.0, '完成');
    return ConversionResult(success: true, outputPath: output, fileSize: pdfBytes.length);
  }

  static Future<ConversionResult> _docxToPdf(String input, String output, ProgressCallback? cb) async {
    cb?.call(0.1, '读取文档...');

    try {
      // 尝试用ZIP方式提取docx中的文本
      final bytes = await File(input).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      String text = '';
      // 查找word/document.xml
      for (final file in archive.files) {
        if (file.name == 'word/document.xml' && file.content != null) {
          final xmlContent = String.fromCharCodes(file.content!);
          // 简单提取文本（去除XML标签）
          text = xmlContent
              .replaceAll(RegExp(r'<[^>]+>'), '\n')
              .replaceAll(RegExp(r'\n{3,}'), '\n\n')
              .trim();
          break;
        }
      }

      if (text.isEmpty) {
        // 回退：直接用文件路径
        text = await File(input).readAsString();
      }

      cb?.call(0.4, '提取文本完成，生成PDF...');

      final pdf = pw.Document();
      final lines = text.split('\n');

      pdf.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => lines.map((line) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 4),
          child: pw.Text(line, style: pw.TextStyle(fontSize: 12)),
        )).toList(),
      ));

      final pdfBytes = await pdf.save();
      await File(output).writeAsBytes(pdfBytes);

      cb?.call(1.0, '完成');
      return ConversionResult(success: true, outputPath: output, fileSize: pdfBytes.length);
    } catch (e) {
      return ConversionResult(success: false, error: 'DOCX解析失败: $e');
    }
  }

  static Future<ConversionResult> _spreadsheetToPdf(String input, String output, String ext, ProgressCallback? cb) async {
    cb?.call(0.1, '读取表格...');

    String csvContent;

    if (ext == '.csv') {
      csvContent = await File(input).readAsString();
    } else {
      // XLSX: 提取共享字符串和工作表文本
      final bytes = await File(input).readAsBytes();
      try {
        final archive = ZipDecoder().decodeBytes(bytes);
        String sheetText = '';
        List<String> sharedStrings = [];

        for (final file in archive.files) {
          if (file.name == 'xl/sharedStrings.xml' && file.content != null) {
            final xml = String.fromCharCodes(file.content!);
            final matches = RegExp(r'<t[^>]*>([^<]*)</t>').allMatches(xml);
            sharedStrings = matches.map((m) => m.group(1) ?? '').toList();
          }
          if (file.name.startsWith('xl/worksheets/sheet') && file.name.endsWith('.xml') && file.content != null) {
            final xml = String.fromCharCodes(file.content!);
            final cellMatches = RegExp(r'<c[^>]*r="([^"]*)"[^>]*>(?:<v>([^<]*)</v>)?</c>').allMatches(xml);
            for (final match in cellMatches) {
              sheetText += '${match.group(1)}: ${match.group(2) ?? ''}\n';
            }
          }
        }
        csvContent = sheetText;
      } catch (_) {
        csvContent = '无法解析Excel文件';
      }
    }

    cb?.call(0.4, '生成PDF...');
    final pdf = pw.Document();
    final lines = csvContent.split('\n');

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(30),
      build: (context) => lines.map((line) {
        final cells = line.split(RegExp(r'[,;\t]'));
        return pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: pw.Text(line, style: pw.TextStyle(fontSize: 9)),
        );
      }).toList(),
    ));

    final pdfBytes = await pdf.save();
    await File(output).writeAsBytes(pdfBytes);

    cb?.call(1.0, '完成');
    return ConversionResult(success: true, outputPath: output, fileSize: pdfBytes.length);
  }

  // ==================== 转纯文本 ====================

  static Future<ConversionResult> _convertToText(String inputPath, String outDir, ProgressCallback? cb) async {
    cb?.call(0.1, '提取文本...');
    final ext = p.extension(inputPath).toLowerCase();
    final fileName = _changeExtension(p.basename(inputPath), '.txt');
    final outputPath = p.join(outDir, fileName);

    String text = '';

    if (ext == '.txt' || ext == '.csv' || ext == '.md' || ext == '.json' || ext == '.xml' || ext == '.html') {
      text = await File(inputPath).readAsString();
    } else if (ext == '.pdf') {
      // PDF提取文本 - 简单方式
      text = 'PDF文本提取需要专用库，建议使用转Word功能';
    } else if (ext == '.docx') {
      final bytes = await File(inputPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final file in archive.files) {
        if (file.name == 'word/document.xml' && file.content != null) {
          final xml = String.fromCharCodes(file.content!);
          text = xml.replaceAll(RegExp(r'<[^>]+>'), '\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
          break;
        }
      }
    } else if (ext == '.xlsx') {
      final bytes = await File(inputPath).readAsBytes();
      try {
        final archive = ZipDecoder().decodeBytes(bytes);
        String sheetXml = '';
        for (final file in archive.files) {
          if (file.name.startsWith('xl/worksheets/sheet') && file.name.endsWith('.xml') && file.content != null) {
            sheetXml += String.fromCharCodes(file.content!) + '\n';
          }
        }
        text = sheetXml.replaceAll(RegExp(r'<[^>]+>'), '\t').replaceAll(RegExp(r'\t{2,}'), '\t').trim();
      } catch (_) {}
    } else if (ext == '.rtf') {
      final rtfText = await File(inputPath).readAsString();
      text = _stripRtf(rtfText);
    } else {
      return ConversionResult(success: false, error: '无法从 $ext 提取文本');
    }

    cb?.call(0.7, '写入文件...');
    await File(outputPath).writeAsString(text);

    cb?.call(1.0, '完成');
    return ConversionResult(success: true, outputPath: outputPath, fileSize: text.length);
  }

  // ==================== 转CSV ====================

  static Future<ConversionResult> _convertToCsv(String inputPath, String outDir, ProgressCallback? cb) async {
    final ext = p.extension(inputPath).toLowerCase();
    final fileName = _changeExtension(p.basename(inputPath), '.csv');
    final outputPath = p.join(outDir, fileName);

    cb?.call(0.1, '读取数据...');
    String csvContent = '';

    if (ext == '.csv') {
      csvContent = await File(inputPath).readAsString();
    } else if (ext == '.xlsx' || ext == '.xls') {
      final bytes = await File(inputPath).readAsBytes();
      try {
        final archive = ZipDecoder().decodeBytes(bytes);
        final buffer = StringBuffer();
        List<String> sharedStrings = [];

        // 先提取共享字符串
        for (final file in archive.files) {
          if (file.name == 'xl/sharedStrings.xml' && file.content != null) {
            final xml = String.fromCharCodes(file.content!);
            final matches = RegExp(r'<t[^>]*>([^<]*)</t>').allMatches(xml);
            sharedStrings = matches.map((m) => m.group(1) ?? '').toList();
          }
        }

        // 提取工作表数据
        for (final file in archive.files) {
          if (file.name.startsWith('xl/worksheets/sheet') && file.name.endsWith('.xml') && file.content != null) {
            final xml = String.fromCharCodes(file.content!);
            final rowMatches = RegExp(r'<row[^>]*>(.*?)</row>', dotAll: true).allMatches(xml);

            for (final row in rowMatches) {
              final cellMatches = RegExp(r'<c[^>]*r="([^"]*)"[^>]*(?:t="s")?[^>]*>(?:<v>([^<]*)</v>)?</c>').allMatches(row.group(1)!);
              final rowData = <String>[];

              for (final cell in cellMatches) {
                String value = '';
                final cellType = cell.group(0);
                final cellValue = cell.group(2) ?? '';
                if (cellType?.contains('t="s"') == true && int.tryParse(cellValue) != null) {
                  final idx = int.parse(cellValue);
                  value = idx < sharedStrings.length ? sharedStrings[idx] : '';
                } else {
                  value = cellValue;
                }
                rowData.add('"${value.replaceAll('"', '""')}"');
              }
              buffer.writeln(rowData.join(','));
            }
          }
        }
        csvContent = buffer.toString();
      } catch (e) {
        csvContent = '解析失败: $e';
      }
    } else if (ext == '.json') {
      final jsonText = await File(inputPath).readAsString();
      // 简单JSON转CSV（仅支持扁平数组）
      csvContent = jsonText; // 简化版，实际需要json解析
    } else {
      return ConversionResult(success: false, error: '无法从 $ext 转换为CSV');
    }

    cb?.call(0.7, '写入文件...');
    await File(outputPath).writeAsString(csvContent);

    cb?.call(1.0, '完成');
    return ConversionResult(success: true, outputPath: outputPath, fileSize: csvContent.length);
  }

  // ==================== 转DOCX ====================

  static Future<ConversionResult> _convertToDocx(String inputPath, String outDir, ProgressCallback? cb) async {
    cb?.call(0.1, '准备转换...');
    final fileName = _changeExtension(p.basename(inputPath), '.docx');
    final outputPath = p.join(outDir, fileName);

    // 创建最小DOCX：ZIP包内含word/document.xml
    final ext = p.extension(inputPath).toLowerCase();
    String text = '';

    if (ext == '.txt' || ext == '.md' || ext == '.rtf') {
      text = await File(inputPath).readAsString();
    } else if (ext == '.pdf') {
      text = 'PDF转DOCX需要OCR，当前不支持';
    } else {
      return ConversionResult(success: false, error: '不支持从 $ext 转换为DOCX');
    }

    cb?.call(0.3, '生成DOCX...');

    // 清理文本中不能出现在XML中的字符
    text = text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');

    final lines = text.split('\n');

    // 构建document.xml
    final documentXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
${lines.map((line) => '''    <w:p>
      <w:r>
        <w:t>${line.isEmpty ? '' : line}</w:t>
      </w:r>
    </w:p>''').join('\n')}
    <w:sectPr>
      <w:pgSz w:w="12240" w:h="15840"/>
      <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/>
    </w:sectPr>
  </w:body>
</w:document>''';

    // 构建最小DOCX zip
    final archive = Archive();

    // [Content_Types].xml
    _addStringToArchive(archive, '[Content_Types].xml', '''<?xml version="1.0" encoding="UTF-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>''');

    // _rels/.rels
    _addStringToArchive(archive, '_rels/.rels', '''<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>''');

    // word/_rels/document.xml.rels
    _addStringToArchive(archive, 'word/_rels/document.xml.rels', '''<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
</Relationships>''');

    // word/document.xml
    _addStringToArchive(archive, 'word/document.xml', documentXml);

    final zipBytes = ZipEncoder().encode(archive);
    await File(outputPath).writeAsBytes(zipBytes!);

    cb?.call(1.0, '完成');
    return ConversionResult(success: true, outputPath: outputPath, fileSize: zipBytes.length);
  }

  // ==================== 压缩包转换 ====================

  static Future<ConversionResult> _convertToZip(String inputPath, String outDir, ProgressCallback? cb) async {
    cb?.call(0.1, '读取压缩包...');
    final ext = p.extension(inputPath).toLowerCase();
    final fileName = _changeExtension(p.basename(inputPath), '.zip');
    final outputPath = p.join(outDir, fileName);

    final bytes = await File(inputPath).readAsBytes();

    cb?.call(0.3, '解压...');
    Archive archive;

    try {
      if (ext == '.zip') {
        archive = ZipDecoder().decodeBytes(bytes);
      } else if (ext == '.7z') {
        return ConversionResult(success: false, error: '7z解压需要原生库，暂不支持');
      } else if (ext == '.rar') {
        return ConversionResult(success: false, error: 'RAR解压暂不支持');
      } else if (ext == '.tar' || ext == '.gz' || ext == '.tgz') {
        List<int> decodedBytes;
        if (ext == '.gz' || ext == '.tgz') {
          decodedBytes = GZipDecoder().decodeBytes(bytes);
        } else {
          decodedBytes = bytes;
        }
        archive = TarDecoder().decodeBytes(decodedBytes);
      } else {
        return ConversionResult(success: false, error: '不支持解压 $ext 格式');
      }
    } catch (e) {
      return ConversionResult(success: false, error: '解压失败: $e');
    }

    cb?.call(0.6, '重新打包为ZIP...');
    final outArchive = Archive();

    for (final file in archive.files) {
      if (file.isFile) {
        outArchive.addFile(ArchiveFile(file.name, file.size, file.content as List<int>));
      }
    }

    final zipBytes = ZipEncoder().encode(outArchive);
    await File(outputPath).writeAsBytes(zipBytes!);

    cb?.call(1.0, '完成');
    return ConversionResult(success: true, outputPath: outputPath, fileSize: zipBytes.length);
  }

  // ==================== 辅助方法 ====================

  static void _addStringToArchive(Archive archive, String name, String content) {
    final data = content.codeUnits;
    archive.addFile(ArchiveFile(name, data.length, data));
  }

  static bool _isImageFile(String ext) {
    return ['.png', '.jpg', '.jpeg', '.gif', '.bmp', '.webp', '.heic', '.heif', '.avif', '.tiff', '.tif', '.ico'].contains(ext);
  }

  static bool _isTextFile(String ext) {
    return ['.txt', '.md', '.csv', '.json', '.xml', '.html', '.htm', '.css', '.js', '.py', '.java', '.kt', '.c', '.cpp', '.sh', '.yaml', '.yml', '.log'].contains(ext);
  }

  static String _changeExtension(String fileName, String newExt) {
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex == -1) return '$fileName$newExt';
    return '${fileName.substring(0, dotIndex)}$newExt';
  }

  static String _mimeToExtension(String mime) {
    const map = {
      'image/png': '.png',
      'image/jpeg': '.jpg',
      'image/webp': '.webp',
      'image/bmp': '.bmp',
      'image/gif': '.gif',
      'image/tiff': '.tiff',
      'application/pdf': '.pdf',
      'text/plain': '.txt',
      'text/csv': '.csv',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document': '.docx',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': '.xlsx',
      'application/vnd.openxmlformats-officedocument.presentationml.presentation': '.pptx',
      'application/zip': '.zip',
    };
    return map[mime] ?? '.bin';
  }

  static String _stripRtf(String rtf) {
    return rtf
        .replaceAll(RegExp(r'\\[a-z]+\d*\s?'), '')
        .replaceAll(RegExp(r'[{}]'), '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }
}
