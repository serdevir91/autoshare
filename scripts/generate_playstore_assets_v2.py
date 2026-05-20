from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps

ROOT = Path(r"c:/Users/serde/OneDrive/Belgeler/Desktop/Code/autoshare")
SRC_SS = [
    ROOT / "ss" / "ss1.jpeg",
    ROOT / "ss" / "ss2.jpeg",
    ROOT / "ss" / "ss3.jpeg",
    ROOT / "ss" / "ss4.jpeg",
]
ICON = ROOT / "assets" / "icon.png"

OUT = ROOT / "playstore_ready_v2"
PHONE = OUT / "phone"
TABLET7 = OUT / "tablet_7"
TABLET10 = OUT / "tablet_10"
SLIDES = OUT / "slides"
for d in [OUT, PHONE, TABLET7, TABLET10, SLIDES]:
    d.mkdir(parents=True, exist_ok=True)

font_bold_candidates = [
    r"C:/Windows/Fonts/segoeuib.ttf",
    r"C:/Windows/Fonts/arialbd.ttf",
]
font_reg_candidates = [
    r"C:/Windows/Fonts/segoeui.ttf",
    r"C:/Windows/Fonts/arial.ttf",
]


def load_font(cands: list[str], size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    for c in cands:
        p = Path(c)
        if p.exists():
            return ImageFont.truetype(str(p), size)
    return ImageFont.load_default()


def wrap(draw: ImageDraw.ImageDraw, text: str, font: ImageFont.ImageFont, max_w: int) -> list[str]:
    words = text.split()
    lines: list[str] = []
    cur = ""
    for w in words:
        t = w if not cur else cur + " " + w
        if draw.textbbox((0, 0), t, font=font)[2] <= max_w:
            cur = t
        else:
            if cur:
                lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return lines


phone_specs = [
    (
        "01_share_fast.jpg",
        "Share Files in Seconds",
        "Send photos, videos, documents and APK files across nearby devices over local Wi-Fi.",
        0,
    ),
    (
        "02_pair_securely.jpg",
        "Pair Once, Share Safely",
        "Approve trusted devices and transfer privately inside your own network.",
        1,
    ),
    (
        "03_open_apk_native.jpg",
        "Open APK with Native Installer",
        "Tap an APK file to launch Android native app installer quickly and safely.",
        2,
    ),
    (
        "04_manage_files.jpg",
        "Built-In File Manager",
        "Browse folders, move files, create directories, and keep your storage organized.",
        3,
    ),
    (
        "05_no_cloud_needed.jpg",
        "No Cloud, No Waiting",
        "Direct local transfer means your files stay on your devices and move faster.",
        0,
    ),
    (
        "06_cross_device.jpg",
        "Phone to Phone, Phone to PC",
        "AutoShare works across nearby devices on the same Wi-Fi network.",
        1,
    ),
]

for name, title, subtitle, idx in phone_specs:
    w, h = 1080, 1920
    base = Image.new("RGB", (w, h), (11, 23, 43))
    draw = ImageDraw.Draw(base)

    for y in range(h):
        t = y / h
        r = int(11 + (20 - 11) * t)
        g = int(23 + (39 - 23) * t)
        b = int(43 + (70 - 43) * t)
        draw.line([(0, y), (w, y)], fill=(r, g, b))

    panel_h = 430
    draw.rounded_rectangle(
        [34, 34, w - 34, panel_h],
        radius=34,
        fill=(8, 16, 30, 230),
        outline=(54, 209, 186, 220),
        width=3,
    )

    title_f = load_font(font_bold_candidates, 70)
    sub_f = load_font(font_reg_candidates, 37)
    badge_f = load_font(font_bold_candidates, 30)

    badge = "AUTOSHARE"
    bw = draw.textbbox((0, 0), badge, font=badge_f)[2] + 26
    draw.rounded_rectangle([62, 62, 62 + bw, 110], radius=14, fill=(24, 190, 164, 255))
    draw.text((75, 72), badge, font=badge_f, fill="white")

    y = 136
    for line in wrap(draw, title, title_f, w - 124)[:2]:
        draw.text((62, y), line, font=title_f, fill="white")
        y += 76
    y += 12
    for line in wrap(draw, subtitle, sub_f, w - 124)[:3]:
        draw.text((62, y), line, font=sub_f, fill=(219, 233, 255))
        y += 46

    card = [80, 500, w - 80, h - 84]
    draw.rounded_rectangle(card, radius=58, fill=(235, 242, 252), outline=(255, 255, 255, 220), width=2)

    ss = Image.open(SRC_SS[idx]).convert("RGB")
    inner_w = card[2] - card[0] - 42
    inner_h = card[3] - card[1] - 42
    ss_fit = ImageOps.fit(ss, (inner_w, inner_h), method=Image.Resampling.LANCZOS)
    base.paste(ss_fit, (card[0] + 21, card[1] + 21))

    footer_f = load_font(font_reg_candidates, 30)
    footer = "Private • Local • Fast"
    fw = draw.textbbox((0, 0), footer, font=footer_f)[2]
    fx = (w - fw) // 2
    draw.rounded_rectangle([fx - 16, h - 70, fx + fw + 16, h - 26], radius=14, fill=(7, 16, 30, 215))
    draw.text((fx, h - 64), footer, font=footer_f, fill=(255, 255, 255))

    base.save(PHONE / name, quality=95)

slide_specs = [
    (
        "07_why_autoshare.jpg",
        "Why AutoShare?",
        [
            "No internet upload required",
            "Local Wi-Fi transfer",
            "Built-in pairing and file manager",
            "Designed for speed and privacy",
        ],
    ),
    (
        "08_core_features.jpg",
        "Core Features",
        [
            "Nearby device discovery",
            "Secure pairing requests",
            "One-tap APK installer",
            "Folder move and organize tools",
        ],
    ),
]
for name, title, bullets in slide_specs:
    w, h = 1080, 1920
    img = Image.new("RGB", (w, h), (10, 22, 40))
    d = ImageDraw.Draw(img)
    for y in range(h):
        t = y / h
        d.line([(0, y), (w, y)], fill=(int(10 + 14 * t), int(22 + 25 * t), int(40 + 55 * t)))

    d.ellipse([730, -120, 1230, 380], fill=(24, 190, 164, 80))
    d.ellipse([-180, 1420, 360, 1960], fill=(64, 126, 255, 70))

    title_f = load_font(font_bold_candidates, 82)
    body_f = load_font(font_reg_candidates, 42)
    badge_f = load_font(font_bold_candidates, 30)

    d.rounded_rectangle([52, 52, 52 + 220, 100], radius=14, fill=(24, 190, 164, 255))
    d.text((67, 63), "AUTOSHARE", font=badge_f, fill="white")

    y = 170
    for line in wrap(d, title, title_f, 960)[:2]:
        d.text((60, y), line, font=title_f, fill="white")
        y += 90

    y += 40
    for b in bullets:
        d.rounded_rectangle([66, y + 10, 84, y + 28], radius=6, fill=(24, 190, 164, 255))
        for line in wrap(d, b, body_f, 900):
            d.text((102, y), line, font=body_f, fill=(222, 236, 255))
            y += 52
        y += 16

    img.save(SLIDES / name, quality=95)
    img.save(PHONE / name, quality=95)


def make_tablet(dst_dir: Path, suffix: str) -> None:
    tablet_specs = [
        ("01_dashboard_" + suffix + ".jpg", "Nearby Devices and Pairing", 0),
        ("02_transfer_" + suffix + ".jpg", "Fast Local File Transfer", 1),
        ("03_apk_" + suffix + ".jpg", "APK Install from File Manager", 2),
        ("04_privacy_" + suffix + ".jpg", "Private Sharing on Your Network", 3),
    ]
    for name, title, idx in tablet_specs:
        w, h = 1920, 1080
        canvas = Image.new("RGB", (w, h), (13, 25, 44))
        d = ImageDraw.Draw(canvas)
        for y in range(h):
            t = y / h
            d.line([(0, y), (w, y)], fill=(int(13 + 20 * t), int(25 + 24 * t), int(44 + 38 * t)))

        d.rounded_rectangle([40, 40, 820, h - 40], radius=30, fill=(7, 16, 30, 220), outline=(54, 209, 186, 220), width=3)
        tf = load_font(font_bold_candidates, 66)
        sf = load_font(font_reg_candidates, 36)
        badge_f = load_font(font_bold_candidates, 28)
        d.rounded_rectangle([72, 70, 72 + 200, 114], radius=12, fill=(24, 190, 164, 255))
        d.text((86, 78), "AUTOSHARE", font=badge_f, fill="white")
        y = 150
        for line in wrap(d, title, tf, 700)[:3]:
            d.text((72, y), line, font=tf, fill="white")
            y += 74
        y += 16
        for line in wrap(d, "Send files directly between nearby devices without cloud upload.", sf, 700)[:3]:
            d.text((72, y), line, font=sf, fill=(220, 233, 255))
            y += 46

        panel = [860, 80, w - 50, h - 80]
        d.rounded_rectangle(panel, radius=36, fill=(233, 241, 251), outline=(255, 255, 255), width=2)
        ss = Image.open(SRC_SS[idx]).convert("RGB")
        fit = ImageOps.fit(ss, (panel[2] - panel[0] - 30, panel[3] - panel[1] - 30), method=Image.Resampling.LANCZOS)
        canvas.paste(fit, (panel[0] + 15, panel[1] + 15))
        canvas.save(dst_dir / name, quality=95)


make_tablet(TABLET7, "7in")
make_tablet(TABLET10, "10in")

fg = Image.new("RGB", (1024, 500), (12, 26, 48))
d = ImageDraw.Draw(fg)
for y in range(500):
    t = y / 500
    d.line([(0, y), (1024, y)], fill=(int(12 + 16 * t), int(26 + 18 * t), int(48 + 30 * t)))

d.ellipse([760, -90, 1130, 260], fill=(24, 190, 164, 90))
d.ellipse([-140, 300, 240, 680], fill=(64, 126, 255, 70))

if ICON.exists():
    icon = Image.open(ICON).convert("RGBA").resize((164, 164), Image.Resampling.LANCZOS)
    fg.paste(icon, (70, 84), icon)

h1 = load_font(font_bold_candidates, 74)
h2 = load_font(font_reg_candidates, 34)
b3 = load_font(font_reg_candidates, 28)

d.text((260, 104), "AutoShare", font=h1, fill="white")
d.text((260, 194), "Private local file sharing over Wi-Fi", font=h2, fill=(219, 233, 255))
d.text((260, 242), "Pair devices, transfer fast, manage files easily.", font=h2, fill=(219, 233, 255))

chip_items = ["Fast transfer", "APK installer", "Built-in file manager"]
chip_gap = 14
chip_h = 48
chip_y = 312
chip_w_list: list[int] = []
for txt in chip_items:
    tw = d.textbbox((0, 0), txt, font=b3)[2]
    chip_w_list.append(tw + 36)

total_chip_w = sum(chip_w_list) + chip_gap * (len(chip_w_list) - 1)
start_x = max(260, (1024 - total_chip_w) // 2)
x = start_x
for idx, txt in enumerate(chip_items):
    cw = chip_w_list[idx]
    d.rounded_rectangle([x, chip_y, x + cw, chip_y + chip_h], radius=14, fill=(7, 16, 30, 220), outline=(54, 209, 186, 210), width=2)
    tw = d.textbbox((0, 0), txt, font=b3)[2]
    d.text((x + (cw - tw) // 2, chip_y + 12), txt, font=b3, fill="white")
    x += cw + chip_gap

fg.save(OUT / "feature_graphic_1024x500.jpg", quality=95)

short_desc = "Fast local Wi-Fi file sharing with secure pairing and built-in file manager."
full_desc = """AutoShare is a local network file sharing app built for fast, private transfers between nearby devices.

Why AutoShare:
• Share files directly over local Wi-Fi
• No cloud upload needed
• Pair trusted devices for safer transfers
• Open APK files with Android native installer
• Manage received files with built-in file manager

What you can do:
• Discover nearby devices automatically
• Send photos, videos, documents, and app files
• Accept or reject pairing requests
• Move, organize, and browse folders in one place
• Track transfer progress with notifications

Privacy first:
AutoShare is designed for local sharing. Your files stay on your devices and move only between devices you connect.

Best for:
• Phone-to-phone transfer
• Phone-to-PC local sharing
• Quick offline file exchange at home, office, or hotspot

Use AutoShare when you want simple, fast, and private file transfer without cloud friction."""

(OUT / "store_text_en.txt").write_text(
    "APP NAME:\nAutoShare\n\nSHORT DESCRIPTION (<=80):\n"
    + short_desc
    + f"\nLength: {len(short_desc)}\n\nFULL DESCRIPTION:\n"
    + full_desc,
    encoding="utf-8",
)

print("Generated assets in:", OUT)
for folder in [PHONE, TABLET7, TABLET10, SLIDES]:
    print(folder)
    for p in sorted(folder.glob("*.jpg")):
        with Image.open(p) as im:
            print(" ", p.name, im.size)
print("Feature:", OUT / "feature_graphic_1024x500.jpg")
