// Plantillas 1-3 (DISEÑO.md §4.1.4, §7.4, §12 día 2): se cargan los JSON
// reales con dart:io y se validan; ids deterministas; claves compartidas; y
// la regla de sugerencia (O2 y F2.2) con sus fronteras de la Tabla 3.1.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
// Con prefijo: Drift genera también `Plantilla` e `ItemPlantilla`.
import 'package:inspecta/data/local/app_database.dart' as db;
import 'package:inspecta/dominio/normativa.dart';
import 'package:inspecta/dominio/plantillas.dart';
import 'package:inspecta/dominio/tipos.dart';
import 'package:uuid/uuid.dart';

const _dir = 'assets/plantillas';

String _leer(String fichero) => File('$_dir/$fichero').readAsStringSync();

Map<String, dynamic> _crudo(String fichero) =>
    jsonDecode(_leer(fichero)) as Map<String, dynamic>;

/// Copia de [fichero] como versión [version] (ids deterministas y
/// `sustituye_a` coherentes), con [cambiar] aplicado antes de recalcular ids.
Map<String, dynamic> _otraVersion(
  String fichero,
  int version, [
  void Function(Map<String, dynamic> doc)? cambiar,
]) {
  final doc = _crudo(fichero);
  cambiar?.call(doc);
  final clave = doc['plantilla']['clave'] as String;
  final pid = idPlantilla(clave, version);
  doc['plantilla']
    ..['version'] = version
    ..['id'] = pid
    ..['sustituye_a'] = idPlantilla(clave, version - 1);
  for (final i in doc['items_plantilla'] as List) {
    (i as Map<String, dynamic>)
      ..['plantilla_id'] = pid
      ..['id'] = idItemPlantilla(clave, version, i['clave'] as String);
  }
  return doc;
}

Map<String, dynamic> _itemDe(Map<String, dynamic> doc, String clave) =>
    (doc['items_plantilla'] as List).cast<Map<String, dynamic>>().firstWhere(
      (i) => i['clave'] == clave,
    );

