import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/formato.dart' as fmt;
import 'datos_informe.dart';

// PDF del informe, generado en el aparato sin red (DISEÑO.md §8.4).
//
// Función pura: datos y fuentes entran, bytes salen. En Android corre en un
// isolate (`Isolate.run`); en la web, en el hilo principal. No decodifica las
// fotos: el paquete `pdf` incrusta el JPEG tal cual. La fuente (Roboto,
// `assets/fuentes/`) va incrustada: nunca `PdfGoogleFonts`, que necesita red.
// Roboto no tiene «₂»: se escribe «CO2».

const _azul = PdfColor.fromInt(0xFF0B5FD3);
const _gris = PdfColor.fromInt(0xFF454B57);
const _linea = PdfColor.fromInt(0xFFC9CDD4);
const _rojo = PdfColor.fromInt(0xFFB3261E);

String _estadoTexto(String? e) => switch (e) {
  'ok' => 'OK',
  'observacion' => 'Observación',
  'defecto' => 'Defecto',
  'na' => 'N.A.',
  _ => '—',
};

String _gravedad(String? g) => switch (g) {
  'leve' => 'Leve',
  'grave' => 'Grave',
  'muy_grave' => 'Muy grave',
  _ => '—',
};

String _intervencion(String t) => switch (t) {
  'preventivo' => 'Mantenimiento preventivo',
  'correctivo' => 'Correctivo',
  'control_fugas' => 'Control de fugas',
  'recontrol_fugas' => 'Nuevo control de fugas',
  _ => 'Puesta en marcha',
};

String _fechaHora(DateTime? d) =>
    d == null ? '—' : '${fmt.fecha(d)} ${fmt.hora(d)}';

/// Roboto no tiene «→»: en el PDF se escribe «:».
String _sinFlecha(Object? t) => '${t ?? '—'}'.replaceAll(' → ', ': ');

String _categoria(Object? c) => switch (c) {
  'aire_acondicionado_bomba_calor' => 'Aire acondicionado o bomba de calor',
  'refrigeracion' => 'Refrigeración',
  'otro' => 'Otro',
  _ => '—',
};

Map<String, Object?> _mapa(Object? o) =>
    o is Map ? o.cast<String, Object?>() : const {};

String _t(Map<String, Object?> m, String k) {
  final v = m[k];
  if (v == null) return '—';
  if (v is bool) return v ? 'Sí' : 'No';
  if (v is num) return fmt.numero(v.toDouble());
  return '$v';
}

