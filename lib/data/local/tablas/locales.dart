import 'package:drift/drift.dart';

// DISEÑO.md §7.7 Solo locales: nunca se sincronizan como filas.

/// Bytes de fotos, notas, firmas e informes. Fuera del payload de la cola
/// (§8.2, «Cambio obligatorio»): la entrada lleva `{bucket, ruta, blob_id}` y
/// los bytes están aquí.
@DataClassName('BlobLocal')
@TableIndex(name: 'blobs_origen', columns: {#origenId})
class Blobs extends Table {
  TextColumn get id => text()();

  /// Foto, nota, firma o informe.
  TextColumn get origenId => text()();

  /// `original|pdf_1000|miniatura`. Solo `original` (y el PDF) se suben.
  TextColumn get variante => text()();
  BlobColumn get bytes => blob()();
  TextColumn get mime => text()();
  TextColumn get sha256 => text()();
  TextColumn get bucket => text().nullable()();
  TextColumn get ruta => text().nullable()();

  /// Limpieza: lo subido y firmado con más de 14 días (salvo la miniatura).
  DateTimeColumn get subidoAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Cola de IA (`IaQueue`, §8.2), aparte de la de salida.
@DataClassName('TrabajoIa')
@TableIndex(name: 'trabajos_ia_estado', columns: {#estado})
@TableIndex(name: 'trabajos_ia_objetivo', columns: {#objetivoId})
class TrabajosIa extends Table {
  TextColumn get id => text()();

  /// `foto|placa|voz|resumen`.
  TextColumn get tipo => text()();
  TextColumn get objetivoId => text()();

  /// `pendiente|esperando_subida|enviado|hecho|fallido|descartado`.
  TextColumn get estado => text().withDefault(const Constant('pendiente'))();
  IntColumn get intentos => integer().withDefault(const Constant(0))();
  TextColumn get error => text().nullable()();
  TextColumn get propuestaId => text().nullable()();

  /// No está en §7.7: la cola necesita un orden de llegada estable y los ids
  /// son UUID v4, que no lo dan.
  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Caché del último número por serie (`2026-JLM-A`), inicializada desde el
/// servidor al iniciar sesión (§7.9).
@DataClassName('ContadorInforme')
class ContadoresInforme extends Table {
  TextColumn get serie => text()();
  IntColumn get ultimo => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {serie};
}
