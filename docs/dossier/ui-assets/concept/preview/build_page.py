"""Builds the 'Clic de brique' preview page (A08 concept v3.2).

Usage: python -I build_page.py <repo_root> <output.html>
Injects the COHUE 16 palette, the brick icons and portraits as data URIs, and the markup of the three
stages (level up, Victory, HUD) laid out at the Figma coordinates (844 x 390, phone landscape).
"""
import base64
import io
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO, OUT = sys.argv[1], sys.argv[2]
UI = os.path.join(REPO, "docs", "dossier", "ui-assets")

PAL = {"Ink": "1C1726", "Cream": "FFE8B8", "Tomato": "E63946", "Leaf": "3DBE4A", "Gold": "FFC21A",
       "Royal": "2D6BE6", "Sky": "3FD0F5", "Grape": "8C52E0", "Ember": "FF7A1A", "Bubblegum": "FF5FB0",
       "Stone": "9C9488", "Steel": "8EA6C2", "Bark": "6E4227", "Leather": "B5713A", "Plum": "4B3866", "Lime": "8FD13F"}
LIGHT, SHADOW = (0xFF, 0xF4, 0xD8), (0x2A, 0x1C, 0x3D)


def rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def mix(a, b, t):
    return "#%02X%02X%02X" % tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def png_uri(path, size=None):
    im = Image.open(path).convert("RGBA")
    if size:
        im = im.resize((size, size), Image.LANCZOS)
    buf = io.BytesIO()
    im.save(buf, "PNG", optimize=True)
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()


def jpg_uri(path, width):
    im = Image.open(path).convert("RGB")
    w, h = im.size
    im = im.resize((width, round(h * width / w)), Image.LANCZOS)
    buf = io.BytesIO()
    im.save(buf, "JPEG", quality=80, optimize=True, progressive=True)
    return "data:image/jpeg;base64," + base64.b64encode(buf.getvalue()).decode()


css = []
for n, h in PAL.items():
    c = rgb(h)
    css.append(f"--{n}:#{h};--{n}-l:{mix(c, LIGHT, .35)};--{n}-d:{mix(c, SHADOW, .35)};--{n}-dd:{mix(c, SHADOW, .6)};")
for f in sorted(os.listdir(os.path.join(UI, "icons", "png"))):
    css.append(f"--I-{f[:-4]}:url({png_uri(os.path.join(UI, 'icons', 'png', f), 128)});")
for f in sorted(os.listdir(os.path.join(UI, "concept", "avatars"))):
    css.append(f"--A-{f[7:-4]}:url({png_uri(os.path.join(UI, 'concept', 'avatars', f), 96)});")


# ------------------------------------------------------------------ helpers
def tv(c):
    return f"--c:var(--{c});--cl:var(--{c}-l);--cd:var(--{c}-dd);"


def brick(x, y, w, h, c, lip=6, r=6, studs=False, so=.38, cls="", attrs="", inner="", style=""):
    k = "brick" + (" studs" if studs else "") + (" " + cls if cls else "")
    return (f'<div class="{k}" {attrs} style="left:{x}px;top:{y}px;width:{w}px;height:{h}px;{tv(c)}'
            f'--lip:{lip}px;--r:{r}px;--so:{so};{style}">{inner}</div>')


def text(x, y, size, s, color=None, right=None, center_w=None, cls="", attrs="", style=""):
    pos = f"right:{right}px;" if right is not None else (f"left:{x}px;width:{center_w}px;text-align:center;" if center_w else f"left:{x}px;")
    col = f"color:var(--{color});" if color else ""
    return (f'<div class="t {cls}" {attrs} style="{pos}top:{y}px;font-size:{size}px;--sw:{round(size * .26, 1)}px;{col}{style}">{s}</div>')


def icon(x, y, s, name, attrs="", style=""):
    return f'<div class="ico" {attrs} style="left:{x}px;top:{y}px;width:{s}px;height:{s}px;background-image:var(--I-{name});{style}"></div>'


def portrait(x, y, s, av, rim, style=""):
    return f'<div class="pt" style="left:{x}px;top:{y}px;width:{s}px;height:{s}px;background-image:var(--A-{av});--rim:var(--{rim});{style}"></div>'


def sheens(xs):
    return "".join(f'<div class="sheen" style="left:{x}px;width:{w}px"></div>' for x, w in xs)


