# Inspecta — guía para trabajar en este repo

App Flutter de partes e inspecciones para empresas mantenedoras de
climatización en España: el técnico hace la visita entera sin cobertura
(checklist RITE, fotos, notas de voz, registro de gases fluorados, firma y PDF)
y todo se sincroniza con Supabase al volver la red. La IA (Gemini en Edge
Functions) lee placas, propone incidencias en fotos y convierte la voz en
campos del parte.

**El diseño completo está en [`docs/DISEÑO.md`](docs/DISEÑO.md).** Antes de
cambiar el modelo de datos, la sincronización, la IA o el plan, léelo: las
decisiones tomadas están en el §14.

## Reglas que no se rompen

1. **Offline-first:** ninguna pantalla espera a la red. Drift es la fuente de
   verdad en el móvil; la red solo sincroniza.
2. **Un informe firmado no se toca.** Ni su contenido, ni su PDF, ni su hash.
3. **La IA propone y el técnico confirma.** Nada de la IA entra en el PDF sin
   una decisión registrada en `decisiones_ia`, descartes incluidos.
4. **Las cifras normativas las calcula el código** (PCG, t CO2-eq,
   periodicidades, plazos, bloqueo del art. 13.4), con pruebas y datos
   versionados en `assets/normativa/`. La IA nunca da una cifra normativa.
5. **La clave de Gemini solo vive en Edge Functions.** Nunca en la app, nunca
   en `env.json`, nunca en el repositorio.
6. **Cada tabla sincronizada lleva `id`, `empresa_id`, `updated_at`** y su
   prueba de RLS.
7. **Nada mutable vive en una fila hija de un informe firmado:** va en filas
   nuevas o lo deriva un trigger.
8. **El número de un informe firmado no cambia nunca.**

## Principios de la IA (DISEÑO.md §9.1)

- La gravedad legal (leve, grave, muy grave) la elige una persona, sin valor
  por defecto. La IA solo sugiere una prioridad de revisión.
- Salida estructurada siempre (`responseSchema`), enums cerrados y validación
  en el servidor antes de guardar.
- La IA nunca bloquea el trabajo del técnico.
- Cada propuesta guarda `modelo` y `version_prompt`.
- **Capa gratuita de Gemini** (decisión de Pau): solo se envían fotos de
  equipos y datos inventados. Nunca personas, clientes ni datos reales.

## Diseño para el técnico en la azotea (DISEÑO.md §6.0)

- Objetivos táctiles de 56 dp como mínimo (72 las acciones primarias, 88 foto y
  voz) y 12 dp entre ellos: se usa con guantes. Usa `Touch` de
  `lib/design/tokens.dart`.
- Ninguna acción depende solo de un gesto: siempre hay botón.
- El estado va siempre con icono + texto + color.
- Tema Sol (claro, contraste máximo) por defecto; Sótano (oscuro) a un toque.

## Comandos

Flutter va fijado con FVM a la 3.47.9 (`.fvmrc`), sin tocar el SDK global con
el que se publica Forja. Usa siempre `fvm flutter …`.

```bash
fvm flutter pub get
fvm flutter test
fvm flutter analyze
fvm dart run build_runner build     # regenerar Drift tras tocar tablas
fvm flutter run -d chrome            # modo local, sin Supabase
fvm flutter run --dart-define-from-file=env.json   # con Supabase
```

`env.json` no se sube nunca (está en `.gitignore`); la plantilla es
`env.example.json`.

## Origen del código

Parte de la infraestructura viene de Forja (`forja`): cola de
salida, sincronización, codecs, ids, tema. El §8.6 del diseño dice qué se
reutiliza y cómo se adapta. No modifiques Forja desde aquí.
