import 'package:drift/drift.dart';

import '../conversores.dart';
import 'comunes.dart';

// DISEÑO.md §7.4 Plantillas versionadas. Sin `deleted_at`: una plantilla
// publicada es inmutable y se retira con `estado = 'retirada'`, nunca se
// borra (las inspecciones firmadas apuntan a su versión).

/// `empresa_id` nulo = plantilla base de Inspecta, legible para todos.
@DataClassName('Plantilla')
class Plantillas extends Table with FilaSincronizada {
  TextColumn get empresaId => text().nullable()();

  /// `split_hasta_12kw`…; única con `empresa_id` y `version` en el servidor.
  TextColumn get clave => text()();
  IntColumn get version => integer()();
  TextColumn get titulo => text()();
  TextColumn get baseNormativa => text().nullable()();

  /// jsonb: tipos, rango de potencia, uso.
  TextColumn get aplicaA => text().map(const Jsonb())();

  /// `borrador|publicada|retirada`.
  TextColumn get estado => text().withDefault(const Constant('borrador'))();

  /// `plantillas.id` de la versión anterior.
  TextColumn get sustituyeA => text().nullable()();
  DateTimeColumn get publicadaAt => dateTime().nullable()();
}

@DataClassName('ItemPlantilla')
@TableIndex(name: 'items_plantilla_plantilla', columns: {#plantillaId})
class ItemsPlantilla extends Table with FilaSincronizada {
  TextColumn get empresaId => text().nullable()();
  TextColumn get plantillaId => text()();

  /// Estable entre versiones: la usa `estado_equipo.ultimos_valores_json`.
  TextColumn get clave => text()();
  IntColumn get orden => integer()();
  TextColumn get seccion => text().nullable()();
  TextColumn get codigoNormativo => text().nullable()();
  TextColumn get texto => text()();

  /// `estado|estado_valor|solo_valor|si_no`.
  TextColumn get tipoRespuesta => text()();
  TextColumn get unidad => text().nullable()();
  RealColumn get rangoMin => real().nullable()();
  RealColumn get rangoMax => real().nullable()();
  BoolColumn get obligatorio => boolean().withDefault(const Constant(false))();
  BoolColumn get fotoObligatoria =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get analizableIa => boolean().withDefault(const Constant(false))();
}
