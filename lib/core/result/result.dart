/// Result<T, F extends Failure> — eliminates raw exceptions in the domain layer.
///
/// Forces every caller to handle both success and failure paths explicitly.
/// Follows the railway-oriented programming pattern.
library result;

import 'package:vocky_call/core/errors/failures.dart';

/// Represents either a successful value [T] or a [Failure].
sealed class Result<T> {
  const Result();

  /// Creates a successful result.
  factory Result.success(T value) => Success(value);

  /// Creates a failed result.
  factory Result.failure(Failure failure) => FailureResult(failure);

  bool get isSuccess => this is Success<T>;
  bool get isFailure => this is FailureResult<T>;

  T get value => (this as Success<T>).data;
  Failure get failure => (this as FailureResult<T>).err;

  /// Pattern-match on success or failure.
  R fold<R>({
    required R Function(T value) onSuccess,
    required R Function(Failure failure) onFailure,
  }) {
    return switch (this) {
      Success<T> s => onSuccess(s.data),
      FailureResult<T> f => onFailure(f.err),
    };
  }

  /// Map the success value, preserving failure.
  Result<R> map<R>(R Function(T value) transform) {
    return switch (this) {
      Success<T> s => Result.success(transform(s.data)),
      FailureResult<T> f => Result.failure(f.err),
    };
  }
}

final class Success<T> extends Result<T> {
  final T data;
  Success(this.data);
}

final class FailureResult<T> extends Result<T> {
  final Failure err;
  FailureResult(this.err);
}
