enum ProfileFieldType {
  section,
  text,
  longtext,
  number,
  date,
  bool_,
  dropdown;

  String get dbValue {
    switch (this) {
      case ProfileFieldType.section:
        return 'section';
      case ProfileFieldType.text:
        return 'text';
      case ProfileFieldType.longtext:
        return 'longtext';
      case ProfileFieldType.number:
        return 'number';
      case ProfileFieldType.date:
        return 'date';
      case ProfileFieldType.bool_:
        return 'bool';
      case ProfileFieldType.dropdown:
        return 'dropdown';
    }
  }

  static ProfileFieldType fromDb(String? v) {
    switch (v) {
      case 'section':
        return ProfileFieldType.section;
      case 'longtext':
        return ProfileFieldType.longtext;
      case 'number':
        return ProfileFieldType.number;
      case 'date':
        return ProfileFieldType.date;
      case 'bool':
        return ProfileFieldType.bool_;
      case 'dropdown':
        return ProfileFieldType.dropdown;
      case 'text':
      default:
        return ProfileFieldType.text;
    }
  }

  String get label {
    switch (this) {
      case ProfileFieldType.section:
        return 'Bolk';
      case ProfileFieldType.text:
        return 'Tekst';
      case ProfileFieldType.longtext:
        return 'Lang tekst';
      case ProfileFieldType.number:
        return 'Tall';
      case ProfileFieldType.date:
        return 'Dato';
      case ProfileFieldType.bool_:
        return 'Ja/Nei';
      case ProfileFieldType.dropdown:
        return 'Nedtrekksliste';
    }
  }
}

class ProfileField {
  final String id;
  final String companyId;
  final String? parentId;
  final String title;
  final ProfileFieldType type;
  final List<String> options;
  final bool required;
  final int sortOrder;

  const ProfileField({
    required this.id,
    required this.companyId,
    required this.parentId,
    required this.title,
    required this.type,
    this.options = const [],
    this.required = false,
    this.sortOrder = 0,
  });

  bool get isSection => parentId == null;

  factory ProfileField.fromJson(Map<String, dynamic> j) {
    final rawOptions = j['options'];
    List<String> opts = const [];
    if (rawOptions is List) {
      opts = rawOptions.map((e) => e.toString()).toList();
    }
    return ProfileField(
      id: j['id'] as String,
      companyId: j['company_id'] as String,
      parentId: j['parent_id'] as String?,
      title: (j['title'] as String?) ?? '',
      type: ProfileFieldType.fromDb(j['field_type'] as String?),
      options: opts,
      required: (j['required'] as bool?) ?? false,
      sortOrder: (j['sort_order'] as int?) ?? 0,
    );
  }

  Map<String, dynamic> toInsert() => {
        'company_id': companyId,
        'parent_id': parentId,
        'title': title,
        'field_type': type.dbValue,
        'options': options.isEmpty ? null : options,
        'required': required,
        'sort_order': sortOrder,
      };

  Map<String, dynamic> toUpdate() => {
        'title': title,
        'field_type': type.dbValue,
        'options': options.isEmpty ? null : options,
        'required': required,
        'sort_order': sortOrder,
      };
}
