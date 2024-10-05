library expressions.parser;

import 'package:meta/meta.dart';
import 'package:petitparser/petitparser.dart';

import 'expressions.dart';

class ExpressionParser {
  ExpressionParser() {
    expression.set(
      binaryExpression.seq(conditionArguments.optional()).map(
            (l) => l[1] == null
                ? l[0]
                : ConditionalExpression(l[0], l[1][0], l[1][1]),
          ),
    );
    token.set((literal | unaryExpression | variable).cast<Expression>());
  }

  // Gobbles only identifiers
  // e.g.: `foo`, `_value`, `$x1`
  Parser<Identifier> get identifier =>
      (digit().not() & (word() | char(r'$')).plus()).flatten().map(
            (v) => Identifier(v),
          );

  // Parse simple numeric literals: `12`, `3.4`, `.5`.
  Parser<Literal> get numericLiteral => ((digit() | char('.')).and() &
              (digit().star() &
                  ((char('.') & digit().plus()) |
                          (char('x') & digit().plus()) |
                          (anyOf('Ee') &
                              anyOf('+-').optional() &
                              digit().plus()))
                      .optional()))
          .flatten()
          .map((v) {
        return Literal(num.parse(v), v);
      });

  Parser<String> get escapedChar =>
      (char(r'\') & anyOf("nrtbfv\"'\\")).pick(1).cast();

  String unescape(String v) => v.replaceAllMapped(
      RegExp("\\\\[nrtbf\"'\\\\]"),
      (v) => const {
            'n': '\n',
            'r': '\r',
            't': '\t',
            'b': '\b',
            'f': '\f',
            'v': '\v',
            "'": "'",
            '"': '"',
            '\\': '\\',
          }[v.group(0)!.substring(1)]!);

  Parser<Literal> get sqStringLiteral => (char("'") &
          (anyOf(r"'\").neg() | escapedChar).star().flatten() &
          char("'"))
      .pick(1)
      .map((v) => Literal(unescape(v), "'$v'"));

  Parser<Literal> get dqStringLiteral => (char('"') &
          (anyOf(r'"\').neg() | escapedChar).star().flatten() &
          char('"'))
      .pick(1)
      .map((v) => Literal(unescape(v), '"$v"'));

  // Parses a string literal, staring with single or double quotes with basic
  // support for escape codes e.g. `'hello world'`, `'this is\nJSEP'`
  Parser<Literal> get stringLiteral =>
      sqStringLiteral.or(dqStringLiteral).cast();

  // Parses a boolean literal
  Parser<Literal> get boolLiteral =>
      (string('true') | string('false')).map((v) => Literal(v == 'true', v));

  // Parses the null literal
  Parser<Literal> get nullLiteral =>
      string('null').map((v) => Literal(null, v));

  // Parses the this literal
  Parser<ThisExpression> get thisExpression =>
      string('this').map((v) => ThisExpression());

  // Responsible for parsing Array literals `[1, 2, 3]`
  // This function assumes that it needs to gobble the opening bracket
  // and then tries to gobble the expressions as arguments.
  Parser<Literal> get arrayLiteral =>
      (char('[').trim() & arguments & char(']').trim())
          .pick(1)
          .map((l) => Literal(l, '$l'));

  Parser<Literal> get mapLiteral =>
      (char('{').trim() & mapArguments & char('}').trim())
          .pick(1)
          .map((l) => Literal(l, '$l'));

  Parser<Literal> get literal => (numericLiteral |
          stringLiteral |
          boolLiteral |
          nullLiteral |
          arrayLiteral |
          mapLiteral)
      .cast();

  // An individual part of a binary expression:
  // e.g. `foo.bar(baz)`, `1`, `'abc'`, `(a % 2)` (because it's in parenthesis)
  final SettableParser<Expression> token = undefined<Expression>();

  // Also use a map for the binary operations but set their values to their
  // binary precedence for quick reference:
  // see [Order of operations](http://en.wikipedia.org/wiki/Order_of_operations#Programming_language)
  static const Map<String, int> binaryOperations = {
    '||': 1,
    '&&': 2,
    '|': 3,
    '^': 4,
    '&': 5,
    '==': 6,
    '!=': 6,
    '<=': 7,
    '>=': 7,
    '<': 7,
    '>': 7,
    '<<': 8,
    '>>': 8,
    '+': 9,
    '-': 9,
    '*': 10,
    '/': 10,
    '%': 10,
    '~/': 10,
    '??': 11,
    '=': 8,
  };

  // This function is responsible for gobbling an individual expression,
  // e.g. `1`, `1+2`, `a+(b*2)-Math.sqrt(2)`
  Parser<String> get binaryOperation => binaryOperations.keys
      .map<Parser<String>>((v) => string(v))
      .reduce((a, b) => (a | b).cast<String>())
      .trim();

  Parser<Expression> get binaryExpression =>
      token.plusSeparated(binaryOperation).withSeparators().map((l) {
        final first = l[0];
        final stack = <dynamic>[first];

        for (var i = 1; i < l.length; i += 2) {
          final op = l[i];
          final prec = BinaryExpression.precedenceForOperator(op);

          // Reduce: make a binary expression from the three topmost entries.
          while ((stack.length > 2) &&
              (prec <=
                  BinaryExpression.precedenceForOperator(
                      stack[stack.length - 2]))) {
            final right = stack.removeLast();
            final op = stack.removeLast();
            final left = stack.removeLast();
            final node = BinaryExpression(op, left, right);
            stack.add(node);
          }

          final node = l[i + 1];
          stack.addAll([op, node]);
        }

        var i = stack.length - 1;
        var node = stack[i];
        while (i > 1) {
          node = BinaryExpression(stack[i - 1], stack[i - 2], node);
          i -= 2;
        }
        return node;
      });

  // Use a quickly-accessible map to store all of the unary operators
  // Values are set to `true` (it really doesn't matter)
  static const _unaryOperations = ['-', '!', '~', '+'];

  Parser<UnaryExpression> get unaryExpression => _unaryOperations
      .map<Parser<String>>((v) => string(v))
      .reduce((a, b) => (a | b).cast<String>())
      .trim()
      .seq(token)
      .map((l) => UnaryExpression(l[0], l[1]));

  // Gobbles a list of arguments within the context of a function call
  // or array literal. This function also assumes that the opening character
  // `(` or `[` has already been gobbled, and gobbles expressions and commas
  // until the terminator character `)` or `]` is encountered.
  // e.g. `foo(bar, baz)`, `my_func()`, or `[bar, baz]`
  Parser<List<Expression>> get arguments => expression
      .plusSeparated(char(',').trim())
      .expressionList<Expression>()
      .optionalWith([]);

  Parser<Map<Expression, Expression>> get mapArguments =>
      (expression & char(':').trim() & expression)
          .map((l) => MapEntry<Expression, Expression>(l[0], l[2]))
          .plusSeparated(char(',').trim())
          .expressionList<MapEntry<Expression, Expression>>()
          .map((l) => Map.fromEntries(l))
          .optionalWith({});

  // Gobble a non-literal variable name. This variable name may include properties
  // e.g. `foo`, `bar.baz`, `foo['bar'].baz`
  // It also gobbles function calls:
  // e.g. `Math.acos(obj.angle)`
  Parser<Expression> get variable => groupOrIdentifier
          .seq((memberArgument.cast() | indexArgument | callArgument).star())
          .map((l) {
        final a = l[0] as Expression;
        final b = l[1] as List;
        return b.fold(a, (Expression object, argument) {
          dynamic result;

          if (argument is Identifier) {
            result = MemberExpression(object, argument, nullable: true);
          } else if (argument is Expression) {
            result = IndexExpression(object, argument, nullable: true);
          } else if (argument is List<Expression>) {
            result = CallExpression(object, argument);
          } else {
            throw ArgumentError('Invalid type ${argument.runtimeType}');
          }

          return result;
        });
      });

  // Responsible for parsing a group of things within parentheses `()`
  // This function assumes that it needs to gobble the opening parenthesis
  // and then tries to gobble everything within that parenthesis, assuming
  // that the next thing it should see is the close parenthesis. If not,
  // then the expression probably doesn't have a `)`
  Parser<Expression> get group =>
      (char('(') & expression.trim() & char(')')).pick(1).cast();

  Parser<Expression> get groupOrIdentifier =>
      (group | thisExpression | identifier.map((v) => Variable(v))).cast();

  Parser<Identifier> get memberArgument =>
      (char('.') & identifier).pick(1).cast();

  Parser<Expression> get indexArgument =>
      (char('[') & expression.trim() & char(']')).pick(1).cast();

  Parser<List<Expression>> get callArgument =>
      (char('(') & arguments & char(')')).pick(1).cast();

  // Ternary expression: test ? consequent : alternate
  Parser<List<Expression>> get conditionArguments =>
      (char('?').trim() & expression & char(':').trim())
          .pick(1)
          .seq(expression)
          .castList();

  final SettableParser<Expression> expression = undefined();
}

extension SeparatedListParserExtension<T> on Parser<T> {
  @useResult
  Parser<List<R>> expressionList<R>() => SeparatedListParser(this);

  @useResult
  Parser<List<R>> withSeparators<R>() => WithSeparatorListParser(this);
}

class SeparatedListParser<T, R> extends DelegateParser<T, List<R>> {
  SeparatedListParser(super.delegate);

  @override
  Result<List<R>> parseOn(Context context) {
    final result = delegate.parseOn(context);
    if (result is Success) {
      return result.success((result.value as SeparatedList).elements.cast<R>());
    } else {
      return result.failure(result.message);
    }
  }

  @override
  int fastParseOn(String buffer, int position) =>
      delegate.fastParseOn(buffer, position);

  @override
  SeparatedListParser<T, R> copy() => SeparatedListParser<T, R>(delegate);
}

class WithSeparatorListParser<T, R> extends DelegateParser<T, List<R>> {
  WithSeparatorListParser(super.delegate);

  @override
  Result<List<R>> parseOn(Context context) {
    final result = delegate.parseOn(context);
    if (result is Success) {
      return result.success(
          (result.value as SeparatedList).sequential.toList().cast<R>());
    } else {
      return result.failure(result.message);
    }
  }

  @override
  int fastParseOn(String buffer, int position) =>
      delegate.fastParseOn(buffer, position);

  @override
  WithSeparatorListParser<T, R> copy() =>
      WithSeparatorListParser<T, R>(delegate);
}
