/// One device a file or folder is on, as the Quark names it in a listing's
/// `devices` list: the device's serial (empty for the internal drive) and its
/// display name.
class FileDevice {
  const FileDevice({required this.serial, required this.name});

  /// The device's serial, empty for the internal drive.
  final String serial;

  /// The device's display name.
  final String name;

  factory FileDevice.fromJson(Map<String, dynamic> json) => FileDevice(
    serial: json['serial']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
  );

  Map<String, dynamic> toJson() => {'serial': serial, 'name': name};

  @override
  bool operator ==(Object other) =>
      other is FileDevice && other.serial == serial && other.name == name;

  @override
  int get hashCode => Object.hash(serial, name);

  @override
  String toString() => 'FileDevice($serial, $name)';
}
