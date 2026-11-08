import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inspecta/data/local/app_database.dart';
import 'package:inspecta/data/sync/mapper.dart';
import 'package:inspecta/dominio/tipos.dart';

// Prueba de ida y vuelta Drift↔JSON de PostgREST (DISEÑO.md §8.2, «Mappers
// Drift↔Postgres», y hito del día 2 en §12): decide si basta con
// `use_sql_column_name_as_json_key` + el mapper genérico o si hace falta el
// plan B de mappers a mano.

/// Lo que haría la red: el payload sale como texto y vuelve a decodificarse.
Map<String, dynamic> porLaRed(Map<String, dynamic> json) =>
    (jsonDecode(jsonEncode(json)) as Map).cast<String, dynamic>();

/// Columnas `jsonb` de §7 (las que se guardan como texto JSON en local).
const columnasJsonb = {
  'plantillas.aplica_a',
  'inspecciones.datos_cabecera_json',
  'inspecciones.gps_inicio',
  'inspecciones.gps_firma',
  'inspeccion_equipos.datos_equipo_json',
  'propuestas_ia.resultado_json',
  'decisiones_ia.valor_final_json',
  'estado_equipo.ultimos_valores_json',
  'estado_equipo.incidencias_abiertas_json',
  'fotos.gps',
  'firmas.gps',
};

/// Enums de `lib/dominio/tipos.dart`: un valor wire que no es el primero, para
/// que un `index` en vez del `wire` no pase por casualidad.
final enumsWire = {
  'equipos.tipo': TipoEquipo.bombaCalor.wire,
  'equipos.categoria_fgas': CategoriaFgas.aireAcondicionadoBombaCalor.wire,
  'instalaciones.uso_edificio': UsoEdificio.vivienda.wire,
};

/// jsonb que no son un mapa, para la pasada [filaDeEjemplo] `variante`: un
/// `jsonb` de PostgREST puede ser cualquier valor JSON, y un escalar de
/// texto llega como `String` de Dart (ver `Jsonb` en conversores.dart).
const jsonbNoMapa = <Object>[
  'Filtro sucio',
  [
    1,
    'dos',
    {'tres': 3},
  ],
  12.5,
  false,
];

/// Una fila de ejemplo de [tabla] tal como la devolvería PostgREST, generada
/// desde las columnas de Drift, y el JSON que debe salir al subirla.
///
/// Con [variante], la otra cara: todas las columnas nulas a null, los bool a
/// `false` y los jsonb no nulos como escalar o lista. Así un conversor que
/// devuelva siempre lo mismo, un `asNullable` roto o un jsonb escalar mal
/// guardado no pasan por casualidad.
({Map<String, dynamic> delServidor, Map<String, dynamic> haciaServidor})
filaDeEjemplo(TableInfo tabla, {bool variante = false}) {
  final delServidor = <String, dynamic>{};
  final haciaServidor = <String, dynamic>{};
  var n = 0;
  for (final c in tabla.$columns) {
    n++;
    final clave = '${tabla.actualTableName}.${c.$name}';
    final convertida = c is GeneratedColumnWithTypeConverter;
    final (Object? entra, Object? sale) = switch (c.type) {
      _ when variante && c.$nullable => (null, null),
      _ when enumsWire.containsKey(clave) => (
        enumsWire[clave]!,
        enumsWire[clave]!,
      ),
      // jsonb: llega ya decodificado y sale decodificado.
      DriftSqlType.string when convertida && variante => (
        jsonbNoMapa[n % jsonbNoMapa.length],
        jsonbNoMapa[n % jsonbNoMapa.length],
      ),
      DriftSqlType.string when convertida => (
        {'lat': 40.4168, 'lon': -3.7038, 'precision': 5, 'n': n},
        {'lat': 40.4168, 'lon': -3.7038, 'precision': 5, 'n': n},
      ),
      DriftSqlType.string => ('${c.$name}-$n', '${c.$name}-$n'),
      // `date`: viaja como `AAAA-MM-DD` en los dos sentidos.
      DriftSqlType.dateTime when convertida => ('2026-03-31', '2026-03-31'),
      // `timestamptz`: llega con offset y sale en UTC con `Z`.
      DriftSqlType.dateTime => (
        '2026-11-08T09:30:15.123456+02:00',
        '2026-11-08T07:30:15.123456Z',
      ),
      // `numeric`: PostgREST puede mandarlo como cadena.
      DriftSqlType.double => ('12.50', 12.5),
      DriftSqlType.int => (n, n),
      DriftSqlType.bool when variante => ('f', false),
      DriftSqlType.bool => (true, true),
      _ => throw UnsupportedError('${c.type} en $clave'),
    };
    delServidor[c.$name] = entra;
    haciaServidor[c.$name] = sale;
  }
  for (final columna in columnasSoloServidor[tabla.actualTableName] ?? {}) {
    haciaServidor.remove(columna);
  }
  return (delServidor: delServidor, haciaServidor: haciaServidor);
}

