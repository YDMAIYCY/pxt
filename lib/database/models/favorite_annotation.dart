class FavoriteAnnotation {
  const FavoriteAnnotation({
    required this.id,
    required this.start,
    required this.end,
    required this.quote,
    this.color,
    this.note,
  });

  final String id;
  final int start;
  final int end;
  final String quote;
  final String? color;
  final String? note;

  bool matches(String body) =>
      start >= 0 &&
      end > start &&
      end <= body.length &&
      body.substring(start, end) == quote;

  Map<String, Object?> toJson() => {
    'id': id,
    'start': start,
    'end': end,
    'quote': quote,
    'color': color,
    'note': note,
  };

  static FavoriteAnnotation? fromJson(Object? value) {
    if (value is! Map ||
        value['id'] is! String ||
        value['start'] is! int ||
        value['end'] is! int ||
        value['quote'] is! String) {
      return null;
    }
    return FavoriteAnnotation(
      id: value['id'] as String,
      start: value['start'] as int,
      end: value['end'] as int,
      quote: value['quote'] as String,
      color: value['color'] as String?,
      note: value['note'] as String?,
    );
  }
}
