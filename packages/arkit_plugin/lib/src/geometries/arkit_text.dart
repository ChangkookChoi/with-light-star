import 'package:arkit_plugin/src/geometries/arkit_geometry.dart';
import 'package:arkit_plugin/src/geometries/material/arkit_material.dart';
import 'package:arkit_plugin/src/utils/json_converters.dart';
import 'package:flutter/widgets.dart';
import 'package:json_annotation/json_annotation.dart';

part 'arkit_text.g.dart';

/// Represents a block of text that has been extruded.
@JsonSerializable()
class ARKitText extends ARKitGeometry {
  ARKitText({
    required String text,
    required this.extrusionDepth,
    this.chamferRadius = 0.0,
    this.fontName,
    super.materials,
  }) : text = ValueNotifier(text);

  /// The text to be represented.
  @StringValueNotifierConverter()
  final ValueNotifier<String> text;

  /// The extrusion depth.
  /// If the value is 0, we get a mono-sided, 2D version of the text.
  final double extrusionDepth;

  /// The chamfer radius.
  final double chamferRadius;

  /// The font name.
  final String? fontName;

  static ARKitText fromJson(Map<String, dynamic> json) =>
      _$ARKitTextFromJson(json);

  @override
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'dartType': 'ARKitText',
      'text': text.value,
      'extrusionDepth': extrusionDepth,
      'chamferRadius': chamferRadius,
      'fontName': fontName,
    };

    // [수정 핵심] materials.value를 통해 접근해야 합니다!
    if (materials.value != null) {
      json['materials'] = materials.value!.map((m) => m.toJson()).toList();
    }

    return json..removeWhere((k, v) => v == null);
  }
}
