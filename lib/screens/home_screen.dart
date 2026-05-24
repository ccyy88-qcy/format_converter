import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import '../utils/file_format_detector.dart';
import '../engines/format_converter_engine.dart';
import '../widgets/format_selector.dart';
import '../widgets/convert_progress.dart';
import '../widgets/result_view.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _selectedFile;
  String? _detectedMime;
  String _detectedFormat = '';
  String _fileCategory = '';
  int _fileSize = 0;
  List<String> _targetFormats = [];
  String? _selectedTarget;
  bool _isConverting = false;
  double _progress = 0;
  String _progressText = '';
  ConversionResult? _result;

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );

    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      final file = File(path);

      setState(() {
        _selectedFile = path;
        _isConverting = false;
        _result = null;
        _progress = 0;
        _progressText = '';
        _selectedTarget = null;
      });

      // 检测格式
      final mime = await FileFormatDetector.detect(path);
      final stat = await file.stat();

      setState(() {
        _detectedMime = mime;
        _detectedFormat = FileFormatDetector.getFormatName(mime);
        _fileCategory = FileFormatDetector.getCategory(mime);
        _fileSize = stat.size;
        _targetFormats = FileFormatDetector.getSupportedTargets(mime);

        // 默认选中第一个目标格式
        if (_targetFormats.isNotEmpty) {
          _selectedTarget = _targetFormats.first;
        }
      });
    }
  }

  Future<void> _convert() async {
    if (_selectedFile == null || _selectedTarget == null) return;

    setState(() {
      _isConverting = true;
      _progress = 0;
      _progressText = '准备中...';
      _result = null;
    });

    final result = await FormatConverterEngine.convert(
      inputPath: _selectedFile!,
      targetMime: _selectedTarget!,
      outputDir: p.dirname(_selectedFile!),
      onProgress: (p, text) {
        setState(() {
          _progress = p;
          _progressText = text;
        });
      },
    );

    setState(() {
      _isConverting = false;
      _result = result;
      _progress = 1;
      _progressText = result.success ? '转换完成' : '转换失败';
    });
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case '图片': return Icons.image;
      case '文档': return Icons.description;
      case '视频': return Icons.videocam;
      case '音频': return Icons.audiotrack;
      case '压缩包': return Icons.folder_zip;
      default: return Icons.insert_drive_file;
    }
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case '图片': return Colors.green;
      case '文档': return Colors.blue;
      case '视频': return Colors.red;
      case '音频': return Colors.purple;
      case '压缩包': return Colors.orange;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('全能格式转换', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              // TODO: 设置页
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 选文件按钮
            if (_selectedFile == null) _buildFilePicker() else _buildFileInfo(),

            const SizedBox(height: 16),

            // 目标格式选择
            if (_selectedFile != null && _targetFormats.isNotEmpty) ...[
              _buildTargetSelector(),
              const SizedBox(height: 16),
            ],

            // 不支持的提示
            if (_selectedFile != null && _targetFormats.isEmpty) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.amber.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('该格式暂无支持的转换目标',
                        style: TextStyle(color: Colors.amber.shade900)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // 转换进度
            if (_isConverting) ...[
              ConvertProgress(progress: _progress, status: _progressText),
              const SizedBox(height: 16),
            ],

            // 转换结果
            if (_result != null) ResultView(result: _result!),

            // 转换按钮
            if (_selectedFile != null && _selectedTarget != null && !_isConverting && _result == null)
              _buildConvertButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildFilePicker() {
    return InkWell(
      onTap: _pickFile,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 48),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.blue.shade200, width: 2, strokeAlign: BorderSide.strokeAlignInside),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_circle_outline, size: 48, color: Colors.blue.shade400),
            const SizedBox(height: 12),
            Text('点击选择文件', style: TextStyle(fontSize: 18, color: Colors.blue.shade700, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('支持图片、文档、音频、视频、压缩包', style: TextStyle(fontSize: 13, color: Colors.blue.shade400)),
          ],
        ),
      ),
    );
  }

  Widget _buildFileInfo() {
    final fileName = p.basename(_selectedFile!);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _getCategoryColor(_fileCategory).withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _getCategoryColor(_fileCategory).withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _getCategoryColor(_fileCategory).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_getCategoryIcon(_fileCategory),
                  color: _getCategoryColor(_fileCategory), size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(fileName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: _getCategoryColor(_fileCategory).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(_detectedFormat,
                            style: TextStyle(fontSize: 11, color: _getCategoryColor(_fileCategory), fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(width: 8),
                        Text(_formatSize(_fileSize),
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () {
                  setState(() {
                    _selectedFile = null;
                    _detectedMime = null;
                    _targetFormats = [];
                    _selectedTarget = null;
                    _result = null;
                  });
                },
                icon: const Icon(Icons.close, size: 20),
                color: Colors.grey.shade500,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTargetSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('转换为', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.grey.shade800)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _targetFormats.map((mime) {
              final isSelected = mime == _selectedTarget;
              final label = FileFormatDetector.getFormatName(mime);
              return ChoiceChip(
                label: Text(label),
                selected: isSelected,
                onSelected: (_) => setState(() => _selectedTarget = mime),
                selectedColor: Colors.blue.shade100,
                labelStyle: TextStyle(
                  color: isSelected ? Colors.blue.shade800 : Colors.grey.shade700,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildConvertButton() {
    return ElevatedButton(
      onPressed: _convert,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 0,
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.transform, size: 22),
          SizedBox(width: 8),
          Text('开始转换', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
