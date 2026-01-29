import 'dart:math' as math;

import 'package:flutter/material.dart';

class UCupProgress extends StatefulWidget {
  final double progress; // 0.0 (boş) ile 1.0 (dolu) arasında
  final int countdownValue; // Geri sayım değeri
  final Color fillColor;
  final Color borderColor;

  const UCupProgress({
    Key? key,
    required this.progress,
    required this.countdownValue,
    this.fillColor = const Color(0xFF6D4C41), // React Native'deki gibi turuncu
    this.borderColor = Colors.black,
  }) : super(key: key);

  @override
  _UCupProgressState createState() => _UCupProgressState();
}

class _UCupProgressState extends State<UCupProgress>
    with TickerProviderStateMixin {
  late AnimationController _animatedProgressController;
  late Animation<double> _animatedProgress;

  late AnimationController _wavePhaseController;
  late Animation<double> _wavePhase;

  // Sıvının çizilip çizilmeyeceğini kontrol eden bayrak
  bool _shouldDrawLiquid = false;

  @override
  void initState() {
    super.initState();

    _animatedProgressController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _animatedProgress =
        Tween<double>(begin: widget.progress, end: widget.progress)
            .animate(_animatedProgressController);

    _wavePhaseController = AnimationController(
      duration: const Duration(milliseconds: 2500),
      vsync: this,
    )..repeat();
    _wavePhase =
        Tween<double>(begin: 0, end: 2 * math.pi).animate(_wavePhaseController);

    // Initial value for _shouldDrawLiquid
    _shouldDrawLiquid = widget.progress > 0;

    _animatedProgressController.value = widget.progress;
    _animatedProgress =
        Tween<double>(begin: _animatedProgress.value, end: widget.progress)
            .animate(CurvedAnimation(
      parent: _animatedProgressController,
      curve: Curves.linear, // Sıvının düzgün azalması için linear eğri
    ));
    _animatedProgressController.forward(from: 0.0);
  }

  @override
  void didUpdateWidget(covariant UCupProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.progress != oldWidget.progress) {
      _shouldDrawLiquid =
          widget.progress > 0; // Her progress değişiminde güncelliyoruz
      _animatedProgress =
          Tween<double>(begin: _animatedProgress.value, end: widget.progress)
              .animate(CurvedAnimation(
        parent: _animatedProgressController,
        curve: Curves.linear,
      ));
      _animatedProgressController.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _animatedProgressController.dispose();
    _wavePhaseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_animatedProgress, _wavePhase]),
      builder: (context, child) {
        final currentProgress = _animatedProgress.value;
        final phase = _wavePhase.value;

        double screenWidth = MediaQuery.of(context).size.width;
        double screenHeight = MediaQuery.of(context).size.height;
        double cupWidth = screenWidth * 0.15;
        double cupHeight = screenHeight * 0.22;

        final Path cupOutlinePath = Path();
        // Bardağın alt kenarı
        cupOutlinePath.moveTo(
            cupWidth * (50 / 175), cupHeight * (162 / 162)); // Sol alt köşe
        cupOutlinePath.lineTo(
            cupWidth * (125 / 175), cupHeight * (162 / 162)); // Sağ alt köşe

        // Bardağın sağ kenarı
        cupOutlinePath.lineTo(
            cupWidth * (140 / 175), cupHeight * (30 / 162)); // Sağ üst köşe

        // Bardağın sol kenarı
        cupOutlinePath.lineTo(
            cupWidth * (35 / 175), cupHeight * (30 / 162)); // Sol üst köşe

        // Bardağın üst kenarını kapatma
        cupOutlinePath.lineTo(cupWidth * (50 / 175),
            cupHeight * (162 / 162)); // Sol alt köşeye geri dönme

        cupOutlinePath.close();

        // Kapak çizmek için ayrı yollar tanımlayalım
        final Path lidPath = Path();
        lidPath.moveTo(cupWidth * (41 / 220), cupHeight * (25 / 159));
        lidPath.lineTo(cupWidth * (177 / 220), cupHeight * (25 / 159));
        lidPath.lineTo(cupWidth * (171 / 220), cupHeight * (15 / 159));
        lidPath.lineTo(cupWidth * (46 / 220), cupHeight * (15 / 159));
        lidPath.close();

        // Bardağın üst ve alt Y koordinatlarını alıyoruz
        final double cupTopY = cupHeight * (30 / 162);
        final double cupBottomY = cupHeight * (162 / 162);

        // Bardağın sol ve sağ kenarlarının üst ve alt X koordinatlarını alıyoruz
        final double cupTopLeftX = cupWidth * (35 / 175);
        final double cupBottomLeftX = cupWidth * (50 / 175);
        final double cupTopRightX = cupWidth * (140 / 175);
        final double cupBottomRightX = cupWidth * (125 / 175);

        // Sıvının dolabileceği maksimum ve minimum Y koordinatları
        const double minY =
            35; // Sıvının ulaşabileceği en üst nokta (kapağın hemen altı)
        const double maxY =
            155; // Sıvının ulaşabileceği en alt nokta (bardağın tabanı)

        final double scaledMinY = cupHeight * (minY / 162);
        final double scaledMaxY = cupHeight * (maxY / 162);
        final double scaledWaveHeight =
            cupHeight * (2 / 162); // Dalga yüksekliği

        // Sıvının mevcut doluluk seviyesine göre Y koordinatını hesaplıyoruz
        double fillLevel =
            scaledMaxY - (scaledMaxY - scaledMinY) * currentProgress;

        final Path wavePath = Path();

        if (_shouldDrawLiquid) {
          // Sıvı seviyesinin Y koordinatına göre sol ve sağ X koordinatlarını hesaplıyoruz
          final double leftSideX = cupTopLeftX +
              (fillLevel - cupTopY) *
                  ((cupBottomLeftX - cupTopLeftX) / (cupBottomY - cupTopY));
          final double rightSideX = cupTopRightX +
              (fillLevel - cupTopY) *
                  ((cupBottomRightX - cupTopRightX) / (cupBottomY - cupTopY));
          final double currentWaveWidth = rightSideX - leftSideX;

          // Dalgalı üst sınırı çiz
          wavePath.moveTo(leftSideX, fillLevel);
          for (double x = 0; x <= currentWaveWidth; x += 1) {
            final y = math.sin((x / currentWaveWidth) * 2 * math.pi + phase) *
                scaledWaveHeight;
            wavePath.lineTo(leftSideX + x, fillLevel + y);
          }

          // Sıvıyı bardağın alt kenarına doğru kapatıyoruz
          wavePath.lineTo(cupBottomRightX, cupBottomY);
          wavePath.lineTo(cupBottomLeftX, cupBottomY);
          wavePath.close();
        }

        return SizedBox(
          width: cupWidth,
          height: cupHeight,
          child: CustomPaint(
            painter: _UCupProgressPainter(
              cupOutlinePath: cupOutlinePath,
              lidPath: lidPath,
              wavePath: wavePath, // Boş veya dolu yol
              fillColor: widget.fillColor,
              borderColor: widget.borderColor,
              shouldDrawLiquid:
                  _shouldDrawLiquid, // Yeni parametreyi painter'a iletiyoruz
            ),
            child: Center(
              child: Text(
                widget.countdownValue > 0 ? '${widget.countdownValue}' : '',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _UCupProgressPainter extends CustomPainter {
  final Path cupOutlinePath;
  final Path lidPath;
  final Path wavePath;
  final Color fillColor;
  final Color borderColor;
  final bool shouldDrawLiquid; // Yeni parametre

  _UCupProgressPainter({
    required this.cupOutlinePath,
    required this.lidPath,
    required this.wavePath,
    required this.fillColor,
    required this.borderColor,
    required this.shouldDrawLiquid, // Constructor'a ekledik
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paintOutline = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0;

    final paintFill = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;

    // `shouldDrawLiquid` bayrağını kullanarak sıvıyı çizip çizmeyeceğimizi kontrol et
    if (shouldDrawLiquid) {
      canvas.drawPath(wavePath, paintFill);
    }

    canvas.drawPath(cupOutlinePath, paintOutline); // Bardağın ana gövdesini çiz
    canvas.drawPath(lidPath, paintOutline); // Kapağı çiz
  }

  @override
  bool shouldRepaint(covariant _UCupProgressPainter oldDelegate) {
    return oldDelegate.cupOutlinePath != cupOutlinePath ||
        oldDelegate.lidPath != lidPath ||
        oldDelegate.wavePath != wavePath ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.shouldDrawLiquid != shouldDrawLiquid;
  }
}
