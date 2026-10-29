// SPDX-License-Identifier: GPL-3.0-only
/// A bounded, pure-Dart expression parser and evaluator. No `eval` is used.
library;

import 'dart:math' as math;

sealed class Expression {
  const Expression();

  double evaluate([Map<String, double> variables = const {}]);

  Map<String, Object?> toJson();

  static Expression parse(String source) =>
      _Parser(source, maxLength: 4096, maxNodes: 2048).parse();

  factory Expression.fromJson(Object? value) => _expressionFromJson(value);
}

final class NumberExpression extends Expression {
  const NumberExpression(this.value);
  final double value;

  @override
  double evaluate([Map<String, double> variables = const {}]) => value;

  @override
  Map<String, Object?> toJson() => {'type': 'number', 'value': value};
}

final class VariableExpression extends Expression {
  const VariableExpression(this.name);
  final String name;

  @override
  double evaluate([Map<String, double> variables = const {}]) {
    final value = variables[name];
    if (value == null) throw FormatException('Unknown variable "$name".');
    return value;
  }

  @override
  Map<String, Object?> toJson() => {'type': 'variable', 'name': name};
}

final class UnaryExpression extends Expression {
  const UnaryExpression(this.operator, this.operand);
  final String operator;
  final Expression operand;

  @override
  double evaluate([Map<String, double> variables = const {}]) {
    final value = operand.evaluate(variables);
    return operator == '-' ? -value : value;
  }

  @override
  Map<String, Object?> toJson() => {
    'type': 'unary',
    'operator': operator,
    'operand': operand.toJson(),
  };
}

final class BinaryExpression extends Expression {
  const BinaryExpression(this.operator, this.left, this.right);
  final String operator;
  final Expression left;
  final Expression right;

  @override
  double evaluate([Map<String, double> variables = const {}]) {
    final a = left.evaluate(variables);
    final b = right.evaluate(variables);
    return switch (operator) {
      '+' => a + b,
      '-' => a - b,
      '*' => a * b,
      '/' =>
        b == 0 ? throw const EvaluationException('Division by zero.') : a / b,
      '^' => math.pow(a, b).toDouble(),
      _ => throw FormatException('Unknown operator "$operator".'),
    };
  }

  @override
  Map<String, Object?> toJson() => {
    'type': 'binary',
    'operator': operator,
    'left': left.toJson(),
    'right': right.toJson(),
  };
}

final class CallExpression extends Expression {
  const CallExpression(this.name, this.arguments);
  final String name;
  final List<Expression> arguments;

  @override
  double evaluate([Map<String, double> variables = const {}]) {
    final values = [
      for (final argument in arguments) argument.evaluate(variables),
    ];
    return _call(name, values);
  }

  @override
  Map<String, Object?> toJson() => {
    'type': 'call',
    'name': name,
    'arguments': [for (final argument in arguments) argument.toJson()],
  };
}

class EvaluationException implements Exception {
  const EvaluationException(this.message);
  final String message;
  @override
  String toString() => 'EvaluationException: $message';
}

class ExpressionEvaluator {
  const ExpressionEvaluator({this.maxLength = 4096, this.maxNodes = 2048});

  final int maxLength;
  final int maxNodes;

  double evaluate(String source, {Map<String, double> variables = const {}}) {
    final result = parse(source).evaluate(variables);
    if (!result.isFinite) {
      throw const EvaluationException('Expression result is not finite.');
    }
    return result;
  }

  Expression parse(String source) =>
      _Parser(source, maxLength: maxLength, maxNodes: maxNodes).parse();
}

class _Parser {
  _Parser(this.source, {required this.maxLength, required this.maxNodes});

  final String source;
  final int maxLength;
  final int maxNodes;
  int _index = 0;
  int _depth = 0;
  int _nodes = 0;

  Expression parse() {
    if (source.isEmpty) {
      throw const FormatException('Expression is empty.');
    }
    if (source.length > maxLength) {
      throw const FormatException('Expression exceeds the maximum length.');
    }
    final expression = _sum();
    _skipWhitespace();
    if (_index != source.length) {
      throw FormatException('Unexpected token at position $_index.');
    }
    return expression;
  }

  Expression _sum() {
    var value = _product();
    while (true) {
      _skipWhitespace();
      if (_take('+')) {
        value = _node(BinaryExpression('+', value, _product()));
      } else if (_take('-')) {
        value = _node(BinaryExpression('-', value, _product()));
      } else {
        return value;
      }
    }
  }

  Expression _product() {
    var value = _unary();
    while (true) {
      _skipWhitespace();
      if (_take('*')) {
        value = _node(BinaryExpression('*', value, _unary()));
      } else if (_take('/')) {
        value = _node(BinaryExpression('/', value, _unary()));
      } else {
        return value;
      }
    }
  }

