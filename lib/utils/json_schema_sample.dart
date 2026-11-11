/// A sample value shaped like [schema], a JSON schema as the Swagger spec
/// writes one with every `$ref` already resolved: what the API explorer's
/// body field starts from (#4077).
///
/// An object gets every property, an array one sample item, a string its
/// first `enum` value or `''`, a number `0`, a boolean `false`. A schema's
/// own `example` wins, and `allOf` merges its parts. Anything else is null.
Object? jsonSchemaSample(Map<String, dynamic> schema) {
  if (schema.containsKey('example')) return schema['example'];
  final allOf = schema['allOf'];
  if (allOf is List) {
    return {
      for (final part in [
        ...allOf,
        {...schema}..remove('allOf'),
      ])
        if (part is Map<String, dynamic>)
          if (jsonSchemaSample(part) case final Map<String, dynamic> sample)
            ...sample,
    };
  }
  final enumValues = schema['enum'];
  if (enumValues is List && enumValues.isNotEmpty) return enumValues.first;
  final properties = schema['properties'];
  final items = schema['items'];
  return switch (schema['type']) {
    'object' || null when properties is Map<String, dynamic> => {
      for (final MapEntry(:key, :value) in properties.entries)
        key: value is Map<String, dynamic> ? jsonSchemaSample(value) : null,
    },
    'object' => <String, dynamic>{},
    'array' => [if (items is Map<String, dynamic>) jsonSchemaSample(items)],
    'string' => '',
    'integer' || 'number' => 0,
    'boolean' => false,
    _ => null,
  };
}
