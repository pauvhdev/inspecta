/// Configuración de entorno.
///
/// Los valores llegan por `--dart-define-from-file=env.json`, nunca desde un
/// fichero committeado. Arranca la app así:
///
///     flutter run --dart-define-from-file=env.json
///
/// La anon key de Supabase es pública por diseño (la protege el RLS), pero la
/// URL del proyecto cambia entre dev y prod, así que tampoco va incrustada.
///
/// La API key de Gemini NO aparece aquí a propósito: vive en los secretos de
/// Supabase y solo la ve la Edge Function. Cualquier clave dentro del APK se
/// extrae en dos minutos con `apktool`.
class Env {
  const Env._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Nombre visible de la app. Separado del nombre del paquete Dart para
  /// poder cambiar la marca sin tocar un solo import.
  static const appName = String.fromEnvironment(
    'APP_NAME',
    defaultValue: 'Inspecta',
  );

  /// Demo pública: modo local con una empresa mantenedora inventada, sus
  /// clientes, equipos y órdenes (DISEÑO.md §11.1). Sin Supabase no hace nada.
  static const demo = bool.fromEnvironment('INSPECTA_DEMO');

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Mensaje accionable en vez de un crash opaco al arrancar.
  static String get missingConfigMessage => '''
Falta la configuración de Supabase.

Crea un fichero env.json en la raíz del proyecto:

{
  "SUPABASE_URL": "https://TU-PROYECTO.supabase.co",
  "SUPABASE_ANON_KEY": "eyJ..."
}

Y arranca con:

  flutter run --dart-define-from-file=env.json
''';
}