  Expression _unary() {
    _skipWhitespace();
    if (_take('+')) return _nested(() => _node(UnaryExpression('+', _unary())));
    if (_take('-')) return _nested(() => _node(UnaryExpression('-', _unary())));
    return _power();
  }

  Expression _power() {
    final base = _primary();
    _skipWhitespace();
    if (_take('^')) {
      return _node(BinaryExpression('^', base, _nested(_unary)));
    }
    return base;
  }

  Expression _primary() {
    _skipWhitespace();
    if (_take('(')) {
      return _nested(() {
        final value = _sum();
        if (!_take(')')) {
          throw const FormatException('Missing closing parenthesis.');
        }
        return value;
      });
    }
    if (_index >= source.length) {
      throw FormatException('Unexpected end at position $_index.');
    }
    final char = source[_index];
    if (_isDigit(char) ||
        (char == '.' &&
            _index + 1 < source.length &&
            _isDigit(source[_index + 1]))) {
      return _number();
    }
    if (_isIdentifierStart(char)) {
      final identifier = _identifier();
      _skipWhitespace();
      if (_take('(')) {
        final args = <Expression>[];
        _skipWhitespace();
        if (!_take(')')) {
          do {
            args.add(_nested(_sum));
            _skipWhitespace();
            if (_take(')')) break;
            if (!_take(',')) {
              throw FormatException('Expected "," or ")" at $_index.');
            }
          } while (args.length <= 16);
        }
        if (args.length > 16) {
          throw const FormatException('Too many function arguments.');
        }
        _validateCall(identifier, args.length);
        return _node(CallExpression(identifier, args));
      }
      return switch (identifier) {
        'pi' => _node(NumberExpression(math.pi)),
        'e' => _node(NumberExpression(math.e)),
        'tau' => _node(NumberExpression(2 * math.pi)),
        'phi' => _node(NumberExpression((1 + math.sqrt(5)) / 2)),
        _ => _node(VariableExpression(identifier)),
      };
    }
    throw FormatException('Unexpected character "$char" at $_index.');
  }

  Expression _number() {
    final start = _index;
    var hasDigits = false;
    while (_index < source.length && _isDigit(source[_index])) {
      _index++;
      hasDigits = true;
    }
    if (_index < source.length && source[_index] == '.') {
      _index++;
      while (_index < source.length && _isDigit(source[_index])) {
        _index++;
        hasDigits = true;
      }
    }
    if (!hasDigits) {
      throw FormatException('Invalid number at position $start.');
    }
    if (_index < source.length &&
        (source[_index] == 'e' || source[_index] == 'E')) {
      final exponentStart = _index;
      _index++;
      if (_index < source.length &&
          (source[_index] == '+' || source[_index] == '-')) {
        _index++;
      }
      final digitsStart = _index;
      while (_index < source.length && _isDigit(source[_index])) {
        _index++;
      }
      if (_index == digitsStart) {
        throw FormatException('Invalid exponent at position $exponentStart.');
      }
    }
    final value = double.tryParse(source.substring(start, _index));
    if (value == null || !value.isFinite) {
      throw FormatException('Invalid number at position $start.');
    }
    return _node(NumberExpression(value));
  }

  void _validateCall(String name, int arity) {
    final range = _functions[name];
    if (range == null) {
      throw FormatException('Unsupported function "$name".');
    }
    if (arity < range.$1 || arity > range.$2) {
      throw FormatException(
        '"$name" expects ${range.$1 == range.$2 ? range.$1 : '${range.$1}..${range.$2}'} argument(s), got $arity.',
      );
    }
  }

  Expression _node(Expression expression) {
    _nodes++;
    if (_nodes > maxNodes) {
      throw const FormatException('Expression has too many nodes.');
    }
    return expression;
  }

  T _nested<T>(T Function() body) {
    _depth++;
    if (_depth > 64) {
      throw const FormatException('Expression nesting is too deep.');
    }
    try {
      return body();
    } finally {
      _depth--;
    }
  }

  String _identifier() {
    final start = _index;
    _index++;
    while (_index < source.length && _isIdentifierPart(source[_index])) {
      _index++;
    }
    return source.substring(start, _index);
  }

  void _skipWhitespace() {
    while (_index < source.length && source[_index].trim().isEmpty) {
      _index++;
    }
  }

  bool _take(String token) {
    _skipWhitespace();
    if (source.startsWith(token, _index)) {
      _index += token.length;
      return true;
    }
    return false;
  }

  static bool _isDigit(String char) =>
      char.codeUnitAt(0) >= 48 && char.codeUnitAt(0) <= 57;
  static bool _isIdentifierStart(String char) =>
      RegExp(r'[A-Za-z_]').hasMatch(char);
  static bool _isIdentifierPart(String char) =>
      RegExp(r'[A-Za-z0-9_]').hasMatch(char);
}

