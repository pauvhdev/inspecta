// Worker de drift compilado desde la version exacta que usa este proyecto.
//
// El `drift_worker.js` que se publica en las releases de GitHub puede no
// cuadrar con la version del paquete que tengas en pubspec.lock, y el sintoma
// es peor que un error: la base abre y la primera consulta se queda colgada
// para siempre, sin decir nada.
//
// Regenerar con:
//   dart compile js -O4 tool/drift_worker.dart -o web/drift_worker.js
import 'package:drift/wasm.dart';

void main() => WasmDatabase.workerMainForOpen();
