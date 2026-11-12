import 'package:flutter_test/flutter_test.dart';
import 'package:quark/utils/json_schema_sample.dart';

/// The API explorer's body field starts from a sample of the request schema
/// (#4077).
void main() {
  test('fills every property of an object with a value of its type', () {
    expect(
      jsonSchemaSample({
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
          'count': {'type': 'integer'},
          'ratio': {'type': 'number'},
          'enabled': {'type': 'boolean'},
          'level': {
            'type': 'string',
            'enum': ['read', 'write'],
          },
          'tags': {
            'type': 'array',
            'items': {'type': 'string'},
          },
          'owner': {
            'type': 'object',
            'properties': {
              'id': {'type': 'integer'},
            },
          },
          'extra': {'type': 'object'},
        },
      }),
      {
        'name': '',
        'count': 0,
        'ratio': 0,
        'enabled': false,
        'level': 'read',
        'tags': [''],
        'owner': {'id': 0},
        'extra': <String, dynamic>{},
      },
    );
  });

  test('an example wins over the type', () {
    expect(jsonSchemaSample({'type': 'string', 'example': 'ada'}), 'ada');
  });

  test('allOf merges its parts and the schema beside it', () {
    expect(
      jsonSchemaSample({
        'allOf': [
          {
            'type': 'object',
            'properties': {
              'a': {'type': 'integer'},
            },
          },
          {
            'properties': {
              'b': {'type': 'boolean'},
            },
          },
        ],
        'properties': {
          'c': {'type': 'string'},
        },
      }),
      {'a': 0, 'b': false, 'c': ''},
    );
  });

  test('an unknown type is null', () {
    expect(jsonSchemaSample({'type': 'file'}), isNull);
    expect(jsonSchemaSample({}), isNull);
  });
}
