import 'dart:async';

import 'package:rxdart/rxdart.dart';
import 'package:template_expressions_4/expressions.dart';

Stream _asStream(v) => v is Stream
    ? v
    : v is Future
    ? Stream.fromFuture(v)
    : Stream.value(v);
Literal _asLiteral(v) {
  if (v is Map) {
    return Literal(v.map((k, v) => MapEntry(_asLiteral(k), _asLiteral(v))));
  }
  if (v is List) {
    return Literal(v.map((v) => _asLiteral(v)).toList());
  }
  return Literal(v);
}

class AsyncExpressionEvaluator extends ExpressionEvaluator {
  const AsyncExpressionEvaluator({super.memberAccessors});

  final ExpressionEvaluator baseEvaluator = const ExpressionEvaluator();

  @override
  Stream eval(
    Expression expression,
    Map<String, dynamic> context, {
    void Function(String name, dynamic value)? onValueAssigned,
  }) {
    return _asStream(
      super.eval(expression, context, onValueAssigned: onValueAssigned),
    );
  }

  @override
  Stream evalBinaryExpression(
    BinaryExpression expression,
    Map<String, dynamic> context, {
    void Function(String name, dynamic value)? onValueAssigned,
  }) {
    final left = eval(expression.left, context);
    final right = eval(expression.right, context);

    return CombineLatestStream.combine2(left, right, (a, b) {
      return baseEvaluator.evalBinaryExpression(
        BinaryExpression(
          expression.operator,
          expression.operator == '=' ? expression.left : _asLiteral(a),
          _asLiteral(b),
        ),
        context,
        onValueAssigned: onValueAssigned,
      );
    });
  }

  @override
  Stream evalUnaryExpression(
    UnaryExpression expression,
    Map<String, dynamic> context,
  ) {
    final argument = eval(expression.argument, context);

    return argument.map((v) {
      return baseEvaluator.evalUnaryExpression(
        UnaryExpression(
          expression.operator,
          _asLiteral(v),
          prefix: expression.prefix,
        ),
        context,
      );
    });
  }

  @override
  dynamic evalCallExpression(
    CallExpression expression,
    Map<String, dynamic> context,
  ) {
    final callee = eval(expression.callee, context);
    final arguments = expression.arguments
        .map((e) => eval(e, context))
        .toList();
    return CombineLatestStream([callee, ...arguments], (l) {
      return baseEvaluator.evalCallExpression(
        CallExpression(_asLiteral(l.first), [
          for (var v in l.skip(1)) _asLiteral(v),
        ]),
        context,
      );
    }).switchMap((v) => _asStream(v));
  }

  @override
  Stream evalConditionalExpression(
    ConditionalExpression expression,
    Map<String, dynamic> context,
  ) {
    final test = eval(expression.test, context);
    final cons = eval(expression.consequent, context);
    final alt = eval(expression.alternate, context);

    return CombineLatestStream.combine3(test, cons, alt, (test, cons, alt) {
      return baseEvaluator.evalConditionalExpression(
        ConditionalExpression(
          _asLiteral(test),
          _asLiteral(cons),
          _asLiteral(alt),
        ),
        context,
      );
    });
  }

  @override
  Stream evalIndexExpression(
    IndexExpression expression,
    Map<String, dynamic> context, {
    bool nullable = false,
  }) {
    final obj = eval(expression.object, context);
    final index = eval(expression.index, context);
    return CombineLatestStream.combine2(obj, index, (obj, index) {
      return baseEvaluator.evalIndexExpression(
        IndexExpression(_asLiteral(obj), _asLiteral(index)),
        context,
      );
    });
  }

  @override
  Stream evalLiteral(Literal literal, Map<String, dynamic> context) {
    return Stream.value(literal.value);
  }

  @override
  Stream evalThis(ThisExpression expression, Map<String, dynamic> context) {
    return _asStream(baseEvaluator.evalThis(expression, context));
  }

  @override
  Stream evalVariable(Variable variable, Map<String, dynamic> context) {
    return _asStream(baseEvaluator.evalVariable(variable, context));
  }

  @override
  Stream evalMemberExpression(
    MemberExpression expression,
    Map<String, dynamic> context, {
    bool nullable = false,
  }) {
    final v = eval(expression.object, context);

    return v.switchMap((v) {
      return _asStream(getMember(v, expression.property.name));
    });
  }
}
