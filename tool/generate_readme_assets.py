"""Generate documentation images from the existing demo UI previews.

Optional documentation tool; requires Python and Pillow, not used by the app.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

PROJECT = Path(__file__).resolve().parents[1]
OUTPUT = PROJECT / 'docs' / 'media'
PREVIEWS = PROJECT / 'build' / 'ui-previews'


def generate():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    w, h = 1440, 360
    banner = Image.new('RGB', (w, h))
    pixels = banner.load()
    for y in range(h):
        for x in range(w):
            left = max(0, 1 - ((x / w) ** 2 + (y / h * .6) ** 2) ** .5)
            right = max(0, 1 - (((x - w) / w) ** 2 + ((y - h) / h * .5) ** 2) ** .5)
            pixels[x, y] = (int(5 + 29 * left), int(14 + 42 * left + 10 * right), int(26 + 69 * left + 15 * right))
    draw = ImageDraw.Draw(banner)
    regular = PROJECT / 'assets/fonts/NotoSans-Regular.ttf'
    bold = PROJECT / 'assets/fonts/NotoSans-Bold.ttf'
    def font(size, heavy=False):
        return ImageFont.truetype(str(bold if heavy else regular), size)
    draw.ellipse((1080, -130, 1620, 410), outline='#284C73', width=2)
    draw.ellipse((1160, -60, 1550, 330), outline='#226272', width=2)
    logo = Image.open(PROJECT / 'assets/branding/ledgy-icon-1024.png').convert('RGBA')
    logo.thumbnail((150, 150), Image.Resampling.LANCZOS)
    banner.paste(logo, (76, 71), logo)
    draw.text((266, 61), 'Ledgy 2.0', font=font(72, True), fill='#F3F7FF')
    draw.text((270, 167), 'Catat. Pahami. Kendalikan.', font=font(32), fill='#C3CFE2')
    chips = [('OFFLINE FIRST', 236), ('ANDROID', 176), ('WINDOWS', 182)]
    left = 270
    for text, width in chips:
        draw.rounded_rectangle((left, 237, left + width, 281), radius=22, fill='#142B46', outline='#3F688A')
        draw.text((left + 19, 246), text, font=font(19, True), fill='#45CCD7')
        left += width + 14
    banner.save(OUTPUT / 'ledgy-banner.png', optimize=True)

    previews = {
        'dashboard-desktop.png': ('dashboard-1440.png', None),
        'dashboard-mobile.png': ('dashboard-390.png', None),
        'transaction-form.png': ('new-transaction-390.png', (0, 200, 390, 844)),
        'quick-input-confirmation.png': ('prompt-transfer-390.png', (0, 94, 390, 844)),
        'settings-security.png': ('settings-1280.png', None),
        'transaction-filter.png': ('transaction-filter-text-only.png', None),
        'budget-recurring.png': ('budget-recurring-1280.png', None),
    }
    for destination, (source, crop) in previews.items():
        image = Image.open(PREVIEWS / source).convert('RGB')
        if crop:
            image = image.crop(crop)
        image.save(OUTPUT / destination, optimize=True)
        print(destination, image.size)


if __name__ == '__main__':
    generate()
