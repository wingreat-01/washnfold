class Shop {
  final String id;
  final String name;
  final String ownerId;
  final String? branchName;
  final DateTime createdAt;

  const Shop({
    required this.id,
    required this.name,
    required this.ownerId,
    this.branchName,
    required this.createdAt,
  });

  factory Shop.fromJson(Map<String, dynamic> json) {
    return Shop(
      id: json['id'] as String,
      name: json['name'] as String,
      ownerId: json['owner_id'] as String,
      branchName: json['branch_name'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'owner_id': ownerId,
        'branch_name': branchName,
        'created_at': createdAt.toIso8601String(),
      };
}
