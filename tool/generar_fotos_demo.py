"""Genera las «fotos de ejemplo» de la demo (DISEÑO.md §11.1).

No son fotos reales: son ilustraciones dibujadas aquí, con la marca
«IMAGEN DE EJEMPLO GENERADA», para que la demo web funcione sin cámara y sin
enseñar instalaciones de nadie. Uso: python -I tool/generar_fotos_demo.py
"""
import os
import random

from PIL import Image, ImageDraw, ImageFilter, ImageFont

SALIDA = os.path.join(os.path.dirname(__file__), '..', 'assets', 'demo')
W, H = 1200, 900


def fuente(t):
    for nombre in ('arialbd.ttf', 'arial.ttf', 'DejaVuSans-Bold.ttf'):
        try:
            return ImageFont.truetype(nombre, t)
        except OSError:
            pass
    return ImageFont.load_default()


def marca(d):
    d.rectangle([0, H - 70, W, H], fill=(20, 20, 20))
    d.text((30, H - 58), 'IMAGEN DE EJEMPLO GENERADA · Inspecta demo', font=fuente(34), fill=(255, 210, 0))


def fondo(color):
    img = Image.new('RGB', (W, H), color)
    d = ImageDraw.Draw(img)
    rnd = random.Random(7)
    for _ in range(4000):
        x, y = rnd.randrange(W), rnd.randrange(H)
        c = tuple(max(0, min(255, v + rnd.randint(-18, 18))) for v in color)
        d.point((x, y), fill=c)
    return img, d


def etiqueta():
    img, d = fondo((188, 190, 186))
    d.rounded_rectangle([170, 150, 1030, 720], 24, fill=(250, 250, 245), outline=(40, 40, 40), width=6)
    d.text((210, 185), 'Contiene gases fluorados de efecto invernadero', font=fuente(31), fill=(0, 0, 0))
    filas = [('Refrigerante', 'R-410A'), ('Carga', '12,0 kg'), ('PCG', '2.088'),
             ('t CO2-eq', '25,05'), ('Sellado hermético', 'No')]
    for i, (k, v) in enumerate(filas):
        y = 270 + i * 80
        d.text((220, y), k, font=fuente(40), fill=(60, 60, 60))
        d.text((700, y), v, font=fuente(44), fill=(0, 0, 0))
        d.line([210, y + 62, 990, y + 62], fill=(170, 170, 170), width=2)
    marca(d)
    return img


def placa():
    img, d = fondo((90, 96, 104))
    d.rectangle([120, 120, 1080, 760], fill=(205, 208, 212), outline=(30, 30, 30), width=8)
    for x, y in ((150, 150), (1050, 150), (150, 730), (1050, 730)):
        d.ellipse([x - 14, y - 14, x + 14, y + 14], fill=(120, 120, 120))
    d.text((180, 180), 'MARCA FICTICIA   ·   VRF-400', font=fuente(50), fill=(10, 10, 10))
    datos = ['N.º serie: DEMO-HOTEL_VRF', 'Frío: 40,0 kW   Calor: 45,0 kW', 'Refrigerante: R-410A  12,0 kg',
             '400 V 3N~ 50 Hz', 'PS alta: 4,15 MPa   PS baja: 2,21 MPa']
    for i, t in enumerate(datos):
        d.text((180, 290 + i * 80), t, font=fuente(42), fill=(20, 20, 20))
    marca(d)
    return img.filter(ImageFilter.GaussianBlur(0.6))


def filtro():
    img, d = fondo((215, 215, 210))
    d.rectangle([200, 140, 1000, 740], fill=(150, 140, 120), outline=(70, 70, 70), width=10)
    rnd = random.Random(3)
    for x in range(220, 990, 18):
        d.line([x, 150, x, 730], fill=(110, 100, 85), width=6)
    for _ in range(220):
        x, y, r = rnd.randrange(220, 980), rnd.randrange(160, 720), rnd.randrange(6, 26)
        d.ellipse([x - r, y - r, x + r, y + r], fill=(95, 85, 70))
    d.text((230, 80), 'Filtro de retorno (ejemplo)', font=fuente(44), fill=(30, 30, 30))
    marca(d)
    return img


if __name__ == '__main__':
    os.makedirs(SALIDA, exist_ok=True)
    for nombre, f in (('etiqueta_fgas', etiqueta), ('placa', placa), ('filtro', filtro)):
        ruta = os.path.join(SALIDA, f'{nombre}.jpg')
        f().save(ruta, quality=80)
        print(ruta, os.path.getsize(ruta))
