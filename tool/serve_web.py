"""Sirve el build de web en local, con aislamiento entre origenes.

Sin estas dos cabeceras el navegador no da SharedArrayBuffer, y drift cae a
una implementacion peor. Cualquier hosting de produccion tiene que mandarlas.
"""
import functools, http.server, sys

class H(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Cross-Origin-Opener-Policy', 'same-origin')
        self.send_header('Cross-Origin-Embedder-Policy', 'require-corp')
        self.send_header('Cross-Origin-Resource-Policy', 'same-origin')
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()

d = sys.argv[1] if len(sys.argv) > 1 else 'build/web'
port = int(sys.argv[2]) if len(sys.argv) > 2 else 8080
print(f'Inspecta en http://localhost:{port}  (sirviendo {d})', flush=True)
http.server.ThreadingHTTPServer(
    ('127.0.0.1', port), functools.partial(H, directory=d)).serve_forever()