/// Genera el PDF. [contenidoSha] va en el pie (§7.10.6): el PDF no puede
/// llevar el hash de sí mismo.
Future<Uint8List> construirPdf(
  DatosInforme d, {
  required String contenidoSha,
  required Uint8List fuenteRegular,
  required Uint8List fuenteNegrita,
}) async {
  final base = pw.Font.ttf(ByteData.sublistView(fuenteRegular));
  final negrita = pw.Font.ttf(ByteData.sublistView(fuenteNegrita));
  final doc = pw.Document(
    title: 'Informe ${d.inspeccion.numero ?? ''}',
    author: 'Inspecta',
    theme: pw.ThemeData.withFont(base: base, bold: negrita),
  );
  final i = d.inspeccion;
  final cab = d.cabecera;
  final emp = _mapa(cab['empresa']);
  final tec = _mapa(cab['tecnico']);
  final cli = _mapa(cab['cliente']);
  final inst = _mapa(cab['instalacion']);

  pw.Widget titulo(String t) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
    child: pw.Text(
      t,
      style: pw.TextStyle(
        fontSize: 13,
        fontWeight: pw.FontWeight.bold,
        color: _azul,
      ),
    ),
  );

  pw.Widget pares(List<(String, String)> filas) => pw.Table(
    columnWidths: const {0: pw.FixedColumnWidth(150), 1: pw.FlexColumnWidth()},
    children: [
      for (final (k, v) in filas)
        pw.TableRow(
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 2),
              child: pw.Text(
                k,
                style: const pw.TextStyle(color: _gris, fontSize: 9),
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 2),
              child: pw.Text(v, style: const pw.TextStyle(fontSize: 9)),
            ),
          ],
        ),
    ],
  );

  pw.Widget tabla(
    List<String> cabeceras,
    List<List<String>> filas, {
    Map<int, pw.TableColumnWidth>? anchos,
  }) => pw.TableHelper.fromTextArray(
    headers: cabeceras,
    data: filas,
    headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
    cellStyle: const pw.TextStyle(fontSize: 8),
    headerDecoration: const pw.BoxDecoration(
      color: PdfColor.fromInt(0xFFE8EAEE),
    ),
    border: const pw.TableBorder(
      horizontalInside: pw.BorderSide(color: _linea, width: 0.5),
      bottom: pw.BorderSide(color: _linea, width: 0.5),
    ),
    cellAlignment: pw.Alignment.centerLeft,
    columnWidths: anchos,
  );

  final contenido = <pw.Widget>[
    // 1. Cabecera.
    pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                _t(emp, 'razon_social'),
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                'CIF ${_t(emp, 'cif')} · Habilitación RITE ${_t(emp, 'n_habilitacion_rite')}',
                style: const pw.TextStyle(fontSize: 9),
              ),
              pw.Text(
                'Certificado F-gas de empresa ${_t(emp, 'n_certificado_fgas_empresa')}',
                style: const pw.TextStyle(fontSize: 9),
              ),
            ],
          ),
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              'Informe n.º',
              style: const pw.TextStyle(fontSize: 9, color: _gris),
            ),
            pw.Text(
              i.numero ?? '—',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              'Versión ${i.version}',
              style: const pw.TextStyle(fontSize: 9),
            ),
          ],
        ),
      ],
    ),
    pw.SizedBox(height: 8),
    pw.Text(
      _intervencion(d.tipoIntervencion),
      style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
    ),
    pares([
      ('Inicio de la visita', _fechaHora(i.iniciadaAt)),
      ('Fin y firma', _fechaHora(i.firmadaAt)),
    ]),
    // 2. Técnico.
    titulo('Técnico'),
    pares([
      ('Nombre', _t(tec, 'nombre')),
      ('Carné RITE', _t(tec, 'carne_rite')),
      (
        'Certificado F-gas',
        tec['cert_fgas_numero'] == null
            ? 'No consta'
            : '${_t(tec, 'cert_fgas_tipo')} ${_t(tec, 'cert_fgas_numero')} (caduca ${_t(tec, 'cert_fgas_caduca')})',
      ),
    ]),
    // 3. Titular e instalación.
    titulo('Titular e instalación'),
    pares([
      ('Titular', _t(cli, 'razon_social')),
      ('CIF', _t(cli, 'cif')),
      (
        'Contacto',
        '${_t(cli, 'contacto_nombre')} · ${_t(cli, 'contacto_telefono')}',
      ),
      ('Instalación', _t(inst, 'nombre')),
      ('Dirección', _t(inst, 'direccion')),
      (
        'Uso',
        inst['uso_edificio'] == 'vivienda' ? 'Vivienda' : 'Restantes usos',
      ),
      ('Expediente', _t(inst, 'expediente_ccaa')),
      (
        'Potencia declarada',
        '${_t(inst, 'potencia_frio_kw')} kW frío · ${_t(inst, 'potencia_calor_kw')} kW calor',
      ),
      (
        'Contrato / manual',
        '${_t(inst, 'contrato_mantenimiento')} / ${_t(inst, 'manual_disponible')}',
      ),
    ]),
  ];

  // 4-6. Por equipo.
  final vencimientos = <(String, String, String)>[];
  for (final e in d.equipos) {
    final datos = e.datos;
    final eq = _mapa(datos['equipo']);
    final fgas = _mapa(datos['fgas']);
    final nombre = '${datos['nombre'] ?? 'Equipo'}';
    vencimientos.add((
      nombre,
      _sinFlecha(fgas['titular']),
      '${datos['rite'] ?? '—'}',
    ));
    contenido.addAll([
      pw.NewPage(freeSpace: 200),
      titulo('Equipo: $nombre'),
      pares([
        ('Marca y modelo', '${_t(eq, 'marca')} ${_t(eq, 'modelo')}'),
        ('N.º de serie', _t(eq, 'n_serie')),
        (
          'Potencia',
          '${_t(eq, 'potencia_frio_kw')} kW frío · ${_t(eq, 'potencia_calor_kw')} kW calor',
        ),
        (
          'Refrigerante y carga',
          '${_t(eq, 'refrigerante')} · ${_t(eq, 'carga_kg')} kg',
        ),
        (
          'Hermético / detección',
          '${_t(eq, 'hermetico_etiquetado')} / ${_t(eq, 'deteccion_fugas')}',
        ),
        ('Categoría F-gas', _categoria(eq['categoria_fgas'])),
      ]),
      pw.Container(
        margin: const pw.EdgeInsets.only(top: 6),
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _azul, width: 0.8),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'F-gas: ${_sinFlecha(fgas['titular'])}',
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            ),
            for (final x in (fgas['detalle'] as List?) ?? const [])
              pw.Text(
                '$x',
                style: const pw.TextStyle(fontSize: 8, color: _gris),
              ),
            pw.SizedBox(height: 3),
            pw.Text(
              'RITE: ${datos['rite'] ?? '—'}',
              style: const pw.TextStyle(fontSize: 9),
            ),
          ],
        ),
      ),
      pw.SizedBox(height: 6),
      tabla(
        ['Código', 'Operación', 'Resultado', 'Valor', 'Observación'],
        [
          for (final r in e.respuestas)
            [
              r.codigoNormativo ?? '',
              r.textoItem,
              _estadoTexto(r.estado),
              r.valorNum == null
                  ? ''
                  : '${fmt.numero(r.valorNum!, decimales: 3)} ${r.unidad ?? ''}',
              r.observacion ?? '',
            ],
        ],
        anchos: const {
          0: pw.FixedColumnWidth(95),
          1: pw.FlexColumnWidth(3),
          2: pw.FixedColumnWidth(55),
          3: pw.FixedColumnWidth(55),
          4: pw.FlexColumnWidth(2),
        },
      ),
    ]);
    // Fotos, dos por fila, con su hora.
    final fotos = [
      for (final f in e.fotos)
        if (d.bytes[f.id] != null) f,
    ];
    if (fotos.isNotEmpty) {
      contenido.add(titulo('Fotos'));
      for (var k = 0; k < fotos.length; k += 2) {
        contenido.add(
          pw.Row(
            children: [
              for (final f in fotos.skip(k).take(2))
                pw.Expanded(
                  child: pw.Padding(
                    padding: const pw.EdgeInsets.all(4),
                    child: pw.Column(
                      children: [
                        pw.Image(
                          pw.MemoryImage(d.bytes[f.id]!),
                          height: 150,
                          fit: pw.BoxFit.contain,
                        ),
                        pw.Text(
                          '${_fechaHora(f.tomadaAt)} · sha256 ${f.sha256.substring(0, 12)}',
                          style: const pw.TextStyle(fontSize: 7, color: _gris),
                        ),
                      ],
                    ),
                  ),
                ),
              if (fotos.length - k == 1) pw.Expanded(child: pw.SizedBox()),
            ],
          ),
        );
      }
    }
    if (e.controles.isNotEmpty) {
      contenido.addAll([
        titulo('Control de fugas'),
        tabla(
          [
            'Método',
            'Detector',
            'Resultado',
            'Localización',
            'Reparada',
            'Nuevo control',
          ],
          [
            for (final c in e.controles)
              [
                c.metodo ?? '—',
                c.detectorModelo ?? '—',
                c.resultado == 'fuga' ? 'Fuga' : 'Sin fuga',
                c.localizacion ?? '',
                c.reparada == null ? '' : (c.reparada! ? 'Sí' : 'No'),
                c.recontrolDesde == null
                    ? ''
                    : 'Entre el ${fmt.fecha(c.recontrolDesde!)} y el ${fmt.fecha(c.recontrolHasta!)}',
              ],
          ],
        ),
      ]);
    }
    if (e.movimientos.isNotEmpty) {
      contenido.addAll([
        titulo('Movimientos de gas (art. 7)'),
        tabla(
          ['Tipo', 'Gas', 'kg', 'Origen', 'Gestor', 'Regla'],
          [
            for (final m in e.movimientos)
              [
                m.tipo,
                m.refrigerante,
                fmt.numero(m.kg, decimales: 3),
                m.origenGas ?? '',
                [?m.gestorNombre, ?m.gestorDocumento].join(' · '),
                m.reglaAplicada ?? '',
              ],
          ],
        ),
      ]);
    }
    if (e.incidencias.isNotEmpty) {
      contenido.addAll([
        titulo('Incidencias'),
        for (final inc in e.incidencias)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Text(
              '${_gravedad(inc.gravedad)}: ${inc.descripcion}'
              '${inc.accionRecomendada == null ? '' : ' · Acción: ${inc.accionRecomendada}'}'
              '${inc.plazoDias == null ? '' : ' · Plazo: ${inc.plazoDias} días'}'
              '${inc.paraEquipo ? ' · OBLIGA A PARAR EL EQUIPO' : ''}'
              '${inc.origen == 'ia' ? ' · Propuesta por IA, confirmada por el técnico' : ''}',
              style: pw.TextStyle(
                fontSize: 9,
                color: inc.gravedad == 'leve' ? PdfColors.black : _rojo,
              ),
            ),
          ),
      ]);
    }
    if (e.resoluciones.isNotEmpty) {
      contenido.add(
        pw.Text(
          '${e.resoluciones.length} incidencia(s) de visitas anteriores resuelta(s) en esta visita.',
          style: const pw.TextStyle(fontSize: 9),
        ),
      );
    }
  }

  // 7. Resumen y vencimientos.
  contenido.addAll([
    pw.NewPage(freeSpace: 220),
    titulo('Resumen'),
    pw.Text(i.resumenTexto ?? '—', style: const pw.TextStyle(fontSize: 10)),
    titulo('Próximos vencimientos'),
    tabla(
      ['Equipo', 'F-gas', 'RITE'],
      [
        for (final (n, f, r) in vencimientos) [n, f, r],
      ],
    ),
    // 8. Declaración (solo preventivos).
    if (d.tipoIntervencion == 'preventivo')
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 10),
        child: pw.Text(
          inst['manual_disponible'] == true
              ? 'Mantenido según el Manual de Uso y Mantenimiento de la instalación y la IT 3 del RITE.'
              : 'Mantenido según las operaciones de la Tabla 3.2 de la IT 3 del RITE.',
          style: pw.TextStyle(fontSize: 9, fontStyle: pw.FontStyle.italic),
        ),
      ),
    // 9. Firmas.
    titulo('Firmas'),
    pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (final rol in ['cliente', 'tecnico'])
          for (final f in d.firmas.where((f) => f.rol == rol))
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    rol == 'cliente' ? 'Por el titular' : 'Técnico',
                    style: const pw.TextStyle(fontSize: 8, color: _gris),
                  ),
                  if (d.bytes[f.id] != null)
                    pw.Image(pw.MemoryImage(d.bytes[f.id]!), height: 70),
                  pw.Text(
                    '${f.nombre}${f.cargo == null ? '' : ', ${f.cargo}'}',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                  pw.Text(
                    _fechaHora(f.firmadaAt),
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ],
              ),
            ),
      ],
    ),
    pw.SizedBox(height: 6),
    pw.Text(
      'Firma electrónica simple. El titular debe conservar este documento al '
      'menos 5 años (art. 27 RITE; art. 7 Reglamento (UE) 2024/573).',
      style: const pw.TextStyle(fontSize: 8, color: _gris),
    ),
  ]);

  doc.addPage(
    pw.MultiPage(
      maxPages: 200,
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 48),
        // 11. Marca de agua en la demo.
        buildBackground: d.esDemo
            ? (ctx) => pw.FullPage(
                ignoreMargins: true,
                child: pw.Center(
                  child: pw.Opacity(
                    opacity: 0.12,
                    child: pw.Transform.rotate(
                      angle: 0.6,
                      child: pw.Text(
                        'DATOS DE EJEMPLO FICTICIOS',
                        style: pw.TextStyle(
                          fontSize: 46,
                          color: _rojo,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              )
            : null,
      ),
      // 10. Pie: hash del contenido, versiones y conservación.
      footer: (ctx) => pw.Container(
        padding: const pw.EdgeInsets.only(top: 6),
        decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: _linea, width: 0.5)),
        ),
        child: pw.Row(
          children: [
            pw.Expanded(
              child: pw.Text(
                'Contenido sha256 ${contenidoSha.substring(0, 16)} · '
                'app ${i.appVersion ?? '—'} · normativa ${i.normativaVersion ?? '—'} · '
                '${i.numero ?? ''}',
                style: const pw.TextStyle(fontSize: 7, color: _gris),
              ),
            ),
            pw.Text(
              'Página ${ctx.pageNumber} de ${ctx.pagesCount}',
              style: const pw.TextStyle(fontSize: 7, color: _gris),
            ),
          ],
        ),
      ),
      build: (ctx) => contenido,
    ),
  );
  return doc.save();
}
