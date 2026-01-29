import 'dart:async'; // Timer için
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:esc_pos_printer_plus/esc_pos_printer_plus.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart'; // Geçici dosya için
import 'package:pdf/widgets.dart' as pw;
import 'package:permission_handler/permission_handler.dart';
import 'package:printing/printing.dart';

import 'coffee_countdown.dart'; // UCupProgress widget'ınızın olduğu dosya

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: CameraScreen(),
    );
  }
}

enum CameraScreenState {
  cameraPreview, // Kamera önizlemesi ve fotoğraf çekme durumu
  imagePreview, // Çekilen fotoğrafın önizlemesi ve seçenekler durumu
  personCountSelection, // Kişi sayısı seçimi durumu
}

class CameraScreen extends StatefulWidget {
  @override
  _CameraScreenState createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  Future<void> _requestPermissions() async {
    await Permission.camera.request();
    await Permission.storage.request();
  }

  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  int _selectedCameraIndex = 1; // Default: rear camera
  int _countdown = 10; // Geri sayım süresi
  final int _initialCountdown = 10; // Başlangıç geri sayım değeri
  bool _isCountingDown = false; // Geri sayım yapılıyor mu?
  late Timer _timer; // Geri sayım için timer
  String _noteText = '';
  final TextEditingController _noteTextController = TextEditingController();
  final GlobalKey _cameraPreviewKey = GlobalKey();
  bool _isProgressVisible = false;
  bool _isLoading = false;
  String? _capturedImagePath; // Çekilen fotoğrafın geçici dosya yolu
  CameraScreenState _currentScreenState =
      CameraScreenState.cameraPreview; // Mevcut ekran durumu

