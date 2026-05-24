import 'dart:io';
import 'package:flutter/material.dart';

/// 简单的内置文件浏览器
class FileBrowser extends StatefulWidget {
  final String initialPath;
  final void Function(String path) onFileSelected;

  const FileBrowser({
    super.key,
    required this.initialPath,
    required this.onFileSelected,
  });

  @override
  State<FileBrowser> createState() => _FileBrowserState();
}

class _FileBrowserState extends State<FileBrowser> {
  late String _currentPath;
  List<FileSystemEntity> _entries = [];
  bool _loading = true;

  final List<String> _storageRoots = [
    '/storage/emulated/0',
    '/sdcard',
    '/storage/emulated/0/Download',
    '/storage/emulated/0/Documents',
  ];

  @override
  void initState() {
    super.initState();
    _currentPath = widget.initialPath;
    _loadDirectory();
  }

  void _loadDirectory() {
    setState(() => _loading = true);
    try {
      final dir = Directory(_currentPath);
      if (dir.existsSync()) {
        _entries = dir.listSync()
          ..sort((a, b) {
            final aIsDir = a is Directory;
            final bIsDir = b is Directory;
            if (aIsDir && !bIsDir) return -1;
            if (!aIsDir && bIsDir) return 1;
            return a.path.toLowerCase().compareTo(b.path.toLowerCase());
          });
      } else {
        _entries = [];
      }
    } catch (_) {
      _entries = [];
    }
    setState(() => _loading = false);
  }

  void _navigateTo(String path) {
    setState(() => _currentPath = path);
    _loadDirectory();
  }

  void _goUp() {
    final parent = Directory(_currentPath).parent.path;
    if (parent != _currentPath) _navigateTo(parent);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 路径导航
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.grey.shade100,
          child: Column(
            children: [
              // 快捷路径
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _storageRoots.map((root) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        label: Text(_rootLabel(root), style: const TextStyle(fontSize: 11)),
                        onPressed: () => _navigateTo(root),
                        backgroundColor: _currentPath == root ? Colors.blue.shade100 : null,
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton(icon: const Icon(Icons.arrow_upward, size: 20), onPressed: _goUp, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(_currentPath, style: const TextStyle(fontSize: 12, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ],
          ),
        ),

        // 文件列表
        Expanded(
          child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _entries.isEmpty
              ? const Center(child: Text('目录为空'))
              : ListView.builder(
                  itemCount: _entries.length,
                  itemBuilder: (context, index) {
                    final entry = _entries[index];
                    final isDir = entry is Directory;
                    final name = entry.path.split('/').last;

                    return ListTile(
                      dense: true,
                      leading: Icon(isDir ? Icons.folder : _fileIcon(name), size: 28,
                        color: isDir ? Colors.amber : Colors.grey.shade600),
                      title: Text(name, style: const TextStyle(fontSize: 14)),
                      subtitle: isDir ? null : Text(_formatSize(entry), style: const TextStyle(fontSize: 11)),
                      trailing: isDir ? const Icon(Icons.chevron_right, size: 20) : null,
                      onTap: () {
                        if (isDir) {
                          _navigateTo(entry.path);
                        } else {
                          widget.onFileSelected(entry.path);
                          Navigator.pop(context);
                        }
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _rootLabel(String path) {
    final parts = path.split('/');
    return parts.last.isEmpty ? '/' : parts.last;
  }

  IconData _fileIcon(String name) {
    final ext = name.toLowerCase().split('.').last;
    if (['png','jpg','jpeg','gif','bmp','webp','heic'].contains(ext)) return Icons.image;
    if (['pdf'].contains(ext)) return Icons.picture_as_pdf;
    if (['doc','docx','odt','rtf','txt','md'].contains(ext)) return Icons.description;
    if (['xls','xlsx','ods','csv'].contains(ext)) return Icons.table_chart;
    if (['ppt','pptx','odp'].contains(ext)) return Icons.slideshow;
    if (['zip','rar','7z','tar','gz'].contains(ext)) return Icons.folder_zip;
    if (['mp3','wav','flac','ogg','aac'].contains(ext)) return Icons.audiotrack;
    if (['mp4','avi','mkv','mov'].contains(ext)) return Icons.videocam;
    return Icons.insert_drive_file;
  }

  String _formatSize(FileSystemEntity entry) {
    if (entry is! File) return '';
    try {
      final size = entry.lengthSync();
      if (size < 1024) return '${size}B';
      if (size < 1024*1024) return '${(size/1024).toStringAsFixed(1)}KB';
      return '${(size/(1024*1024)).toStringAsFixed(1)}MB';
    } catch (_) {
      return '';
    }
  }
}
