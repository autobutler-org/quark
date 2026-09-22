class FileNode {
  const FileNode({
    required this.name,
    required this.size,
    required this.isDir,
    required this.deviceName,
    required this.devicePath,
    required this.deviceSerial,
    required this.dirPath,
    this.fileType = '',
    this.compressedSize = 0,
  });

  final String name;
  final int size;
  final int compressedSize;
  final bool isDir;
  final String deviceName;
  final String devicePath;
  final String deviceSerial;
  final String dirPath;
  final String fileType;

  /// API path relative to the files root, safe to use in API calls.
  String get apiPath {
    final raw = dirPath.trim().isNotEmpty ? dirPath : name;
    return raw.trim().replaceAll(RegExp(r'^/+|/+$'), '');
  }

  /// Whether a library search for [query] (already trimmed and lowercased)
  /// lists this file: its name or its folder path contains it.
  bool matchesSearch(String query) =>
      name.toLowerCase().contains(query) ||
      dirPath.toLowerCase().contains(query);

  factory FileNode.fromJson(Map<String, dynamic> json) {
    int parseSize(Object? value) {
      if (value is int) {
        return value;
      }
      if (value is num) {
        return value.toInt();
      }
      if (value is String) {
        return int.tryParse(value) ?? 0;
      }
      return 0;
    }

    bool parseBool(Object? value) {
      if (value is bool) {
        return value;
      }
      if (value is String) {
        return value.toLowerCase() == 'true';
      }
      return false;
    }

    String parseString(Object? value) {
      return value?.toString() ?? '';
    }

    return FileNode(
      name: parseString(json['name']),
      size: parseSize(json['size']),
      compressedSize: parseSize(
        json['compressedSize'] ?? json['compressed_size'],
      ),
      isDir: parseBool(json['isDir'] ?? json['is_dir']),
      deviceName: parseString(json['deviceName'] ?? json['device_name']),
      devicePath: parseString(json['devicePath'] ?? json['device_path']),
      deviceSerial: parseString(json['deviceSerial'] ?? json['device_serial']),
      dirPath: parseString(json['dirPath'] ?? json['dir_path']),
      fileType: parseString(json['fileType'] ?? json['file_type']),
    );
  }
}