/// Una [FormatException] cuyo mensaje nombra la tabla y el id de la fila.
Matcher errorDeFila(String tabla, Object? id) => throwsA(
  isA<FormatException>().having(
    (e) => e.message,
    'message',
    allOf(contains(tabla), contains('$id')),
  ),
);

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Iterable<TableInfo<Table, DataClass>> sincronizadas() => db.allTables
      .where((t) => !tablasLocales.contains(t.actualTableName))
      .cast<TableInfo<Table, DataClass>>();

  test('el mapper conoce exactamente las tablas sincronizadas de la base', () {
    expect(
      constructoresDesdeJson.keys.toSet(),
      sincronizadas().map((t) => t.actualTableName).toSet(),
    );
    expect(constructoresDesdeJson, hasLength(26));
  });

  test('las columnas jsonb son las de §7 y todas llevan conversor', () {
    final conConversorDeTexto = {
      for (final t in sincronizadas())
        for (final c in t.$columns)
          if (c is GeneratedColumnWithTypeConverter &&
              c.type == DriftSqlType.string)
            '${t.actualTableName}.${c.$name}',
    };
    expect(
      conConversorDeTexto.difference(enumsWire.keys.toSet()),
      columnasJsonb,
    );
  });

  group('inspecciones (gps, jsonb y fechas): hito del día 2', () {
    final inspeccion = Inspeccion(
      id: '6f1c1d2e-7a4b-4c1e-9a7e-2d4f5b6c7d8e',
      createdAt: DateTime.utc(2026, 11, 8, 8, 0),
      updatedAt: DateTime.utc(2026, 11, 8, 9, 45, 1, 250, 777),
      empresaId: 'e1',
      ordenId: 'o1',
      tecnicoId: 'm1',
      numero: '2026-JLM-A-0042',
      version: 1,
      iniciadaAt: DateTime.utc(2026, 11, 8, 8, 3, 12, 345, 678),
      firmadaAt: DateTime.utc(2026, 11, 8, 9, 44, 59),
      gpsInicio: jsonEncode({
        'lat': 43.3614,
        'lon': -5.8494,
        'precision': 12.5,
      }),
      gpsFirma: jsonEncode({'motivo': 'sin_senal'}),
      estado: 'firmada',
      nEquipos: 2,
      nFotos: 9,
      pdfSha256: 'ab' * 32,
      datosCabeceraJson: jsonEncode({
        'empresa': {'razon_social': 'Climas Norte SL', 'cif': 'B00000000'},
        'tecnico': {'nombre': 'J. L. M.', 'carne_rite': 'RITE-123'},
        'equipos': [1, 2],
      }),
    );

    test('fila Drift → JSON de PostgREST → la misma fila', () async {
      final json = aJsonPostgrest('inspecciones', inspeccion);

      // Las claves son exactamente las columnas SQL, salvo la del servidor.
      final columnas = db.inspecciones.$columns.map((c) => c.$name).toSet();
      expect(json.keys.toSet(), columnas.difference({'sincronizada_at'}));

      // jsonb decodificado (si fuera texto, Postgres guardaría una cadena).
      expect(json['gps_inicio'], {
        'lat': 43.3614,
        'lon': -5.8494,
        'precision': 12.5,
      });
      expect(json['gps_firma'], {'motivo': 'sin_senal'});
      expect((json['datos_cabecera_json'] as Map)['equipos'], [1, 2]);
      // Instantes en ISO-8601 UTC, con los microsegundos de Postgres.
      expect(json['iniciada_at'], '2026-11-08T08:03:12.345678Z');
      expect(json['updated_at'], '2026-11-08T09:45:01.250777Z');
      expect(json['finalizada_at'], isNull);
      expect(json['n_equipos'], 2);

      final vuelta = desdeJsonPostgrest<Inspeccion>(
        'inspecciones',
        porLaRed(json),
      );
      expect(vuelta, inspeccion);

      // Y la fila sobrevive a SQLite (fechas como texto, jsonb como texto).
      await db.into(db.inspecciones).insert(vuelta);
      expect(await db.select(db.inspecciones).getSingle(), inspeccion);
    });

    test('JSON como lo devuelve PostgREST → fila correcta', () {
      final delServidor = {
        ...porLaRed(aJsonPostgrest('inspecciones', inspeccion)),
        // timestamptz con offset, como lo serializa Postgres.
        'iniciada_at': '2026-11-08T08:03:12.345678+00:00',
        'firmada_at': '2026-11-08T10:44:59+01:00',
        'sincronizada_at': '2026-11-08T09:50:00.5+00:00',
        // Postgres reordena las claves de un jsonb.
        'gps_inicio': {'lat': 43.3614, 'lon': -5.8494, 'precision': 12.5},
        // Un `bigint`/`numeric` puede llegar como cadena.
        'n_equipos': '2',
        // Columnas que el móvil no conoce se ignoran.
        'columna_nueva_del_servidor': 'x',
      };
      final fila = desdeJsonPostgrest<Inspeccion>('inspecciones', delServidor);

      expect(fila.iniciadaAt, DateTime.utc(2026, 11, 8, 8, 3, 12, 345, 678));
      expect(fila.firmadaAt, DateTime.utc(2026, 11, 8, 9, 44, 59));
      expect(fila.firmadaAt!.isUtc, isTrue);
      expect(fila.sincronizadaAt, DateTime.utc(2026, 11, 8, 9, 50, 0, 500));
      expect(fila.nEquipos, 2);
      expect(jsonDecode(fila.gpsInicio!), {
        'lat': 43.3614,
        'lon': -5.8494,
        'precision': 12.5,
      });
      expect(fila.copyWith(sincronizadaAt: const Value(null)), inspeccion);
    });

    test('sincronizada_at no se sube nunca (la pone el servidor)', () {
      final conSync = inspeccion.copyWith(
        sincronizadaAt: Value(DateTime.utc(2026, 11, 8, 10)),
      );
      expect(
        aJsonPostgrest('inspecciones', conSync).containsKey('sincronizada_at'),
        isFalse,
      );
    });
  });

  test('fotos desde PostgREST: gps decodificado, numeric como cadena', () {
    final foto = desdeJsonPostgrest<Foto>('fotos', {
      'id': 'f1',
      'empresa_id': 'e1',
      'inspeccion_id': 'i1',
      'inspeccion_equipo_id': null,
      'item_plantilla_id': null,
      'proposito': 'placa',
      'ruta': 'empresas/e1/inspecciones/i1/fotos/f1.jpg',
      'ruta_miniatura': null,
      'sha256': 'cd' * 32,
      'ancho': 1600,
      'alto': 1200,
      'calidad_local': 'ok',
      'calidad_nitidez': '153.250',
      'calidad_brillo': 0.42,
      'tomada_at': '2026-11-08T09:12:00+00:00',
      'gps': {'lat': 43.3614, 'lon': -5.8494, 'precision': 4},
      'created_at': '2026-11-08T09:12:00.000001+00:00',
      'updated_at': '2026-11-08T09:30:00+00:00',
    });
    expect(foto.calidadNitidez, 153.25);
    expect(foto.calidadBrillo, 0.42);
    expect(foto.tomadaAt, DateTime.utc(2026, 11, 8, 9, 12));
    expect(foto.createdAt.microsecond, 1);
    expect(jsonDecode(foto.gps!), {
      'lat': 43.3614,
      'lon': -5.8494,
      'precision': 4,
    });
    expect(aJsonPostgrest('fotos', foto)['gps'], {
      'lat': 43.3614,
      'lon': -5.8494,
      'precision': 4,
    });
  });

  test('equipos: enums por su código wire y fechas `date` sin hora', () {
    final json = {
      ...filaDeEjemplo(db.equipos).delServidor,
      'tipo': 'enfriadora',
      'categoria_fgas': null,
      'fecha_instalacion': '2018-01-01',
      'placa_foto_id': null,
    };
    final equipo = desdeJsonPostgrest<Equipo>('equipos', json);
    expect(equipo.tipo, TipoEquipo.enfriadora);
    expect(equipo.categoriaFgas, isNull);
    expect(equipo.fechaInstalacion, DateTime.utc(2018));

    final salida = aJsonPostgrest('equipos', equipo);
    expect(salida['tipo'], 'enfriadora');
    expect(salida['categoria_fgas'], isNull);
    expect(salida['fecha_instalacion'], '2018-01-01');
  });

  // Un jsonb no nulo que llega null o no llega es un servidor que no cumple
  // el esquema o un `select` de unas pocas columnas: inventar `{}` pisaría el
  // valor local (o diría «ninguna incidencia abierta»). Falla como cualquier
  // otra columna no nula.
  test('jsonb no nulo que llega null o no llega falla con tabla e id', () {
    final ejemplo = filaDeEjemplo(db.estadoEquipo).delServidor;
    expect(
      () => desdeJsonPostgrest<EstadoDeEquipo>('estado_equipo', {
        ...ejemplo,
        'incidencias_abiertas_json': null,
      }),
      errorDeFila('estado_equipo', ejemplo['id']),
    );
    final propuesta = filaDeEjemplo(db.propuestasIa).delServidor
      ..remove('resultado_json');
    expect(
      () => desdeJsonPostgrest<PropuestaIa>('propuestas_ia', propuesta),
      errorDeFila('propuestas_ia', propuesta['id']),
    );
    final plantilla = filaDeEjemplo(db.plantillas).delServidor
      ..remove('aplica_a');
    expect(
      () => desdeJsonPostgrest<Plantilla>('plantillas', plantilla),
      errorDeFila('plantillas', plantilla['id']),
    );
  });

  group('jsonb escalar (decisiones_ia.valor_final_json, §7.6)', () {
    for (final valor in <Object>['Filtro sucio', 'R-32', 12.5, 3, true]) {
      test('${valor.runtimeType} $valor', () async {
        final json = {
          ...filaDeEjemplo(db.decisionesIa).delServidor,
          'valor_final_json': valor,
        };
        final fila = desdeJsonPostgrest<DecisionIa>('decisiones_ia', json);
        // En local, texto JSON válido: la cadena va entre comillas.
        expect(fila.valorFinalJson, jsonEncode(valor));
        expect(jsonDecode(fila.valorFinalJson!), valor);

        await db.into(db.decisionesIa).insert(fila);
        final leida = await db.select(db.decisionesIa).getSingle();
        final salida = aJsonPostgrest('decisiones_ia', leida);
        expect(salida['valor_final_json'], valor);
        expect(
          desdeJsonPostgrest<DecisionIa>('decisiones_ia', porLaRed(salida)),
          fila,
        );
      });
    }
  });

  test('una columna no nula que falta falla con el nombre de la tabla', () {
    final json = filaDeEjemplo(db.fotos).delServidor..remove('ruta');
    expect(
      () => desdeJsonPostgrest<Foto>('fotos', json),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('fotos'),
        ),
      ),
    );
  });

  test('un numeric ilegible no se convierte en null', () {
    final json = {...filaDeEjemplo(db.movimientosGas).delServidor, 'kg': 'x'};
    expect(
      () => desdeJsonPostgrest<MovimientoGas>('movimientos_gas', json),
      throwsFormatException,
    );
  });

  test('bool: solo lo que manda Postgres; lo demás falla con tabla e id', () {
    final base = filaDeEjemplo(db.incidencias).delServidor;
    Incidencia leer(Object v) => desdeJsonPostgrest<Incidencia>('incidencias', {
      ...base,
      'para_equipo': v,
    });
    for (final v in <Object>[false, 'f', 'false', 0, '0']) {
      expect(leer(v).paraEquipo, isFalse, reason: '$v');
    }
    for (final v in <Object>[true, 't', 'true', 1, '1']) {
      expect(leer(v).paraEquipo, isTrue, reason: '$v');
    }
    for (final v in <Object>['quizas', 2, 'si', '']) {
      expect(() => leer(v), errorDeFila('incidencias', base['id']));
    }
  });

  test('un entero con decimales no se trunca', () {
    final base = filaDeEjemplo(db.incidencias).delServidor;
    expect(
      desdeJsonPostgrest<Incidencia>('incidencias', {
        ...base,
        'plazo_dias': 2.0,
      }).plazoDias,
      2,
    );
    for (final v in <Object>[2.7, '2.7', 'dos']) {
      expect(
        () => desdeJsonPostgrest<Incidencia>('incidencias', {
          ...base,
          'plazo_dias': v,
        }),
        errorDeFila('incidencias', base['id']),
        reason: '$v',
      );
    }
  });

  test('un enum desconocido falla con la tabla y el id de la fila', () {
    final base = filaDeEjemplo(db.equipos).delServidor;
    expect(
      () =>
          desdeJsonPostgrest<Equipo>('equipos', {...base, 'tipo': 'cassette'}),
      errorDeFila('equipos', base['id']),
    );
    // Y en una página del pull, el error dice qué fila es.
    expect(
      () => desdeJsonPostgrestLista<Equipo>('equipos', [
        {...base, 'id': 'q-buena'},
        {...base, 'id': 'q-mala', 'categoria_fgas': 'criogenia'},
      ]),
      errorDeFila('equipos', 'q-mala'),
    );
  });

  test('las tablas que solo bajan son las de §7 sin escritura del móvil', () {
    // §7.1 dispositivos, §7.2 estado_equipo, §7.5/§8.5 ordenes_sugeridas
    // (vacía y sin escritura para `authenticated` en el MVP), §7.6
    // propuestas_ia.
    expect(tablasSoloBajada, {
      'dispositivos',
      'estado_equipo',
      'ordenes_sugeridas',
      'propuestas_ia',
    });
  });

  test('las tablas que solo bajan no se suben', () {
    for (final tabla in tablasSoloBajada) {
      final t = sincronizadas().firstWhere((t) => t.actualTableName == tabla);
      final fila = desdeJsonPostgrest(tabla, filaDeEjemplo(t).delServidor);
      expect(() => aJsonPostgrest(tabla, fila), throwsArgumentError);
    }
    expect(
      () => aJsonPostgrest(
        'outbox_entries',
        desdeJsonPostgrest('fotos', filaDeEjemplo(db.fotos).delServidor),
      ),
      throwsArgumentError,
    );
  });

  // La prueba que decide entre el mapper genérico y el plan B (§8.2): una
  // ida y vuelta por cada tabla sincronizada, con todas sus columnas
  // rellenas, y otra con los nulos a null, los bool a false y los jsonb como
  // escalar o lista.
  for (final variante in [false, true]) {
    group(
      variante
          ? 'ida y vuelta por tabla (nulos, false, jsonb escalar o lista)'
          : 'ida y vuelta por tabla',
      () {
        for (final nombre in constructoresDesdeJson.keys) {
          test(nombre, () async {
            final tabla = tablaPorNombre(db, nombre)!;
            final ejemplo = filaDeEjemplo(tabla, variante: variante);

            // PostgREST → Drift → SQLite → Drift.
            final fila = desdeJsonPostgrest(nombre, ejemplo.delServidor);
            await db.into(tabla).insert(fila as Insertable<DataClass>);
            final leida = (await db.select(tabla).get()).single;
            expect(leida, fila);

            // Drift → PostgREST, con las claves exactamente iguales a las
            // columnas SQL y los valores en el formato del servidor.
            final json = tablasSoloBajada.contains(nombre)
                ? leida.toJson(serializer: serializadorPostgrest)
                : aJsonPostgrest(nombre, leida);
            expect(json.keys.toSet(), ejemplo.haciaServidor.keys.toSet());
            expect(json, ejemplo.haciaServidor);

            // Y de vuelta: la fila es la misma.
            final vuelta = desdeJsonPostgrest(nombre, porLaRed(json));
            if (columnasSoloServidor.containsKey(nombre)) {
              // Lo que no se sube vuelve null; el resto, igual.
              final sinServidor = {
                ...leida.toJson(serializer: serializadorPostgrest),
                for (final c in columnasSoloServidor[nombre]!) c: null,
              };
              expect(vuelta, desdeJsonPostgrest(nombre, porLaRed(sinServidor)));
            } else {
              expect(vuelta, leida);
            }
          });
        }
      },
    );
  }
}
