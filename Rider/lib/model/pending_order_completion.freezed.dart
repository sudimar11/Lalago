// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'pending_order_completion.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

PendingOrderCompletion _$PendingOrderCompletionFromJson(
    Map<String, dynamic> json) {
  return _PendingOrderCompletion.fromJson(json);
}

/// @nodoc
mixin _$PendingOrderCompletion {
  String get orderId => throw _privateConstructorUsedError;
  double get earning => throw _privateConstructorUsedError;
  double get totalCommission => throw _privateConstructorUsedError;
  double get totalPayment => throw _privateConstructorUsedError;
  double get incentive => throw _privateConstructorUsedError;
  double get deliveryCharge => throw _privateConstructorUsedError;
  double get tipAmount => throw _privateConstructorUsedError;
  double get platformCommission => throw _privateConstructorUsedError;
  double get restaurantCommission => throw _privateConstructorUsedError;
  double get totalEarning => throw _privateConstructorUsedError;
  int get totalItemCount => throw _privateConstructorUsedError;
  double get itemsTotal => throw _privateConstructorUsedError;
  Map<String, dynamic> get orderData => throw _privateConstructorUsedError;
  DateTime get createdAt => throw _privateConstructorUsedError;
  int get retryCount => throw _privateConstructorUsedError;
  bool get isProcessing => throw _privateConstructorUsedError;

  /// Serializes this PendingOrderCompletion to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of PendingOrderCompletion
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $PendingOrderCompletionCopyWith<PendingOrderCompletion> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $PendingOrderCompletionCopyWith<$Res> {
  factory $PendingOrderCompletionCopyWith(PendingOrderCompletion value,
          $Res Function(PendingOrderCompletion) then) =
      _$PendingOrderCompletionCopyWithImpl<$Res, PendingOrderCompletion>;
  @useResult
  $Res call(
      {String orderId,
      double earning,
      double totalCommission,
      double totalPayment,
      double incentive,
      double deliveryCharge,
      double tipAmount,
      double platformCommission,
      double restaurantCommission,
      double totalEarning,
      int totalItemCount,
      double itemsTotal,
      Map<String, dynamic> orderData,
      DateTime createdAt,
      int retryCount,
      bool isProcessing});
}

/// @nodoc
class _$PendingOrderCompletionCopyWithImpl<$Res,
        $Val extends PendingOrderCompletion>
    implements $PendingOrderCompletionCopyWith<$Res> {
  _$PendingOrderCompletionCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of PendingOrderCompletion
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? orderId = null,
    Object? earning = null,
    Object? totalCommission = null,
    Object? totalPayment = null,
    Object? incentive = null,
    Object? deliveryCharge = null,
    Object? tipAmount = null,
    Object? platformCommission = null,
    Object? restaurantCommission = null,
    Object? totalEarning = null,
    Object? totalItemCount = null,
    Object? itemsTotal = null,
    Object? orderData = null,
    Object? createdAt = null,
    Object? retryCount = null,
    Object? isProcessing = null,
  }) {
    return _then(_value.copyWith(
      orderId: null == orderId
          ? _value.orderId
          : orderId // ignore: cast_nullable_to_non_nullable
              as String,
      earning: null == earning
          ? _value.earning
          : earning // ignore: cast_nullable_to_non_nullable
              as double,
      totalCommission: null == totalCommission
          ? _value.totalCommission
          : totalCommission // ignore: cast_nullable_to_non_nullable
              as double,
      totalPayment: null == totalPayment
          ? _value.totalPayment
          : totalPayment // ignore: cast_nullable_to_non_nullable
              as double,
      incentive: null == incentive
          ? _value.incentive
          : incentive // ignore: cast_nullable_to_non_nullable
              as double,
      deliveryCharge: null == deliveryCharge
          ? _value.deliveryCharge
          : deliveryCharge // ignore: cast_nullable_to_non_nullable
              as double,
      tipAmount: null == tipAmount
          ? _value.tipAmount
          : tipAmount // ignore: cast_nullable_to_non_nullable
              as double,
      platformCommission: null == platformCommission
          ? _value.platformCommission
          : platformCommission // ignore: cast_nullable_to_non_nullable
              as double,
      restaurantCommission: null == restaurantCommission
          ? _value.restaurantCommission
          : restaurantCommission // ignore: cast_nullable_to_non_nullable
              as double,
      totalEarning: null == totalEarning
          ? _value.totalEarning
          : totalEarning // ignore: cast_nullable_to_non_nullable
              as double,
      totalItemCount: null == totalItemCount
          ? _value.totalItemCount
          : totalItemCount // ignore: cast_nullable_to_non_nullable
              as int,
      itemsTotal: null == itemsTotal
          ? _value.itemsTotal
          : itemsTotal // ignore: cast_nullable_to_non_nullable
              as double,
      orderData: null == orderData
          ? _value.orderData
          : orderData // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      retryCount: null == retryCount
          ? _value.retryCount
          : retryCount // ignore: cast_nullable_to_non_nullable
              as int,
      isProcessing: null == isProcessing
          ? _value.isProcessing
          : isProcessing // ignore: cast_nullable_to_non_nullable
              as bool,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$PendingOrderCompletionImplCopyWith<$Res>
    implements $PendingOrderCompletionCopyWith<$Res> {
  factory _$$PendingOrderCompletionImplCopyWith(
          _$PendingOrderCompletionImpl value,
          $Res Function(_$PendingOrderCompletionImpl) then) =
      __$$PendingOrderCompletionImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String orderId,
      double earning,
      double totalCommission,
      double totalPayment,
      double incentive,
      double deliveryCharge,
      double tipAmount,
      double platformCommission,
      double restaurantCommission,
      double totalEarning,
      int totalItemCount,
      double itemsTotal,
      Map<String, dynamic> orderData,
      DateTime createdAt,
      int retryCount,
      bool isProcessing});
}

/// @nodoc
class __$$PendingOrderCompletionImplCopyWithImpl<$Res>
    extends _$PendingOrderCompletionCopyWithImpl<$Res,
        _$PendingOrderCompletionImpl>
    implements _$$PendingOrderCompletionImplCopyWith<$Res> {
  __$$PendingOrderCompletionImplCopyWithImpl(
      _$PendingOrderCompletionImpl _value,
      $Res Function(_$PendingOrderCompletionImpl) _then)
      : super(_value, _then);

  /// Create a copy of PendingOrderCompletion
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? orderId = null,
    Object? earning = null,
    Object? totalCommission = null,
    Object? totalPayment = null,
    Object? incentive = null,
    Object? deliveryCharge = null,
    Object? tipAmount = null,
    Object? platformCommission = null,
    Object? restaurantCommission = null,
    Object? totalEarning = null,
    Object? totalItemCount = null,
    Object? itemsTotal = null,
    Object? orderData = null,
    Object? createdAt = null,
    Object? retryCount = null,
    Object? isProcessing = null,
  }) {
    return _then(_$PendingOrderCompletionImpl(
      orderId: null == orderId
          ? _value.orderId
          : orderId // ignore: cast_nullable_to_non_nullable
              as String,
      earning: null == earning
          ? _value.earning
          : earning // ignore: cast_nullable_to_non_nullable
              as double,
      totalCommission: null == totalCommission
          ? _value.totalCommission
          : totalCommission // ignore: cast_nullable_to_non_nullable
              as double,
      totalPayment: null == totalPayment
          ? _value.totalPayment
          : totalPayment // ignore: cast_nullable_to_non_nullable
              as double,
      incentive: null == incentive
          ? _value.incentive
          : incentive // ignore: cast_nullable_to_non_nullable
              as double,
      deliveryCharge: null == deliveryCharge
          ? _value.deliveryCharge
          : deliveryCharge // ignore: cast_nullable_to_non_nullable
              as double,
      tipAmount: null == tipAmount
          ? _value.tipAmount
          : tipAmount // ignore: cast_nullable_to_non_nullable
              as double,
      platformCommission: null == platformCommission
          ? _value.platformCommission
          : platformCommission // ignore: cast_nullable_to_non_nullable
              as double,
      restaurantCommission: null == restaurantCommission
          ? _value.restaurantCommission
          : restaurantCommission // ignore: cast_nullable_to_non_nullable
              as double,
      totalEarning: null == totalEarning
          ? _value.totalEarning
          : totalEarning // ignore: cast_nullable_to_non_nullable
              as double,
      totalItemCount: null == totalItemCount
          ? _value.totalItemCount
          : totalItemCount // ignore: cast_nullable_to_non_nullable
              as int,
      itemsTotal: null == itemsTotal
          ? _value.itemsTotal
          : itemsTotal // ignore: cast_nullable_to_non_nullable
              as double,
      orderData: null == orderData
          ? _value._orderData
          : orderData // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      retryCount: null == retryCount
          ? _value.retryCount
          : retryCount // ignore: cast_nullable_to_non_nullable
              as int,
      isProcessing: null == isProcessing
          ? _value.isProcessing
          : isProcessing // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$PendingOrderCompletionImpl implements _PendingOrderCompletion {
  const _$PendingOrderCompletionImpl(
      {required this.orderId,
      required this.earning,
      required this.totalCommission,
      required this.totalPayment,
      required this.incentive,
      required this.deliveryCharge,
      required this.tipAmount,
      required this.platformCommission,
      required this.restaurantCommission,
      required this.totalEarning,
      required this.totalItemCount,
      required this.itemsTotal,
      required final Map<String, dynamic> orderData,
      required this.createdAt,
      this.retryCount = 0,
      this.isProcessing = false})
      : _orderData = orderData;

  factory _$PendingOrderCompletionImpl.fromJson(Map<String, dynamic> json) =>
      _$$PendingOrderCompletionImplFromJson(json);

  @override
  final String orderId;
  @override
  final double earning;
  @override
  final double totalCommission;
  @override
  final double totalPayment;
  @override
  final double incentive;
  @override
  final double deliveryCharge;
  @override
  final double tipAmount;
  @override
  final double platformCommission;
  @override
  final double restaurantCommission;
  @override
  final double totalEarning;
  @override
  final int totalItemCount;
  @override
  final double itemsTotal;
  final Map<String, dynamic> _orderData;
  @override
  Map<String, dynamic> get orderData {
    if (_orderData is EqualUnmodifiableMapView) return _orderData;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_orderData);
  }

  @override
  final DateTime createdAt;
  @override
  @JsonKey()
  final int retryCount;
  @override
  @JsonKey()
  final bool isProcessing;

  @override
  String toString() {
    return 'PendingOrderCompletion(orderId: $orderId, earning: $earning, totalCommission: $totalCommission, totalPayment: $totalPayment, incentive: $incentive, deliveryCharge: $deliveryCharge, tipAmount: $tipAmount, platformCommission: $platformCommission, restaurantCommission: $restaurantCommission, totalEarning: $totalEarning, totalItemCount: $totalItemCount, itemsTotal: $itemsTotal, orderData: $orderData, createdAt: $createdAt, retryCount: $retryCount, isProcessing: $isProcessing)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PendingOrderCompletionImpl &&
            (identical(other.orderId, orderId) || other.orderId == orderId) &&
            (identical(other.earning, earning) || other.earning == earning) &&
            (identical(other.totalCommission, totalCommission) ||
                other.totalCommission == totalCommission) &&
            (identical(other.totalPayment, totalPayment) ||
                other.totalPayment == totalPayment) &&
            (identical(other.incentive, incentive) ||
                other.incentive == incentive) &&
            (identical(other.deliveryCharge, deliveryCharge) ||
                other.deliveryCharge == deliveryCharge) &&
            (identical(other.tipAmount, tipAmount) ||
                other.tipAmount == tipAmount) &&
            (identical(other.platformCommission, platformCommission) ||
                other.platformCommission == platformCommission) &&
            (identical(other.restaurantCommission, restaurantCommission) ||
                other.restaurantCommission == restaurantCommission) &&
            (identical(other.totalEarning, totalEarning) ||
                other.totalEarning == totalEarning) &&
            (identical(other.totalItemCount, totalItemCount) ||
                other.totalItemCount == totalItemCount) &&
            (identical(other.itemsTotal, itemsTotal) ||
                other.itemsTotal == itemsTotal) &&
            const DeepCollectionEquality()
                .equals(other._orderData, _orderData) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt) &&
            (identical(other.retryCount, retryCount) ||
                other.retryCount == retryCount) &&
            (identical(other.isProcessing, isProcessing) ||
                other.isProcessing == isProcessing));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      orderId,
      earning,
      totalCommission,
      totalPayment,
      incentive,
      deliveryCharge,
      tipAmount,
      platformCommission,
      restaurantCommission,
      totalEarning,
      totalItemCount,
      itemsTotal,
      const DeepCollectionEquality().hash(_orderData),
      createdAt,
      retryCount,
      isProcessing);

  /// Create a copy of PendingOrderCompletion
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$PendingOrderCompletionImplCopyWith<_$PendingOrderCompletionImpl>
      get copyWith => __$$PendingOrderCompletionImplCopyWithImpl<
          _$PendingOrderCompletionImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$PendingOrderCompletionImplToJson(
      this,
    );
  }
}

