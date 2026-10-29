// SPDX-License-Identifier: GPL-3.0-only
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:moesketchpad_core/moesketchpad_core.dart';

class MeasurementView {
  const MeasurementView({required this.measurement, this.value, this.error});
  final Measurement measurement;
  final MeasurementValue? value;
  final String? error;
}

class MeasureState {
  const MeasureState({this.items = const <MeasurementView>[]});
  final List<MeasurementView> items;
}

class MeasureBloc extends Cubit<MeasureState> {
  MeasureBloc() : super(const MeasureState());

  void refresh(GeometryDocument document) {
    const engine = MeasurementEngine();
    final items = <MeasurementView>[];
    for (final measurement in document.measurements) {
      try {
        items.add(
          MeasurementView(
            measurement: measurement,
            value: engine.measure(measurement, document),
          ),
        );
      } on FormatException catch (error) {
        items.add(
          MeasurementView(measurement: measurement, error: error.message),
        );
      }
    }
    emit(MeasureState(items: items));
  }

  void clear() => emit(const MeasureState());
}