const Map<String, (int, int)> _functions = {
  'sin': (1, 1),
  'cos': (1, 1),
  'tan': (1, 1),
  'asin': (1, 1),
  'acos': (1, 1),
  'atan': (1, 1),
  'atan2': (2, 2),
  'sinh': (1, 1),
  'cosh': (1, 1),
  'tanh': (1, 1),
  'sqrt': (1, 1),
  'cbrt': (1, 1),
  'abs': (1, 1),
  'ln': (1, 1),
  'log10': (1, 1),
  'exp': (1, 1),
  'floor': (1, 1),
  'ceil': (1, 1),
  'round': (1, 1),
  'sign': (1, 1),
  'min': (1, 16),
  'max': (1, 16),
  'pow': (2, 2),
  'mod': (2, 2),
  'deg': (1, 1),
  'rad': (1, 1),
};

double _call(String name, List<double> x) {
  switch (name) {
    case 'sin':
      return math.sin(x[0]);
    case 'cos':
      return math.cos(x[0]);
    case 'tan':
      return math.tan(x[0]);
    case 'asin':
      if (x[0] < -1 || x[0] > 1) {
        throw const EvaluationException('asin domain error.');
      }
      return math.asin(x[0]);
    case 'acos':
      if (x[0] < -1 || x[0] > 1) {
        throw const EvaluationException('acos domain error.');
      }
      return math.acos(x[0]);
    case 'atan':
      return math.atan(x[0]);
    case 'atan2':
      return math.atan2(x[0], x[1]);
    case 'sinh':
      return _sinh(x[0]);
    case 'cosh':
      return _cosh(x[0]);
    case 'tanh':
      return _sinh(x[0]) / _cosh(x[0]);
    case 'sqrt':
      if (x[0] < 0) {
        throw const EvaluationException('sqrt domain error.');
      }
      return math.sqrt(x[0]);
    case 'cbrt':
      return x[0] < 0
          ? -math.pow(-x[0], 1 / 3).toDouble()
          : math.pow(x[0], 1 / 3).toDouble();
    case 'abs':
      return x[0].abs();
    case 'ln':
      if (x[0] <= 0) {
        throw const EvaluationException('ln domain error.');
      }
      return math.log(x[0]);
    case 'log10':
      if (x[0] <= 0) {
        throw const EvaluationException('log10 domain error.');
      }
      return math.log(x[0]) / math.ln10;
    case 'exp':
      return math.exp(x[0]);
    case 'floor':
      return x[0].floorToDouble();
    case 'ceil':
      return x[0].ceilToDouble();
    case 'round':
      return x[0].roundToDouble();
    case 'sign':
      return x[0].sign;
    case 'min':
      return x.reduce(math.min);
    case 'max':
      return x.reduce(math.max);
    case 'pow':
      return math.pow(x[0], x[1]).toDouble();
    case 'mod':
      if (x[1] == 0) {
        throw const EvaluationException('mod by zero.');
      }
      return x[0] % x[1];
    case 'deg':
      return x[0] * 180 / math.pi;
    case 'rad':
      return x[0] * math.pi / 180;
    default:
      throw FormatException('Unsupported function "$name".');
  }
}

double _sinh(double x) => (math.exp(x) - math.exp(-x)) / 2;
double _cosh(double x) => (math.exp(x) + math.exp(-x)) / 2;

Expression _expressionFromJson(Object? value) {
  if (value is! Map) throw const FormatException('Invalid expression AST.');
  final type = value['type'];
  switch (type) {
    case 'number':
      final number = value['value'];
      if (number is! num || !number.isFinite) {
        throw const FormatException('Invalid number node.');
      }
      return NumberExpression(number.toDouble());
    case 'variable':
      final name = value['name'];
      if (name is! String ||
          !RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(name)) {
        throw const FormatException('Invalid variable node.');
      }
      return VariableExpression(name);
    case 'unary':
      final operator = value['operator'];
      if (operator != '+' && operator != '-') {
        throw const FormatException('Invalid unary operator.');
      }
      return UnaryExpression(
        operator as String,
        _expressionFromJson(value['operand']),
      );
    case 'binary':
      final operator = value['operator'];
      if (!const {'+', '-', '*', '/', '^'}.contains(operator)) {
        throw const FormatException('Invalid binary operator.');
      }
      return BinaryExpression(
        operator as String,
        _expressionFromJson(value['left']),
        _expressionFromJson(value['right']),
      );
    case 'call':
      final name = value['name'];
      final args = value['arguments'];
      if (name is! String || args is! List) {
        throw const FormatException('Invalid call node.');
      }
      _validateNodeCall(name, args.length);
      return CallExpression(name, [
        for (final arg in args) _expressionFromJson(arg),
      ]);
    default:
      throw const FormatException('Unknown expression node.');
  }
}

void _validateNodeCall(String name, int arity) {
  final range = _functions[name];
  if (range == null || arity < range.$1 || arity > range.$2) {
    throw const FormatException('Unsupported function call.');
  }
}
