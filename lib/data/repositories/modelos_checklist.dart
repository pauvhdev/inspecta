import 'dart:typed_data';

import '../../dominio/estados.dart';
import '../../dominio/fgas.dart';
import '../../dominio/normativa.dart' show OrigenGas;
import '../local/app_database.dart';

// Modelos de lectura y escritura de T5 Checklist, T10 Incidencia y T11 Gas.

/// Un ítem del checklist con su respuesta (T5).
class ItemConRespuesta {
  const ItemConRespuesta({required this.item, required this.respuesta});
  final ItemPlantilla item;

  /// Null mientras no se ha respondido nunca.
  final Respuesta? respuesta;

  bool get respondido =>
      respuesta != null &&
      (respuesta!.estado != null || respuesta!.valorNum != null);
}

/// Lo que enseña T5 Checklist de un equipo de la visita.
class ChecklistEquipo {
  const ChecklistEquipo({
    required this.inspeccionEquipo,
    required this.inspeccion,
    required this.equipo,
    required this.plantilla,
    required this.items,
    required this.hechos,
    required this.incidencias,
    required this.movimientos,
    required this.controles,
    this.fotos = const [],
  });

  final InspeccionEquipo inspeccionEquipo;
  final Inspeccion inspeccion;
  final Equipo equipo;
  final Plantilla? plantilla;

  /// En el orden de la plantilla.
  final List<ItemConRespuesta> items;
  final HechosEquipo? hechos;

  /// Incidencias de **esta** visita para este equipo.
  final List<Incidencia> incidencias;
  final List<MovimientoGas> movimientos;
  final List<ControlFugas> controles;

  /// Fotos de este equipo en la visita, sin las borradas.
  final List<Foto> fotos;

  List<Foto> fotosDe(String itemId) => [
    for (final f in fotos)
      if (f.itemPlantillaId == itemId) f,
  ];

  bool get editable =>
      inspeccion.firmadaAt == null &&
      (inspeccion.estado == EstadoInspeccion.enCurso.wire ||
          inspeccion.estado == EstadoInspeccion.lista.wire);

  int get respondidos => items.where((i) => i.respondido).length;

  /// Primer ítem sin responder (donde se reanuda tras cerrar la app), o el
  /// último si están todos.
  int get primeroPendiente {
    final i = items.indexWhere((x) => !x.respondido);
    return i < 0 ? items.length - 1 : i;
  }
}

/// Estado anterior de una respuesta, para «Deshacer».
class RespuestaPrevia {
  const RespuestaPrevia({
    required this.inspeccionEquipoId,
    required this.itemId,
    this.estado,
    this.valor,
    this.observacion,
  });
  final String inspeccionEquipoId;
  final String itemId;
  final String? estado;
  final double? valor;
  final String? observacion;
}

/// Los datos de un movimiento de gas que se va a registrar (T11).
class MovimientoGasNuevo {
  const MovimientoGasNuevo({
    required this.tipo,
    required this.refrigerante,
    required this.kg,
    this.origen,
    this.datos = const DatosOrigenGas(),
    this.gestorNombre,
    this.gestorDocumento,
    this.motivo,
  });
  final TipoMovimientoGas tipo;
  final String refrigerante;
  final double kg;
  final OrigenGas? origen;
  final DatosOrigenGas datos;
  final String? gestorNombre;
  final String? gestorDocumento;

  /// `mantenimiento|fuga`.
  final String? motivo;
}

/// El art. 13.4 bloquea la carga: no se guarda.
class CargaGasBloqueada implements Exception {
  const CargaGasBloqueada(this.validacion);
  final CargaBloqueada validacion;
  @override
  String toString() => 'CargaGasBloqueada: ${validacion.motivo}';
}

/// Algo que impide firmar (T12): pulsable, lleva al ítem.
class PendienteFirma {
  const PendienteFirma({
    required this.inspeccionEquipoId,
    required this.equipo,
    required this.indiceItem,
    required this.texto,
  });
  final String? inspeccionEquipoId;
  final String equipo;
  final int? indiceItem;
  final String texto;
}

/// Se intentó firmar con pendientes (doble barrera: T12 ya los enseña).
class FirmaIncompleta implements Exception {
  const FirmaIncompleta(this.pendientes);
  final List<PendienteFirma> pendientes;
  @override
  String toString() => 'FirmaIncompleta: ${pendientes.length} pendientes';
}

/// Una firma dibujada en T13: nombre, cargo y el PNG (sin puntos ni tiempos,
/// §10).
class FirmaCapturada {
  const FirmaCapturada({required this.nombre, this.cargo, required this.png});
  final String nombre;
  final String? cargo;
  final Uint8List png;
}
