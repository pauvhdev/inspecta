import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inspecta/data/local/app_database.dart';
import 'package:inspecta/dominio/tipos.dart';

// Esquema local de Inspecta (DISEÑO.md §7, §12 día 2): todas las tablas se
// crean, tienen exactamente las columnas de §7 con su nombre SQL, sin claves
// foráneas, y se puede escribir y leer en varias de ellas.

/// Columnas de cada tabla tal como las nombra DISEÑO.md §7, más las de la
/// convención (`created_at`, `updated_at` y, donde la oficina borra,
/// `deleted_at`). Si alguien cambia un getter, el nombre SQL cambia y esta
/// prueba falla antes de que el pull lo descubra en producción.
const _sincronizadas = ['created_at', 'updated_at'];
const _borrables = [..._sincronizadas, 'deleted_at'];

const columnasEsperadas = <String, List<String>>{
  // §7.1. `empresas.empresa_id` (= `id`) no está en la lista de §7.1, pero
  // sí en la convención de §7, la política base de §8.5 y la regla 6 de
  // docs/REGLAS.md [A VERIFICAR] (ver `tablas/organizacion.dart`).
  'empresas': [
    'id',
    'empresa_id',
    'razon_social',
    'cif',
    'n_habilitacion_rite',
    'ccaa',
    'n_certificado_fgas_empresa',
    'logo_ruta',
    'es_demo',
    ..._sincronizadas,
  ],
  'miembros': [
    'id', 'empresa_id', 'user_id', 'rol', 'nombre', 'carne_rite', //
    'cert_fgas_tipo', 'cert_fgas_numero', 'cert_fgas_caduca',
    'serie_informes', 'activo', ..._sincronizadas,
  ],
  'dispositivos': [
    'id', 'empresa_id', 'miembro_id', 'letra', 'registrado_at', //
    'ultimo_numero', 'ultima_sync_at', ..._sincronizadas,
  ],
  // §7.2
  'clientes': [
    'id', 'empresa_id', 'razon_social', 'cif', 'contacto_nombre', //
    'contacto_telefono', 'contacto_email', ..._borrables,
  ],
  'instalaciones': [
    'id', 'empresa_id', 'cliente_id', 'nombre', 'direccion', //
    'uso_edificio', 'expediente_ccaa', 'potencia_frio_kw',
    'potencia_calor_kw', 'fecha_primer_certificado',
    'contrato_mantenimiento', 'manual_disponible', 'supervision_remota',
    ..._borrables,
  ],
  'equipos': [
    'id', 'empresa_id', 'instalacion_id', 'tipo', 'categoria_fgas', //
    'marca', 'modelo', 'n_serie', 'ubicacion', 'fecha_instalacion',
    'potencia_frio_kw', 'potencia_calor_kw', 'refrigerante', 'carga_kg',
    'hermetico_etiquetado', 'deteccion_fugas', 'deteccion_ultima_revision',
    'etiqueta_ok', 'preventivo_previo_declarado',
    'control_fugas_previo_declarado', 'origen_datos', 'placa_foto_id',
    'datos_confirmados_por', 'datos_confirmados_at', ..._borrables,
  ],
  'estado_equipo': [
    'id', 'empresa_id', 'ultimo_preventivo_at', 'ultima_inspeccion_id', //
    'ultimo_control_fugas_at', 'ultimo_resultado_fugas',
    'ultimos_valores_json', 'incidencias_abiertas_json', ..._sincronizadas,
  ],
  // §7.4
  'plantillas': [
    'id', 'empresa_id', 'clave', 'version', 'titulo', 'base_normativa', //
    'aplica_a', 'estado', 'sustituye_a', 'publicada_at', ..._sincronizadas,
  ],
  'items_plantilla': [
    'id', 'empresa_id', 'plantilla_id', 'clave', 'orden', 'seccion', //
    'codigo_normativo', 'texto', 'tipo_respuesta', 'unidad', 'rango_min',
    'rango_max', 'obligatorio', 'foto_obligatoria', 'analizable_ia',
    ..._sincronizadas,
  ],
  // §7.5
  'ordenes_trabajo': [
    'id', 'empresa_id', 'instalacion_id', 'tecnico_id', 'fecha_prevista', //
    'tipo_intervencion', 'estado', 'origen_id', 'notas_oficina',
    ..._borrables,
  ],
  'orden_equipos': [
    'id', 'empresa_id', 'orden_id', 'equipo_id', 'plantilla_id', //
    ..._borrables,
  ],
  'ordenes_sugeridas': [
    'id', 'empresa_id', 'equipo_id', 'control_origen_id', 'tipo', 'desde', //
    'hasta', 'estado', 'orden_id', ..._sincronizadas,
  ],
  'inspecciones': [
    'id', 'empresa_id', 'orden_id', 'tecnico_id', 'numero', 'version', //
    'rectifica_a', 'iniciada_at', 'finalizada_at', 'firmada_at',
    'sincronizada_at', 'gps_inicio', 'gps_firma', 'resumen_texto',
    'resumen_origen', 'estado', 'n_equipos', 'n_respuestas',
    'n_incidencias', 'n_fotos', 'n_enlaces_fotos', 'n_notas', 'n_controles',
    'n_movimientos_gas', 'n_resoluciones', 'pdf_ruta', 'pdf_sha256',
    'contenido_sha256', 'normativa_version', 'app_version',
    'datos_cabecera_json', ..._sincronizadas,
  ],
  'inspeccion_equipos': [
    'id', 'empresa_id', 'inspeccion_id', 'equipo_id', 'plantilla_id', //
    'datos_equipo_json', ..._sincronizadas,
  ],
  'respuestas': [
    'id', 'empresa_id', 'inspeccion_equipo_id', 'item_plantilla_id', //
    'texto_item', 'codigo_normativo', 'estado', 'valor_num', 'unidad',
    'observacion', 'origen', 'propuesta_ia_id', ..._sincronizadas,
  ],
  'incidencias': [
    'id', 'empresa_id', 'inspeccion_equipo_id', 'respuesta_id', //
    'descripcion', 'gravedad', 'accion_recomendada', 'plazo_dias',
    'para_equipo', 'origen', 'propuesta_ia_id', 'decidida_por',
    'decidida_at', ..._sincronizadas,
  ],
  'incidencia_fotos': [
    'id', 'empresa_id', 'inspeccion_id', 'incidencia_id', 'foto_id', //
    ..._sincronizadas,
  ],
  'resoluciones_incidencia': [
    'id', 'empresa_id', 'incidencia_id', 'inspeccion_id', //
    'inspeccion_equipo_id', 'nota', 'resuelta_at', ..._sincronizadas,
  ],
  'controles_fugas': [
    'id', 'empresa_id', 'inspeccion_equipo_id', 'metodo', //
    'detector_modelo', 'detector_calibracion', 'resultado', 'localizacion',
    'reparada', 'fecha_reparacion', 'recontrol_desde', 'recontrol_hasta',
    'control_origen_id', 'eficaz', ..._sincronizadas,
  ],
  'movimientos_gas': [
    'id', 'empresa_id', 'inspeccion_equipo_id', 'tipo', 'refrigerante', //
    'kg', 'origen_gas', 'regenerado_lote', 'regenerado_etiqueta_foto_id',
    'reciclado_recuperado_por', 'reciclado_declaracion', 'gestor_nombre',
    'gestor_documento', 'motivo', 'aviso_pcg', 'regla_aplicada',
    ..._sincronizadas,
  ],
  // `calidad_nitidez` y `calidad_brillo` son las «dos métricas» de
  // `calidad_local`, que §7.5 no nombra [A VERIFICAR]. `fotos` y `notas_voz`
  // llevan `deleted_at`: el técnico las borra antes de firmar (§6.0, ver
  // `tablas/trabajo.dart`) [A VERIFICAR].
  'fotos': [
    'id', 'empresa_id', 'inspeccion_id', 'inspeccion_equipo_id', //
    'item_plantilla_id', 'proposito', 'ruta', 'ruta_miniatura', 'sha256',
    'ancho', 'alto', 'calidad_local', 'calidad_nitidez', 'calidad_brillo',
    'tomada_at', 'gps', ..._borrables,
  ],
  'notas_voz': [
    'id', 'empresa_id', 'inspeccion_id', 'inspeccion_equipo_id', 'ruta', //
    'mime', 'sha256', 'duracion_s', 'grabada_at', ..._borrables,
  ],
  'firmas': [
    'id', 'empresa_id', 'inspeccion_id', 'rol', 'nombre', 'cargo', //
    'ruta_png', 'sha256', 'firmada_at', 'gps', ..._sincronizadas,
  ],
  'comparticiones': [
    'id', 'empresa_id', 'inspeccion_id', 'canal', 'at', 'por', //
    ..._sincronizadas,
  ],
  // §7.6
  'propuestas_ia': [
    'id', 'empresa_id', 'tipo', 'objetivo_id', 'entrada_sha256', 'modelo', //
    'version_prompt', 'resultado_json', 'tokens_entrada', 'tokens_salida',
    'reserva_id', ..._sincronizadas,
  ],
  'decisiones_ia': [
    'id', 'empresa_id', 'inspeccion_id', 'propuesta_id', 'indice', //
    'decision', 'valor_final_json', 'decidida_por', 'decidida_at',
    ..._sincronizadas,
  ],
  // §7.7 [local]. `trabajos_ia.created_at` no está en §7.7: da el orden de
  // la cola de IA (ver `tablas/locales.dart`).
  'blobs': [
    'id', 'origen_id', 'variante', 'bytes', 'mime', 'sha256', 'bucket', //
    'ruta', 'subido_at',
  ],
  'trabajos_ia': [
    'id', 'tipo', 'objetivo_id', 'estado', 'intentos', 'error', //
    'propuesta_id', 'created_at',
  ],
  'contadores_informe': ['serie', 'ultimo'],
  'outbox_entries': [
    'seq', 'entity', 'op', 'row_id', 'payload', 'created_at', 'attempts', //
    'last_error', 'is_blocked', 'esperando_hijos',
  ],
  'sync_cursors': ['entity', 'last_pulled_at'],
  'app_settings': ['key', 'value'],
};

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<List<String>> columnasSql(String tabla) async {
    final filas = await db.customSelect('PRAGMA table_info("$tabla")').get();
    return [for (final f in filas) f.read<String>('name')];
  }

  test('la base se abre en la versión 2 con todas las tablas de §7', () async {
    expect(db.schemaVersion, 2);
    final tablas = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name NOT LIKE 'sqlite_%'",
        )
        .get();
    expect(
      tablas.map((f) => f.read<String>('name')).toSet(),
      columnasEsperadas.keys.toSet(),
    );
  });

  test('las tablas [servidor] de §7.6 no existen en local', () async {
    final nombres = db.allTables.map((t) => t.actualTableName).toSet();
    expect(
      nombres.intersection({'ai_usage', 'ia_cupos', 'ai_usage_reservas'}),
      isEmpty,
    );
  });

  for (final MapEntry(key: tabla, value: columnas)
      in columnasEsperadas.entries) {
    test('$tabla tiene exactamente las columnas de §7', () async {
      expect((await columnasSql(tabla)).toSet(), columnas.toSet());
      expect(columnas.toSet().length, columnas.length, reason: 'duplicadas');
    });
  }

  test(
    'las tablas sincronizadas tienen id de texto como clave primaria',
    () async {
      const locales = {
        'contadores_informe',
        'outbox_entries',
        'sync_cursors',
        'app_settings',
      };
      for (final tabla in columnasEsperadas.keys.where(
        (t) => !locales.contains(t),
      )) {
        final filas = await db
            .customSelect('PRAGMA table_info("$tabla")')
            .get();
        final pk = filas.where((f) => f.read<int>('pk') > 0).toList();
        expect(pk, hasLength(1), reason: tabla);
        expect(pk.single.read<String>('name'), 'id', reason: tabla);
        expect(pk.single.read<String>('type'), 'TEXT', reason: tabla);
      }
    },
  );

  test(
    'ninguna tabla declara claves foráneas (§8.2, tablas/comunes.dart)',
    () async {
      for (final tabla in columnasEsperadas.keys) {
        final fks = await db
            .customSelect('PRAGMA foreign_key_list("$tabla")')
            .get();
        expect(fks, isEmpty, reason: tabla);
      }
    },
  );

  test('los hijos tienen índice por su padre', () async {
    final indices = await db
        .customSelect(
          "SELECT tbl_name, sql FROM sqlite_master WHERE type = 'index' "
          'AND sql IS NOT NULL',
        )
        .get();
    bool indexada(String tabla, String columna) => indices.any(
      (f) =>
          f.read<String>('tbl_name') == tabla &&
          f.read<String>('sql').contains('($columna'),
    );

    const esperados = {
      'instalaciones': 'cliente_id',
      'equipos': 'instalacion_id',
      'ordenes_trabajo': 'instalacion_id',
      'orden_equipos': 'orden_id',
      'inspecciones': 'orden_id',
      'inspeccion_equipos': 'inspeccion_id',
      'respuestas': 'inspeccion_equipo_id',
      'incidencias': 'inspeccion_equipo_id',
      'incidencia_fotos': 'inspeccion_id',
      'resoluciones_incidencia': 'incidencia_id',
      'controles_fugas': 'inspeccion_equipo_id',
      'movimientos_gas': 'inspeccion_equipo_id',
      'fotos': 'inspeccion_id',
      'notas_voz': 'inspeccion_id',
      'firmas': 'inspeccion_id',
      'comparticiones': 'inspeccion_id',
      'items_plantilla': 'plantilla_id',
      'decisiones_ia': 'propuesta_id',
      'propuestas_ia': 'objetivo_id',
      'blobs': 'origen_id',
    };
    for (final MapEntry(key: tabla, value: columna) in esperados.entries) {
      expect(indexada(tabla, columna), isTrue, reason: '$tabla($columna)');
    }
  });

  group('escribir y leer', () {
    final ahora = DateTime.utc(2026, 11, 8, 9, 30, 15, 123, 456);

    test('empresa, instalación y equipo con enums y fechas', () async {
      await db
          .into(db.empresas)
          .insert(
            EmpresasCompanion.insert(
              id: 'e1',
              empresaId: 'e1',
              razonSocial: 'Climas Norte SL',
            ),
          );
      await db
          .into(db.instalaciones)
          .insert(
            InstalacionesCompanion.insert(
              id: 'i1',
              empresaId: 'e1',
              clienteId: 'c1',
              nombre: 'Oficinas',
              usoEdificio: UsoEdificio.otros,
              potenciaFrioKw: const Value(85.5),
              fechaPrimerCertificado: Value(DateTime(2019, 6, 1)),
            ),
          );
      await db
          .into(db.equipos)
          .insert(
            EquiposCompanion.insert(
              id: 'q1',
              empresaId: 'e1',
              instalacionId: 'i1',
              tipo: TipoEquipo.bombaCalor,
              categoriaFgas: const Value(
                CategoriaFgas.aireAcondicionadoBombaCalor,
              ),
              cargaKg: const Value(2.4),
              datosConfirmadosAt: Value(ahora),
            ),
          );

      final empresa = await db.select(db.empresas).getSingle();
      expect(empresa.esDemo, isFalse);
      expect(empresa.createdAt.isUtc, isTrue);

      final inst = await db.select(db.instalaciones).getSingle();
      expect(inst.usoEdificio, UsoEdificio.otros);
      expect(inst.fechaPrimerCertificado, DateTime.utc(2019, 6, 1));
      expect(inst.deletedAt, isNull);

      final equipo = await db.select(db.equipos).getSingle();
      expect(equipo.tipo, TipoEquipo.bombaCalor);
      expect(equipo.origenDatos, 'manual');
      expect(equipo.datosConfirmadosAt, ahora);

      // En SQLite el enum va con su código wire y la fecha como texto UTC.
      final crudo = await db
          .customSelect(
            'SELECT tipo, categoria_fgas, datos_confirmados_at FROM equipos',
          )
          .getSingle();
      expect(crudo.read<String>('tipo'), 'bomba_calor');
      expect(
        crudo.read<String>('categoria_fgas'),
        'aire_acondicionado_bomba_calor',
      );
      expect(
        crudo.read<String>('datos_confirmados_at'),
        '2026-11-08T09:30:15.123456Z',
      );
    });

    test('inspección con gps y jsonb, y sus hijos por índice', () async {
      final gps = jsonEncode({'lat': 43.36, 'lon': -5.85, 'precision': 8.0});
      await db
          .into(db.inspecciones)
          .insert(
            InspeccionesCompanion.insert(
              id: 'insp1',
              empresaId: 'e1',
              ordenId: 'o1',
              tecnicoId: 'm1',
              iniciadaAt: ahora,
              gpsInicio: Value(gps),
            ),
          );
      await db
          .into(db.inspeccionEquipos)
          .insert(
            InspeccionEquiposCompanion.insert(
              id: 'ie1',
              empresaId: 'e1',
              inspeccionId: 'insp1',
              equipoId: 'q1',
              plantillaId: 'p1',
            ),
          );
      await db
          .into(db.fotos)
          .insert(
            FotosCompanion.insert(
              id: 'f1',
              empresaId: 'e1',
              inspeccionId: 'insp1',
              inspeccionEquipoId: const Value('ie1'),
              proposito: 'placa',
              ruta: 'empresas/e1/inspecciones/insp1/fotos/f1.jpg',
              sha256: 'abc',
              tomadaAt: ahora,
            ),
          );
      await db
          .into(db.movimientosGas)
          .insert(
            MovimientosGasCompanion.insert(
              id: 'mg1',
              empresaId: 'e1',
              inspeccionEquipoId: 'ie1',
              tipo: 'carga',
              refrigerante: 'R-32',
              kg: 0.75,
              // Referencia blanda: la foto no tiene por qué existir (§8.2).
              regeneradoEtiquetaFotoId: const Value('foto-que-aun-no-existe'),
            ),
          );

      final insp = await db.select(db.inspecciones).getSingle();
      expect(insp.estado, 'en_curso');
      expect(insp.version, 1);
      expect(jsonDecode(insp.gpsInicio!), {
        'lat': 43.36,
        'lon': -5.85,
        'precision': 8.0,
      });
      expect(insp.gpsFirma, isNull);
      expect(insp.nEquipos, isNull);

      final fotos = await (db.select(
        db.fotos,
      )..where((f) => f.inspeccionId.equals('insp1'))).get();
      expect(fotos.single.inspeccionEquipoId, 'ie1');
      expect(fotos.single.deletedAt, isNull);
      final mov = await db.select(db.movimientosGas).getSingle();
      expect(mov.kg, 0.75);
    });

    test('borrar una foto es un UPDATE de deleted_at, no un DELETE', () async {
      // §6.0 «borrar una foto» con la inspección sin firmar: la fila se queda
      // (no hay política DELETE en tablas de informe, §7.10.2) y lo que cuenta
      // para `n_fotos` son las no borradas (ver `tablas/trabajo.dart`).
      for (final id in ['f1', 'f2']) {
        await db
            .into(db.fotos)
            .insert(
              FotosCompanion.insert(
                id: id,
                empresaId: 'e1',
                inspeccionId: 'insp1',
                proposito: 'general',
                ruta: 'empresas/e1/inspecciones/insp1/fotos/$id.jpg',
                sha256: id,
                tomadaAt: ahora,
              ),
            );
      }
      await (db.update(db.fotos)..where((f) => f.id.equals('f1'))).write(
        FotosCompanion(deletedAt: Value(ahora)),
      );
      final vivas = await (db.select(
        db.fotos,
      )..where((f) => f.deletedAt.isNull())).get();
      expect(vivas.map((f) => f.id), ['f2']);
      expect(await db.select(db.fotos).get(), hasLength(2));
    });

    test('resolución de una incidencia que no está en local (§7.5)', () async {
      // Sin FK: la incidencia puede ser de una visita de hace más de 60 días.
      await db
          .into(db.resolucionesIncidencia)
          .insert(
            ResolucionesIncidenciaCompanion.insert(
              id: 'r1',
              empresaId: 'e1',
              incidenciaId: 'incidencia-antigua',
              inspeccionId: 'insp2',
              inspeccionEquipoId: 'ie2',
              resueltaAt: ahora,
            ),
          );
      expect(await db.select(db.resolucionesIncidencia).get(), hasLength(1));
    });

    test('tablas locales: blobs, trabajos_ia, contadores y cola', () async {
      await db
          .into(db.blobs)
          .insert(
            BlobsCompanion.insert(
              id: 'b1',
              origenId: 'f1',
              variante: 'original',
              bytes: Uint8List.fromList([1, 2, 3]),
              mime: 'image/jpeg',
              sha256: 'abc',
            ),
          );
      await db
          .into(db.trabajosIa)
          .insert(
            TrabajosIaCompanion.insert(
              id: 't1',
              tipo: 'placa',
              objetivoId: 'f1',
            ),
          );
      await db
          .into(db.contadoresInforme)
          .insert(ContadoresInformeCompanion.insert(serie: '2026-JLM-A'));
      await db
          .into(db.outboxEntries)
          .insert(
            OutboxEntriesCompanion.insert(
              entity: 'inspecciones',
              op: 'upsert',
              rowId: 'insp1',
              payload: '{}',
              createdAt: DateTime.now(),
            ),
          );

      expect((await db.select(db.blobs).getSingle()).bytes, [1, 2, 3]);
      final trabajo = await db.select(db.trabajosIa).getSingle();
      expect(trabajo.estado, 'pendiente');
      expect(trabajo.intentos, 0);
      expect((await db.select(db.contadoresInforme).getSingle()).ultimo, 0);
      // §7.7: `esperando_hijos` nace en false.
      expect(
        (await db.select(db.outboxEntries).getSingle()).esperandoHijos,
        isFalse,
      );
    });
  });
}
