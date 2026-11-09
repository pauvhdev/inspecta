import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../design/widgets.dart';
import '../dominio/estados.dart';
import '../dominio/plantillas.dart' show TipoIntervencion;
import '../dominio/tipos.dart';

// Textos visibles de los enums del dominio.

String textoTipoEquipo(TipoEquipo t) => switch (t) {
  TipoEquipo.split => 'Split',
  TipoEquipo.conductos => 'Conductos',
  TipoEquipo.vrf => 'VRF',
  TipoEquipo.rooftop => 'Rooftop',
  TipoEquipo.enfriadora => 'Enfriadora',
  TipoEquipo.bombaCalor => 'Bomba de calor',
  TipoEquipo.uta => 'UTA',
  TipoEquipo.otro => 'Otro',
};

String textoIntervencion(TipoIntervencion t) => switch (t) {
  TipoIntervencion.preventivo => 'Preventivo',
  TipoIntervencion.correctivo => 'Correctivo',
  TipoIntervencion.controlFugas => 'Control de fugas',
  TipoIntervencion.recontrolFugas => 'Nuevo control de fugas',
  TipoIntervencion.puestaMarcha => 'Puesta en marcha',
};

String textoCategoria(CategoriaFgas c) => switch (c) {
  CategoriaFgas.aireAcondicionadoBombaCalor =>
    'Aire acondicionado o bomba de calor',
  CategoriaFgas.refrigeracion => 'Refrigeración',
  CategoriaFgas.otro => 'Otro',
};

String textoUso(UsoEdificio u) => switch (u) {
  UsoEdificio.vivienda => 'Vivienda',
  UsoEdificio.otros => 'Restantes usos',
};

String textoSiNo(bool? b) => switch (b) {
  true => 'Sí',
  false => 'No',
  null => 'No consta',
};

/// Estado de la orden con icono + texto + color (§6.0).
Etiqueta etiquetaEstadoOrden(EstadoOrden e, {bool sinSubir = false}) =>
    switch (e) {
      EstadoOrden.pendiente => const Etiqueta(
        texto: 'Pendiente',
        icono: Icons.schedule,
        color: InspectaColors.noAplica,
        fondo: InspectaColors.noAplicaBg,
      ),
      EstadoOrden.enCurso => const Etiqueta(
        texto: 'En curso',
        icono: Icons.play_circle_outline,
        color: InspectaColors.accent,
        fondo: Color(0xFFE3EDFB),
      ),
      EstadoOrden.firmada when sinSubir => const Etiqueta(
        texto: 'Firmada · sin subir',
        icono: Icons.cloud_upload_outlined,
        color: InspectaColors.pending,
        fondo: InspectaColors.pendingBg,
      ),
      EstadoOrden.firmada => const Etiqueta(
        texto: 'Firmada',
        icono: Icons.check_circle_outline,
        color: InspectaColors.ok,
        fondo: InspectaColors.okBg,
      ),
      EstadoOrden.cancelada => const Etiqueta(
        texto: 'Cancelada',
        icono: Icons.cancel_outlined,
        color: InspectaColors.defecto,
        fondo: InspectaColors.defectoBg,
      ),
    };

String textoGravedad(String? g) => switch (g) {
  'leve' => 'Leve',
  'grave' => 'Grave',
  'muy_grave' => 'Muy grave',
  _ => 'Sin gravedad',
};
