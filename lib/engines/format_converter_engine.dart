import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

typedef ProgressCallback = void Function(double progress, String status);

class ConversionResult {
  final bool success;
  final String? outputPath;
  final String? error;
  final int? fileSize;
  ConversionResult({required this.success, this.outputPath, this.error, this.fileSize});
}

class FormatConverterEngine {

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
      final outDir = outputDir ?? p.dirname(inputPath);
      await Directory(outDir).create(recursive: true);

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
    if (image == null) return ConversionResult(success: false, error: '无法解码图片');

    cb?.call(0.4, '转换格式...');
    final ext = _mimeToExtension(targetMime);
    final fileName = _changeExtension(p.basename(inputPath), ext);
    final outputPath = p.join(outDir, fileName);
    Uint8List? outputBytes;

    switch (targetMime) {
      case 'image/png': outputBytes = Uint8List.fromList(img.encodePng(image)); break;
      case 'image/jpeg': outputBytes = Uint8List.fromList(img.encodeJpg(image, quality: quality)); break;
      case 'image/webp': outputBytes = Uint8List.fromList(img.encodePng(image)); break; // 无WebP编码器，用PNG
      case 'image/bmp': outputBytes = Uint8List.fromList(img.encodeBmp(image)); break;
      case 'image/gif': outputBytes = Uint8List.fromList(img.encodeGif(image)); break;
      case 'image/tiff': outputBytes = Uint8List.fromList(img.encodeTiff(image)); break;
      default: return ConversionResult(success: false, error: '不支持的图片目标格式');
    }

    if (outputBytes != null) {
      cb?.call(0.8, '保存文件...');
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

    if (ext == '.pdf') return ConversionResult(success: false, error: '已经是PDF格式');
    if (_isImageFile(ext)) return _imageToPdf(inputPath, outputPath, cb);
    if (_isTextFile(ext)) return _textToPdf(inputPath, outputPath, cb);
    if (ext == '.docx') return _docxToPdf(inputPath, outputPath, cb);
    if (ext == '.xlsx' || ext == '.xls' || ext == '.csv') return _spreadsheetToPdf(inputPath, outputPath, ext, cb);
    if (ext == '.odt') return _zipXmlToPdf(inputPath, outputPath, 'word/document.xml', cb);
    if (ext == '.ods') return _odsToPdf(inputPath, outputPath, cb);
    if (ext == '.odp') return _zipXmlToPdf(inputPath, outputPath, 'content.xml', cb);
    if (ext == '.epub') return _epubToPdf(inputPath, outputPath, cb);
    if (ext == '.html' || ext == '.htm') {
      final html = await File(inputPath).readAsString();
      final text = html.replaceAll(RegExp(r'<[^>]+>'), '\n');
      final tmpFile = File(p.join(outDir, '_tmp.txt'));
      await tmpFile.writeAsString(text);
      final r = await _textToPdf(tmpFile.path, outputPath, cb);
      await tmpFile.delete();
      return r;
    }
    return ConversionResult(success: false, error: '无法将 $ext 转换为PDF');
  }