  // --- Kişi Sayısı Seçimi Değişkenleri ---
  int _selectedPersonCount = 0;
  bool _isTextFieldFocused = false;
  FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _init();
    _countdown = _initialCountdown; // Bardağın başlangıçta 10 göstermesi için
    _noteTextController.text = _noteText;
    _focusNode.addListener(() {
      setState(() {
        _isTextFieldFocused = _focusNode.hasFocus;
      });
    });
  }

  Future<void> _init() async {
    await _requestPermissions();
    await _initializeCamera();
  }

  Future<void> printImageDirect(String imagePath) async {
    final file = File(imagePath);
    final imageBytes = await file.readAsBytes();
    final pdf = pw.Document();

    final image = pw.MemoryImage(imageBytes);

    pdf.addPage(
      pw.Page(
        build: (context) => pw.Center(child: pw.Image(image)),
      ),
    );

    await Printing.layoutPdf(onLayout: (_) => pdf.save());
  }

  Future<void> _initializeCamera() async {
    if (_controller != null) {
      await _controller!.dispose();
      _controller = null; // Mevcut kontrolcüyü serbest bırak
    }

    _cameras = await availableCameras(); // Mevcut kameraları al
    if (_cameras == null || _cameras!.isEmpty) {
      print('Hiç kamera bulunamadı.');
      setState(() {
        _isCameraInitialized = false;
      });
      return;
    }

    _controller = CameraController(
      _cameras![_selectedCameraIndex], // Seçilen kamerayı kullan
      ResolutionPreset.medium, // Orta çözünürlük
    );

    try {
      await _controller?.initialize(); // Kamerayı başlat
      setState(() {
        _isCameraInitialized = true;
        _currentScreenState = CameraScreenState
            .cameraPreview; // Kamerayı başlattıktan sonra önizleme moduna geç
        _capturedImagePath = null; // Daha önceki çekilen fotoğrafı temizle
        _selectedPersonCount = 0; // Kişi sayısını sıfırla
        _isProgressVisible = false; // Geri sayım bardağını gizle
      });
    } catch (e) {
      print('Kamera başlatma hatası: $e');
      setState(() {
        _isCameraInitialized = false;
      });
    }
  }

  // Fotoğraf çekmek için geri sayımı başlatma
  void _startCountdown() {
    if (_isCountingDown) return; // Zaten geri sayım yapılıyorsa tekrar başlatma

    setState(() {
      _isCountingDown = true; // Geri sayım başladı
      _isProgressVisible = true; // Geri sayım bardağını göster
      _countdown = _initialCountdown; // Geri sayımı sıfırla
    });

    // Timer'ı her saniye güncelle
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (_countdown > 0) {
        setState(() {
          _countdown--; // Geri sayımı azalt
        });
      } else {
        _timer.cancel(); // Geri sayımı durdur
        _captureAndProcessImage(); // Geri sayım bitince fotoğrafı çek ve işle
      }
    });
  }

  // Fotoğrafı çekme ve işleme (önizleme için)
  Future<void> _captureAndProcessImage() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kamera henüz hazır değil.')),
      );
      setState(() {
        _isCountingDown = false;
        _isProgressVisible = false;
      });
      return;
    }

    try {
      // Kamera önizleme alanını bir resme dönüştürüyoruz
      RenderRepaintBoundary boundary = _cameraPreviewKey.currentContext!
          .findRenderObject() as RenderRepaintBoundary;

      ui.Image image = await boundary.toImage(
          pixelRatio: 3.0); // Daha yüksek çözünürlük için pixelRatio
      ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      Uint8List pngBytes = byteData!.buffer.asUint8List();

      // Geçici bir dosya oluştur
      final directory = (await getTemporaryDirectory()).path;
      String fileName =
          '${DateTime.now().millisecondsSinceEpoch}.png'; // Benzersiz dosya adı
      File imgFile = File('$directory/$fileName');
      await imgFile.writeAsBytes(pngBytes);

      setState(() {
        _capturedImagePath = imgFile.path; // Çekilen fotoğrafın yolunu kaydet
        _isCountingDown = false; // Geri sayımı durdur
        _isProgressVisible = false; // Geri sayım bardağını gizle
        _countdown = _initialCountdown; // Geri sayımı sıfırla
        _currentScreenState =
            CameraScreenState.imagePreview; // Ekranı önizleme moduna geçir
      });
    } catch (e) {
      print('Fotoğraf çekme hatası: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fotoğraf çekme hatası: $e')),
      );
      setState(() {
        _isCountingDown = false;
        _isProgressVisible = false;
      });
    }
  }

  // Bayer 8x8 matrisi (0..63)
  final List<List<int>> _bayer8 = [
    [0, 48, 12, 60, 3, 51, 15, 63],
    [32, 16, 44, 28, 35, 19, 47, 31],
    [8, 56, 4, 52, 11, 59, 7, 55],
    [40, 24, 36, 20, 43, 27, 39, 23],
    [2, 50, 14, 62, 1, 49, 13, 61],
    [34, 18, 46, 30, 33, 17, 45, 29],
    [10, 58, 6, 54, 9, 57, 5, 53],
    [42, 26, 38, 22, 41, 25, 37, 21],
  ];

  img.Image orderedBayerDither(img.Image src) {
    final img.Image out = img.Image.from(src);

    for (int y = 0; y < out.height; y++) {
      for (int x = 0; x < out.width; x++) {
        final px = out.getPixel(x, y);

        // RGB bileşenlerini çıkar
        final r = (px.r.toDouble());
        final g = (px.g.toDouble());
        final b = (px.b.toDouble());

        // Luminance (parlaklık) hesabı
        final lum = (0.299 * r + 0.587 * g + 0.114 * b);

        // Bayer matrisinden threshold (0–255)
        final m = _bayer8[y % 8][x % 8];
        final threshold = ((m + 0.5) / 64.0) * 255.0;

        final col = lum < threshold ? 0 : 255;

        out.setPixelRgba(x, y, col, col, col, 255);
      }
    }
    return out;
  }

  img.Image cartoonize(img.Image src) {
    // 1. Gri tonlama
    final img.Image gray = img.grayscale(src);

    // 2. Kenar tespiti (daha belirgin)
    final img.Image edges = img.sobel(gray);
    final img.Image invertedEdges = img.invert(edges);

    // 3. Hafif bulanıklaştır (gürültüyü yumuşat)
    final img.Image blurred = img.gaussianBlur(invertedEdges, radius: 1);

    // 4. Renk azaltma: termal yazıcı için gerekli değil (kaldırdık)
    // final img.Image quantized = img.quantize(blurred, numberOfColors: 16);

    // 5. Kontrast artır ve biraz karart
    final img.Image contrasted = img.adjustColor(
      blurred, // 🔹 Kenarları vurgular
// 🔹 Arka planı beyaz tutar, çizgiyi koyulaştırır
    );

    // 6. Eşikleme (threshold) ile siyah-beyaz hale getir
    for (int y = 0; y < contrasted.height; y++) {
      for (int x = 0; x < contrasted.width; x++) {
        final pixel = contrasted.getPixel(x, y);
        final lum = img.getLuminance(pixel);
        if (lum < 180) {
          contrasted.setPixelRgba(x, y, 0, 0, 0, 255); // siyah çizgi
        } else {
          contrasted.setPixelRgba(x, y, 255, 255, 255, 255); // beyaz arka plan
        }
      }
    }

    return contrasted;
  }

  // Çekilen fotoğrafı galeriye kaydetme (birden fazla kopya olabilir)
  Future<void> _savePictureToGallery(String imagePath, int count) async {
    setState(() {
      _isLoading = true; // İşlem başladı
    });
    final profile = await CapabilityProfile.load();
    final printer = NetworkPrinter(PaperSize.mm80, profile);

    // Yazıcıya bağlan
    final res = await printer.connect('192.168.1.87', port: 9100);

    if (_controller != null) {
      await _controller!.dispose();
      _controller = null; // Null olarak işaretle
      _noteTextController.clear(); // Notu temizle
      _noteText = '';
    }

    if (res == PosPrintResult.success) {
      // Resmi oku
      final File file = File(imagePath);
      final Uint8List bytes = await file.readAsBytes();
      final img.Image? original = img.decodeImage(bytes);

      if (original != null) {
        // 🔹 1. Resmi yazıcı genişliğine göre yeniden boyutlandır
        final img.Image resized = img.copyResize(original, width: 576);

        // 🔹 2. Karikatür efekti uygula
        final img.Image cartoon = cartoonize(resized);
        for (int i = 0; i < count; i++) {
          printer.image(cartoon); // Yüksek kontrastlı karakalem görseli gönder
          printer.feed(2);
          printer.cut();
        }
      } else {
        print('Resim okunamadı!');
      }

      // ...
      // Kalan bağlantı ve kamera ayarları aynı kalır
      await Future.delayed(const Duration(milliseconds: 300));
      printer.disconnect();
      await Future.delayed(const Duration(milliseconds: 300));
      await _initializeCamera();
    } else {
      print('Yazıcıya bağlanılamadı: $res');
    }
    setState(() {
      _isLoading = false; // İşlem bitti
    });
  }
  /*if (imagePath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kaydedilecek bir fotoğraf yok.')),
      );
      return;
    }

    // Kamera kontrolcüsünü serbest bırak
    if (_controller != null) {
      await _controller!.dispose();
      _controller = null; // Null olarak işaretle
      _noteTextController.clear(); // Notu temizle
      _noteText = '';
    }

    bool allSavedSuccessfully = true;
    for (int i = 0; i < count; i++) {
      await GallerySaver.saveImage(imagePath).then((bool? success) {
        if (success == false) {
          allSavedSuccessfully = false;
          print('Kaydedilemedi: $imagePath');
        }
      });
    }

    if (allSavedSuccessfully) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$count adet fotoğraf yazıcıya gönderildi.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bazı fotoğraflar kaydedilemedi.')),
      );
    }

    // Geçici dosyayı sildikten sonra kamerayı yeniden başlat
    try {
      await File(imagePath).delete();
    } catch (e) {
      print('Geçici dosya silinirken hata oluştu: $e');
    }

    await _initializeCamera(); // Kamerayı yeniden başlat
  }*/

  // Fotoğrafı tekrar çekme işlevi
  void _retakePicture() async {
    setState(() {
      _capturedImagePath = null; // Çekilen fotoğrafı temizle
      _selectedPersonCount = 0; // Kişi sayısını sıfırla
      _currentScreenState =
          CameraScreenState.cameraPreview; // Kamera önizleme moduna geç
      _isCameraInitialized = false;
    });
    await _initializeCamera(); // Kamerayı yeniden başlat
  }

  // "Devam Et" işlevi (kişi sayısı seçimine geçiş)
  void _continueProcess() {
    setState(() {
      _currentScreenState = CameraScreenState
          .personCountSelection; // Kişi sayısı seçimi moduna geç
      _selectedPersonCount = 0; // Seçimi sıfırla
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    try {
      _timer.cancel();
    } catch (_) {}
    _noteTextController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Kamera henüz başlatılmamışsa yükleme göster
    if (!_isCameraInitialized &&
        _currentScreenState == CameraScreenState.cameraPreview) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Ekran boyutlarını al
    double screenWidth = MediaQuery.of(context).size.width;
    double screenHeight = MediaQuery.of(context).size.height;
    double aspectRatio =
        _controller?.value.aspectRatio ?? 1.0; // Kamera en boy oranı
    // Kamera ve çerçeve boyutlarını hesapla
    double cameraWidth = screenWidth * 0.40;
    //double cameraHeight = screenHeight * 0.552;
    double cameraHeight =
        cameraWidth / aspectRatio; // Yüksekliği en boy oranına göre ayarla
    double bottomFrameThickness = screenHeight * 0.08;
    double pngHeightInFrame = bottomFrameThickness * 0.9;
    print("sss");
    print(cameraHeight);

    // --- Ortak Kullanılan Widget'ları Oluşturma Fonksiyonları ---

    Widget _buildCameraAndFrame() {
      return Positioned(
        left: screenWidth * 0.0078,
        top: screenHeight * 0.045,
        child: RepaintBoundary(
          key: _cameraPreviewKey,
          child: Container(
            // Çerçeve dahil toplam genişlik ve yükseklik
            width:
                cameraWidth + (9.0 * 2), // Sol ve sağ çerçeveler için 9.0 * 2
            height: cameraHeight +
                bottomFrameThickness +
                50, // Alt çerçeve ve üst boşluk
            decoration: BoxDecoration(
              color: Colors.white, // Arka plan beyaz
              border: Border.all(
                color: Colors.black, // Çerçevenin rengi siyah
                width: 3, // Çerçeve kalınlığı
              ),
            ),
            child: Column(
              children: [
                // Üst çerçeve (not alanı)
                Container(
                  width: double.infinity,
                  height: 50,
                  color: Colors.white,
                  alignment: Alignment.center,
                  child: Text(
                    _noteText,
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: 25,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
                // Kamera veya çekilen fotoğraf alanı
                Expanded(
                  child: Row(
                    children: [
                      // Sol çerçeve
                      Container(
                        width: 9.0,
                        color: Colors.white,
                      ),
                      // Kamera Önizlemesi veya Çekilen Fotoğraf
                      Expanded(
                        child: Container(
                          height: cameraHeight,
                          child: _currentScreenState ==
                                  CameraScreenState.cameraPreview
                              ? (_controller != null &&
                                      _controller!.value.isInitialized
                                  ? CameraPreview(
                                      _controller!) // Kamera önizlemesi
                                  : Center(
                                      child:
                                          CircularProgressIndicator())) // Kamera yüklenirken
                              : (_capturedImagePath != null
                                  ? Image.file(
                                      File(
                                          _capturedImagePath!), // Çekilen fotoğraf
                                      fit: BoxFit.contain,
                                    )
                                  : Container()), // Boş container
                        ),
                      ),
                      // Sağ çerçeve
                      Container(
                        width: 9.0,
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
                // Alt çerçeve (logo alanı)
                Container(
                  width: double.infinity,
                  height: bottomFrameThickness,
                  color: Colors.white,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment
                        .spaceEvenly, // Logolar arasına eşit boşluk koyar
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: Image.asset(
                            'assets/images/isma_logo.png',
                            fit: BoxFit.contain,
                            height: pngHeightInFrame,
                          ),
                        ),
                      ),
                      Expanded(
                        flex:
                            2, // Bu logo diğerlerinden iki kat daha geniş yer kaplar
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: Image.asset(
                            'assets/images/isma_yazi.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: Image.asset(
                            'assets/images/isma_logo.png',
                            fit: BoxFit.contain,
                            height: pngHeightInFrame,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget _buildWelcomeMessage() {
      return Positioned(
        right: screenWidth * 0.203,
        top: screenHeight * 0.130,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/images/ismay.png',
              width: screenWidth * 0.171,
              height: screenHeight * 0.286,
            ),
            Text(
              'Hoşgeldiniz',
              style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'sans-serif'),
            ),
          ],
        ),
      );
    }

    Widget _buildCupProgress() {
      return Positioned(
        bottom: screenHeight * 0.018,
        left: screenWidth * 0.148,
        child: UCupProgress(
          progress: _isCountingDown ? _countdown / _initialCountdown : 1.0,
          countdownValue: _isCountingDown ? _countdown : _initialCountdown,
        ),
      );
    }

    Widget _buildCaptureButton() {
      return Positioned(
        bottom: screenHeight * 0.026,
        left: (screenWidth - screenWidth * 0.155) / 2,
        child: ElevatedButton(
          style: ButtonStyle(
            backgroundColor: MaterialStateProperty.all(
              _isCountingDown ? Colors.black38 : Colors.blue,
            ),
            shape: MaterialStateProperty.all(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          onPressed: _isCountingDown ? null : _startCountdown,
          child: _isCountingDown
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 3,
                      ),
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Bekleyin...',
                      style: TextStyle(fontSize: 38, color: Colors.white),
                    ),
                  ],
                )
              : Text(
                  'Resim Çek',
                  style: TextStyle(fontSize: 38, color: Colors.white),
                ),
        ),
      );
    }

    Widget _buildNoteTextField() {
      return Positioned(
        right: screenWidth * 0.031,
        bottom: screenHeight * 0.093,
        child: Container(
          width: screenWidth * 0.359,
          height: screenHeight * 0.188,
          child: TextField(
            focusNode: _focusNode,
            maxLength: 50,
            style: TextStyle(color: Colors.black, fontSize: 25),
            controller: _noteTextController,
            decoration: InputDecoration(
              counterStyle: TextStyle(color: Colors.black, fontSize: 20),
              hintText: 'Emoji ve İsminizi Eklemek İster misiniz?',
              hintStyle: TextStyle(color: Colors.black),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.black),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(
                  color: Colors.black,
                ),
              ),
              fillColor: Colors.white,
              filled: true,
            ),
            onChanged: (value) {
              setState(() {
                _noteText = value; // Not metnini güncelle
              });
            },
          ),
        ),
      );
    }

    Widget _buildPostCaptureButtons() {
      return Positioned(
        bottom: screenHeight * 0.026,
        left: (screenWidth - (screenWidth * 0.334)) /
            2, // Butonları ortalamak için
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: _retakePicture, // Tekrar çekme işlevi
              child: Text(
                'Tekrar Çek',
                style: TextStyle(fontSize: 38, color: Colors.white),
              ),
            ),
            SizedBox(width: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              onPressed: _continueProcess, // Devam etme işlevi
              child: Text(
                'Devam Et',
                style: TextStyle(fontSize: 38, color: Colors.white),
              ),
            ),
          ],
        ),
      );
    }

    Widget _buildPersonCountSelection() {
      return Positioned(
        bottom: screenHeight * 0.026,
        left: (screenWidth - (screenWidth * 0.390)) /
            2, // Seçim alanını ortalamak için
        child: Column(
          children: [
            Text(
              'Kaç kişisiniz?',
              style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.black),
            ),
            SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                int count = index + 1; // 1'den 5'e kadar sayıları oluştur
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedPersonCount =
                            count; // Seçilen kişi sayısını ayarla
                      });
                    },
                    child: Container(
                      width: screenWidth * 0.06,
                      height: screenHeight * 0.104,
                      decoration: BoxDecoration(
                        color: _selectedPersonCount == count
                            ? Colors.blue // Seçiliyse mavi
                            : Colors.black38, // Değilse gri
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: _selectedPersonCount == count
                                ? Colors.blueAccent
                                : Colors.black,
                            width: 2),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.bold,
                          color: _selectedPersonCount == count
                              ? Colors.white
                              : Colors.black,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: _selectedPersonCount > 0 && !_isLoading
                      ? Colors.green
                      : Colors.black38), // Kişi seçilirse yeşil, yoksa gri
              onPressed: _selectedPersonCount > 0
                  ? () /*async*/ => _savePictureToGallery(
                      _capturedImagePath!, _selectedPersonCount)
                  /*await printImageDirect(
                          _capturedImagePath!)*/ // Seçilen kişi sayısı kadar kaydet
                  : null, // Kişi seçilmediyse buton devre dışı
              child: _isLoading
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 3,
                          ),
                        ),
                        SizedBox(width: 12),
                        Text(
                          'Bekleyin...',
                          style: TextStyle(fontSize: 36, color: Colors.white),
                        ),
                      ],
                    )
                  : Text(
                      'Tamamla',
                      style: TextStyle(fontSize: 38, color: Colors.white),
                    ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset:
          true, // Klavye açıldığında ekranın boyutunu ayarla
      body: Center(
        child: Stack(
          children: [
            _buildCameraAndFrame(), // Kamera ve çerçeve her zaman görünür
            _buildWelcomeMessage(), // Hoşgeldiniz mesajı her zaman görünür
            if (_isProgressVisible)
              _buildCupProgress(), // Geri sayım bardağı sadece geri sayımdayken görünür

            // Ekran durumuna göre farklı UI elementlerini göster
            if (_currentScreenState == CameraScreenState.cameraPreview) ...[
              _buildCaptureButton(),
              if (_isTextFieldFocused)
                BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 3.5, sigmaY: 3.5),
                  child: Container(
                    color: Colors.white
                        .withOpacity(0.2), // Optional: a slight overlay
                  ),
                ),
              _buildNoteTextField(),
            ] else if (_currentScreenState ==
                CameraScreenState.imagePreview) ...[
              _buildPostCaptureButtons(), // Tekrar çek ve Devam et butonları
            ] else if (_currentScreenState ==
                CameraScreenState.personCountSelection) ...[
              BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 3.5, sigmaY: 3.5),
                child: Container(
                  color: Colors.white
                      .withOpacity(0.2), // Optional: a slight overlay
                ),
              ),
              _buildPersonCountSelection(), // Kişi sayısı seçimi alanı
            ],
          ],
        ),
      ),
    );
  }
}