abstract class _PendingOrderCompletion implements PendingOrderCompletion {
  const factory _PendingOrderCompletion(
      {required final String orderId,
      required final double earning,
      required final double totalCommission,
      required final double totalPayment,
      required final double incentive,
      required final double deliveryCharge,
      required final double tipAmount,
      required final double platformCommission,
      required final double restaurantCommission,
      required final double totalEarning,
      required final int totalItemCount,
      required final double itemsTotal,
      required final Map<String, dynamic> orderData,
      required final DateTime createdAt,
      final int retryCount,
      final bool isProcessing}) = _$PendingOrderCompletionImpl;

  factory _PendingOrderCompletion.fromJson(Map<String, dynamic> json) =
      _$PendingOrderCompletionImpl.fromJson;

  @override
  String get orderId;
  @override
  double get earning;
  @override
  double get totalCommission;
  @override
  double get totalPayment;
  @override
  double get incentive;
  @override
  double get deliveryCharge;
  @override
  double get tipAmount;
  @override
  double get platformCommission;
  @override
  double get restaurantCommission;
  @override
  double get totalEarning;
  @override
  int get totalItemCount;
  @override
  double get itemsTotal;
  @override
  Map<String, dynamic> get orderData;
  @override
  DateTime get createdAt;
  @override
  int get retryCount;
  @override
  bool get isProcessing;

  /// Create a copy of PendingOrderCompletion
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$PendingOrderCompletionImplCopyWith<_$PendingOrderCompletionImpl>
      get copyWith => throw _privateConstructorUsedError;
}
