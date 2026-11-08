# Plantillas base de Inspecta (DISEÑO.md §4.1.4 y §7.4)

Cada fichero `<clave>.v<version>.json` es **una versión publicada** de una
plantilla base (`empresa_id` null) y se siembra tal cual en Drift y en
Postgres: las claves del JSON son exactamente las columnas de `plantillas` e
`items_plantilla` (snake_case). `created_at` y `updated_at` los pone quien
siembra.

```json
{ "plantilla": { …fila de plantillas… }, "items_plantilla": [ …filas… ] }
```

| Fichero | Plantilla | Ítems |
|---|---|---|
| `split_hasta_12kw.v1.json` | 1 · Split o autónomo ≤ 12 kW (RITE IT 3.3, Tablas 3.1 y 3.2) | 18 |
| `equipo_12_70kw.v1.json` | 2 · Equipo de 12 a 70 kW, en instalaciones ≤ 70 kW | 24 |
| `control_fugas.v1.json` | 3 · Control de fugas (Rgto. (UE) 2024/573 art. 5), cualquier potencia | 12 |

## Reglas

- **Una versión publicada no se toca** (trigger en Postgres, §7.4). Cambiar un
  ítem = fichero nuevo `<clave>.v2.json` con `version: 2` y `sustituye_a` = id
  de la v1. El fichero v1 se queda: hay informes firmados que apuntan a él.
- **Ids deterministas** (UUID v5, namespace `namespacePlantillas` de
  `lib/dominio/plantillas.dart`): `plantilla:<clave>:v<version>` y
  `item:<clave_plantilla>:v<version>:<clave_item>`. Así sembrar es idempotente
  en cualquier aparato y en el servidor. `parsearPlantilla` rechaza un id que
  no coincida y el mensaje dice cuál esperaba.
- **`clave` de ítem estable** y compartida entre plantillas cuando es la misma
  operación (`filtro_limpieza`, `salto_termico`…): la usa
  `estado_equipo.ultimos_valores_json` para el «último valor» (§6.0, §7.2).
  Una clave compartida tiene la misma `unidad` en todas las plantillas y
  versiones (cambiar de unidad = clave nueva), y el mismo `tipo_respuesta` y
  `codigo_normativo` en las versiones vigentes. Lo comprueba
  `comprobarClavesCompartidas` al cargar, no solo las pruebas.
- `tipo_respuesta`: `estado` (OK / Observación / Defecto / N.A.),
  `estado_valor` (los 4 botones y un valor), `solo_valor` (solo el valor) y
  `si_no`. Los de valor llevan `unidad`, `rango_min` < `rango_max`; el rango es
  **plausible**, no normativo: fuera de rango T6 avisa y no bloquea. Una
  medición **obligatoria** es `estado_valor`, nunca `solo_valor`: este no tiene
  N.A. y, si el equipo no arranca, el técnico tendría que inventarse un valor
  para poder firmar (F4.1). `parsearPlantilla` lo rechaza.
- **Presiones manométricas** (unidad `bar (man.)`), nunca absolutas: el
  «último valor» se compara entre visitas por `clave`. La intensidad
  (`intensidad_absorbida`, A) es por fase (en trifásico, la más cargada) y no
  es la «potencia eléctrica absorbida» (kW) de la IT 3.4.2.
- **`foto_obligatoria` no se exige si el ítem se marca N.A.**
  (`ItemPlantilla.exigeFoto`). Así, `etiqueta_fgas` en un equipo con
  refrigerante no fluorado (R-290, R-744) se marca N.A. sin foto: el art. 12
  del Rgto. 2024/573 solo pide etiqueta a los aparatos que contienen gases
  fluorados.
- `aplica_a`: `tipos` y `usos` (códigos wire de `lib/dominio/tipos.dart`),
  `potencia_min_kw` (exclusiva) y `potencia_max_kw` (inclusiva) del equipo,
  como en la Tabla 3.1 («12 kW < Pn ≤ 70 kW»); `potencia_instalacion_max_kw`
  (inclusiva; por encima de 70 kW la Tabla 3.1 pasa a «mensual» y la
  plantilla queda fuera del MVP); `intervenciones` (`ordenes_trabajo.tipo_intervencion`).
- `analizable_ia`: solo las fotos de estos ítems van a `analizar-foto` (§9.3),
  y solo en ítems de tipo `estado`. La etiqueta F-gas **no** es analizable: la
  decide el técnico (la IA no puede afirmar que falta con una sola foto).
  `parsearPlantilla` rechaza las dos cosas.

## Frontera de la plantilla 3 con T11 (§7.5)

La plantilla de control de fugas solo tiene **ítems de checklist**: qué se ha
mirado y en qué estado está (uniones, válvulas, compresor, baterías, sistema
de detección, etiqueta…). Los **datos del control** —método, modelo,
calibración y comprobación del detector, resultado (`sin_fuga|fuga`),
localización, reparación y fechas del nuevo control— no son ítems: se registran desde T11
en `controles_fugas`, y las cargas y recuperaciones en `movimientos_gas`.
Así el registro del art. 7 sale de esas tablas y no de respuestas de checklist,
y nada se apunta dos veces. Si el técnico marca un ítem como Defecto, abre una
incidencia (T10); la fuga en sí la declara T11.

Que un equipo esté sujeto a control de fugas, y cada cuánto, lo calcula
`fgas.dart`; la plantilla nunca lo decide.

El ítem `sistema_deteccion` («si lo hay») cita el art. 6.3 **solo cuando el
sistema es obligatorio** (art. 6.1-6.2: desde 500 t CO2-eq, o 100 kg de gases
del anexo II); un detector voluntario, el que se pone para pasar a 24 meses
por el art. 5, es buena práctica. Responder el ítem **no** actualiza
`equipos.deteccion_ultima_revision`, de la que sale el vencimiento «detector»
del PDF (§8.4, punto 7): esa fecha se anota en la ficha del equipo (T3) **[A VERIFICAR]**: DISEÑO.md no dice quién la actualiza.
