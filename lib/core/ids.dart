import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Genera identificadores en el cliente, no en el servidor.
///
/// Esto es la pieza que hace posible el offline: si el id lo asignara Postgres,
/// no podrías crear una serie sin red ni referenciarla desde otra fila hasta
/// que subiera. Con UUID v4 generado en el móvil, la fila nace completa y la
/// sincronización es un simple upsert idempotente: reintentar no duplica nada.
String newId() => _uuid.v4();
