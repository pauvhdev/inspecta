import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'datos_informe.dart';
import 'pdf_informe.dart';

/// Genera el PDF fuera del hilo de la interfaz en Android (`compute` crea un
/// isolate) y en el principal en la web, donde no hay isolates (§8.4).
Future<Uint8List> generarPdfInforme(
  DatosInforme datos,
  String contenidoSha, {
  AssetBundle? bundle,
}) async {
  final b = bundle ?? rootBundle;
  final regular = (await b.load('assets/fuentes/Roboto-Regular.ttf')).buffer
      .asUint8List();
  final negrita = (await b.load('assets/fuentes/Roboto-Bold.ttf')).buffer
      .asUint8List();
  return compute(_construir, (datos, contenidoSha, regular, negrita));
}

Future<Uint8List> _construir((DatosInforme, String, Uint8List, Uint8List) m) =>
    construirPdf(
      m.$1,
      contenidoSha: m.$2,
      fuenteRegular: m.$3,
      fuenteNegrita: m.$4,
    );
