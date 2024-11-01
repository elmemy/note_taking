import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:record/record.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'dart:ui' as ui;
void main() {
  runApp(const PdfEditorApp());
}

class PdfEditorApp extends StatelessWidget {
  const PdfEditorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PDF Editor',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: PdfEditorHomePage(),
    );
  }
}

class PdfEditorHomePage extends StatefulWidget {
  @override
  _PdfEditorHomePageState createState() => _PdfEditorHomePageState();
}

class _PdfEditorHomePageState extends State<PdfEditorHomePage> {
  String? _pdfPath;
  int _totalPages = 0;
  int _currentPage = 0;
  bool _isReady = false;
  bool _isEditMode = false;
  AudioPlayer audioPlayer = AudioPlayer();
  Map<int, PageEditData> pageEdits = {};
  Path currentPath = Path();
  Offset? startCirclePosition;
  Offset? startRectanglePosition;
  DrawingMode _drawingMode = DrawingMode.none;
  Offset lastAudioPosition = Offset(50, 50); // Starting position for first audio icon
  Color _freehandColor = Colors.black;
  Color _highlightColor = Colors.yellow.withOpacity(0.5);
  double _freehandStrokeWidth = 2.0;
  double _rectangleStrokeWidth = 2.0;
  double _circleStrokeWidth = 2.0;

  final Record _record = Record();
  String? _filePath;
  final AudioPlayer _audioPlayer = AudioPlayer();

  List<DrawingAction> _undoStack = [];