void main() {
  late Plantilla p1;
  late Plantilla p2;
  late Plantilla p3;
  late List<Plantilla> todas;
  // El umbral de 70 kW sale de la normativa versionada, como en rite.dart.
  late double umbral;

  setUpAll(() {
    umbral = parsearNormativa(
      File('assets/normativa/2026-11.json').readAsStringSync(),
    ).rite.umbralRegimenMensualKw;
    p1 = parsearPlantilla(_leer('split_hasta_12kw.v1.json'), origen: 'p1');
    p2 = parsearPlantilla(_leer('equipo_12_70kw.v1.json'), origen: 'p2');
    p3 = parsearPlantilla(_leer('control_fugas.v1.json'), origen: 'p3');
    todas = [p1, p2, p3];
  });

  group('JSON reales', () {
    test('en la carpeta están exactamente las tres plantillas', () {
      // Lo mismo que carga cargarPlantillasBase: solo los .json.
      final ficheros =
          Directory(_dir)
              .listSync()
              .whereType<File>()
              .map((f) => f.uri.pathSegments.last)
              .where((n) => n.endsWith('.json'))
              .toList()
            ..sort();
      expect(ficheros, [
        'control_fugas.v1.json',
        'equipo_12_70kw.v1.json',
        'split_hasta_12kw.v1.json',
      ]);
    });

    test('cargarPlantillasBase lee las tres del bundle (pubspec)', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final cargadas = await cargarPlantillasBase();
      expect([for (final p in cargadas) p.clave]..sort(), [
        'control_fugas',
        'equipo_12_70kw',
        'split_hasta_12kw',
      ]);
    });

    test('claves, versión, estado y número de ítems', () {
      expect(p1.clave, 'split_hasta_12kw');
      expect(p2.clave, 'equipo_12_70kw');
      expect(p3.clave, 'control_fugas');
      for (final p in todas) {
        expect(p.version, 1);
        expect(p.estado, EstadoPlantilla.publicada);
        expect(p.empresaId, isNull);
        expect(p.sustituyeA, isNull);
        expect(p.publicadaAt.isUtc, isTrue);
      }
      // El hito del día 4 cronometra «un checklist de 24 ítems» (§12).
      expect(p2.items, hasLength(24));
      expect(p1.items.length, inInclusiveRange(15, 22));
      expect(p3.items.length, inInclusiveRange(8, 16));
    });

    test('el nombre del fichero es <clave>.v<version>.json', () {
      for (final (f, p) in [
        ('split_hasta_12kw.v1.json', p1),
        ('equipo_12_70kw.v1.json', p2),
        ('control_fugas.v1.json', p3),
      ]) {
        expect(f, '${p.clave}.v${p.version}.json');
      }
    });

    test('las columnas del JSON son las de §7.4, tal cual', () {
      for (final f in [
        'split_hasta_12kw.v1.json',
        'equipo_12_70kw.v1.json',
        'control_fugas.v1.json',
      ]) {
        final doc = _crudo(f);
        final p = parsearPlantilla(_leer(f));
        // Ida y vuelta: el modelo reproduce el JSON sin perder nada.
        expect(p.toJson(), doc['plantilla'], reason: f);
        expect(
          [for (final i in p.items) i.toJson()],
          doc['items_plantilla'],
          reason: f,
        );
      }
    });

    test('las filas se siembran tal cual en Drift (fromJson por columna)', () {
      // §7.4: el JSON usa los nombres de columna de Drift y Postgres. El que
      // siembra solo añade created_at y updated_at (FilaSincronizada).
      const marcas = {
        'created_at': '2026-11-08T00:00:00.000Z',
        'updated_at': '2026-11-08T00:00:00.000Z',
      };
      for (final f in [
        'split_hasta_12kw.v1.json',
        'equipo_12_70kw.v1.json',
        'control_fugas.v1.json',
      ]) {
        final doc = _crudo(f);
        final fila = db.Plantilla.fromJson({
          ...doc['plantilla'] as Map<String, dynamic>,
          ...marcas,
        });
        final p = parsearPlantilla(_leer(f));
        expect(fila.id, p.id, reason: f);
        expect(fila.clave, p.clave, reason: f);
        expect(fila.estado, 'publicada', reason: f);
        expect(fila.publicadaAt, p.publicadaAt, reason: f);
        expect(jsonDecode(fila.aplicaA), p.aplicaA.toJson(), reason: f);
        for (final crudo in doc['items_plantilla'] as List) {
          final i = db.ItemPlantilla.fromJson({
            ...crudo as Map<String, dynamic>,
            ...marcas,
          });
          final dom = p.item(i.clave)!;
          expect(i.id, dom.id);
          expect(i.tipoRespuesta, dom.tipoRespuesta.wire);
          expect(i.rangoMin, dom.rangoMin);
          expect(i.rangoMax, dom.rangoMax);
          expect(i.fotoObligatoria, dom.fotoObligatoria);
          expect(i.analizableIa, dom.analizableIa);
        }
      }
    });

    test('ítems ordenados 1..n y con texto corto', () {
      for (final p in todas) {
        expect([
          for (final i in p.items) i.orden,
        ], List.generate(p.items.length, (n) => n + 1));
        for (final i in p.items) {
          expect(i.texto.length, lessThanOrEqualTo(80), reason: i.clave);
          expect(i.codigoNormativo, isNotEmpty, reason: i.clave);
        }
      }
    });

    test('mediciones con unidad y rango plausible; el resto sin ellos', () {
      for (final p in todas) {
        for (final i in p.items) {
          if (i.tipoRespuesta.llevaValor) {
            expect(i.unidad, isNotNull, reason: i.clave);
            expect(i.rangoMin! < i.rangoMax!, isTrue, reason: i.clave);
          } else {
            expect(i.unidad, isNull, reason: i.clave);
            expect(i.rangoMin, isNull, reason: i.clave);
          }
        }
      }
      expect(p2.item('salto_termico')!.unidad, 'K');
      // Manométricas: el último valor se compara entre visitas por clave.
      expect(p2.item('presion_alta')!.unidad, 'bar (man.)');
      expect(p3.item('presion_baja')!.unidad, 'bar (man.)');
      expect(p2.item('presion_alta')!.texto, contains('manométrica'));
      expect(p2.item('temp_impulsion')!.unidad, '°C');
      expect(p2.item('intensidad_absorbida')!.fueraDeRango(200), isTrue);
      expect(p2.item('intensidad_absorbida')!.fueraDeRango(20), isFalse);
    });

    test('operaciones de la Tabla 3.2 b) del RITE en la 1 y la 2', () {
      for (final p in [p1, p2]) {
        expect(
          p.item('filtro_limpieza')!.codigoNormativo,
          'RITE IT 3.3 Tabla 3.2 b) 4',
        );
        expect(
          p.item('evaporador_limpieza')!.codigoNormativo,
          'RITE IT 3.3 Tabla 3.2 b) 1',
        );
        expect(
          p.item('estanquidad_refrigerante')!.codigoNormativo,
          'RITE IT 3.3 Tabla 3.2 b) 3',
        );
      }
      expect(
        p2.item('recuperador_calor')!.codigoNormativo,
        'RITE IT 3.3 Tabla 3.2 b) 6',
      );
    });

    test('etiqueta F-gas: en las tres, con foto y sin IA (§3.2, §9.3)', () {
      for (final p in todas) {
        final e = p.item(claveEtiquetaFgas);
        expect(e, isNotNull, reason: p.clave);
        expect(e!.fotoObligatoria, isTrue);
        expect(e.analizableIa, isFalse);
        expect(e.tipoRespuesta, TipoRespuesta.estado);
        expect(e.codigoNormativo, contains('2024/573 art. 12'));
        // Art. 12.1: solo aparatos «que contengan gases fluorados». Un split
        // de R-290 se marca N.A. y entonces no exige foto.
        expect(e.texto, contains('si el gas es fluorado'));
        expect(e.exigeFoto(marcadoNa: false), isTrue);
        expect(e.exigeFoto(marcadoNa: true), isFalse);
      }
    });

    test('ninguna medición obligatoria es solo_valor (sin N.A., F4.1)', () {
      for (final p in todas) {
        for (final i in p.items) {
          if (i.obligatorio) {
            expect(
              i.tipoRespuesta,
              isNot(TipoRespuesta.soloValor),
              reason: '${p.clave}:${i.clave}',
            );
          }
        }
      }
      for (final p in [p1, p2]) {
        for (final c in ['temp_retorno', 'temp_impulsion']) {
          expect(p.item(c)!.tipoRespuesta, TipoRespuesta.estadoValor);
        }
      }
    });

    test('códigos normativos que no atribuyen a la norma lo que no dice', () {
      // Tabla 3.2 b) 8 es «unidades terminales de distribución de aire»; los
      // conductos son la operación 37 de la Tabla 3.3 de la IT 3.3.
      final conductos = p2.item('conductos_aire')!.codigoNormativo;
      expect(conductos, isNot(contains('b) 8')));
      expect(conductos, contains('IT 3.3 Tabla 3.3, 37'));
      expect(
        p2.item('unidades_terminales')!.codigoNormativo,
        'RITE IT 3.3 Tabla 3.2 b) 8',
      );
      // La fila 7 de la IT 3.4.2 es potencia (kW), no intensidad (A).
      for (final p in [p1, p2]) {
        final i = p.item('intensidad_absorbida')!;
        expect(i.unidad, 'A');
        expect(i.codigoNormativo, isNot(contains('Tabla 3.3, 7')));
        expect(i.codigoNormativo, contains('intensidad por fase'));
      }
      // Art. 6.3: solo obliga a los sistemas exigidos por el art. 6.1-6.2.
      final det = p3.item('sistema_deteccion')!.codigoNormativo;
      expect(det, contains('art. 6.3 si es obligatorio'));
      expect(det, contains('buena práctica'));
    });

    test(
      'presión de baja de la 3: admite la aspiración de baja temperatura',
      () {
        // R-404A a -40 °C ≈ 0,3 bar man.; R-448A/R-449A ≈ 0 bar man.
        final baja = p3.item('presion_baja')!;
        expect(baja.fueraDeRango(0.3), isFalse);
        expect(baja.fueraDeRango(0.0), isFalse);
        expect(baja.fueraDeRango(-0.3), isFalse);
        expect(baja.fueraDeRango(-1.0), isTrue);
        // En la 2 (aire acondicionado) el rango sigue siendo el de R-410A/R-32.
        expect(p2.item('presion_baja')!.fueraDeRango(0.3), isTrue);
      },
    );

    test('analizable_ia solo en ítems de inspección visual (§9.3)', () {
      for (final p in todas) {
        for (final i in p.items) {
          if (i.analizableIa) {
            expect(i.tipoRespuesta, TipoRespuesta.estado, reason: i.clave);
          }
        }
      }
      expect(p1.item('filtro_limpieza')!.analizableIa, isTrue);
      expect(p2.item('bandeja_condensados')!.analizableIa, isTrue);
      expect(p2.item('salto_termico')!.analizableIa, isFalse);
    });

    test('la 3 no duplica los datos de controles_fugas (§7.5, T11)', () {
      // Método, detector (modelo, calibración y su comprobación), resultado,
      // localización y reparación van a controles_fugas; en el checklist no
      // hay ítems de esos datos (por prefijo: también `detector_verificado`).
      const prefijosT11 = [
        'metodo',
        'detector_',
        'resultado',
        'localizacion',
        'reparad',
        'reparacion',
        'fecha_reparacion',
        'recontrol_',
        'eficaz',
      ];
      for (final p in todas) {
        for (final i in p.items) {
          for (final pre in prefijosT11) {
            expect(i.clave.startsWith(pre), isFalse, reason: i.clave);
          }
        }
      }
      expect(p3.item('detector_verificado'), isNull);
      // `sistema_deteccion` es el sistema fijo del aparato (art. 6), no el
      // detector portátil del técnico: ese sí es un ítem.
      expect(p3.item('sistema_deteccion'), isNotNull);
      expect(p3.aplicaA.potenciaInstalacionMaxKw, isNull);
      expect(p3.aplicaA.potenciaMaxKw, isNull);
      expect(p3.aplicaA.tipos, containsAll(TipoEquipo.values));
    });
  });

  group('ids deterministas (UUID v5)', () {
    test('el namespace es v5(URL, "urn:inspecta:plantillas")', () {
      expect(
        const Uuid().v5(Namespace.url.value, 'urn:inspecta:plantillas'),
        namespacePlantillas,
      );
    });

    test('los ids del JSON son los calculados', () {
      for (final p in todas) {
        expect(p.id, idPlantilla(p.clave, p.version));
        for (final i in p.items) {
          expect(i.id, idItemPlantilla(p.clave, p.version, i.clave));
          expect(i.plantillaId, p.id);
        }
      }
    });

    test('ningún id se repite entre plantillas', () {
      final ids = [
        for (final p in todas) ...[p.id, for (final i in p.items) i.id],
      ];
      expect(ids.toSet().length, ids.length);
    });

    test('el id cambia con la versión', () {
      expect(
        idPlantilla('control_fugas', 1),
        isNot(idPlantilla('control_fugas', 2)),
      );
      expect(
        idItemPlantilla('control_fugas', 1, 'etiqueta_fgas'),
        isNot(idItemPlantilla('control_fugas', 2, 'etiqueta_fgas')),
      );
    });
  });

  group('claves compartidas', () {
    test('la 1 y la 2 comparten las claves de la misma operación', () {
      final c1 = {for (final i in p1.items) i.clave};
      final c2 = {for (final i in p2.items) i.clave};
      // Todo lo de la 1 está en la 2: el equipo que cambia de franja
      // conserva su «último valor» (estado_equipo.ultimos_valores_json).
      expect(c2.containsAll(c1), isTrue, reason: '${c1.difference(c2)}');
      expect(
        c1,
        containsAll([
          'filtro_limpieza',
          'evaporador_limpieza',
          'condensador_limpieza',
          'salto_termico',
          'temp_impulsion',
          'temp_retorno',
          'intensidad_absorbida',
          'etiqueta_fgas',
        ]),
      );
      // Y lo de más en la 2 es propio de equipos grandes.
      expect(
        c2.difference(c1),
        containsAll(['conductos_aire', 'presion_alta', 'presion_baja']),
      );
    });

    test('una clave compartida tiene el mismo tipo y unidad en todas', () {
      final vistas = <String, ItemPlantilla>{};
      for (final p in todas) {
        for (final i in p.items) {
          final otra = vistas[i.clave];
          if (otra == null) {
            vistas[i.clave] = i;
            continue;
          }
          expect(i.tipoRespuesta, otra.tipoRespuesta, reason: i.clave);
          expect(i.unidad, otra.unidad, reason: i.clave);
          expect(i.codigoNormativo, otra.codigoNormativo, reason: i.clave);
        }
      }
      // La 3 reutiliza las presiones de la 2 para el «último valor».
      expect(p3.item('presion_baja'), isNotNull);
      // Y la misma comprobación que hace cargarPlantillasBase.
      expect(() => comprobarClavesCompartidas(todas), returnsNormally);
    });

    PlantillaInvalida? fallo(List<Plantilla> l) {
      try {
        comprobarClavesCompartidas(l);
        return null;
      } on PlantillaInvalida catch (e) {
        return e;
      }
    }

    test('unidad distinta de una clave: rechazada también entre versiones', () {
      final v2 = parsearPlantilla(
        jsonEncode(
          _otraVersion('equipo_12_70kw.v1.json', 2, (d) {
            _itemDe(d, 'presion_alta')['unidad'] = 'bar';
          }),
        ),
      );
      // Aunque la v1 ya no se ofrezca, sus valores siguen en
      // ultimos_valores_json con la unidad antigua.
      expect(
        fallo([p1, p2, v2, p3])?.mensaje,
        allOf(contains('presion_alta'), contains('unidad')),
      );
    });

    test(
      'código distinto: rechazado entre vigentes, admitido entre versiones',
      () {
        final v2 = parsearPlantilla(
          jsonEncode(
            _otraVersion('equipo_12_70kw.v1.json', 2, (d) {
              _itemDe(d, 'filtro_limpieza')['codigo_normativo'] = 'Otro código';
            }),
          ),
        );
        // La v2 de la 2 y la v1 de la 1 son vigentes a la vez: conflicto.
        expect(
          fallo([p1, p2, v2, p3])?.mensaje,
          allOf(contains('filtro_limpieza'), contains('codigo_normativo')),
        );
        // Solo la 2 en dos versiones: la v1 queda sustituida, no hay conflicto.
        expect(fallo([p2, v2]), isNull);
      },
    );

    test('tipo_respuesta distinto entre vigentes: rechazado', () {
      final v2 = parsearPlantilla(
        jsonEncode(
          _otraVersion('control_fugas.v1.json', 2, (d) {
            _itemDe(d, 'presion_baja')['tipo_respuesta'] = 'solo_valor';
          }),
        ),
      );
      expect(
        fallo([p2, p3, v2])?.mensaje,
        allOf(contains('presion_baja'), contains('tipo_respuesta')),
      );
    });
  });

  group('sugerirPlantillas', () {
    SugerenciaPlantillas sugerir({
      TipoEquipo tipo = TipoEquipo.split,
      required double? equipo,
      required double instalacion,
      UsoEdificio uso = UsoEdificio.otros,
      TipoIntervencion intervencion = TipoIntervencion.preventivo,
    }) => sugerirPlantillas(
      umbralRegimenMensualKw: umbral,
      tipo: tipo,
      potenciaEquipoKw: equipo,
      potenciaInstalacionKw: instalacion,
      uso: uso,
      intervencion: intervencion,
      plantillas: todas,
    );

    test('split de 3,5 kW en vivienda → plantilla 1', () {
      final s = sugerir(
        equipo: 3.5,
        instalacion: 3.5,
        uso: UsoEdificio.vivienda,
      );
      expect(s.plantillas, [p1]);
      expect(s.avisos, isEmpty);
    });

    test('rooftop de 30 kW en instalación de 60 kW → plantilla 2', () {
      final s = sugerir(tipo: TipoEquipo.rooftop, equipo: 30, instalacion: 60);
      expect(s.plantillas, [p2]);
      expect(s.avisos, isEmpty);
    });

    test('Tabla 3.1: split de exactamente 12 kW → 1 («Pn ≤ 12 kW»)', () {
      expect(sugerir(equipo: 12, instalacion: 12).plantillas, [p1]);
      expect(sugerir(equipo: 12.01, instalacion: 20).plantillas, [p2]);
    });

    test('Tabla 3.1: instalación de exactamente 70 kW sigue en ≤ 70', () {
      final s = sugerir(tipo: TipoEquipo.vrf, equipo: 40, instalacion: 70);
      expect(s.plantillas, [p2]);
      expect(s.avisos, isEmpty);
    });

    test('cualquier equipo en instalación de 75 kW → solo la 3 y aviso', () {
      for (final tipo in TipoEquipo.values) {
        for (final kw in [null, 3.5, 12.0, 30.0]) {
          final s = sugerir(tipo: tipo, equipo: kw, instalacion: 75);
          expect(s.plantillas, [p3], reason: '$tipo $kw');
          expect(s.avisos, [AvisoPlantillas.preventivoRiteFueraMvp]);
          expect(s.plantillas, isNot(contains(p1)));
          expect(s.plantillas, isNot(contains(p2)));
        }
      }
    });

    test('10 splits de 10 kW en un hotel (100 kW) → nunca la 1', () {
      final s = sugerir(equipo: 10, instalacion: 100);
      expect(s.plantillas, [p3]);
      expect(s.avisos, [AvisoPlantillas.preventivoRiteFueraMvp]);
    });

    test('equipo mayor que la instalación declarada → manda el equipo', () {
      final s = sugerir(tipo: TipoEquipo.rooftop, equipo: 80, instalacion: 60);
      expect(s.plantillas, [p3]);
      expect(s.avisos, [AvisoPlantillas.preventivoRiteFueraMvp]);
    });

    test('control de fugas sugerido siempre que se pide', () {
      for (final tipo in TipoEquipo.values) {
        for (final uso in UsoEdificio.values) {
          for (final inst in [3.5, 60.0, 75.0, 2000.0]) {
            final s = sugerir(
              tipo: tipo,
              equipo: null,
              instalacion: inst,
              uso: uso,
              intervencion: TipoIntervencion.controlFugas,
            );
            expect(s.plantillas, [p3], reason: '$tipo $uso $inst');
            expect(s.avisos, isEmpty);
          }
        }
      }
    });

    test('nuevo control tras reparar → la 3 con aviso (plantilla 4 fuera)', () {
      final s = sugerir(
        equipo: 7,
        instalacion: 7,
        intervencion: TipoIntervencion.recontrolFugas,
      );
      expect(s.plantillas, [p3]);
      expect(s.avisos, [AvisoPlantillas.recontrolConPlantillaControlFugas]);
    });

    test('sin potencia del equipo en 30 kW → la 2 y la 1, con aviso', () {
      // La instalación es la cota superior del equipo: cabe en las dos
      // franjas; primero la de 30 kW, la fila que usa rite.dart.
      final s = sugerir(equipo: null, instalacion: 30);
      expect(s.plantillas, [p2, p1]);
      expect(s.avisos, [AvisoPlantillas.potenciaEquipoDesconocida]);
    });

    test('sin potencia del equipo en ≤ 12 kW → solo la 1 (como rite.dart)', () {
      for (final inst in [3.5, 12.0]) {
        final s = sugerir(equipo: null, instalacion: inst);
        expect(s.plantillas, [p1], reason: '$inst');
        expect(s.recomendada, p1);
        expect(s.avisos, [AvisoPlantillas.potenciaEquipoDesconocida]);
      }
      // Justo por encima de 12 kW el equipo puede estar en cualquiera.
      expect(sugerir(equipo: null, instalacion: 12.5).plantillas, [p2, p1]);
    });

    test(
      'sin ninguna potencia (0 kW) → la 2 y la 1, la más completa antes',
      () {
        final s = sugerir(equipo: null, instalacion: 0);
        expect(s.plantillas, [p2, p1]);
        expect(s.avisos, [AvisoPlantillas.potenciaEquipoDesconocida]);
      },
    );

    test('el umbral de las plantillas 1 y 2 es el de la normativa', () {
      // rite.dart decide el régimen con umbral_regimen_mensual_kw; si cambia,
      // hace falta una v2 de la 1 y la 2 con su potencia_instalacion_max_kw.
      expect(umbral, 70);
      for (final p in [p1, p2]) {
        expect(p.aplicaA.potenciaInstalacionMaxKw, umbral, reason: p.clave);
      }
    });

    test('manda el umbral recibido, no una constante', () {
      SugerenciaPlantillas con(double u, List<Plantilla> l) =>
          sugerirPlantillas(
            umbralRegimenMensualKw: u,
            tipo: TipoEquipo.rooftop,
            potenciaEquipoKw: 30,
            potenciaInstalacionKw: 80,
            uso: UsoEdificio.otros,
            intervencion: TipoIntervencion.preventivo,
            plantillas: l,
          );
      // Con 70 kW, 80 kW es régimen mensual.
      expect(con(70, todas).avisos, [AvisoPlantillas.preventivoRiteFueraMvp]);
      // Si la normativa sube el umbral a 100 kW y hay una v2 de la 2 que
      // cubre instalaciones de hasta 100 kW, se ofrece esa v2.
      final p2v2 = parsearPlantilla(
        jsonEncode(
          _otraVersion('equipo_12_70kw.v1.json', 2, (d) {
            d['plantilla']['aplica_a']['potencia_instalacion_max_kw'] = 100.0;
          }),
        ),
      );
      final s = con(100, [p1, p2, p2v2, p3]);
      expect(s.plantillas, [p2v2]);
      expect(s.avisos, isEmpty);
      // Sin esa v2 no se finge: ninguna plantilla cubre esa potencia.
      final sin = con(100, todas);
      expect(sin.plantillas, isEmpty);
      expect(sin.avisos, [AvisoPlantillas.potenciaSinPlantilla]);
    });

    test('enfriadora en ≤ 70 kW → sin preventivo y con aviso', () {
      final s = sugerir(
        tipo: TipoEquipo.enfriadora,
        equipo: 40,
        instalacion: 40,
      );
      expect(s.plantillas, isEmpty);
      expect(s.avisos, [AvisoPlantillas.tipoSinPlantillaPreventiva]);
    });

    test('puesta en marcha → sin plantilla y con aviso', () {
      final s = sugerir(
        equipo: 5,
        instalacion: 5,
        intervencion: TipoIntervencion.puestaMarcha,
      );
      expect(s.plantillas, isEmpty);
      expect(s.avisos, [AvisoPlantillas.intervencionSinPlantilla]);
    });

    test('con dos versiones se ofrece la más alta', () {
      final p3v2 = parsearPlantilla(
        jsonEncode(_otraVersion('control_fugas.v1.json', 2)),
      );
      final s = sugerirPlantillas(
        umbralRegimenMensualKw: umbral,
        tipo: TipoEquipo.split,
        potenciaEquipoKw: 5,
        potenciaInstalacionKw: 5,
        uso: UsoEdificio.vivienda,
        intervencion: TipoIntervencion.controlFugas,
        plantillas: [p3, p3v2, p1, p2],
      );
      expect(s.plantillas.single.version, 2);
    });

    test('potencias negativas o no finitas → ArgumentError', () {
      expect(() => sugerir(equipo: 5, instalacion: -1), throwsArgumentError);
      expect(
        () => sugerir(equipo: double.nan, instalacion: 5),
        throwsArgumentError,
      );
      expect(
        () => sugerirPlantillas(
          umbralRegimenMensualKw: 0,
          tipo: TipoEquipo.split,
          potenciaEquipoKw: 5,
          potenciaInstalacionKw: 5,
          uso: UsoEdificio.vivienda,
          intervencion: TipoIntervencion.preventivo,
          plantillas: todas,
        ),
        throwsArgumentError,
      );
    });
  });

  group('JSON inválidos rechazados con mensaje claro', () {
    Map<String, dynamic> base() => _crudo('equipo_12_70kw.v1.json');
    List<Map<String, dynamic>> items(Map<String, dynamic> d) =>
        (d['items_plantilla'] as List).cast<Map<String, dynamic>>();

    void rechaza(Map<String, dynamic> doc, String fragmento) {
      expect(
        () => parsearPlantilla(jsonEncode(doc), origen: 'prueba.json'),
        throwsA(
          isA<PlantillaInvalida>().having(
            (e) => e.mensaje,
            'mensaje',
            allOf(contains('prueba.json'), contains(fragmento)),
          ),
        ),
      );
    }

    test('clave de ítem duplicada', () {
      final d = base();
      final it = items(d);
      // Misma clave y su id determinista, para que falle por la clave.
      it[1]['clave'] = it[0]['clave'];
      it[1]['id'] = it[0]['id'];
      rechaza(d, 'clave de ítem duplicada «filtro_limpieza» (órdenes 1 y 2)');
    });

    test('rango invertido', () {
      final d = base();
      final salto = items(d).firstWhere((i) => i['clave'] == 'salto_termico');
      salto['rango_min'] = 30.0;
      salto['rango_max'] = 0.0;
      rechaza(d, 'rango invertido');
    });

    test('rango vacío (min = max)', () {
      final d = base();
      final salto = items(d).firstWhere((i) => i['clave'] == 'salto_termico');
      salto['rango_max'] = salto['rango_min'];
      rechaza(d, 'rango invertido o vacío');
    });

    test('tipo_respuesta desconocido', () {
      final d = base();
      items(d)[0]['tipo_respuesta'] = 'texto_libre';
      rechaza(d, 'tipo_respuesta desconocido «texto_libre»');
    });

    test('ítem de valor sin unidad', () {
      final d = base();
      items(d).firstWhere((i) => i['clave'] == 'presion_alta')['unidad'] = null;
      rechaza(d, 'necesita unidad');
    });

    test('ítem de estado con rango', () {
      final d = base();
      items(d)[0]['rango_min'] = 1.0;
      rechaza(d, 'no lleva unidad ni rango');
    });

    test('orden repetido', () {
      final d = base();
      items(d)[3]['orden'] = 1;
      rechaza(d, 'orden 1 repetido');
    });

    test('orden con huecos', () {
      final d = base();
      items(d).last['orden'] = 99;
      rechaza(d, 'falta el 24');
    });

    test('id de plantilla no determinista', () {
      final d = base();
      d['plantilla']['id'] = '00000000-0000-0000-0000-000000000000';
      rechaza(d, 'debe ser «${idPlantilla('equipo_12_70kw', 1)}»');
    });

    test('id de ítem no determinista', () {
      final d = base();
      items(d)[0]['id'] = '00000000-0000-0000-0000-000000000000';
      rechaza(d, 'no es el determinista');
    });

    test('estado distinto de publicada', () {
      final d = base();
      d['plantilla']['estado'] = 'borrador';
      rechaza(d, 'solo se siembran versiones publicadas');
    });

    test('columna de más (no se podría sembrar tal cual)', () {
      final d = base();
      items(d)[0]['comentario'] = 'hola';
      rechaza(d, 'sobran comentario');
    });

    test('columna de menos', () {
      final d = base();
      items(d)[0].remove('analizable_ia');
      rechaza(d, 'faltan analizable_ia');
    });

    test('tipo de equipo desconocido en aplica_a', () {
      final d = base();
      d['plantilla']['aplica_a']['tipos'] = ['split', 'cassette'];
      rechaza(d, 'tipos «cassette» desconocido');
    });

    test('franja de potencia invertida en aplica_a', () {
      final d = base();
      d['plantilla']['aplica_a']['potencia_min_kw'] = 80.0;
      rechaza(d, 'debe ser menor que potencia_max_kw');
    });

    test('v2 con sustituye_a que no es la v1', () {
      final d = base();
      d['plantilla']
        ..['version'] = 2
        ..['id'] = idPlantilla('equipo_12_70kw', 2);
      rechaza(d, 'sustituye_a debe ser el id de la v1');
    });

    test('solo_valor obligatorio (no tiene N.A.)', () {
      final d = base();
      _itemDe(d, 'temp_retorno')['tipo_respuesta'] = 'solo_valor';
      rechaza(d, 'un ítem solo_valor no puede ser obligatorio');
    });

    test('solo_valor opcional sí vale', () {
      final d = base();
      expect(_itemDe(d, 'temp_exterior')['tipo_respuesta'], 'solo_valor');
      expect(_itemDe(d, 'temp_exterior')['obligatorio'], isFalse);
      expect(() => parsearPlantilla(jsonEncode(d)), returnsNormally);
    });

    test('analizable_ia en un ítem de valor', () {
      final d = base();
      _itemDe(d, 'temp_retorno')['analizable_ia'] = true;
      rechaza(d, 'analizable_ia solo en ítems de tipo estado');
    });

    test('analizable_ia en la etiqueta F-gas', () {
      final d = base();
      _itemDe(d, claveEtiquetaFgas)['analizable_ia'] = true;
      rechaza(d, 'la etiqueta F-gas no es analizable');
    });

    test('JSON mal formado', () {
      expect(
        () => parsearPlantilla('{"plantilla": ', origen: 'roto.json'),
        throwsA(
          isA<PlantillaInvalida>().having(
            (e) => e.mensaje,
            'mensaje',
            contains('roto.json: JSON mal formado'),
          ),
        ),
      );
    });
  });
}
