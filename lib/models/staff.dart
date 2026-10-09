enum StaffRole { owner, attendant }

StaffRole staffRoleFromString(String value) {
  switch (value) {
    case 'owner':
      return StaffRole.owner;
    case 'attendant':
    default:
      return StaffRole.attendant;
  }
}

extension StaffRoleX on StaffRole {
  String get asString => this == StaffRole.owner ? 'owner' : 'attendant';

  /// Owners see revenue/reports; attendants only see their own queue.
  bool get canViewReports => this == StaffRole.owner;
  bool get canManagePricing => this == StaffRole.owner;
  bool get canManageStaff => this == StaffRole.owner;
}

class Staff {
  final String id;
  final String shopId;
  final String name;
  final StaffRole role;
  final bool active;
  final DateTime createdAt;

  const Staff({
    required this.id,
    required this.shopId,
    required this.name,
    required this.role,
    this.active = true,
    required this.createdAt,
  });

  factory Staff.fromJson(Map<String, dynamic> json) {
    return Staff(
      id: json['id'] as String,
      shopId: json['shop_id'] as String,
      name: json['name'] as String,
      role: staffRoleFromString(json['role'] as String? ?? 'attendant'),
      active: json['active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'shop_id': shopId,
        'name': name,
        'role': role.asString,
        'active': active,
        'created_at': createdAt.toIso8601String(),
      };
}