# ------------------------------------------------------------------ level up
def level_up():
    h = ['<div class="bgimg" id="lbg" style="filter:grayscale(.65) brightness(.62)"></div>',
         '<div class="abs" id="lveil" style="inset:0;background:var(--Plum-dd);opacity:.45"></div>',
         '<div class="abs" id="lrays" style="left:-278px;top:-524px;width:1400px;height:1400px;opacity:.16;'
         'background:repeating-conic-gradient(from 0deg at 50% 50%,var(--Cream) 0deg 6.2deg,transparent 6.2deg 22.5deg)"></div>']

    def panel(pid, x, title, inner):
        return (f'<div class="abs out" id="{pid}" style="left:{x}px;top:44px;width:178px;height:300px;background:var(--Plum-dd);'
                f'border-radius:8px;box-shadow:inset 0 0 0 3px var(--Plum)">'
                f'<div class="abs" style="left:0;top:0;width:178px;height:36px;background:var(--Plum);border-bottom:3px solid var(--Ink);'
                f'border-radius:6px 6px 0 0;box-sizing:border-box">{text(0, 4, 18, title, center_w=178)}</div>{inner}</div>')

    def slot(sid, x, y, ic, label):
        bg = "var(--Cream)" if ic and ic != "lock" else "var(--Plum-d)"
        ico = icon(2, 1, 32, ic) if ic else '<div class="ico" style="left:2px;top:1px;width:32px;height:32px"></div>'
        lab = text(x - 10, y + 37, 14, label, center_w=56) if label else ""
        return (f'<div class="abs out" id="{sid}" style="left:{x}px;top:{y}px;width:36px;height:36px;border-width:2.5px;margin:-2.5px;'
                f'border-radius:6px;background:{bg};box-shadow:inset 0 -3px 0 rgba(0,0,0,.22)">{ico}</div>{lab}')

    inv = [text(12, 42, 14, "WEAPONS", color="Cream", style="text-shadow:none")]
    for k, (ic, lv) in enumerate([("sword", "Lv4"), ("lightning", "Lv2"), ("firestaff", "Lv1"), ("lock", "")]):
        inv.append(slot(f"s-w{k + 1}", 12 + k * 40, 64, ic, lv))
    inv.append(text(12, 122, 14, "RUNES", color="Cream", style="text-shadow:none"))
    for k, (ic, lv) in enumerate([("rune_damage", "Lv2"), ("rune_area", "Lv1"), (None, ""), (None, "")]):
        inv.append(slot(f"s-r{k + 1}", 12 + k * 40, 144, ic, lv))
    inv.append(text(12, 202, 14, "ITEMS", color="Cream", style="text-shadow:none"))
    for k, (ic, lv) in enumerate([("sock", "x1"), ("lunchbox", "x2"), ("chalk", "x1")]):
        inv.append(slot(f"s-i{k + 1}", 12 + k * 40, 224, ic, lv))
    h.append(panel("linv", 44, "INVENTORY", "".join(inv)))

    rows = [("hp", "Max HP", "100"), ("reg", "Regen", "0.2/s"), ("arm", "Armor", "3"), ("dmg", "Damage", "+16%"),
            ("as", "Attack Speed", "+7%"), ("proj", "Projectiles", "+1"), ("area", "Area", "+8%"), ("cd", "Cooldown", "-4%"),
            ("crit", "Crit", "4%"), ("luck", "Luck", "3"), ("mag", "Magnet", "9"), ("ms", "Move Speed", "+4%")]
    st = []
    for i, (k, lab, v) in enumerate(rows):
        st.append(f'<div class="abs srow" data-k="{k}" data-v="{v}" style="left:0;top:{44 + i * 21}px;width:178px;height:21px">'
                  f'<div class="abs shl" style="left:5px;top:-2px;width:164px;height:17px;background:var(--Leaf);border:2px solid var(--Ink);border-radius:4px;opacity:0"></div>'
                  + text(12, 0, 14, lab, style="--sw:3.6px;text-shadow:none")
                  + text(0, 0, 14, v, right=12, color="Cream", cls="sv", style="--sw:3.6px;text-shadow:none") + "</div>")
    h.append(panel("lsta", 622, "STATS", "".join(st)))

    win = ['<div class="abs" id="lwin" style="left:234px;top:12px;width:376px;height:356px">']
    body = ['<div class="abs out" style="left:0;top:42px;width:376px;height:314px;background:var(--Plum-dd);border-radius:8px;'
            'box-shadow:inset 0 0 0 4px var(--Sky)">']
    for i in range(3):
        y = 18 + i * 76
        inner = (sheens([(230, 14)]) + text(74, 6, 20, "", cls="oti") + text(74, 34, 15, "", cls="oli")
                 + text(0, 38, 14, "", right=10, color="Cream", cls="ora")
                 + f'<div class="brick otg" style="right:8px;top:7px;height:22px;padding:0 7px;--c:var(--Tomato);--cl:var(--Tomato-l);--cd:var(--Tomato-dd);--lip:3px;--r:5px;border-width:2.5px;margin:-2.5px">'
                 + '<div class="t" style="position:relative;font-size:14px;--sw:3.6px;text-shadow:none;top:0"></div></div>')
        body.append(brick(14, y, 348, 70, "Royal", lip=7, r=8, studs=True, so=.2, cls="pick-me",
                          attrs=f'id="of{i}" tabindex="0" role="button"', inner=inner, style="overflow:hidden"))
        body.append(f'<div class="ico" id="oi{i}" style="left:8px;top:{y - 4}px;width:70px;height:70px"></div>')
    for k, (bid, lab, c, n) in enumerate([("lRe", "REROLL", "Royal", 2), ("lSk", "SKIP", "Stone", 1), ("lBa", "BANISH", "Tomato", 1)]):
        badge = brick(90, -12, 24, 24, "Gold", lip=3, r=6, cls="badge", style="border-width:2.5px;margin:-2.5px",
                      inner=text(0, 0, 15, str(n), center_w=24, cls="cnt", style="text-shadow:none"))
        body.append(brick(20 + k * 116, 256, 104, 44, c, lip=6, r=8, studs=True, so=.3, attrs=f'id="{bid}" tabindex="0" role="button"',
                          inner=text(0, 8, 17, lab, center_w=104) + badge, style="cursor:pointer"))
    body.append("</div>")
    win.append("".join(body))
    win.append(brick(0, 0, 376, 54, "Sky", lip=6, r=8, studs=True, so=.42, style="overflow:hidden",
                     inner=sheens([(110, 22), (146, 10)]) + text(0, 6, 30, "LEVEL 13!", center_w=376, attrs='id="lvTitle"')))
    win.append("</div>")
    h.append("".join(win))
    return "".join(h)


