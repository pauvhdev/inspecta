import 'package:drift/drift.dart';

import '../conversores.dart';
import 'comunes.dart';

// DISEÑO.md §7.2 Clientes y activos. Clientes, instalaciones y equipos los
// puede borrar la oficina: llevan `deleted_at`.

@DataClassName('Cliente')
class Clientes extends Table with FilaSincronizada, BorradoLogico {
  TextColumn get empresaId => text()();
  TextColumn get razonSocial => text()();
  TextColumn get cif => text().nullable()();
  TextColumn get contactoNombre => text().nullable()();
  TextColumn get contactoTelefono => text().nullable()();
  TextColumn get contactoEmail => text().nullable()();
}

@DataClassName('Instalacion')
@TableIndex(name: 'instalaciones_cliente', columns: {#clienteId})
class Instalaciones extends Table with FilaSincronizada, BorradoLogico {
  TextColumn get empresaId => text()();
  TextColumn get clienteId => text()();
  TextColumn get nombre => text()();
  TextColumn get direccion => text().nullable()();

  /// Cambia la periodicidad de la Tabla 3.1 del RITE: sin él no se puede
  /// calcular nada, por eso no es nulo.
  TextColumn get usoEdificio => text().map(const ConversorUsoEdificio())();
  TextColumn get expedienteCcaa => text().nullable()();

  /// Potencia térmica nominal total instalada declarada (§3.2). `rite.dart`
  /// usa la mayor de frío y calor y la mayor entre esto y la suma de equipos.
  RealColumn get potenciaFrioKw => real().nullable()();
  RealColumn get potenciaCalorKw => real().nullable()();
  DateTimeColumn get fechaPrimerCertificado =>
      dateTime().map(const SoloFecha()).nullable()();

  // Nulos a propósito: «no consta» no es lo mismo que «no».
  BoolColumn get contratoMantenimiento => boolean().nullable()();
  BoolColumn get manualDisponible => boolean().nullable()();
  BoolColumn get supervisionRemota => boolean().nullable()();
}

@DataClassName('Equipo')
@TableIndex(name: 'equipos_instalacion', columns: {#instalacionId})
class Equipos extends Table with FilaSincronizada, BorradoLogico {
  TextColumn get empresaId => text()();
  TextColumn get instalacionId => text()();
  TextColumn get tipo => text().map(const ConversorTipoEquipo())();

  /// Nula hasta que el técnico confirma en T3 la que `fgas.dart` deduce de
  /// `tipo`: decide el art. 13.3 o el 13.4 y no debe inventarse.
  TextColumn get categoriaFgas =>
      text().map(const ConversorCategoriaFgas()).nullable()();
  TextColumn get marca => text().nullable()();
  TextColumn get modelo => text().nullable()();
  TextColumn get nSerie => text().nullable()();
  TextColumn get ubicacion => text().nullable()();
  DateTimeColumn get fechaInstalacion =>
      dateTime().map(const SoloFecha()).nullable()();
  RealColumn get potenciaFrioKw => real().nullable()();
  RealColumn get potenciaCalorKw => real().nullable()();
  TextColumn get refrigerante => text().nullable()();
  RealColumn get cargaKg => real().nullable()();
  BoolColumn get hermeticoEtiquetado => boolean().nullable()();
  BoolColumn get deteccionFugas => boolean().nullable()();
  DateTimeColumn get deteccionUltimaRevision =>
      dateTime().map(const SoloFecha()).nullable()();
  BoolColumn get etiquetaOk => boolean().nullable()();

  /// Fechas anteriores a Inspecta, declaradas al dar de alta (opcionales).
  DateTimeColumn get preventivoPrevioDeclarado =>
      dateTime().map(const SoloFecha()).nullable()();
  DateTimeColumn get controlFugasPrevioDeclarado =>
      dateTime().map(const SoloFecha()).nullable()();

  /// `manual|placa_ia_confirmada`.
  TextColumn get origenDatos => text().withDefault(const Constant('manual'))();

  /// Referencia blanda a `fotos.id`, sin clave foránea tampoco en Postgres:
  /// la foto de la placa nace después que el equipo y la coalescencia de la
  /// cola subiría el cambio antes que la foto (§8.2).
  TextColumn get placaFotoId => text().nullable()();

  /// `miembros.id` de quien confirmó los datos.
  TextColumn get datosConfirmadosPor => text().nullable()();
  DateTimeColumn get datosConfirmadosAt => dateTime().nullable()();
}

/// Hechos del equipo que deriva el servidor al recibir un cierre firmado
/// (§7.2). `id` = `equipo_id` (una fila por equipo). La escribe solo un
/// trigger; en local la app la recalcula al firmar para no esperar al
/// servidor, pero nunca la encola (por eso reconcile no la poda, §8.2).
@DataClassName('EstadoDeEquipo')
class EstadoEquipo extends Table with FilaSincronizada {
  TextColumn get empresaId => text()();
  DateTimeColumn get ultimoPreventivoAt => dateTime().nullable()();
  TextColumn get ultimaInspeccionId => text().nullable()();
  DateTimeColumn get ultimoControlFugasAt => dateTime().nullable()();
  TextColumn get ultimoResultadoFugas => text().nullable()();

  /// jsonb: por `clave` de ítem, `{valor, unidad, fecha}`.
  TextColumn get ultimosValoresJson => text().map(const Jsonb())();

  /// jsonb: lista de `{id, descripcion, gravedad, fecha}`.
  TextColumn get incidenciasAbiertasJson => text().map(const Jsonb())();
}