  static Future<ConversionResult> _imageToPdf(String input, String output, ProgressCallback? cb) async {
    cb?.call(0.1, '读取图片...');
    final bytes = await File(input).readAsBytes();
    cb?.call(0.3, '生成PDF...');
    final pdf = pw.Document();
    final image = pw.MemoryImage(bytes);
    pdf.addPage(pw.Page(pageFormat: PdfPageFormat.a4,
      build: (context) => pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain))));
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
    pdf.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(40),
      build: (context) => [pw.Text(lines.join('\n'), style: pw.TextStyle(fontSize: 11, lineSpacing: 1.5))]));
    cb?.call(0.7, '写入文件...');
    final pdfBytes = await pdf.save();
    await File(output).writeAsBytes(pdfBytes);
    cb?.call(1.0, '完成');
    return ConversionResult(success: true, outputPath: output, fileSize: pdfBytes.length);
  }

  static Future<ConversionResult> _docxToPdf(String input, String output, ProgressCallback? cb) async {
    cb?.call(0.1, '读取文档...');
    try {
      final text = _extractZipXml(input, 'word/document.xml');
      cb?.call(0.4, '生成PDF...');
      final pdf = pw.Document();
      final lines = text.split('\n');
      pdf.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(40),
        build: (context) => lines.map((l) => pw.Padding(padding: const pw.EdgeInsets.only(bottom: 4),
          child: pw.Text(l, style: pw.TextStyle(fontSize: 12)))).toList()));
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
      csvContent = _extractXlsxText(input);
      if (csvContent.isEmpty) csvContent = '无法解析Excel文件';
    }
    cb?.call(0.4, '生成PDF...');
    final pdf = pw.Document();
    final lines = csvContent.split('\n');
    pdf.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(30),
      build: (context) => lines.map((line) => pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Text(line, style: pw.TextStyle(fontSize: 9)))).toList()));
    final pdfBytes = await pdf.save();
    await File(output).writeAsBytes(pdfBytes);
    cb?.call(1.0, '完成');
    return ConversionResult(success: true, outputPath: output, fileSize: pdfBytes.length);
  }

  static Future<ConversionResult> _epubToPdf(String input, String output, ProgressCallback? cb) async {
    final text = _extractEpubText(input);
    final tmpFile = File(p.join(p.dirname(output), '_tmp.txt'));
    await tmpFile.writeAsString(text);
    final r = await _textToPdf(tmpFile.path, output, cb);
    await tmpFile.delete();
    return r;
  }

  static Future<ConversionResult> _odsToPdf(String input, String output, ProgressCallback? cb) async {
    final text = _extractZipXml(input, 'content.xml');
    final tmpFile = File(p.join(p.dirname(output), '_tmp.txt'));
    await tmpFile.writeAsString(text);
    final r = await _textToPdf(tmpFile.path, output, cb);
    await tmpFile.delete();
    return r;
  }

  static Future<ConversionResult> _zipXmlToPdf(String input, String output, String xmlPath, ProgressCallback? cb) async {
    final text = _extractZipXml(input, xmlPath);
    final tmpFile = File(p.join(p.dirname(output), '_tmp.txt'));
    await tmpFile.writeAsString(text);
    final r = await _textToPdf(tmpFile.path, output, cb);
    await tmpFile.delete();
    return r;
  }

  // ==================== 转纯文本 ====================

  static Future<ConversionResult> _convertToText(String inputPath, String outDir, ProgressCallback? cb) async {
    cb?.call(0.1, '提取文本...');
    final ext = p.extension(inputPath).toLowerCase();
    final fileName = _changeExtension(p.basename(inputPath), '.txt');
    final outputPath = p.join(outDir, fileName);

    String text;
    if (_isTextFile(ext)) {
      text = await File(inputPath).readAsString();
    } else if (ext == '.pdf') {
      text = 'PDF文本提取暂不支持';
    } else if (ext == '.docx') {
      text = _extractZipXml(inputPath, 'word/document.xml');
    } else if (ext == '.xlsx' || ext == '.xls') {
      text = _extractXlsxText(inputPath);
    } else if (ext == '.odt') {
      text = _extractZipXml(inputPath, 'content.xml');
    } else if (ext == '.ods') {
      text = _extractZipXml(inputPath, 'content.xml');
    } else if (ext == '.epub') {
      text = _extractEpubText(inputPath);
    } else if (ext == '.html' || ext == '.htm') {
      final html = await File(inputPath).readAsString();
      text = html.replaceAll(RegExp(r'<[^>]+>'), '\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
    } else if (ext == '.rtf') {
      final rtfText = await File(inputPath).readAsString();
      text = rtfText.replaceAll(RegExp(r'\\[a-z]+\d*\s?'), '').replaceAll(RegExp(r'[{}]'), '').trim();
    } else if (ext == '.json') {
      text = await File(inputPath).readAsString();
    } else {
      return ConversionResult(success: false, error: '无法从 $ext 提取文本');
    }

    if (text.isEmpty) text = '(空文件)';
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

    String csvContent;
    if (ext == '.csv') {
      csvContent = await File(inputPath).readAsString();
    } else if (ext == '.xlsx' || ext == '.xls') {
      csvContent = _extractXlsxCsv(inputPath);
    } else if (ext == '.ods') {
      csvContent = _extractZipXml(inputPath, 'content.xml');
    } else if (ext == '.json') {
      csvContent = await File(inputPath).readAsString();
    } else if (ext == '.tsv') {
      final tsv = await File(inputPath).readAsString();
      csvContent = tsv.replaceAll('\t', ',');
    } else {
      return ConversionResult(success: false, error: '无法从 $ext 转换为CSV');
    }

    if (csvContent.isEmpty) csvContent = '(空)';
    await File(outputPath).writeAsString(csvContent);
    cb?.call(1.0, '完成');
    return ConversionResult(success: true, outputPath: outputPath, fileSize: csvContent.length);
  }

  // ==================== 转DOCX ====================

  static Future<ConversionResult> _convertToDocx(String inputPath, String outDir, ProgressCallback? cb) async {
    cb?.call(0.1, '提取文本...');
    final fileName = _changeExtension(p.basename(inputPath), '.docx');
    final outputPath = p.join(outDir, fileName);
    final ext = p.extension(inputPath).toLowerCase();

    String text;
    if (ext == '.txt' || ext == '.md' || ext == '.csv' || ext == '.json' || ext == '.xml' || ext == '.yaml' || ext == '.yml') {
      text = await File(inputPath).readAsString();
    } else if (ext == '.html' || ext == '.htm') {
      final html = await File(inputPath).readAsString();
      text = html.replaceAll(RegExp(r'<[^>]+>'), '\n').trim();
    } else if (ext == '.rtf') {
      final rtfText = await File(inputPath).readAsString();
      text = rtfText.replaceAll(RegExp(r'\\[a-z]+\d*\s?'), '').replaceAll(RegExp(r'[{}]'), '').trim();
    } else if (ext == '.docx') {
      text = _extractZipXml(inputPath, 'word/document.xml');
    } else if (ext == '.odt') {
      text = _extractZipXml(inputPath, 'content.xml');
    } else if (ext == '.epub') {
      text = _extractEpubText(inputPath);
    } else if (ext == '.pdf') {
      text = '(PDF→DOCX当前仅支持文本层提取)\n${_tryExtractPdfText(inputPath)}';
    } else {
      return ConversionResult(success: false, error: '不支持从 $ext 转换为DOCX');
    }

    cb?.call(0.3, '生成DOCX...');
    text = text.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
    final lines = text.split('\n');

    final documentXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
${lines.map((l) => '''    <w:p><w:r><w:t>${l.isEmpty ? '' : l}</w:t></w:r></w:p>''').join('\n')}
    <w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/></w:sectPr>
  </w:body>
</w:document>''';

    final archive = Archive();
    _addZipEntry(archive, '[Content_Types].xml', '''<?xml version="1.0" encoding="UTF-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>''');
    _addZipEntry(archive, '_rels/.rels', '''<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>''');
    _addZipEntry(archive, 'word/_rels/document.xml.rels', '''<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"></Relationships>''');
    _addZipEntry(archive, 'word/document.xml', documentXml);

    final zipBytes = ZipEncoder().encode(archive);
    await File(outputPath).writeAsBytes(zipBytes!);
    cb?.call(1.0, '完成');
    return ConversionResult(success: true, outputPath: outputPath, fileSize: zipBytes.length);
  }

  // ==================== 转ZIP ====================

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
      } else if (ext == '.7z' || ext == '.rar') {
        return ConversionResult(success: false, error: '${ext} 需要原生库，暂不支持');
      } else if (ext == '.tar' || ext == '.gz' || ext == '.tgz' || ext == '.bz2') {
        List<int> decodedBytes = bytes;
        if (ext == '.gz' || ext == '.tgz') decodedBytes = GZipDecoder().decodeBytes(bytes);
        archive = TarDecoder().decodeBytes(decodedBytes);
      } else {
        return ConversionResult(success: false, error: '不支持解压 $ext');
      }
    } catch (e) {
      return ConversionResult(success: false, error: '解压失败: $e');
    }

    cb?.call(0.6, '打包ZIP...');
    final outArchive = Archive();
    for (final file in archive.files) {
      if (file.isFile) outArchive.addFile(ArchiveFile(file.name, file.size, file.content as List<int>));
    }
    final zipBytes = ZipEncoder().encode(outArchive);
    await File(outputPath).writeAsBytes(zipBytes!);
    cb?.call(1.0, '完成');
    return ConversionResult(success: true, outputPath: outputPath, fileSize: zipBytes.length);
  }

  // ==================== ZIP内部文本提取工具 ====================

  static String _extractZipXml(String zipPath, String xmlPath) {
    try {
      final bytes = File(zipPath).readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final file in archive.files) {
        if (file.name == xmlPath && file.content != null) {
          return String.fromCharCodes(file.content!)
            .replaceAll(RegExp(r'<[^>]+>'), '\n')
            .replaceAll(RegExp(r'\n{3,}'), '\n\n')
            .trim();
        }
      }
    } catch (_) {}
    return '';
  }

  static String _extractXlsxText(String path) {
    try {
      final bytes = File(path).readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(bytes);
      List<String> sharedStrings = [];
      StringBuffer sb = StringBuffer();
      for (final f in archive.files) {
        if (f.name == 'xl/sharedStrings.xml' && f.content != null) {
          final xml = String.fromCharCodes(f.content!);
          for (final m in RegExp(r'<t[^>]*>([^<]*)</t>').allMatches(xml)) {
            sharedStrings.add(m.group(1) ?? '');
          }
        }
        if (f.name.startsWith('xl/worksheets/sheet') && f.name.endsWith('.xml') && f.content != null) {
          final xml = String.fromCharCodes(f.content!);
          for (final m in RegExp(r'<c[^>]*r="([^"]*)"[^>]*>(?:<v>([^<]*)</v>)?</c>').allMatches(xml)) {
            sb.write('${m.group(1)}: ${m.group(2) ?? ''}\n');
          }
        }
      }
      return sb.toString();
    } catch (_) {
      return '';
    }
  }

  static String _extractXlsxCsv(String path) {
    try {
      final bytes = File(path).readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(bytes);
      List<String> ss = [];
      StringBuffer sb = StringBuffer();
      for (final f in archive.files) {
        if (f.name == 'xl/sharedStrings.xml' && f.content != null) {
          for (final m in RegExp(r'<t[^>]*>([^<]*)</t>').allMatches(String.fromCharCodes(f.content!))) {
            ss.add(m.group(1) ?? '');
          }
        }
        if (f.name.startsWith('xl/worksheets/sheet') && f.name.endsWith('.xml') && f.content != null) {
          final xml = String.fromCharCodes(f.content!);
          for (final row in RegExp(r'<row[^>]*>(.*?)</row>', dotAll: true).allMatches(xml)) {
            final rowData = <String>[];
            for (final c in RegExp(r'<c[^>]*r="([^"]*)"[^>]*(?:t="s")?[^>]*>(?:<v>([^<]*)</v>)?</c>').allMatches(row.group(1)!)) {
              final ct = c.group(0);
              final cv = c.group(2) ?? '';
              String v = cv;
              if (ct?.contains('t="s"') == true && int.tryParse(cv) != null) {
                final idx = int.parse(cv);
                v = idx < ss.length ? ss[idx] : '';
              }
              rowData.add('"${v.replaceAll('"', '""')}"');
            }
            sb.writeln(rowData.join(','));
          }
        }
      }
      return sb.toString();
    } catch (e) {
      return '解析失败: $e';
    }
  }

  static String _extractEpubText(String path) {
    try {
      final bytes = File(path).readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(bytes);
      StringBuffer sb = StringBuffer();
      for (final file in archive.files) {
        if ((file.name.endsWith('.html') || file.name.endsWith('.xhtml') || file.name.endsWith('.htm')) && file.content != null) {
          sb.writeln(String.fromCharCodes(file.content!)
            .replaceAll(RegExp(r'<[^>]+>'), '\n')
            .replaceAll(RegExp(r'\n{3,}'), '\n\n'));
        }
      }
      return sb.toString().trim();
    } catch (_) {
      return '';
    }
  }

  static String _tryExtractPdfText(String path) {
    final bytes = File(path).readAsBytesSync();
    final s = String.fromCharCodes(bytes);
    final matches = RegExp(r'\((.*?)\)\s*Tj').allMatches(s);
    return matches.map((m) => m.group(1) ?? '').join(' ');
  }

  // ==================== 辅助 ====================

  static void _addZipEntry(Archive archive, String name, String content) {
    final data = content.codeUnits;
    archive.addFile(ArchiveFile(name, data.length, data));
  }

  static bool _isImageFile(String ext) => [
    '.png','.jpg','.jpeg','.gif','.bmp','.webp','.heic','.heif','.avif','.tiff','.tif','.ico'
  ].contains(ext);

  static bool _isTextFile(String ext) => [
    '.txt','.md','.csv','.tsv','.json','.xml','.html','.htm','.css','.js','.py','.java','.kt','.c','.cpp','.h','.sh','.yaml','.yml','.log','.ini','.cfg','.sql'
  ].contains(ext);

  static String _changeExtension(String fileName, String newExt) {
    final dotIndex = fileName.lastIndexOf('.');
    return dotIndex == -1 ? '$fileName$newExt' : '${fileName.substring(0, dotIndex)}$newExt';
  }

  static String _mimeToExtension(String mime) => const {
    'image/png':'.png','image/jpeg':'.jpg','image/webp':'.webp','image/bmp':'.bmp',
    'image/gif':'.gif','image/tiff':'.tiff','application/pdf':'.pdf','text/plain':'.txt',
    'text/csv':'.csv',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document':'.docx',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet':'.xlsx',
    'application/zip':'.zip',
  }[mime] ?? '.bin';
}