# ------------------------------------------------------------------ victory
def victory():
    h = ['<div class="bgimg"></div><div class="abs" id="vScrim" style="inset:0;background:var(--Ink);opacity:.55"></div>',
         '<div class="abs" id="vWin" style="left:158px;top:45px;width:528px;height:316px">']
    body = ['<div class="abs out" id="vBody" style="left:0;top:50px;width:528px;height:266px;background:var(--Bark-dd);border-radius:8px;'
            'box-shadow:inset 0 0 0 5px var(--Gold),inset 0 0 0 7px var(--Gold-dd)">',
            icon(100, 20, 44, "ko"), text(150, 20, 30, "2,431 KO", attrs='id="vKoNum"'),
            brick(312, 28, 118, 30, "Tomato", lip=4, attrs='id="vBest"', inner=text(0, 2, 16, "NEW BEST!", center_w=118, style="text-shadow:none")),
            text(0, 64, 15, "Your loot is safe. Pick one:", center_w=528, color="Cream", attrs='id="vStake"')]
    for cid, x, c, title, line, av, rim, who in [("cCash", 16, "Gold", "CASH OUT", "Leave now with your loot", "archer", "Grape", "SAM"),
                                                 ("cKeep", 272, "Leaf", "KEEP GOING", "Overtime: more KO!", "knight", "Royal", "ALEX")]:
        inner = (sheens([(150, 18)]) + text(14, 8, 22, title) + text(14, 40, 15, line)
                 + '<div class="abs pickrow" style="left:14px;top:70px;height:28px;display:flex;gap:8px;align-items:center">'
                 + portrait(0, 0, 28, av, rim, style="position:relative;margin:0") + f'<div class="t" style="position:relative;font-size:15px;--sw:3.9px">{who}</div></div>')
        body.append(brick(x, 92, 240, 116, c, lip=8, r=8, studs=True, so=.22, cls="pick-me",
                          attrs=f'id="{cid}" tabindex="0" role="button" aria-label="{title.title()}"', inner=inner, style="overflow:hidden"))
    body.append(icon(186, 84, 66, "chest", attrs='id="iChest"') + icon(442, 84, 66, "flame", attrs='id="iFlame"'))
    body.append(brick(0, 0, 40, 26, "Ember", lip=3, r=5, attrs='id="vMe"', style="position:relative;margin:0;display:none;align-items:center;justify-content:center",
                      inner='<div class="t" style="position:relative;font-size:15px;--sw:3.9px;text-shadow:none">YOU</div>'))
    body.append('<div class="abs" id="vFoot" style="left:0;top:206px;width:528px;height:44px">'
                + portrait(22, 10, 26, "mage", "Ember") + text(56, 12, 15, "MIA …")
                + text(0, 4, 15, "AUTO CASH OUT IN 12s", right=22, color="Cream", attrs='id="vCountTxt"', style="transform-origin:100% 50%")
                + '<div class="track" style="right:22px;top:28px;width:176px;height:10px;border-width:2.5px;margin:-2.5px;border-radius:3px">'
                + '<div class="abs" id="vBar" style="left:0;top:0;bottom:0;width:100%;background:var(--Tomato)"></div></div></div>')
    body.append("</div>")
    h.append("".join(body))
    h.append(brick(0, 0, 528, 62, "Gold", lip=7, r=8, studs=True, so=.42, style="overflow:hidden",
                   inner='<div class="sheen" id="vSheen" style="left:-80px;width:40px;opacity:0"></div>' + sheens([(150, 26), (190, 12)])
                   + text(0, 2, 40, "VICTORY!", center_w=528, style="text-shadow:0 3px 0 var(--Ink)")))
    h.append(icon(-34, -36, 92, "trophy", attrs='id="vTrophy"', style="transform:rotate(-8deg)"))
    h.append("</div>")
    return "".join(h)


