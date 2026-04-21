import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Renders an ayah/dua as a shareable image (via dart:ui Canvas) and invokes
/// the platform share sheet. Also supports plain-text sharing.
class VerseShareService {
  VerseShareService._();

  static const _bgTop = Color(0xFF060B11);
  static const _bgBottom = Color(0xFF0F1A26);
  static const _card = Color(0xFF121D2B);
  static const _gold = Color(0xFFD4A84B);
  static const _goldSoft = Color(0x40D4A84B);
  static const _textPrimary = Color(0xFFF0F2F5);
  static const _textSecondary = Color(0xFF9EACBD);
  static const _textMuted = Color(0xFF5A6A7E);

  /// Shares an Arabic + translation block via the platform share sheet as text.
  static Future<void> shareAsText({
    required String arabic,
    String? translation,
    String? reference,
  }) async {
    final buffer = StringBuffer();
    if (reference != null && reference.isNotEmpty) {
      buffer
        ..writeln(reference)
        ..writeln();
    }
    buffer.writeln(arabic);
    if (translation != null && translation.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(translation);
    }
    buffer
      ..writeln()
      ..write('Shared from Noor AI');
    await Share.share(buffer.toString());
  }

  /// Renders the verse as a PNG and invokes the share sheet.
  static Future<void> shareAsImage({
    required String arabic,
    String? translation,
    String? reference,
  }) async {
    final bytes = await renderVerseImage(
      arabic: arabic,
      translation: translation,
      reference: reference,
    );
    if (bytes == null) return;
    final dir = await getTemporaryDirectory();
    final file = XFile.fromData(
      bytes,
      name: 'noor-verse.png',
      mimeType: 'image/png',
      path:
          '${dir.path}/noor-verse-${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await Share.shareXFiles(
      [file],
      text: reference ?? 'Shared from Noor AI',
    );
  }

  /// Pure-canvas renderer. Returns PNG bytes.
  static Future<Uint8List?> renderVerseImage({
    required String arabic,
    String? translation,
    String? reference,
  }) async {
    const double width = 1080;
    const double padding = 64;
    const double innerPadding = 48;
    const double cardRadius = 32;
    final double innerWidth = width - 2 * (padding + innerPadding);

    final arabicPara = _buildPara(
      text: arabic,
      width: innerWidth,
      fontSize: 44,
      color: _textPrimary,
      align: TextAlign.right,
      direction: TextDirection.rtl,
      height: 2.0,
      fontWeight: FontWeight.w500,
    );

    ui.Paragraph? translationPara;
    if (translation != null && translation.isNotEmpty) {
      translationPara = _buildPara(
        text: translation,
        width: innerWidth,
        fontSize: 26,
        color: _textSecondary,
        align: TextAlign.left,
        direction: TextDirection.ltr,
        height: 1.65,
      );
    }

    ui.Paragraph? refPara;
    if (reference != null && reference.isNotEmpty) {
      refPara = _buildPara(
        text: reference,
        width: innerWidth,
        fontSize: 22,
        color: _gold,
        align: TextAlign.right,
        direction: TextDirection.ltr,
        fontWeight: FontWeight.w600,
      );
    }

    final brandPara = _buildPara(
      text: 'Noor AI',
      width: width - 2 * padding,
      fontSize: 28,
      color: _gold,
      align: TextAlign.left,
      direction: TextDirection.ltr,
      fontWeight: FontWeight.w600,
    );

    final footerPara = _buildPara(
      text: 'noor.ai · Quran companion',
      width: width - 2 * padding,
      fontSize: 18,
      color: _textMuted,
      align: TextAlign.center,
      direction: TextDirection.ltr,
    );

    double cardBodyHeight = arabicPara.height;
    if (translationPara != null) {
      cardBodyHeight += 40 + translationPara.height;
    }
    if (refPara != null) {
      cardBodyHeight += 32 + refPara.height;
    }
    final cardHeight = cardBodyHeight + 2 * innerPadding;

    const double headerHeight = 80;
    const double headerBottomGap = 40;
    const double cardBottomGap = 36;
    final height = padding +
        headerHeight +
        headerBottomGap +
        cardHeight +
        cardBottomGap +
        footerPara.height +
        padding;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, width, height),
    );

    // Background gradient.
    final bgRect = Rect.fromLTWH(0, 0, width, height);
    canvas.drawRect(
      bgRect,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 0),
          Offset(width, height),
          const [_bgTop, _bgBottom],
        ),
    );

    // Header logo.
    final logoRect = Rect.fromLTWH(padding, padding, 52, 52);
    canvas.drawRRect(
      RRect.fromRectAndRadius(logoRect, const Radius.circular(12)),
      Paint()
        ..shader = ui.Gradient.linear(
          logoRect.topLeft,
          logoRect.bottomRight,
          const [Color(0xFFAD8528), _gold, Color(0xFFEDD48B)],
        ),
    );
    final nPara = _buildPara(
      text: 'ن',
      width: 52,
      fontSize: 34,
      color: Colors.black,
      align: TextAlign.center,
      direction: TextDirection.rtl,
      fontWeight: FontWeight.w800,
    );
    canvas.drawParagraph(nPara, Offset(padding, padding + 4));
    canvas.drawParagraph(brandPara, Offset(padding + 64, padding + 10));

    // Card.
    final cardTop = padding + headerHeight + headerBottomGap;
    final cardRect = Rect.fromLTWH(
      padding,
      cardTop,
      width - 2 * padding,
      cardHeight,
    );
    final cardRR =
        RRect.fromRectAndRadius(cardRect, const Radius.circular(cardRadius));
    canvas.drawRRect(cardRR, Paint()..color = _card);
    canvas.drawRRect(
      cardRR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = _goldSoft,
    );

    // Arabic.
    double cursorY = cardTop + innerPadding;
    canvas.drawParagraph(
      arabicPara,
      Offset(padding + innerPadding, cursorY),
    );
    cursorY += arabicPara.height;

    if (translationPara != null) {
      cursorY += 20;
      canvas.drawRect(
        Rect.fromLTWH(padding + innerPadding, cursorY, innerWidth, 1),
        Paint()..color = _goldSoft,
      );
      cursorY += 20;
      canvas.drawParagraph(
        translationPara,
        Offset(padding + innerPadding, cursorY),
      );
      cursorY += translationPara.height;
    }

    if (refPara != null) {
      cursorY += 32;
      canvas.drawParagraph(
        refPara,
        Offset(padding + innerPadding, cursorY),
      );
    }

    // Footer.
    final footerY = cardTop + cardHeight + cardBottomGap;
    canvas.drawParagraph(footerPara, Offset(padding, footerY));

    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(width.toInt(), height.toInt());
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return bytes?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  static ui.Paragraph _buildPara({
    required String text,
    required double width,
    required double fontSize,
    required Color color,
    required TextAlign align,
    required TextDirection direction,
    double? height,
    FontWeight? fontWeight,
  }) {
    final style = ui.ParagraphStyle(
      textAlign: align,
      textDirection: direction,
      fontSize: fontSize,
      height: height,
      fontWeight: fontWeight,
    );
    final builder = ui.ParagraphBuilder(style)
      ..pushStyle(
        ui.TextStyle(
          color: color,
          fontSize: fontSize,
          height: height,
          fontWeight: fontWeight,
        ),
      )
      ..addText(text);
    return builder.build()..layout(ui.ParagraphConstraints(width: width));
  }
}
