import 'package:template_expressions_4/template_expressions.dart';

/// Syntax that begins and ends with a double hash, `##`, character.
class HashExpressionSyntax extends ExpressionSyntax {
  const HashExpressionSyntax() : super(endToken: '##', startToken: '##');
}