# ------------------------------------------------------------------ HUD
def hud():
    h = ['<div class="bgimg"></div>']
    v = ['<div class="abs out" style="left:56px;top:64px;width:280px;height:62px;background:rgba(53,38,75,.9);border-radius:8px">',
         brick(5, 5, 52, 52, "Sky", lip=6, attrs='id="hLv"', style="overflow:hidden",
               inner=text(0, 1, 14, "LV", center_w=52, style="text-shadow:none") + text(0, 14, 24, "12", center_w=52, attrs='id="hLvNum"')),
         '<div class="track" id="hHp" style="left:88px;top:7px;width:184px;height:26px">'
         '<div class="abs" id="hHpChip" style="left:0;top:0;bottom:0;width:72%;background:var(--Cream)"></div>'
         + brick(0, 0, 0, 26, "Tomato", lip=5, studs=True, so=.45, attrs='id="hHpFill"',
                 style="width:72%;border:0;margin:0;border-right:3px solid var(--Ink);border-radius:0")
         + text(0, 1, 15, "72/100", right=6, attrs='id="hHpTxt"') + "</div>",
         icon(58, 1, 34, "hp", attrs='id="hHeart"'),
         '<div class="track" style="left:88px;top:42px;width:112px;height:11px;border-width:2.5px;margin:-2.5px;border-radius:3px">'
         '<div class="abs" id="hXp" style="left:0;top:0;bottom:0;width:56%;background:var(--Sky);box-shadow:inset 0 3px 0 var(--Sky-l)"></div></div>',
         icon(206, 34, 26, "coin"), text(234, 34, 18, "340"), "</div>"]
    h.append("".join(v))
    team = ['<div class="abs" style="left:56px;top:138px;width:286px;height:36px">']
    for k, (nm, av, rim, val) in enumerate([("Alex", "knight", "Royal", 80), ("Sam", "archer", "Grape", 45), ("Mia", "mage", "Ember", 95)]):
        x = k * 96
        team.append(portrait(x, 0, 32, av, rim) + text(x + 38, -3, 14, nm)
                    + f'<div class="track" style="left:{x + 38}px;top:20px;width:48px;height:9px;border-width:2.5px;margin:-2.5px;border-radius:3px">'
                    f'<div class="abs" style="left:0;top:0;bottom:0;width:{val}%;background:var(--Leaf)"></div></div>')
    team.append("</div>")
    h.append("".join(team))
    h.append('<div class="abs" style="left:352px;top:6px;width:140px;height:60px">' + icon(10, 2, 30, "timer")
             + text(46, -2, 28, "9:42", attrs='id="hTime"', style="font-variant-numeric:tabular-nums")
             + text(0, 37, 15, "WORLD 1/3", center_w=140) + "</div>")
    h.append('<div class="abs" style="left:498px;top:2px;width:190px;height:70px">'
             '<div class="abs" id="hKoRow" style="right:0;top:-2px;display:flex;align-items:center;gap:6px;transform-origin:100% 50%">'
             f'<div class="ico" id="hKoIcon" style="position:relative;width:44px;height:44px;background-image:var(--I-ko)"></div>'
             '<div class="t" id="hKo" style="position:relative;font-size:34px;--sw:8.8px;font-variant-numeric:tabular-nums">1,284</div></div>'
             + text(0, 44, 15, "BEST 2,050", right=0, color="Gold") + "</div>")
    dots = "".join(f'<div class="abs" style="left:{x}px;top:{y}px;width:7px;height:7px;background:var(--Tomato);border:1.5px solid var(--Ink);border-radius:1px"></div>'
                   for x, y in [(20, 22), (60, 18), (70, 34), (26, 42), (66, 58), (18, 64), (54, 30)])
    h.append('<div class="abs out" style="left:705px;top:8px;width:92px;height:92px;border-radius:6px;overflow:hidden;'
             'background:url({{STUD}}) 0 0/24px 24px repeat,var(--Leaf-d)">'
             '<div class="abs" style="left:40px;top:0;width:12px;height:92px;background:var(--Leather-l)"></div>' + dots
             + '<div class="abs" style="left:72px;top:6px;width:11px;height:11px;background:var(--Gold);border:2px solid var(--Ink)"></div>'
             '<div class="abs" style="left:40px;top:70px;width:0;height:0;border-left:7px solid transparent;border-right:7px solid transparent;border-bottom:14px solid #fff;filter:drop-shadow(0 0 1px var(--Ink)) drop-shadow(0 0 1px var(--Ink))"></div></div>')
    h.append(brick(751, 112, 46, 46, "Stone", lip=6, studs=True, so=.3, cls="tile", attrs='tabindex="0" role="button" aria-label="Settings"',
                   inner=icon(7, 4, 32, "settings_light")))
    hb = ['<div class="abs" style="left:315px;top:306px;width:214px;height:56px">']
    for k, (ic, lv) in enumerate([("sword", "Lv4"), ("lightning", "Lv2"), ("firestaff", "Lv1"), ("lock", "")]):
        tag = brick(14, 32, 36, 22, "Gold", lip=3, r=4, style="border-width:2.5px;margin:-2.5px",
                    inner=text(0, 0, 14, lv, center_w=36, style="--sw:3.6px;text-shadow:none")) if lv else ""
        hb.append(brick(k * 56, 0, 46, 46, "Plum" if ic == "lock" else "Cream", lip=5, inner=icon(4, 1, 38, ic) + tag, style="overflow:visible"))
    hb.append("</div>")
    h.append("".join(hb))
    for tid, lab, ic, c, x, y, s in [("tJump", "JUMP", "jump", "Royal", 713, 276, 84), ("tSlide", "SLIDE", "slide", "Royal", 629, 288, 72),
                                     ("tPing", "PING", "ping", "Royal", 739, 196, 58), ("tCapture", "CAPTURE", "capture_light", "Bubblegum", 629, 196, 72)]:
        ring = '<div class="abs" id="tCapRing" style="inset:-7px;border:4px solid var(--Bubblegum);border-radius:12px;opacity:0"></div>' if tid == "tCapture" else ""
        h.append(f'<div class="abs tile" id="{tid}" tabindex="0" role="button" aria-label="{lab.title()}" style="left:{x}px;top:{y}px;width:{s}px;height:{s + 10}px">'
                 + ring + brick(0, 0, s, s, c, lip=7, r=8, studs=True, so=.35)
                 + icon(round(s * .15), round(s * .05), round(s * .7), ic)
                 + text(-12, s - 13, 16 if s >= 70 else 15, lab, center_w=s + 24) + "</div>")
    return "".join(h)


