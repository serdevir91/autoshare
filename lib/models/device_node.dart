class DeviceNode {
  final String id;
  final String name;
  final String ip;
  final int port;
  final String type; // 'pc' or 'mobile'
  final bool isPaired;
  final DateTime lastSeen;
  final String? pairToken; // Cryptographic key for auto-accepting transfers

  DeviceNode({
    required this.id,
    required this.name,
    required this.ip,
    required this.port,
    required this.type,
    this.isPaired = false,
    required this.lastSeen,
    this.pairToken,
  });

  DeviceNode copyWith({
    String? id,
    String? name,
    String? ip,
    int? port,
    String? type,
    bool? isPaired,
    DateTime? lastSeen,
    String? pairToken,
  }) {
    return DeviceNode(
      id: id ?? this.id,
      name: name ?? this.name,
      ip: ip ?? this.ip,
      port: port ?? this.port,
      type: type ?? this.type,
      isPaired: isPaired ?? this.isPaired,
      lastSeen: lastSeen ?? this.lastSeen,
      pairToken: pairToken ?? this.pairToken,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'ip': ip,
      'port': port,
      'type': type,
      'isPaired': isPaired,
      'lastSeen': lastSeen.toIso8601String(),
      'pairToken': pairToken,
    };
  }

  factory DeviceNode.fromJson(Map<String, dynamic> json) {
    return DeviceNode(
      id: json['id'] as String,
      name: json['name'] as String,
      ip: json['ip'] as String,
      port: json['port'] as int,
      type: json['type'] as String,
      isPaired: json['isPaired'] as bool? ?? false,
      lastSeen: json['lastSeen'] != null 
          ? DateTime.parse(json['lastSeen'] as String)
          : DateTime.now(),
      pairToken: json['pairToken'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeviceNode && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
