import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:ocr_scan_text/ocr_scan/widget/scan_widget.dart';


extension Nv21Converter on CameraImage {
  Uint8List getNv21Uint8List() {
    var width = this.width;
    var height = this.height;

    var yPlane = planes[0];
    var uPlane = planes[1];
    var vPlane = planes[2];

    var yBuffer = yPlane.bytes;
    var uBuffer = uPlane.bytes;
    var vBuffer = vPlane.bytes;

    var numPixels = (width * height * 1.5).toInt();
    var nv21 = List<int>.filled(numPixels, 0);

    // Full size Y channel and quarter size U+V channels.
    int idY = 0;
    int idUV = width * height;
    var uvWidth = width ~/ 2;
    var uvHeight = height ~/ 2;
    // Copy Y & UV channel.
    // NV21 format is expected to have YYYYVU packaging.
    // The U/V planes are guaranteed to have the same row stride and pixel stride.
    // getRowStride analogue??
    var uvRowStride = uPlane.bytesPerRow;
    // getPixelStride analogue
    var uvPixelStride = uPlane.bytesPerPixel ?? 0;
    var yRowStride = yPlane.bytesPerRow;
    var yPixelStride = yPlane.bytesPerPixel ?? 0;

    for (int y = 0; y < height; ++y) {
      var uvOffset = y * uvRowStride;
      var yOffset = y * yRowStride;

      for (int x = 0; x < width; ++x) {
        nv21[idY++] = yBuffer[yOffset + x * yPixelStride];

        if (y < uvHeight && x < uvWidth) {
          var bufferIndex = uvOffset + (x * uvPixelStride);
          //V channel
          nv21[idUV++] = vBuffer[bufferIndex];
          //V channel
          nv21[idUV++] = uBuffer[bufferIndex];
        }
      }
    }
    return Uint8List.fromList(nv21);
  }
}


/// Widget allowing "live" scanning using the camera
class LiveScanWidget extends ScanWidget {
  const LiveScanWidget({
    super.key,
    required super.scanModules,
    required super.ocrTextResult,
    super.respectRatio = false,
  });

  @override
  LiveScanWidgetState createState() => LiveScanWidgetState();
}

class LiveScanWidgetState extends ScanWidgetState<LiveScanWidget> {
  CameraController? _controller;
  late List<CameraDescription> _cameras;

  @override
  void initState() {
    super.initState();
    _startCamera();
  }

  @override
  void dispose() {
    _stopCamera();
    super.dispose();
  }

  /// Display the camera widget as soon as it is ready
  @override
  Widget build(BuildContext context) {
    return _controller == null ||
            _controller?.value == null ||
            _controller?.value.isInitialized == false
        ? Container()
        : _cameraWidget();
  }

  /// Camera widget showing preview
  Widget _cameraWidget() {
    final CameraController? cameraController = _controller;
    cameraController?.lockCaptureOrientation(DeviceOrientation.portraitUp);

    final size = MediaQuery.of(context).size;
    if (cameraController == null || !cameraController.value.isInitialized) {
      return Container(
        width: size.width,
        height: size.height,
        color: Colors.black,
      );
    } else {
      CustomPaint? customPaint = this.customPaint;

      /// Preview
      CameraPreview preview = CameraPreview(
        cameraController,
        child: customPaint == null
            ? null
            : LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  return customPaint;
                },
              ),
      );

      return widget.respectRatio
          ? preview
          : Stack(
              children: [
                SizedBox(
                  width: size.width,
                  height: size.height,
                  child: AspectRatio(
                    aspectRatio: cameraController.value.aspectRatio,
                    child: preview,
                  ),
                ),
              ],
            );
    }
  }

  /// Start image analysis
  Future _processCameraImage(CameraImage image) async {
    if (_controller == null) return;

    final inputImage = cameraImageToInputImage(
      image,
      _cameras[0],
      _controller!.value.deviceOrientation,
    );

    if (inputImage == null) {
      debugPrint('Failed to convert CameraImage to InputImage.');
      return;
    }

    processImage(
      inputImage,
      Size(image.width.toDouble(), image.height.toDouble()),
      null,
    );
  }

  /// Start camera
  Future _startCamera() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return;
    }
    _cameras = await availableCameras();

    final camera = _cameras[0];
    _controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
    );
    _controller?.initialize().then((_) {
      if (!mounted) {
        return;
      }
      _controller?.startImageStream(_processCameraImage);
      setState(() {});
    }).catchError((Object e) {
      if (e is CameraException) {
        switch (e.code) {
          case 'CameraAccessDenied':
            break;
          default:
            break;
        }
      }
    });
  }

  /// Stop camera
  Future _stopCamera() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return;
    }
    await _controller?.stopImageStream();
    await _controller?.dispose();
    _controller = null;
  }
}

const _orientations = {
  DeviceOrientation.portraitUp: 0,
  DeviceOrientation.landscapeLeft: 90,
  DeviceOrientation.portraitDown: 180,
  DeviceOrientation.landscapeRight: 270,
};

InputImage? cameraImageToInputImage(
  CameraImage image,
  CameraDescription camera,
  DeviceOrientation deviceOrientation,
) {
  final format = InputImageFormatValue.fromRawValue(image.format.raw);
  if (format == null) {
    return null;
  }
  final plane = image.planes.firstOrNull;
  if (plane == null) {
    return null;
  }

  final sensorOrientation = camera.sensorOrientation;

  final InputImageRotation? rotation;
  if (Platform.isIOS) {
    rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
  } else if (Platform.isAndroid) {
    var rotationCompensation = _orientations[deviceOrientation];
    if (rotationCompensation == null) {
      return null;
    }
    if (camera.lensDirection == CameraLensDirection.front) {
      // front-facing
      rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
    } else {
      // back-facing
      rotationCompensation =
          (sensorOrientation - rotationCompensation + 360) % 360;
    }
    rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
  } else {
    rotation = null;
  }

  if (rotation == null) {
    return null;
  }

  final Uint8List bytes;
  if (Platform.isAndroid) {
    bytes = image.getNv21Uint8List();
  } else {
    final allBytes = WriteBuffer();
    for (final plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    bytes = allBytes.done().buffer.asUint8List();
  }

  return InputImage.fromBytes(
    bytes: bytes,
    metadata: InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation, // used only in Android
      format: Platform.isAndroid
          ? InputImageFormat.nv21
          : format, // Hardcode format for Android
      bytesPerRow: plane.bytesPerRow, // used only in iOS
    ),
  );
}