recipes = [
    ("Le jeu se fige", "0,22 s", "Quad Out", "Le monde pâlit (gris 65 %, luminosité 62 %), un voile violet, des rayons crème tournent lentement.",
     "ColorCorrection (Saturation, Brightness) ; rayons = ImageLabel, Rotation en boucle de 40 s"),
    ("Fenêtre qui s'emboîte", "0,30 s puis 0,11 s", "Back Out, puis Quad Out", "Tombe de 30 px en passant de 88 % à 100 %, puis s'écrase de 4 % en touchant : le « clic ».",
     "Tween de Size du cadre, enfants en Scale (UIScale reste uniforme)"),
    ("Panneaux latéraux", "0,28 s (+0,12 s)", "Back Out", "L'inventaire arrive de la gauche, les stats de la droite (48 px).", "Tween de Position"),
    ("Offres distribuées", "0,26 s, décalées de 0,07 s", "Back Out", "Chaque carte glisse de 46 px et grandit de 90 % à 100 % ; son icône saute 0,08 s après ; un clic par carte.", "Tween de Position + Size"),
    ("Aperçu de stat", "0,18 s", "Back Out", "Survol ou sélection d'une offre : la stat changée s'allume en vert avec sa future valeur.", "SelectionChanged / MouseEnter"),
    ("Choix d'une offre", "0,46 s puis 0,24 s", "In Out, puis Back Out", "Les autres cartes tombent, l'icône vole en arc jusqu'à sa case d'inventaire, la case grossit à 125 % et lâche des tenons.", "ImageLabel cloné, Position en deux tweens"),
    ("Reroll", "0,12 s puis 0,18 s", "Quad In, puis Back Out", "Chaque carte se retourne (décalage 0,05 s), le compteur rebondit.", "Size.Y à 0 puis 1 (pas de rotation 3D en UI)"),
    ("Banish", "0,22 s", "Quad In", "Mode Banish : les cartes rougissent ; la carte bannie tombe en tournant, une nouvelle arrive.", "Rotation + Position + ImageTransparency"),
    ("Fenêtre qui se ferme", "0,15 s", "Quad In", "Rétrécit à 92 % et s'efface ; panneaux qui repartent ; le monde reprend ses couleurs en 0,22 s.", "GroupTransparency (CanvasGroup) ou chaque élément"),
    ("Trophée, tampon NEW BEST!", "0,38 s / 0,22 s", "Quad Out / Back Out", "Le trophée saute (0 → 115 % → 100 %), le tampon arrive à 190 % penché de −16° et se plaque ; 12 tenons dorés.", "Size + Rotation"),
    ("Reflet sur les tenons", "0,56 s", "Quad Out", "Une bande claire traverse la barre de titre.", "UIGradient.Offset de −1 à 1 (pas de bande tournée : ClipsDescendants ne la couperait pas)"),
    ("Compte à rebours Victory", "12 s", "Linear", "La barre se vide ; sous 5 s le texte pulse à 110 % ; à 0, Cash out automatique.", "Tween de Size.X"),
    ("Appui sur une brique", "0,06 s puis 0,18 s", "Quad Out, puis Back Out", "S'enfonce de 3 px (la lèvre), remonte avec 3 % de rebond. Son « clic ».", "Position.Y + HapticService (petite vibration)"),
    ("+1 KO", "0,15 s", "Back Out", "Le compteur grossit à 116 %, la tête pivote ; pas de son à chaque KO (un clic tous les 100).", "UIScale ; pulsation au plus toutes les 0,11 s"),
    ("Dégât", "0 s, puis 0,32 s (+0,22 s)", "Quad Out", "La barre tombe tout de suite, un reste crème fond derrière, la barre tremble de 4 px, le cœur se serre.", "Deux Frames de remplissage"),
    ("Niveau gagné (HUD)", "0,38 s", "Quad Out", "Le badge s'écrase puis rebondit, le chiffre tombe, 14 tenons bleus jaillissent, trois clics montants.", "Size du badge ; particules = 14 Frames recyclées"),
    ("Capture prête", "0,26 s, puis 1,2 s en boucle", "Back Out, puis Linear", "La tuile monte en grandissant, un anneau rose s'élargit et s'efface en boucle.", "Anneau = ImageLabel à part (Size + ImageTransparency)"),
]
rec_html = "".join(f"<tr><td>{a}</td><td class=\"num\">{b}</td><td><code>{c}</code></td><td>{d}</td><td>{e}</td></tr>" for a, b, c, d, e in recipes)

page = open(os.path.join(HERE, "template.html"), encoding="utf-8").read()
page = (page.replace("{{LEVELUP}}", level_up()).replace("{{VICTORY}}", victory()).replace("{{HUD}}", hud())
        .replace("{{RECIPES}}", rec_html).replace("{{PALETTE}}", "\n  ".join(css)))
page = page.replace("{{BG}}", jpg_uri(os.path.join(UI, "concept", "run_landscape.png"), 1688)).replace("{{STUD}}", png_uri(os.path.join(UI, "stud_tile_128.png")))
left = sorted(set(p.split("}}")[0] for p in page.split("{{")[1:]))
open(OUT, "w", encoding="utf-8").write(page)
print("written", OUT, round(len(page) / 1024), "KB", "unfilled:", left)
