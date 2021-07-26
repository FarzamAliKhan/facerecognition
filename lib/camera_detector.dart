// Google ML Vision Face Detection and recognition app
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart=2.9

import 'dart:convert';
import 'dart:io';
import 'package:quiver/collection.dart';
import 'package:image/image.dart' as imglib;
import 'package:camera/camera.dart';
import 'package:google_ml_vision/google_ml_vision.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart' as tfl;

import 'detector_painters.dart';
import 'detector_utils.dart';

enum Choice {view, delete, landmarkFace, normalFace }
bool _landMarkFace = false;

class CameraDetector extends StatefulWidget {
  const CameraDetector({Key key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _CameraDetectorState();
}

class _CameraDetectorState extends State<CameraDetector> {

  File jsonFile;
  dynamic data = {};
  double threshold = 1.0;
  Directory _savedFacesDir;
  List _predictedData;
  tfl.Interpreter interpreter;
  final TextEditingController _name = new TextEditingController();
  dynamic _scanResults;
  CameraController _camera;
  Detector _currentDetector = Detector.face;
  bool _isDetecting = false;
  CameraLensDirection _direction = CameraLensDirection.front;
  bool _faceFound = false;
  bool _camPos = false;

  final FaceDetector _faceDetector = GoogleVision.instance
      .faceDetector(FaceDetectorOptions(
        enableLandmarks: true,
        enableContours: true,
        enableTracking: true,
        enableClassification: false,
        mode: FaceDetectorMode.accurate,
  ));

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future loadModel() async {
    //tfl.Delegate delegate;
    try {
      /*
      if (Platform.isAndroid) {
        delegate = tfl.GpuDelegateV2(
        options: tfl.GpuDelegateOptionsV2(
          false,
          tfl.TfLiteGpuInferenceUsage.fastSingleAnswer,
          tfl.TfLiteGpuInferencePriority.minLatency,
          tfl.TfLiteGpuInferencePriority.auto,
          tfl.TfLiteGpuInferencePriority.auto,
        ));
      } else if (Platform.isIOS) {
        delegate = tfl.GpuDelegate(
          options: tfl.GpuDelegateOptions(
              true,
              tfl.TFLGpuDelegateWaitType.active
          ),
        );
      }
      var interpreterOptions = tfl.InterpreterOptions()..addDelegate(delegate);
      */
      this.interpreter = await tfl.Interpreter.fromAsset('mobilefacenet.tflite');
      //this.interpreter = await tfl.Interpreter.fromAsset('mobilefacenet.tflite',
      //    options: interpreterOptions);
      print('**********\n Loaded successfully model mobilefacenet.tflite \n*********\n');
    } catch (e) {
      print('Failed to load model.');
      print(e);
    }
  }

  Future<void> _initializeCamera() async {
    await loadModel();
    final CameraDescription description =
    await ScannerUtils.getCamera(_direction);

    if (_direction == CameraLensDirection.front) {
      _camPos = false;
    } else {
      _camPos = true;
    }

    _camera = CameraController(
      description,
      defaultTargetPlatform == TargetPlatform.iOS
          ? ResolutionPreset.low
          : ResolutionPreset.low,
      enableAudio: false,
    );
    await _camera.initialize();
    //Load file from assets directory to store the detected faces
    _savedFacesDir = await getApplicationDocumentsDirectory();
    String _fullPathSavedFaces = _savedFacesDir.path + '/savedFaces.json';
    jsonFile = new File(_fullPathSavedFaces);
    if (jsonFile.existsSync()) {
      data = json.decode(jsonFile.readAsStringSync());
      print('Saved faced from memory: ' + data.toString());
    }
    await _camera.startImageStream((CameraImage image) {
      if (_isDetecting) return;

      _isDetecting = true;

      String res;
      dynamic finalResults = Multimap<String, Face>();

      ScannerUtils.detect(
        image: image,
        detectInImage: _getDetectionMethod(),
        imageRotation: description.sensorOrientation,
      ).then(
            (dynamic results) {
          if (_currentDetector == null) return;
          if (results.length == 0) {
            _faceFound = false;
          } else {
            _faceFound = true;
          }
          // Start storing faces and use Tensorflow to recognize
          Face _face;
          imglib.Image convertedImage =
          _convertCameraImage(image, _direction);
          for (_face in results) {
            double x, y, w, h;
            x = (_face.boundingBox.left - 10);
            y = (_face.boundingBox.top - 10);
            w = (_face.boundingBox.width + 10);
            h = (_face.boundingBox.height + 10);
            imglib.Image croppedImage = imglib.copyCrop(
                convertedImage, x.round(), y.round(), w.round(), h.round());
            croppedImage = imglib.copyResizeCropSquare(croppedImage, 112);
            // int startTime = new DateTime.now().millisecondsSinceEpoch;
            res = _recognizeFace(croppedImage);
            // int endTime = new DateTime.now().millisecondsSinceEpoch;
            // print("Inference took ${endTime - startTime}ms");
            finalResults.add(res, _face);
          }
          setState(() {
            _scanResults = finalResults;
          });
        },
      ).whenComplete(() => Future.delayed(
          Duration(
            milliseconds: 100,
          ),
              () => {_isDetecting = false}));
    });
  }

  Future<dynamic> Function(GoogleVisionImage image) _getDetectionMethod() {
    return _faceDetector.processImage;
  }

  Widget _buildResults() {
    const Text noResultsText = Text('No results!');

    if (_scanResults == null ||
        _camera == null ||
        !_camera.value.isInitialized) {
      return noResultsText;
    }

    CustomPainter painter;

    final Size imageSize = Size(
      _camera.value.previewSize.height,
      _camera.value.previewSize.width,
    );

    assert(_currentDetector == Detector.face);

    if (_landMarkFace) painter = FaceDetectorLandmarkPainter(imageSize, _scanResults, _camPos);
    else painter = FaceDetectorNormalPainter(imageSize, _scanResults, _camPos);

    return CustomPaint(
      painter: painter,
    );
  }

  Widget _buildImage() {
    return Container(
      constraints: const BoxConstraints.expand(),
      child: _camera == null
          ? const Center(
        child: Text(
          'Initializing Camera...',
          style: TextStyle(
            color: Colors.lime,
            fontSize: 30,
          ),
        ),
      )
          : Stack(
        fit: StackFit.expand,
        children: <Widget>[
          CameraPreview(_camera),
          _buildResults(),
        ],
      ),
    );
  }

  Future<void> _toggleCameraDirection() async {

    if (_direction == CameraLensDirection.back) {
      _direction = CameraLensDirection.front;
      _camPos = false;
    } else {
      _direction = CameraLensDirection.back;
      _camPos = true;
    }

    await _camera.stopImageStream();
    await _camera.dispose();

    setState(() {
      _camera = null;
    });

    await _initializeCamera();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Realtime Face Recognition'),
        actions: <Widget>[
          PopupMenuButton<Choice>(
            onSelected: (Choice result) {
              if (result == Choice.delete) _resetFile();
              else if (result == Choice.view) _viewLabels();
              else if (result == Choice.landmarkFace) _landMarkFace = true;
              else if (result == Choice.normalFace) _landMarkFace = false;
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<Choice>>[
              const PopupMenuItem<Choice>(
                value: Choice.view,
                child: Text('View Saved Faces'),
              ),
              const PopupMenuItem<Choice>(
                value: Choice.delete,
                child: Text('Remove All Faces'),
              ),
              const PopupMenuItem<Choice>(
                value: Choice.landmarkFace,
                child: Text('Landmark Faces'),
              ),
              const PopupMenuItem<Choice>(
                value: Choice.normalFace,
                child: Text('Normal Faces'),
              ),
            ],
          ),
        ],
      ),
      body: _buildImage(),
      floatingActionButton:
      Column(mainAxisAlignment: MainAxisAlignment.end, children: [
        FloatingActionButton(
          backgroundColor: (_faceFound) ? Colors.blue : Colors.blueGrey,
          child: Icon(Icons.add),
          onPressed: () {
            if (_faceFound) _addLabel();
          },
        ),
        SizedBox(
          height: 10,
        ),
        FloatingActionButton(
          onPressed: _toggleCameraDirection,
          child: _direction == CameraLensDirection.back
              ? const Icon(Icons.camera_front)
              : const Icon(Icons.camera_rear),
        ),
      ]),
    );
  }

  String _recognizeFace(imglib.Image img) {
    List input = ScannerUtils.imageToByteListFloat32(img, 112, 128, 128);
    input = input.reshape([1, 112, 112, 3]);
    List output = List.generate(1, (index) => List.filled(192, 0));

    interpreter.run(input, output);
    output = output.reshape([192]);
    _predictedData = List.from(output);
    return _compareExistSavedFaces(_predictedData).toUpperCase();
  }

  String _compareExistSavedFaces(List currEmb) {
    if (data.length == 0) return "No Face saved";
    double minDist = 999;
    double currDist = 0.0;
    String predRes = "NOT RECOGNIZED";
    for (String label in data.keys) {
      currDist = ScannerUtils.euclideanDistance(data[label], currEmb);
      if (currDist <= threshold && currDist < minDist) {
        minDist = currDist;
        predRes = label;
      }
    }
    print(minDist.toString() + " " + predRes);
    return predRes;
  }

  void _resetFile() {
    data = {};
    jsonFile.deleteSync();
  }

  void _viewLabels() {
    setState(() {
      _camera = null;
    });
    String name;
    var alert = new AlertDialog(
      title: new Text("Saved Faces"),
      content: Container (
        height: 100.0,
        width: 300.0,
        child: new ListView.builder(
            padding: new EdgeInsets.all(2),
            itemCount: data.length,
            itemBuilder: (BuildContext context, int index) {
              name = data.keys.elementAt(index);
              return new Column(
                children: <Widget>[
                  new ListTile(
                    title: new Text(
                      name,
                      style: new TextStyle(
                        fontSize: 14,
                        color: Colors.grey[400],
                      ),
                    ),
                  ),
                  new Padding(
                    padding: EdgeInsets.all(2),
                  ),
                  new Divider(),
                ],
              );
            }),
      ),
      actions: <Widget>[
        new TextButton(
          child: Text("OK"),
          onPressed: () {
            _initializeCamera();
            Navigator.pop(context);
          },
        )
      ],
    );
    showDialog(
        context: context,
        builder: (context) {
          return alert;
        });
  }

  void _addLabel() {
    setState(() {
      _camera = null;
    });
    print("Adding new face");
    var alert = new AlertDialog(
      title: new Text("Add Face"),
      content: new Row(
        children: <Widget>[
          new Expanded(
            child: new TextField(
              controller: _name,
              autofocus: true,
              decoration: new InputDecoration(
                  labelText: "Name", icon: new Icon(Icons.face)),
            ),
          )
        ],
      ),
      actions: <Widget>[
        new TextButton(
            child: Text("Save"),
            onPressed: () {
              _handleWriteJSON(_name.text.toUpperCase());
              _name.clear();
              Navigator.pop(context);
            }),
        new TextButton(
          child: Text("Cancel"),
          onPressed: () {
            _initializeCamera();
            Navigator.pop(context);
          },
        )
      ],
    );
    showDialog(
        context: context,
        builder: (context) {
          return alert;
        });
  }

  void _handleWriteJSON(String text) {
    data[text] = _predictedData;
    jsonFile.writeAsStringSync(json.encode(data));
    _initializeCamera();
  }

  static imglib.Image _convertCameraImage(CameraImage image, CameraLensDirection _dir) {
    try {
      imglib.Image img;
      if (image.format.group == ImageFormatGroup.yuv420) {
        img = _convertYUV420(image, _dir);
      } else if (image.format.group == ImageFormatGroup.bgra8888) {
        img = _convertBGRA8888(image, _dir);
      }

      return img;
    } catch (e) {
      print(">>>>>>>>>>>> ERROR:" + e.toString());
    }
    return null;
  }

  static imglib.Image _convertBGRA8888(CameraImage image, CameraLensDirection _dir) {
    var img = imglib.Image.fromBytes(
      image.width,
      image.height,
      image.planes[0].bytes,
      format: imglib.Format.bgra,
    );

    var img1 = (_dir == CameraLensDirection.front)
        ? imglib.copyRotate(img, -90)
        : imglib.copyRotate(img, 90);
    return img1;

  }

  static imglib.Image _convertYUV420(CameraImage image, CameraLensDirection _dir) {
    int width = image.width;
    int height = image.height;
    var img = imglib.Image(width, height);
    const int hexFF = 0xFF000000;
    final int uvyButtonStride = image.planes[1].bytesPerRow;
    final int uvPixelStride = image.planes[1].bytesPerPixel;
    for (int x = 0; x < width; x++) {
      for (int y = 0; y < height; y++) {
        final int uvIndex =
            uvPixelStride * (x / 2).floor() + uvyButtonStride * (y / 2).floor();
        final int index = y * width + x;
        final yp = image.planes[0].bytes[index];
        final up = image.planes[1].bytes[uvIndex];
        final vp = image.planes[2].bytes[uvIndex];
        int r = (yp + vp * 1436 / 1024 - 179).round().clamp(0, 255);
        int g = (yp - up * 46549 / 131072 + 44 - vp * 93604 / 131072 + 91)
            .round()
            .clamp(0, 255);
        int b = (yp + up * 1814 / 1024 - 227).round().clamp(0, 255);
        img.data[index] = hexFF | (b << 16) | (g << 8) | r;
      }
    }
    var img1 = (_dir == CameraLensDirection.front)
        ? imglib.copyRotate(img, -90)
        : imglib.copyRotate(img, 90);
    return img1;

  }

  @override
  void dispose() {
    _camera.dispose().then((_) {
      _faceDetector.close();
    });

    _currentDetector = null;
    super.dispose();
  }
}