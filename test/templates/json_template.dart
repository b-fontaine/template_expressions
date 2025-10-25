import 'dart:convert';

import 'package:template_expressions_4/template_expressions.dart';
import 'package:test/test.dart';

void main() {
  final context = {
    'person': {'firstName': 'John', 'lastName': 'Smith'},
  };

  test('json template', () {
    final template = Template(value: _kTemplate);

    final result = template.process(context: context);

    expect(json.decode(result), {
      'firstName': 'John',
      'lastName': 'Smith',
      'email': 'john.smith@example.com',
    });
  });
}

const _kTemplate = r'''
{
  "firstName": "${person['firstName']}",
  "lastName": "${person['lastName']}",
  "email": "${(person['firstName']).toLowerCase()}.${(person['lastName']).toLowerCase()}@example.com"
}
''';
