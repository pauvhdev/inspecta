import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inspecta/data/local/app_database.dart';
import 'package:inspecta/data/sync/outbox.dart';

void main() {
  late AppDatabase db;
  late Outbox outbox;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    outbox = Outbox(db);
  });

  tearDown(() => db.close());

  Future<void> encolarInspeccionYFoto(String inspeccion, String foto) async {
    await outbox.enqueueUpsert(
      entity: 'inspecciones',
      rowId: inspeccion,
      payload: {'id': inspeccion, 'estado': 'en_curso'},
    );
    await outbox.enqueueUpsert(
      entity: 'fotos',
      rowId: foto,
      payload: {'id': foto, 'inspeccion_id': inspeccion, 'ruta': 'f.jpg'},
    );
  }

  test('bloquear una inspección aparta también su foto', () async {
    await encolarInspeccionYFoto('r1', 'a1');

    final lote = await outbox.nextBatch();
    final inspeccion = lote.firstWhere((e) => e.entity == 'inspecciones');

    // El servidor rechaza la inspección. Sin arrastrar a la foto, esta se
    // subiría apuntando a una inspección que no existe: un 23503 que además
    // taparía la causa real.
    await outbox.markBlocked(inspeccion.seq, '42501 nueva politica de RLS');
    final arrastradas = await outbox.blockDependents(
      inspeccion.seq,
      inspeccion.rowId,
    );

    expect(arrastradas, 1);
    expect(await outbox.nextBatch(), isEmpty);

    final bloqueadas = await outbox.watchBlocked().first;
    expect(bloqueadas, hasLength(2));
  });

  test('la causa es la entrada más vieja, no la más nueva', () async {
    await encolarInspeccionYFoto('r1', 'a1');
    final lote = await outbox.nextBatch();
    final inspeccion = lote.firstWhere((e) => e.entity == 'inspecciones');

    await outbox.markBlocked(inspeccion.seq, '42501 nueva politica de RLS');
    await outbox.blockDependents(inspeccion.seq, inspeccion.rowId);

    // watchBlocked ordena de más nueva a más vieja. La pantalla enseña `last`
    // justamente por esto: `first` mostraba la consecuencia.
    final bloqueadas = await outbox.watchBlocked().first;
    expect(bloqueadas.last.entity, 'inspecciones');
    expect(bloqueadas.last.lastError, contains('42501'));
    expect(bloqueadas.first.entity, 'fotos');
  });

  test('no arrastra lo que no depende de la fila bloqueada', () async {
    await encolarInspeccionYFoto('r1', 'a1');
    await outbox.enqueueUpsert(
      entity: 'equipos',
      rowId: 'e1',
      payload: {'id': 'e1', 'marca': 'Daikin'},
    );

    final lote = await outbox.nextBatch();
    final inspeccion = lote.firstWhere((e) => e.entity == 'inspecciones');
    await outbox.markBlocked(inspeccion.seq, 'error');
    await outbox.blockDependents(inspeccion.seq, inspeccion.rowId);

    // El equipo no tiene nada que ver con la inspección: debe seguir subiendo.
    final quedan = await outbox.nextBatch();
    expect(quedan.map((e) => e.entity), ['equipos']);
  });

  test('reintentar devuelve todo a la cola', () async {
    await encolarInspeccionYFoto('r1', 'a1');
    final lote = await outbox.nextBatch();
    final inspeccion = lote.firstWhere((e) => e.entity == 'inspecciones');
    await outbox.markBlocked(inspeccion.seq, 'error');
    await outbox.blockDependents(inspeccion.seq, inspeccion.rowId);
    expect(await outbox.nextBatch(), isEmpty);

    // Descartar tiraría partes de verdad; reintentar es lo que se quiere
    // cuando la causa se ha corregido en el servidor.
    await outbox.retryBlocked();

    final vuelta = await outbox.nextBatch();
    expect(vuelta, hasLength(2));
    expect(vuelta.first.entity, 'inspecciones', reason: 'el padre, primero');
    expect(await outbox.watchBlocked().first, isEmpty);
  });

  test('reintentar no resucita lo que ya se subio', () async {
    await encolarInspeccionYFoto('r1', 'a1');
    final lote = await outbox.nextBatch();
    for (final e in lote) {
      await outbox.markDone(e.seq);
    }

    // Lo que subio bien esta fuera de la cola: retryBlocked no puede traerlo
    // de vuelta y subirlo dos veces.
    await outbox.retryBlocked();
    expect(await outbox.nextBatch(), isEmpty);
  });

  test('reintentar con la cola limpia no hace nada raro', () async {
    await outbox.retryBlocked();
    expect(await outbox.nextBatch(), isEmpty);
    expect(await outbox.watchBlocked().first, isEmpty);
  });

  test('un cambio que llega mientras sube la respuesta no se pierde', () async {
    await outbox.enqueueUpsert(
      entity: 'respuestas',
      rowId: 's1',
      payload: {'id': 's1', 'valor': 7.2, 'estado': 'observacion'},
    );
    // El motor coge la entrada y empieza a subirla...
    final enviada = (await outbox.nextBatch()).single;

    // ...y mientras tanto se cambia a "defecto". La entrada aún tiene 0
    // intentos, así que la coalescencia la reescribe en vez de crear otra.
    await outbox.enqueueUpsert(
      entity: 'respuestas',
      rowId: 's1',
      payload: {'id': 's1', 'valor': 7.2, 'estado': 'defecto'},
    );

    // Acaba la subida de lo viejo. Borrar la entrada tiraba el cambio.
    await outbox.markDone(enviada.seq, enviado: enviada.payload);

    final queda = (await outbox.nextBatch()).single;
    expect(queda.payload, contains('"defecto"'));

    // Y cuando sube lo nuevo, ya sí se va.
    await outbox.markDone(queda.seq, enviado: queda.payload);
    expect(await outbox.nextBatch(), isEmpty);
  });

  test('descartar una fila tira sus cambios y deja los demás', () async {
    await outbox.enqueueUpsert(
      entity: 'respuestas',
      rowId: 's1',
      payload: {'id': 's1', 'valor': 5},
    );
    await outbox.enqueueUpsert(
      entity: 'equipos',
      rowId: 'w2',
      payload: {'id': 'w2'},
    );

    final s1 = (await outbox.nextBatch()).firstWhere((e) => e.rowId == 's1');
    await outbox.descartarFila(s1.seq, 's1');

    final quedan = await outbox.nextBatch();
    expect(quedan.map((e) => e.rowId), ['w2']);
  });
}
