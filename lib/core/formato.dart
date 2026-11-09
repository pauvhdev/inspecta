// Formato de números y fechas en español de España, sin depender de `intl`.

import '../dominio/normativa.dart' show DiaCalendario, enHoraLocal;

/// 25.056 → «25,06»; 12.0 → «12». Hasta [decimales] decimales, sin ceros de
/// sobra.
String numero(double v, {int decimales = 2}) {
  var s = v.toStringAsFixed(decimales);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
  return s.replaceAll('.', ',');
}

/// «12 kW», o «—» si no hay dato.
String kw(double? v) => v == null ? '—' : '${numero(v, decimales: 1)} kW';

String _dos(int n) => n.toString().padLeft(2, '0');

/// Día de calendario como `dd/mm/aaaa`.
String dia(DiaCalendario d) => '${_dos(d.dia)}/${_dos(d.mes)}/${d.anio}';

/// Día local de un instante como `dd/mm/aaaa`.
String fecha(DateTime instante) => dia(DiaCalendario.deInstante(instante));

/// Fecha `SoloFecha` (medianoche UTC) como `dd/mm/aaaa`, sin cambiar de zona.
String soloFecha(DateTime d) => dia(DiaCalendario.deComponentes(d));

/// Hora local `HH:mm` de un instante.
String hora(DateTime instante) {
  final l = enHoraLocal(instante);
  return '${_dos(l.hour)}:${_dos(l.minute)}';
}
