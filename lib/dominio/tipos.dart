// Tipos del dominio compartidos por la normativa (fgas.dart, rite.dart), las
// plantillas y la base de datos. En la base y en Postgres se guardan como
// texto con el código `wire` (DISEÑO.md §7.2); aquí son enums para que el
// compilador avise si falta un caso.

/// Tipo de equipo (`equipos.tipo`).
enum TipoEquipo {
  split('split'),
  conductos('conductos'),
  vrf('vrf'),
  rooftop('rooftop'),
  enfriadora('enfriadora'),
  bombaCalor('bomba_calor'),
  uta('uta'),
  otro('otro');

  const TipoEquipo(this.wire);
  final String wire;

  static TipoEquipo desde(String wire) => values.firstWhere(
    (t) => t.wire == wire,
    orElse: () => throw ArgumentError.value(wire, 'tipo', 'Tipo desconocido'),
  );
}

/// Categoría a efectos del Reglamento (UE) 2024/573 (`equipos.categoria_fgas`):
/// decide si aplica el art. 13.4 (aire acondicionado y bomba de calor) o el
/// 13.3 (refrigeración).
enum CategoriaFgas {
  aireAcondicionadoBombaCalor('aire_acondicionado_bomba_calor'),
  refrigeracion('refrigeracion'),
  otro('otro');

  const CategoriaFgas(this.wire);
  final String wire;

  static CategoriaFgas desde(String wire) => values.firstWhere(
    (c) => c.wire == wire,
    orElse: () =>
        throw ArgumentError.value(wire, 'categoria_fgas', 'Desconocida'),
  );
}

/// Uso del edificio (`instalaciones.uso_edificio`), que cambia la
/// periodicidad de la Tabla 3.1 del RITE.
enum UsoEdificio {
  vivienda('vivienda'),
  otros('otros');

  const UsoEdificio(this.wire);
  final String wire;

  static UsoEdificio desde(String wire) => values.firstWhere(
    (u) => u.wire == wire,
    orElse: () =>
        throw ArgumentError.value(wire, 'uso_edificio', 'Desconocido'),
  );
}