  Future<void> _pickPdf() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result != null && result.files.single.path != null) {
      setState(() {
        _pdfPath = result.files.single.path!;
        pageEdits.clear();
      });
    }
  }

  void _drawPathOnPdf(PdfPage page, Path path, PdfPen pen) {
    final pathMetrics = path.computeMetrics();
    for (final pathMetric in pathMetrics) {
      final extractedPath = pathMetric.extractPath(0, pathMetric.length);
      final pathPoints = <Offset>[];

      extractedPath.computeMetrics().forEach((metric) {
        pathPoints.add(metric.extractPath(0, metric.length).getBounds().topLeft);
      });

      for (int j = 0; j < pathPoints.length - 1; j++) {
        final startPoint = pathPoints[j];
        final endPoint = pathPoints[j + 1];
        final adjustedStart = Offset(startPoint.dx, page.getClientSize().height - startPoint.dy);
        final adjustedEnd = Offset(endPoint.dx, page.getClientSize().height - endPoint.dy);

        page.graphics.drawLine(pen, adjustedStart, adjustedEnd);
      }
    }
  }


  Future<void> _savePdf() async {
    if (_pdfPath == null) return;

    final pdfDocument = PdfDocument(inputBytes: File(_pdfPath!).readAsBytesSync());

    for (int i = 0; i < pdfDocument.pages.count; i++) {
      final page = pdfDocument.pages[i];
      final currentEdits = pageEdits[i] ?? PageEditData();

      // Draw text items
      for (var textItem in currentEdits.textItems) {
        page.graphics.drawString(
          textItem.text,
          PdfStandardFont(PdfFontFamily.helvetica, textItem.fontSize),
          brush: PdfSolidBrush(PdfColor(textItem.color.red, textItem.color.green, textItem.color.blue)),
          bounds: Rect.fromLTWH(textItem.position.dx, textItem.position.dy, 200, 20),
        );
      }

      // Draw image items
      for (var imageItem in currentEdits.imageItems) {
        final image = PdfBitmap(await File(imageItem.filePath).readAsBytes());
        page.graphics.drawImage(
          image,
          Rect.fromLTWH(imageItem.position.dx, imageItem.position.dy, image.width.toDouble(), image.height.toDouble()),
        );
      }

      // Draw freehand paths
      final freehandPen = PdfPen(PdfColor(_freehandColor.red, _freehandColor.green, _freehandColor.blue), width: _freehandStrokeWidth);
      for (var freehandPath in currentEdits.freehandPaths) {
        _drawPathOnPdf(page, freehandPath, freehandPen);
      }

      // Draw highlight paths
      final highlightPen = PdfPen(PdfColor(_highlightColor.red, _highlightColor.green, _highlightColor.blue, 128), width: _freehandStrokeWidth);
      for (var highlightPath in currentEdits.highlightPaths) {
        _drawPathOnPdf(page, highlightPath, highlightPen);
      }

      // Add audio icons
      for (var audioItem in currentEdits.audioItems) {
        page.graphics.drawString(
          "🎵",
          PdfStandardFont(PdfFontFamily.helvetica, 20),
          brush: PdfSolidBrush(PdfColor(0, 0, 255)),
          bounds: Rect.fromLTWH(audioItem.position.dx, audioItem.position.dy, 20, 20),
        );
      }
    }

    final appDocDir = await getApplicationDocumentsDirectory();
    String newPath = '${appDocDir.path}/edited_${DateTime.now().millisecondsSinceEpoch}.pdf';
    File newPdf = File(newPath);
    await newPdf.writeAsBytes(await pdfDocument.save());
    pdfDocument.dispose();

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF Saved at $newPath')));
  }

  // Method to start recording
  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Microphone Permission'),
          content: Text('Microphone access is permanently denied. Please enable it in settings.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Settings'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _startRecording() async {
    if (await _record.hasPermission()) {
      final appDocDir = await getApplicationDocumentsDirectory();
      _filePath = '${appDocDir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _record.start(
        path: _filePath,
        encoder: AudioEncoder.aacLc,
      );
      setState(() {
        _filePath = null; // Clear previous recordings
      });
    } else {
      _showSettingsDialog();
    }
  }



  Future<void> _stopRecording() async {
    _filePath = await _record.stop();
    playLocalAudio(_filePath!);
    setState(() {});
  }


  Future<void> playLocalAudio(String filePath) async {
    try {
      final correctFilePath = await ensureFileExtension(filePath, 'm4a');
      File file = File(correctFilePath);
      if (await file.exists()) {
        await Future.delayed(Duration(milliseconds: 500));
        await audioPlayer.setSource(DeviceFileSource(correctFilePath));
        await audioPlayer.resume();
      } else {
        print("File does not exist at path: $correctFilePath");
      }
    } catch (e) {
      print("Error occurred during playback: $e");
      _handlePlaybackError(e);
    }
  }


  Future<String> ensureFileExtension(String filePath, String extension) async {
    if (!filePath.endsWith(extension)) {
      final newFilePath = "$filePath.$extension";
      await File(filePath).rename(newFilePath);
      return newFilePath;
    }
    return filePath;
  }

  void _handlePlaybackError(dynamic error) {
    if (error.toString().contains("DarwinAudioError")) {
      print("Audio playback failed on iOS. Check file format and encoding.");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Audio playback failed. Verify the file format and encoding.')),
      );
    }
  }



  // Method to add audio item
  void _addAudioItem() {
    if (_filePath != null) {
      setState(() {
        final currentEdits = pageEdits.putIfAbsent(_currentPage, () => PageEditData());
        currentEdits.audioItems.add(EditableAudioItem(
          filePath: _filePath!,
          position: lastAudioPosition,
        ));

        // Update the position for the next audio item
        lastAudioPosition = Offset(
          lastAudioPosition.dx + 20, // Adjust as needed
          lastAudioPosition.dy + 20, // Adjust as needed
        );

        // Optional: Reset position if it goes off the visible PDF area
        if (lastAudioPosition.dy > 500) { // Example threshold
          lastAudioPosition = Offset(50, 50); // Reset to start
        }
      });
    }
  }




  void _addTextItem() {
    setState(() {
      final currentEdits = pageEdits.putIfAbsent(_currentPage, () => PageEditData());
      currentEdits.textItems.add(EditableTextItem(
        text: 'New Text',
        position: const Offset(50, 50),
        fontSize: 16,
        color: Colors.black,
      ));
    });
  }

  Future<void> _addImageItem() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        final currentEdits = pageEdits.putIfAbsent(_currentPage, () => PageEditData());
        currentEdits.imageItems.add(EditableImageItem(
          filePath: pickedFile.path,
          position: const Offset(50, 50),
          scale: 1.0,
        ));
      });
    }
  }

  void _toggleEditMode() {
    setState(() {
      _isEditMode = !_isEditMode;
      _drawingMode = DrawingMode.none;
    });
  }

  void _setDrawingMode(DrawingMode mode) {
    setState(() {
      _drawingMode = mode;
    });
  }

  void _selectColor(DrawingMode mode) async {
    Color? selectedColor = await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Select Color'),
          content: SingleChildScrollView(
            child: BlockPicker(
              pickerColor: mode == DrawingMode.freehand ? _freehandColor : _highlightColor,
              onColorChanged: (color) {
                Navigator.of(context).pop(color);
              },
            ),
          ),
        );
      },
    );

    if (selectedColor != null) {
      setState(() {
        if (mode == DrawingMode.freehand) {
          _freehandColor = selectedColor;
        } else if (mode == DrawingMode.highlight) {
          _highlightColor = selectedColor;
        }
      });
    }
  }

  void _onPageChanged(int page) {
    setState(() {
      _currentPage = page;
    });
  }

  void _startDrawing(DragStartDetails details) {
    if (_isEditMode) {
      setState(() {
        if (_drawingMode == DrawingMode.freehand || _drawingMode == DrawingMode.highlight) {
          currentPath = Path();
          currentPath.moveTo(details.localPosition.dx, details.localPosition.dy);
        } else if (_drawingMode == DrawingMode.circle) {
          startCirclePosition = details.localPosition;
        } else if (_drawingMode == DrawingMode.rectangle) {
          startRectanglePosition = details.localPosition;
        }
      });
    }
  }

  void _updateDrawing(DragUpdateDetails details) {
    if (_isEditMode) {
      if (_drawingMode == DrawingMode.freehand || _drawingMode == DrawingMode.highlight) {
        setState(() {
          currentPath.lineTo(details.localPosition.dx, details.localPosition.dy);
        });
      } else if (_drawingMode == DrawingMode.erase) {
        _eraseDrawing(details.localPosition);
      }
    }
  }

  void _endDrawing(DragEndDetails details) {
    if (_isEditMode) {
      final currentEdits = pageEdits.putIfAbsent(_currentPage, () => PageEditData());

      setState(() {
        if (_drawingMode == DrawingMode.freehand) {
          currentEdits.freehandPaths.add(currentPath);
          _undoStack.add(DrawingAction.freehand(currentPath));
        } else if (_drawingMode == DrawingMode.highlight) {
          currentEdits.highlightPaths.add(currentPath);
          _undoStack.add(DrawingAction.highlight(currentPath));
        } else if (_drawingMode == DrawingMode.circle && startCirclePosition != null) {
          final endCirclePosition = details.localPosition;
          final radius = (startCirclePosition! - endCirclePosition).distance / 2;
          final center = Offset(
            (startCirclePosition!.dx + endCirclePosition.dx) / 2,
            (startCirclePosition!.dy + endCirclePosition.dy) / 2,
          );
          currentEdits.circles.add(CircleShape(center: center, radius: radius));
          _undoStack.add(DrawingAction.circle(center, radius));
        } else if (_drawingMode == DrawingMode.rectangle && startRectanglePosition != null) {
          final endRectanglePosition = details.localPosition;
          final rect = Rect.fromPoints(startRectanglePosition!, endRectanglePosition);
          currentEdits.rectangles.add(RectangleShape(rect: rect));
          _undoStack.add(DrawingAction.rectangle(rect));
        }
        currentPath = Path();
      });
    }
  }

  void _setEraseMode() {
    setState(() {
      _drawingMode = DrawingMode.erase;
    });
  }

  void _eraseDrawing(Offset position) {
    final currentEdits = pageEdits[_currentPage] ?? PageEditData();

    setState(() {
      currentEdits.freehandPaths.removeWhere((path) {
        final pathBounds = path.getBounds();
        if (pathBounds.inflate(5).contains(position)) { // Add margin for easier touch detection
          _undoStack.add(DrawingAction.freehand(path));
          return true;
        }
        return false;
      });

      currentEdits.highlightPaths.removeWhere((path) {
        final pathBounds = path.getBounds();
        if (pathBounds.inflate(5).contains(position)) {
          _undoStack.add(DrawingAction.highlight(path));
          return true;
        }
        return false;
      });

      currentEdits.circles.removeWhere((circle) {
        final circleBounds = Rect.fromCircle(center: circle.center, radius: circle.radius).inflate(5);
        if (circleBounds.contains(position)) {
          _undoStack.add(DrawingAction.circle(circle.center, circle.radius));
          return true;
        }
        return false;
      });

      currentEdits.rectangles.removeWhere((rect) {
        if (rect.rect.inflate(5).contains(position)) {
          _undoStack.add(DrawingAction.rectangle(rect.rect));
          return true;
        }
        return false;
      });
    });
  }

  void _undoLastAction() {
    if (_undoStack.isNotEmpty) {
      setState(() {
        final lastAction = _undoStack.removeLast();
        final currentEdits = pageEdits.putIfAbsent(_currentPage, () => PageEditData());

        switch (lastAction.type) {
          case DrawingActionType.freehand:
            currentEdits.freehandPaths.remove(lastAction.path);
            break;
          case DrawingActionType.highlight:
            currentEdits.highlightPaths.remove(lastAction.path);
            break;
          case DrawingActionType.circle:
            currentEdits.circles.removeWhere((circle) =>
            circle.center == lastAction.center && circle.radius == lastAction.radius);
            break;
          case DrawingActionType.rectangle:
            currentEdits.rectangles.removeWhere((rect) =>
            rect.rect == lastAction.rect);
            break;
        }
      });
    }
  }

  void _editTextItem(EditableTextItem item) {
    TextEditingController controller = TextEditingController(text: item.text);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Edit Text'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  decoration: InputDecoration(labelText: 'Text'),
                ),
                SizedBox(height: 10),
                Text('Font Size:'),
                DropdownButton<double>(
                  value: item.fontSize,
                  items: [10, 12, 14, 16, 18, 20, 24, 30, 36, 48, 60]
                      .map((size) => DropdownMenuItem<double>(
                    value: size.toDouble(),
                    child: Text(size.toString()),
                  ))
                      .toList(),
                  onChanged: (newSize) {
                    if (newSize != null) {
                      setState(() {
                        item.fontSize = newSize;
                      });
                    }
                  },
                ),
                SizedBox(height: 10),
                Text('Color:'),
                GestureDetector(
                  onTap: () async {
                    Color? selectedColor = await showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return AlertDialog(
                          title: Text('Select Text Color'),
                          content: SingleChildScrollView(
                            child: BlockPicker(
                              pickerColor: item.color,
                              onColorChanged: (color) {
                                Navigator.of(context).pop(color);
                              },
                            ),
                          ),
                        );
                      },
                    );

                    if (selectedColor != null) {
                      setState(() {
                        item.color = selectedColor;
                      });
                    }
                  },
                  child: Container(
                    width: 50,
                    height: 50,
                    color: item.color,
                    child: Center(child: Text(' ')),
                  ),
                ),
              ],
            ),
          ),
          actions: [

            TextButton(
              child: Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),

            TextButton(
              child: Text('Save'),
              onPressed: () {
                setState(() {
                  item.editText(controller.text);
                });
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  void _setStrokeWidth(DrawingMode mode) {
    double currentStrokeWidth;

    if (mode == DrawingMode.freehand) {
      currentStrokeWidth = _freehandStrokeWidth;
    } else if (mode == DrawingMode.rectangle) {
      currentStrokeWidth = _rectangleStrokeWidth;
    } else if (mode == DrawingMode.circle) {
      currentStrokeWidth = _circleStrokeWidth;
    } else {
      return;
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Select Stroke Width for ${mode.toString().split('.').last}'),
          content: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Slider(
                    value: currentStrokeWidth,
                    min: 1.0,
                    max: 10.0,
                    divisions: 9,
                    label: currentStrokeWidth.round().toString(),
                    onChanged: (value) {
                      setState(() {
                        currentStrokeWidth = value;
                      });
                    },
                  ),
                  Text('Current stroke width: ${currentStrokeWidth.toStringAsFixed(1)}'),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              child: Text('Save'),
              onPressed: () {
                setState(() {
                  if (mode == DrawingMode.freehand) {
                    _freehandStrokeWidth = currentStrokeWidth;
                  } else if (mode == DrawingMode.rectangle) {
                    _rectangleStrokeWidth = currentStrokeWidth;
                  } else if (mode == DrawingMode.circle) {
                    _circleStrokeWidth = currentStrokeWidth;
                  }
                });
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text('Close'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentEdits = pageEdits[_currentPage] ?? PageEditData();
    final mediaQueryData = MediaQuery.of(context);
    final isLandscape = mediaQueryData.orientation == Orientation.landscape;

    // Set width and height based on landscape mode and iPad dimensions
    final double width = isLandscape ? mediaQueryData.size.width * 0.8 : mediaQueryData.size.width;
    final double height = isLandscape ? mediaQueryData.size.height * 0.8 : mediaQueryData.size.height;

    return Scaffold(
      appBar: AppBar(
        title: Text('PDF Editor'),
        actions: [

          IconButton(
            icon: Icon(Icons.mic),
            onPressed: _startRecording,
          ),
          IconButton(
            icon: Icon(Icons.stop),
            onPressed: _stopRecording,
          ),
          IconButton(
            icon: Icon(Icons.audiotrack),
            onPressed: _addAudioItem,
          ),
          IconButton(
            icon: Icon(Icons.folder_open),
            onPressed: _pickPdf,
          ),
          IconButton(
            icon: Icon(Icons.text_fields),
            onPressed: _addTextItem,
          ),
          IconButton(
            icon: Icon(Icons.image),
            onPressed: _addImageItem,
          ),
          IconButton(
            icon: Icon(Icons.save),
            onPressed: _savePdf,
          ),
          IconButton(
            icon: Icon(Icons.edit),
            onPressed: _toggleEditMode,
          ),
          if (_isEditMode) ...[
            IconButton(
              icon: Icon(Icons.pan_tool), // Hand icon for scroll mode
              onPressed: () {
                setState(() {
                  _isEditMode = false; // Disable edit mode to enable scroll
                });
              },
            ),
            IconButton(
              icon: Icon(Icons.brush),
              onPressed: () {
                _setDrawingMode(DrawingMode.freehand);
                _setStrokeWidth(DrawingMode.freehand);
              },
            ),
            IconButton(
              icon: Icon(Icons.color_lens),
              onPressed: () => _selectColor(DrawingMode.freehand),
            ),
            IconButton(
              icon: Icon(Icons.highlight),
              onPressed: () {
                _setDrawingMode(DrawingMode.highlight);
                _setStrokeWidth(DrawingMode.highlight);
              },
            ),
            IconButton(
              icon: Icon(Icons.color_lens),
              onPressed: () => _selectColor(DrawingMode.highlight),
            ),
            IconButton(
              icon: Icon(Icons.circle),
              onPressed: () {
                _setDrawingMode(DrawingMode.circle);
                _setStrokeWidth(DrawingMode.circle);
              },
            ),
            IconButton(
              icon: Icon(Icons.rectangle),
              onPressed: () {
                _setDrawingMode(DrawingMode.rectangle);
                _setStrokeWidth(DrawingMode.rectangle);
              },
            ),
            IconButton(
              icon: Icon(Icons.delete),
              onPressed: _setEraseMode,
            ),
            IconButton(
              icon: Icon(Icons.undo),
              onPressed: _undoLastAction,
            ),
          ],
        ],
      ),
      body: _pdfPath != null
          ? Stack(
        children: [
          Container(
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height,
            child: PDFView(
              filePath: _pdfPath!,
              enableSwipe: true,
              autoSpacing: true,
              pageSnap: false,
              fitPolicy: FitPolicy.BOTH, // Adjusts the PDF to fit both width and height
              swipeHorizontal: true, // Enable horizontal swipe in landscape
              onRender: (_pages) {
                setState(() {
                  _totalPages = _pages!;
                  _isReady = true;
                });
              },
              onPageChanged: (int? page, int? total) {
                if (page != null) _onPageChanged(page);
              },
            ),
          ),
            if (_isEditMode)
            GestureDetector(
              onPanStart: _isEditMode ? _startDrawing : null,
              onPanUpdate: _isEditMode ? _updateDrawing : null,
              onPanEnd: _isEditMode ? _endDrawing : null,
              child: CustomPaint(
                painter: CombinedPainter(
                  freehandPaths: currentEdits.freehandPaths,
                  highlightPaths: currentEdits.highlightPaths,
                  circles: currentEdits.circles,
                  rectangles: currentEdits.rectangles,
                  currentPath: currentPath,
                  drawingMode: _drawingMode,
                  freehandColor: _freehandColor,
                  highlightColor: _highlightColor,
                  freehandStrokeWidth: _freehandStrokeWidth,
                  rectangleStrokeWidth: _rectangleStrokeWidth,
                  circleStrokeWidth: _circleStrokeWidth,
                ),
                size: Size(width, height), // Use dynamic size for landscape mode
              ),
            )
          else
              CustomPaint(
                painter: CombinedPainter(
                  freehandPaths: currentEdits.freehandPaths,
                  highlightPaths: currentEdits.highlightPaths,
                  circles: currentEdits.circles,
                  rectangles: currentEdits.rectangles,
                  currentPath: currentPath,
                  drawingMode: _drawingMode,
                  freehandColor: _freehandColor,
                  highlightColor: _highlightColor,
                  freehandStrokeWidth: _freehandStrokeWidth,
                  rectangleStrokeWidth: _rectangleStrokeWidth,
                  circleStrokeWidth: _circleStrokeWidth,
                ),
                size: Size(width, height), // Use dynamic size for landscape mode
              ),


          // Draw existing text items

          // Inside the Stack children in the PDF view:
          ...currentEdits.audioItems.map(
                (audioItem) => Positioned(
              left: audioItem.position.dx,
              top: audioItem.position.dy,
              child: GestureDetector(
                onTap: () => playLocalAudio(audioItem.filePath), // Play audio on tap
                child: Icon(
                  Icons.audiotrack,
                  color: Colors.blue,
                  size: 30, // Adjust size as needed
                ),
              ),
            ),
          ),
          ...currentEdits.textItems.map(
                (item) => Positioned(
              left: item.position.dx,
              top: item.position.dy,
              child: Draggable(
                feedback: Material(
                  color: Colors.transparent,
                  child: Text(
                    item.text,
                    style: TextStyle(color: item.color, fontSize: item.fontSize),
                  ),
                ),
                childWhenDragging: Container(),
                onDragEnd: (dragDetails) {
                  setState(() {
                    item.position = dragDetails.offset;
                  });
                },
                child: GestureDetector(
                  onTap: () {
                    _editTextItem(item);
                  },
                  child: Text(
                    item.text,
                    style: TextStyle(color: item.color, fontSize: item.fontSize),
                  ),
                ),
              ),
            ),
          ),
          // Draw existing image items
          ...currentEdits.imageItems.map(
                (item) => Positioned(
              left: item.position.dx,
              top: item.position.dy,
              child: GestureDetector(
                onPanUpdate: (details) {
                  setState(() {
                    item.position += details.delta;
                  });
                },
                child: Transform.scale(
                  scale: item.scale,
                  child: Draggable(
                    feedback: Image.file(
                      File(item.filePath),
                      width: 100,
                      height: 100,
                    ),
                    childWhenDragging: Container(),
                    onDragEnd: (dragDetails) {
                      setState(() {
                        item.position = dragDetails.offset;
                      });
                    },
                    child: Image.file(
                      File(item.filePath),
                      width: 100,
                      height: 100,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      )
          : Center(child: Text('No PDF selected')),
    );
  }
}

enum DrawingMode { none, freehand, highlight, circle, rectangle, erase }

class PageEditData {
  List<EditableTextItem> textItems = [];
  List<EditableImageItem> imageItems = [];
  List<Path> freehandPaths = [];
  List<Path> highlightPaths = [];
  List<CircleShape> circles = [];
  List<EditableAudioItem> audioItems = [];
  List<RectangleShape> rectangles = [];
}

class EditableTextItem {
  String text;
  Offset position;
  double fontSize;
  Color color;

  EditableTextItem({
    required this.text,
    required this.position,
    required this.fontSize,
    required this.color,
  });

  void editText(String newText) {
    text = newText;
  }
}

class EditableImageItem {
  String filePath;
  Offset position;
  double scale;

  EditableImageItem({
    required this.filePath,
    required this.position,
    this.scale = 1.0,
  });
}

class CircleShape {
  final Offset center;
  final double radius;

  CircleShape({required this.center, required this.radius});
}

class RectangleShape {
  final Rect rect;

  RectangleShape({required this.rect});
}

class CombinedPainter extends CustomPainter {
  final List<Path> freehandPaths;
  final List<Path> highlightPaths;
  final List<CircleShape> circles;
  final List<RectangleShape> rectangles;
  final Path currentPath;
  final DrawingMode drawingMode;
  final Color freehandColor;
  final Color highlightColor;
  final double freehandStrokeWidth;
  final double rectangleStrokeWidth;
  final double circleStrokeWidth;

  CombinedPainter({
    required this.freehandPaths,
    required this.highlightPaths,
    required this.circles,
    required this.rectangles,
    required this.currentPath,
    required this.drawingMode,
    required this.freehandColor,
    required this.highlightColor,
    required this.freehandStrokeWidth,
    required this.rectangleStrokeWidth,
    required this.circleStrokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final freehandPaint = Paint()
      ..color = freehandColor
      ..strokeWidth = freehandStrokeWidth
      ..style = PaintingStyle.stroke;

    final highlightPaint = Paint()
      ..color = highlightColor
      ..strokeWidth = freehandStrokeWidth * 2
      ..style = PaintingStyle.stroke;

    final rectanglePaint = Paint()
      ..color = freehandColor
      ..strokeWidth = rectangleStrokeWidth
      ..style = PaintingStyle.stroke;

    final circlePaint = Paint()
      ..color = freehandColor
      ..strokeWidth = circleStrokeWidth
      ..style = PaintingStyle.stroke;

    for (var path in freehandPaths) {
      canvas.drawPath(path, freehandPaint);
    }

    for (var path in highlightPaths) {
      canvas.drawPath(path, highlightPaint);
    }

    for (var circle in circles) {
      canvas.drawCircle(circle.center, circle.radius, circlePaint);
    }

    for (var rectangle in rectangles) {
      canvas.drawRect(rectangle.rect, rectanglePaint);
    }

    if (drawingMode == DrawingMode.freehand) {
      canvas.drawPath(currentPath, freehandPaint);
    } else if (drawingMode == DrawingMode.highlight) {
      canvas.drawPath(currentPath, highlightPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}

enum DrawingActionType { freehand, highlight, circle, rectangle }

class DrawingAction {
  final DrawingActionType type;
  final Path path;
  final Offset center;
  final double radius;
  final Rect rect;

  DrawingAction.freehand(this.path)
      : type = DrawingActionType.freehand,
        center = Offset.zero,
        radius = 0.0,
        rect = Rect.zero;

  DrawingAction.highlight(this.path)
      : type = DrawingActionType.highlight,
        center = Offset.zero,
        radius = 0.0,
        rect = Rect.zero;

  DrawingAction.circle(this.center, this.radius)
      : type = DrawingActionType.circle,
        path = Path(),
        rect = Rect.zero;

  DrawingAction.rectangle(this.rect)
      : type = DrawingActionType.rectangle,
        path = Path(),
        center = Offset.zero,
        radius = 0.0;
}

// New class for EditableAudioItem
class EditableAudioItem {
  String filePath;
  Offset position;

  EditableAudioItem({
    required this.filePath,
    required this.position,
  });
}


class MicrophonePermission {
  static const platform = MethodChannel('com.example.microphone/permissions');

  static Future<bool> checkMicrophonePermission() async {
    try {
      final bool isGranted = await platform.invokeMethod('checkMicrophonePermission');
      return isGranted;
    } on PlatformException catch (e) {
      print("Failed to get permission: '${e.message}'.");
      return false;
    }
  }
}
