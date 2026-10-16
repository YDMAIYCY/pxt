// ========== 资料预设 ==========
// 统一管理资料页使用的头像和背景样式键。

class ProfilePresetIds {
  const ProfilePresetIds._();

  static const String avatarSky = 'avatar_sky';
  static const String avatarSunset = 'avatar_sunset';
  static const String avatarForest = 'avatar_forest';
  static const String avatarViolet = 'avatar_violet';
  static const String avatarLogo = 'avatar_logo';

  static const String backgroundAurora = 'background_aurora';
  static const String backgroundLake = 'background_lake';
  static const String backgroundCosmos = 'background_cosmos';
  static const String backgroundMist = 'background_mist';
  static const String backgroundSunrise = 'background_sunrise';

  static const String defaultAvatarStyle = avatarSky;
  static const String defaultBackgroundStyle = backgroundLake;
}

// ========== 用户资料模型 ==========
// 承载“我的”页展示与编辑所需的用户信息。

class UserProfile {
  const UserProfile({
    required this.id,
    required this.username,
    required this.displayName,
    required this.bio,
    required this.gender,
    required this.avatarStyle,
    required this.backgroundStyle,
    this.avatarImagePath,
    this.backgroundImagePath,
    this.age,
    this.lastLoginAt,
  });

  final int id;
  final String username;
  final String displayName;
  final String bio;
  final String gender;
  final String avatarStyle;
  final String backgroundStyle;
  final String? avatarImagePath;
  final String? backgroundImagePath;
  final int? age;
  final DateTime? lastLoginAt;

  String get primaryName => displayName.trim().isEmpty ? username : displayName;

  String get monogram {
    final source = primaryName.trim();
    if (source.isEmpty) {
      return '我';
    }

    return source.substring(0, 1).toUpperCase();
  }

  UserProfile copyWith({
    String? username,
    String? displayName,
    String? bio,
    String? gender,
    String? avatarStyle,
    String? backgroundStyle,
    Object? avatarImagePath = _sentinel,
    Object? backgroundImagePath = _sentinel,
    Object? age = _sentinel,
    Object? lastLoginAt = _sentinel,
  }) {
    return UserProfile(
      id: id,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      bio: bio ?? this.bio,
      gender: gender ?? this.gender,
      avatarStyle: avatarStyle ?? this.avatarStyle,
      backgroundStyle: backgroundStyle ?? this.backgroundStyle,
      avatarImagePath: avatarImagePath == _sentinel
          ? this.avatarImagePath
          : avatarImagePath as String?,
      backgroundImagePath: backgroundImagePath == _sentinel
          ? this.backgroundImagePath
          : backgroundImagePath as String?,
      age: age == _sentinel ? this.age : age as int?,
      lastLoginAt: lastLoginAt == _sentinel
          ? this.lastLoginAt
          : lastLoginAt as DateTime?,
    );
  }

  Map<String, Object?> toDatabaseMap() {
    return {
      'display_name': displayName.trim(),
      'bio': bio.trim(),
      'gender': gender.trim(),
      'age': age,
      'avatar_style': avatarStyle.trim(),
      'background_style': backgroundStyle.trim(),
      'avatar_image_path': avatarImagePath,
      'background_image_path': backgroundImagePath,
    };
  }

  factory UserProfile.fromMap(Map<String, Object?> map) {
    final username = (map['username'] as String?)?.trim() ?? '';
    final displayName = (map['display_name'] as String?)?.trim();
    final bio = (map['bio'] as String?)?.trim();
    final gender = (map['gender'] as String?)?.trim();
    final avatarStyle = (map['avatar_style'] as String?)?.trim();
    final backgroundStyle = (map['background_style'] as String?)?.trim();
    final avatarImagePath = (map['avatar_image_path'] as String?)?.trim();
    final backgroundImagePath =
        (map['background_image_path'] as String?)?.trim();
    final lastLoginAtRaw = map['last_login_at'] as String?;

    return UserProfile(
      id: map['id'] as int,
      username: username,
      displayName: displayName == null || displayName.isEmpty
          ? username
          : displayName,
      bio: bio == null || bio.isEmpty ? _defaultBio : bio,
      gender: gender == null || gender.isEmpty ? _defaultGender : gender,
      avatarStyle: avatarStyle == null || avatarStyle.isEmpty
          ? ProfilePresetIds.defaultAvatarStyle
          : avatarStyle,
      backgroundStyle: backgroundStyle == null || backgroundStyle.isEmpty
          ? ProfilePresetIds.defaultBackgroundStyle
          : backgroundStyle,
      avatarImagePath: avatarImagePath == null || avatarImagePath.isEmpty
          ? null
          : avatarImagePath,
      backgroundImagePath:
          backgroundImagePath == null || backgroundImagePath.isEmpty
          ? null
          : backgroundImagePath,
      age: map['age'] as int?,
      lastLoginAt: lastLoginAtRaw == null || lastLoginAtRaw.isEmpty
          ? null
          : DateTime.tryParse(lastLoginAtRaw)?.toLocal(),
    );
  }

  static const String _defaultBio = '记录今天的学习灵感，慢慢长成自己的知识库。';
  static const String _defaultGender = '保密';
}

const Object _sentinel = Object();
