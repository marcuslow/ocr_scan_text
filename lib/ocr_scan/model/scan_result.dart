import 'dart:math';
import 'dart:ui';

import 'package:ocr_scan_text/ocr_scan/model/recognizer_text/text_element.dart';
import 'package:ocr_scan_text/ocr_scan/model/shape/trapezoid.dart';

/// Each ScanModule should return a list of results. The results are the ScanResults.
/// It contains the list of TextElements constituting the result.
class ScanResult {
  /// Final result, it may be different from the text actually found.
  /// Ex :
  /// - Real text : FR768792929389238923
  /// - Cleaned Text : FR768 7929 2938 9238 923
  final String? _cleanedText;

  /// List of all TextElements forming the result
  List<BrsTextElement> scannedElementList;

  ScanResult({
    String? cleanedText,
    required this.scannedElementList,
  }) : _cleanedText = cleanedText;

  /// Return _cleanedText if it exists, or else real text
  String get cleanedText {
    return _cleanedText ?? text;
  }

  /// Return real text
  String get text {
    String text = '';
    for (var textElement in scannedElementList) {
      if (scannedElementList.first != textElement) {
        text += ' ';
      }
      text += textElement.text;
    }
    return text;
  }

  /// Return the global trapezoid containing the list of TextElements
  Trapezoid get trapezoid {
    if (scannedElementList.isEmpty) {
      return Trapezoid(
        bottomLeftOffset: Offset.zero,
        bottomRightOffset: Offset.zero,
        topLeftOffset: Offset.zero,
        topRightOffset: Offset.zero,
      );
    }

    List<Offset> offsets = [];
    for (BrsTextElement element in scannedElementList) {
      offsets.add(element.trapezoid.topLeftOffset);
      offsets.add(element.trapezoid.bottomRightOffset);
      offsets.add(element.trapezoid.topRightOffset);
      offsets.add(element.trapezoid.bottomLeftOffset);
    }
    return _findTrapezoid(offsets);
  }

  /// Return the global trapezoid containing the list of Offsets
  Trapezoid _findTrapezoid(List<Offset> offsets) {
    double left = double.infinity;
    double top = double.infinity;
    double right = double.negativeInfinity;
    double bottom = double.negativeInfinity;

    for (var offset in offsets) {
      left = min(left, offset.dx);
      top = min(top, offset.dy);
      right = max(right, offset.dx);
      bottom = max(bottom, offset.dy);
    }

    return Trapezoid(
      topLeftOffset: Offset(left, top),
      bottomLeftOffset: Offset(left, bottom),
      topRightOffset: Offset(right, top),
      bottomRightOffset: Offset(right, bottom),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScanResult && runtimeType == other.runtimeType && cleanedText == cleanedText && trapezoid == trapezoid;

  @override
  int get hashCode => cleanedText.hashCode ^ trapezoid.hashCode;
}
