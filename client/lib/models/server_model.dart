class ServerModel {
  final String name;
  final String ip;
  final String port;
  final String link;

  ServerModel({
    required this.name,
    required this.ip,
    required this.port,
    required this.link,
  });

  factory ServerModel.fromJson(Map<String, dynamic> json) {
    return ServerModel(
      name: json['name'] ?? '',
      ip: json['ip'] ?? '',
      port: json['port'] ?? '',
      link: json['link'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'ip': ip,
      'port': port,
      'link': link,
    };
  }
}
