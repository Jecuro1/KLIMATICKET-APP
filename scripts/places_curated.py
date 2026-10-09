"""Curated reference data for build_tags.py and the build_places.py v2 stage (stdlib only, small helpers).

Own work (no OpenStreetMap content): ski-area and region names, resorts, member Gemeinden, Landesfarben approximations,
KlimaTicket rules, operator display names, ski-area styling (glyph, monogram, SummitHue). Shipped in places.bin.

LEGAL (read before using anything here in the app):
  * Nothing in this file copies a logo, wordmark or coat of arms. Ski-area, region, Verbund and operator NAMES are
    plain text (nominative use); colours and glyphs are our own design ("Wegzeichen", BADGE_SPEC) and deliberately do
    not imitate the official marks. The `style.color` values below are design hints only: the build maps them to one
    of the 8 own SummitHue values and never ships them (ENRICH_SPEC §1.4.1, AT-D9).
  * Original ski-area/region logos and Landeswappen are a separate, owner-approved channel (docs/LOGO_SPEC.md):
    Landeswappen ship in the app bundle, brand logos only via the remote logo pack. None of them belongs in this file
    or in the places data.
  * Landesfarben (flag colours) are facts from the Landesverfassungen; the stripe chip remains the fallback mark.

Gemeinde names must match Statistik Austria (Gemeinden 2026-01-01) exactly - build_tags.py validates them.
"""
import re as _re
import unicodedata as _ud

# ---------------------------------------------------------------------------------------------------------
# Bundesländer
# ---------------------------------------------------------------------------------------------------------
# key = state code used in places.json
STATES = {
    "B": {
        "name": "Burgenland", "code2": "BG", "iso": "AT-1", "gkz": 1,
        "landesfarben": ["Rot", "Gold"], "flag": ["#C8102E", "#F2B705"],
        "verbund": "VOR", "verbund_name": "Verkehrsverbund Ost-Region",
        "badge": {"bg": "#B3122E", "fg": "#FFFFFF", "accent": "#E7B416",
                  "bgDark": "#F07A8B", "fgDark": "#26060B", "accentDark": "#F5C842"},
    },
    "K": {
        "name": "Kärnten", "code2": "KT", "iso": "AT-2", "gkz": 2,
        "landesfarben": ["Gelb", "Rot", "Weiß"], "flag": ["#FFD200", "#C8102E", "#FFFFFF"],
        "verbund": "VKG", "verbund_name": "Kärntner Linien (Verkehrsverbund Kärnten)",
        "badge": {"bg": "#F2C200", "fg": "#3A1A00", "accent": "#C8102E",
                  "bgDark": "#FFD83D", "fgDark": "#2A1500", "accentDark": "#FF5A6E"},
    },
    "NÖ": {
        "name": "Niederösterreich", "code2": "NÖ", "ascii2": "NO", "iso": "AT-3", "gkz": 3,
        "landesfarben": ["Blau", "Gelb"], "flag": ["#0F4C97", "#FFD200"],
        "verbund": "VOR", "verbund_name": "Verkehrsverbund Ost-Region",
        "badge": {"bg": "#1D4E91", "fg": "#FFE14D", "accent": "#FFD200",
                  "bgDark": "#7FA8E8", "fgDark": "#0B1E3D", "accentDark": "#FFE14D"},
    },
    "OÖ": {
        "name": "Oberösterreich", "code2": "OÖ", "ascii2": "OO", "iso": "AT-4", "gkz": 4,
        "landesfarben": ["Weiß", "Rot"], "flag": ["#FFFFFF", "#C8102E"],
        "verbund": "OÖVV", "verbund_name": "Oberösterreichischer Verkehrsverbund",
        "badge": {"bg": "#FFFFFF", "fg": "#B0132B", "accent": "#C8102E", "border": "#E3B5BC",
                  "bgDark": "#2A1418", "fgDark": "#FF8A99", "accentDark": "#FF5A6E"},
    },
    "S": {
        "name": "Salzburg", "code2": "SB", "iso": "AT-5", "gkz": 5,
        "landesfarben": ["Rot", "Weiß"], "flag": ["#C8102E", "#FFFFFF"],
        "verbund": "SVV", "verbund_name": "Salzburger Verkehrsverbund",
        "badge": {"bg": "#A3122B", "fg": "#FFFFFF", "accent": "#FFFFFF",
                  "bgDark": "#FF8A99", "fgDark": "#2A060C", "accentDark": "#FFD6DC"},
    },
    "ST": {
        "name": "Steiermark", "code2": "ST", "iso": "AT-6", "gkz": 6,
        "landesfarben": ["Weiß", "Grün"], "flag": ["#FFFFFF", "#00843D"],
        "verbund": "VVSt", "verbund_name": "Steirischer Verkehrsverbund (Verbund Linie)",
        "badge": {"bg": "#0B7A3E", "fg": "#FFFFFF", "accent": "#FFFFFF",
                  "bgDark": "#3FBF73", "fgDark": "#04210F", "accentDark": "#D6F5E2"},
    },
    "T": {
        "name": "Tirol", "code2": "TI", "iso": "AT-7", "gkz": 7,
        "landesfarben": ["Weiß", "Rot"], "flag": ["#FFFFFF", "#C8102E"],
        "verbund": "VVT", "verbund_name": "Verkehrsverbund Tirol",
        "badge": {"bg": "#C41630", "fg": "#FFFFFF", "accent": "#FFFFFF",
                  "bgDark": "#F0566B", "fgDark": "#26040A", "accentDark": "#FFE3E7"},
    },
    "V": {
        "name": "Vorarlberg", "code2": "VB", "iso": "AT-8", "gkz": 8,
        "landesfarben": ["Rot", "Weiß"], "flag": ["#C8102E", "#FFFFFF"],
        "verbund": "VVV", "verbund_name": "Verkehrsverbund Vorarlberg (VMOBIL)",
        "badge": {"bg": "#D23A28", "fg": "#FFFFFF", "accent": "#FFFFFF",
                  "bgDark": "#FF6E5C", "fgDark": "#2B0703", "accentDark": "#FFE1DC"},
    },
    "W": {
        "name": "Wien", "code2": "WI", "iso": "AT-9", "gkz": 9,
        "landesfarben": ["Rot", "Weiß"], "flag": ["#C8102E", "#FFFFFF"],
        "verbund": "VOR", "verbund_name": "Verkehrsverbund Ost-Region",
        "badge": {"bg": "#8E1230", "fg": "#FFFFFF", "accent": "#FFFFFF",
                  "bgDark": "#E07A92", "fgDark": "#24060D", "accentDark": "#FFD9E1"},
    },
    "X": {
        "name": "Ausland", "code2": "XX", "iso": None, "gkz": None,
        "landesfarben": [], "flag": [],
        "verbund": None, "verbund_name": None,
        "badge": {"bg": "#5B6470", "fg": "#FFFFFF", "accent": "#D0D5DB",
                  "bgDark": "#9AA3AE", "fgDark": "#0E1114", "accentDark": "#E3E7EB"},
    },
}

STATE_LEGAL = ("Landesfarben laut Landesverfassungen (Bgld Rot-Gold, Ktn Gelb-Rot-Weiß, NÖ Blau-Gelb, OÖ Weiß-Rot, "
               "Sbg Rot-Weiß, Stmk Weiß-Grün, Tirol Weiß-Rot, Vbg Rot-Weiß, Wien Rot-Weiß). Flag-Hexwerte sind "
               "heraldische Näherungen, keine CI-Werte. Landeswappen/Landeslogos sind landesgesetzlich geschützt "
               "und werden NICHT verwendet; Badge = eigene Gestaltung (Kürzel + Streifen-Chip).")

# Politische Bezirke (Statistik Austria code = first 3 digits of the GKZ). Statutarstädte marked (Stadt).
BEZIRKE = {
    "101": "Eisenstadt (Stadt)", "102": "Rust (Stadt)", "103": "Eisenstadt-Umgebung", "104": "Güssing",
    "105": "Jennersdorf", "106": "Mattersburg", "107": "Neusiedl am See", "108": "Oberpullendorf",
    "109": "Oberwart",
    "201": "Klagenfurt am Wörthersee (Stadt)", "202": "Villach (Stadt)", "203": "Hermagor",
    "204": "Klagenfurt-Land", "205": "St. Veit an der Glan", "206": "Spittal an der Drau", "207": "Villach-Land",
    "208": "Völkermarkt", "209": "Wolfsberg", "210": "Feldkirchen",
    "301": "Krems an der Donau (Stadt)", "302": "St. Pölten (Stadt)", "303": "Waidhofen an der Ybbs (Stadt)",
    "304": "Wiener Neustadt (Stadt)", "305": "Amstetten", "306": "Baden", "307": "Bruck an der Leitha",
    "308": "Gänserndorf", "309": "Gmünd", "310": "Hollabrunn", "311": "Horn", "312": "Korneuburg",
    "313": "Krems-Land", "314": "Lilienfeld", "315": "Melk", "316": "Mistelbach", "317": "Mödling",
    "318": "Neunkirchen", "319": "St. Pölten-Land", "320": "Scheibbs", "321": "Tulln",
    "322": "Waidhofen an der Thaya", "323": "Wiener Neustadt-Land", "325": "Zwettl",
    "401": "Linz (Stadt)", "402": "Steyr (Stadt)", "403": "Wels (Stadt)", "404": "Braunau am Inn",
    "405": "Eferding", "406": "Freistadt", "407": "Gmunden", "408": "Grieskirchen", "409": "Kirchdorf an der Krems",
    "410": "Linz-Land", "411": "Perg", "412": "Ried im Innkreis", "413": "Rohrbach", "414": "Schärding",
    "415": "Steyr-Land", "416": "Urfahr-Umgebung", "417": "Vöcklabruck", "418": "Wels-Land",
    "501": "Salzburg (Stadt)", "502": "Hallein (Tennengau)", "503": "Salzburg-Umgebung (Flachgau)",
    "504": "St. Johann im Pongau (Pongau)", "505": "Tamsweg (Lungau)", "506": "Zell am See (Pinzgau)",
    "601": "Graz (Stadt)", "603": "Deutschlandsberg", "606": "Graz-Umgebung", "610": "Leibnitz", "611": "Leoben",
    "612": "Liezen", "614": "Murau", "616": "Voitsberg", "617": "Weiz", "620": "Murtal",
    "621": "Bruck-Mürzzuschlag", "622": "Hartberg-Fürstenfeld", "623": "Südoststeiermark",
    "701": "Innsbruck (Stadt)", "702": "Imst", "703": "Innsbruck-Land", "704": "Kitzbühel", "705": "Kufstein",
    "706": "Landeck", "707": "Lienz (Osttirol)", "708": "Reutte (Außerfern)", "709": "Schwaz",
    "801": "Bludenz", "802": "Bregenz", "803": "Dornbirn", "804": "Feldkirch",
    # Wien: one Bezirk in the political sense; the 23 Gemeindebezirke are 901..923
    "900": "Wien (Stadt)",
}
WIEN_BEZIRKE = {
    1: "Innere Stadt", 2: "Leopoldstadt", 3: "Landstraße", 4: "Wieden", 5: "Margareten", 6: "Mariahilf",
    7: "Neubau", 8: "Josefstadt", 9: "Alsergrund", 10: "Favoriten", 11: "Simmering", 12: "Meidling",
    13: "Hietzing", 14: "Penzing", 15: "Rudolfsheim-Fünfhaus", 16: "Ottakring", 17: "Hernals", 18: "Währing",
    19: "Döbling", 20: "Brigittenau", 21: "Floridsdorf", 22: "Donaustadt", 23: "Liesing",
}

# ---------------------------------------------------------------------------------------------------------
# KlimaTicket coverage hints (from research/klimaticket_products.json, verified 2026-10-09)
# ---------------------------------------------------------------------------------------------------------
KLIMATICKET_REGIONAL = {
    "V": [{"id": "vbg-maximo", "name": "KlimaTicket VMOBIL MAXIMO"}],
    "T": [{"id": "tirol", "name": "KlimaTicket Tirol"}],
    "S": [{"id": "salzburg", "name": "KlimaTicket Salzburg"}],
    "OÖ": [{"id": "ooe-regional", "name": "KlimaTicket OÖ Regional"},
           {"id": "ooe-gesamt", "name": "KlimaTicket OÖ Gesamt"}],
    "ST": [{"id": "stmk", "name": "KlimaTicket Steiermark"}],
    "K": [{"id": "ktn", "name": "Kärnten Ticket"}],
    "NÖ": [{"id": "vor-region", "name": "VOR KlimaTicket Region"},
           {"id": "vor-metropolregion", "name": "VOR KlimaTicket MetropolRegion"}],
    "B": [{"id": "vor-region", "name": "VOR KlimaTicket Region"},
          {"id": "vor-metropolregion", "name": "VOR KlimaTicket MetropolRegion"}],
    "W": [{"id": "vor-metropolregion", "name": "VOR KlimaTicket MetropolRegion"},
          {"id": "wien-jahreskarte", "name": "Jahreskarte WIEN (Wiener Linien)"}],
}
# Extra regional tickets valid at specific Gemeinden outside their home state (tariff extensions)
KLIMATICKET_EXTENSIONS = [
    # (state, gemeinde, ticket id, ticket name)
    ("T", "St. Anton am Arlberg", "vbg-maximo", "KlimaTicket VMOBIL MAXIMO"),
    ("S", "Radstadt", "stmk", "KlimaTicket Steiermark"),
    ("S", "Tamsweg", "stmk", "KlimaTicket Steiermark"),
    ("K", "Reichenfels", "stmk", "KlimaTicket Steiermark"),
    ("B", "Oberwart", "stmk", "KlimaTicket Steiermark"),
    ("B", "Bad Tatzmannsdorf", "stmk", "KlimaTicket Steiermark"),
    ("T", "Lienz", "ktn", "Kärnten Ticket"),
]
KLIMATICKET_CITY = {  # Gemeinde -> local KlimaTicket variants
    ("T", "Innsbruck"): "KlimaTicket Innsbruck", ("T", "Kufstein"): "KlimaTicket Kufstein",
    ("T", "Schwaz"): "KlimaTicket Schwaz", ("T", "Lienz"): "KlimaTicket Lienz",
    ("T", "St. Anton am Arlberg"): "KlimaTicket St. Anton",
}
OOE_KERNZONEN = {"Linz": "ooe-regional-linz", "Wels": "ooe-regional-wels", "Steyr": "ooe-regional-steyr"}
# KlimaTicket Ö validity abroad: up to these Gemeinschaftsbahnhöfe (name regex against stop name)
KT_BORDER_STATIONS = r"(?i)^(Buchs SG|St\.? Margrethen|Lindau[- ]Reutin|Passau Hbf|Passau Hauptbahnhof|Simbach|Tarvisio|Innichen|San Candido|Brenner|Brennero|Sopron|Freilassing)"
KT_EXCLUDED_NAMES = r"(?i)(Schneebergbahn|Schafbergbahn|Wachaubahn|Waldviertelbahn|Reblaus|Festungsbahn|Mönchsberg ?aufzug|Wälderbähnle|Zahnradbahn|Achenseebahn|Taurachbahn|Feistritztalbahn|Murtalbahn Dampf|Stainzer Flascherlzug|Nostalgie)"
KT_SOURCE = "research/klimaticket_products.json (klimaticket.at Gültigkeitskarte + AGB 2026-01, Verbund-Seiten), Stand 2026-10-09"

# ---------------------------------------------------------------------------------------------------------
# Ski areas
# ---------------------------------------------------------------------------------------------------------
# kind: alliance (ticket/brand group) | area (Skigebiet) | sector (part of an area, own OSM polygon)
# osm: exact OSM landuse=winter_sports names (zero-width spaces are stripped before matching)
# gem: {state: [Gemeinde,...]} = resort Gemeinden (Skiorte); a stop in such a Gemeinde gets the area when it is
#      within max_km of the area geometry. Without osm polygon, geometry = buffered lifts selected by lift_re
#      inside the member Gemeinden.
# glacier: Gletscherskigebiet. parent: area for sectors. alliances: list of alliance ids.
# style: own design proposal - colour (light/dark), glyph = SF Symbol + our custom peak glyph spec, monogram.
SKI = [
    # ---- alliances ----------------------------------------------------------------------------------------
    {"id": "ski-amade", "kind": "alliance", "name": "Ski amadé", "osm": ["Ski amadé"],
     "note": "Skiverbund Salzburger Sportwelt, Schladming-Dachstein, Gastein, Hochkönig, Großarltal"},
    {"id": "zillertal-superskipass", "kind": "alliance", "name": "Zillertaler Superskipass", "osm": []},
    {"id": "zillertal-3000", "kind": "alliance", "name": "Ski- und Gletscherwelt Zillertal 3000", "osm": []},
    {"id": "ski-plus-city", "kind": "alliance", "name": "Ski plus City Pass Stubai Innsbruck", "osm": []},
    {"id": "alpin-card", "kind": "alliance", "name": "ALPIN CARD", "osm": [],
     "note": "Skicircus Saalbach Hinterglemm Leogang Fieberbrunn + Schmitten + Kitzsteinhorn"},
    {"id": "4-berge", "kind": "alliance", "name": "4-Berge-Skischaukel Schladming", "osm": ["Schladming Dachstein"],
     "note": "Hauser Kaibling, Planai, Hochwurzen, Reiteralm (OSM relation 'Schladming Dachstein' used as hull)"},
    {"id": "tiroler-zugspitz-arena", "kind": "alliance", "name": "Tiroler Zugspitz Arena", "osm": []},
    {"id": "oetztal", "kind": "alliance", "name": "Ötztal Superskipass", "osm": []},
    {"id": "stubai", "kind": "alliance", "name": "Stubaital", "osm": ["Stubai"]},

    # ---- Vorarlberg / Arlberg ----------------------------------------------------------------------------
    {"id": "ski-arlberg", "kind": "area", "name": "Ski Arlberg", "short": "Arlberg",
     "osm": ["Ski Arlberg"], "gem": {"V": ["Lech", "Warth", "Schröcken", "Klösterle"], "T": ["St. Anton am Arlberg"]},
     "max_km": 6, "resorts": ["St. Anton", "St. Christoph", "Stuben", "Lech", "Zürs", "Oberlech", "Zug", "Warth",
                              "Schröcken", "Klösterle (Sonnenkopf)"],
     "style": {"color": "#B1182F", "colorDark": "#FF6177", "glyph": "peaks3", "sf": "mountain.2.fill", "mono": "ARL"}},
    {"id": "sonnenkopf", "kind": "sector", "parent": "ski-arlberg", "name": "Sonnenkopf", "osm": ["Sonnenkopf"],
     "gem": {"V": ["Klösterle", "Dalaas"]}, "max_km": 2.5},
    {"id": "silvretta-montafon", "kind": "area", "name": "Silvretta Montafon", "osm": ["Silvretta Montafon"],
     "gem": {"V": ["Schruns", "St. Gallenkirch", "Gaschurn", "Tschagguns"]}, "max_km": 5,
     "style": {"color": "#1F5FA8", "colorDark": "#6FA6EE", "glyph": "peaks3", "sf": "mountain.2.fill", "mono": "SM"}},
    {"id": "gargellen", "kind": "area", "name": "Gargellen", "osm": ["Gargellen"],
     "gem": {"V": ["St. Gallenkirch"]}, "max_km": 2.5},
    {"id": "golm", "kind": "area", "name": "Golm", "osm": ["Golm"], "gem": {"V": ["Vandans", "Tschagguns"]}, "max_km": 4},
    {"id": "kristberg", "kind": "area", "name": "Kristberg", "osm": ["Kristberg-Silbertal"],
     "gem": {"V": ["Silbertal"]}, "max_km": 4},
    {"id": "brandnertal", "kind": "area", "name": "Brandnertal", "osm": ["Brandnertal – Brand/Bürserberg"],
     "gem": {"V": ["Brand", "Bürserberg"]}, "max_km": 4},
    {"id": "damuels-mellau", "kind": "area", "name": "Damüls Mellau Faschina", "osm": [],
     "gem": {"V": ["Damüls", "Mellau", "Fontanella"]}, "max_km": 4,
     "lift_re": r"(?i)(damüls|mellau|uga|ragaz|hohes licht|elsenalp|wildgunten|sunnegg|furka|faschina|rosstelle|roßstelle|"
                r"oberdamüls|kanis|mittagsspitze|gräsalp|hohenecken|sonnenlift|rossboden|jägerlift)"},
    {"id": "diedamskopf", "kind": "area", "name": "Diedamskopf", "osm": ["Diedamskopf"],
     "gem": {"V": ["Schoppernau", "Au"]}, "max_km": 4},
    {"id": "oberstdorf-kleinwalsertal", "kind": "area", "name": "Oberstdorf Kleinwalsertal",
     "osm": ["Fellhorn/Kanzelwand", "Ifen", "Heuberg Arena/Walmendingerhorn", "Söllereck", "Wildentallift",
             "Ski lift Schwärzenbach"],
     "gem": {"V": ["Mittelberg"]}, "max_km": 4,
     "style": {"color": "#2E7D6B", "colorDark": "#5FD0B6", "glyph": "peaks2", "sf": "mountain.2.fill", "mono": "KW"}},
    {"id": "sonntag-stein", "kind": "area", "name": "Sonntag-Stein", "osm": ["Sonntag Stein"],
     "gem": {"V": ["Sonntag"]}, "max_km": 3},
    {"id": "laterns", "kind": "area", "name": "Laterns-Gapfohl", "osm": ["Laterns-Gapfohl"],
     "gem": {"V": ["Laterns"]}, "max_km": 4},
    {"id": "boedele", "kind": "area", "name": "Bödele", "osm": ["Bödele"],
     "gem": {"V": ["Schwarzenberg"]}, "max_km": 3},
    {"id": "hochhaederich", "kind": "area", "name": "Hochhäderich", "osm": ["Hochhäderich"],
     "gem": {"V": ["Hittisau", "Riefensberg"]}, "max_km": 3},
    {"id": "niedere", "kind": "area", "name": "Niedere Andelsbuch-Bezau", "osm": ["Niedere Andelsbuch-Bezau"],
     "gem": {"V": ["Andelsbuch", "Bezau"]}, "max_km": 3},
    {"id": "schetteregg", "kind": "area", "name": "Schetteregg", "osm": ["Schetteregg"],
     "gem": {"V": ["Egg"]}, "max_km": 3},

    # ---- Tirol: Paznaun, Oberland, Ötztal, Pitztal, Kaunertal -------------------------------------------
    {"id": "silvretta-arena", "kind": "area", "name": "Silvretta Arena Ischgl/Samnaun", "short": "Ischgl",
     "osm": ["Ischgl-Samnaun"], "gem": {"T": ["Ischgl"]}, "max_km": 6,
     "style": {"color": "#5A2D91", "colorDark": "#A983E8", "glyph": "peaks3", "sf": "mountain.2.fill", "mono": "ISG"}},
    {"id": "galtuer", "kind": "area", "name": "Silvapark Galtür", "osm": ["Galtür"], "gem": {"T": ["Galtür"]},
     "max_km": 4},
    {"id": "kappl", "kind": "area", "name": "Kappl", "osm": ["Kappl"], "gem": {"T": ["Kappl"]}, "max_km": 4},
    {"id": "see-paznaun", "kind": "area", "name": "See im Paznaun", "osm": ["See"], "gem": {"T": ["See"]},
     "max_km": 4},
    {"id": "serfaus-fiss-ladis", "kind": "area", "name": "Serfaus-Fiss-Ladis", "osm": ["Serfaus-Fiss-Ladis"],
     "gem": {"T": ["Serfaus", "Fiss", "Ladis"]}, "max_km": 5,
     "style": {"color": "#B8500F", "colorDark": "#FF9D5C", "glyph": "peaks3", "sf": "mountain.2.fill", "mono": "SFL"}},
    {"id": "nauders", "kind": "area", "name": "Nauders Bergkastel", "osm": ["Nauders am Reschenpass"],
     "gem": {"T": ["Nauders"]}, "max_km": 4},
    {"id": "venet", "kind": "area", "name": "Venet", "osm": ["Venet"], "gem": {"T": ["Zams", "Fließ"]},
     "max_km": 1.2},
    {"id": "fendels", "kind": "area", "name": "Fendels", "osm": ["Fendels"],
     "gem": {"T": ["Fendels", "Ried im Oberinntal"]}, "max_km": 3},
    {"id": "kaunertaler-gletscher", "kind": "area", "name": "Kaunertaler Gletscher", "osm": ["Kaunertaler Gletscher"],
     "gem": {"T": ["Kaunertal"]}, "max_km": 3, "glacier": True,
     "style": {"color": "#1F6FA0", "colorDark": "#7FCBF5", "glyph": "glacier", "sf": "snowflake", "mono": "KTG"}},
    {"id": "pitztaler-gletscher", "kind": "area", "name": "Pitztaler Gletscher & Rifflsee",
     "osm": ["Pitztaler Gletscher", "Rifflsee"], "gem": {"T": ["St. Leonhard im Pitztal"]}, "max_km": 4,
     "glacier": True,
     "style": {"color": "#176B9E", "colorDark": "#6CC3F2", "glyph": "glacier", "sf": "snowflake", "mono": "PTG"}},
    {"id": "hochzeiger", "kind": "area", "name": "Hochzeiger", "osm": ["Hochzeiger"], "gem": {"T": ["Jerzens"]},
     "max_km": 4},
    {"id": "soelden", "kind": "area", "name": "Sölden", "osm": ["Sölden"], "gem": {"T": ["Sölden"]}, "max_km": 3,
     "glacier": True, "alliances": ["oetztal"], "resorts": ["Sölden", "Hochsölden", "Rettenbach-/Tiefenbachgletscher"],
     "style": {"color": "#111827", "colorDark": "#E5E7EB", "glyph": "glacier", "sf": "snowflake", "mono": "SÖL"}},
    {"id": "obergurgl-hochgurgl", "kind": "area", "name": "Obergurgl-Hochgurgl", "osm": ["Obergurgl-Hochgurgl"],
     "gem": {"T": ["Sölden"]}, "max_km": 2.5, "alliances": ["oetztal"],
     "style": {"color": "#3A5BA0", "colorDark": "#8FA9E6", "glyph": "peaks2", "sf": "mountain.2.fill", "mono": "OHG"}},
    {"id": "vent", "kind": "area", "name": "Vent", "osm": ["Vent"], "gem": {"T": ["Sölden"]}, "max_km": 1.5,
     "alliances": ["oetztal"]},
    {"id": "hochoetz-kuehtai", "kind": "area", "name": "Hochoetz-Kühtai", "osm": ["Hochoetz-Kühtai"],
     "gem": {"T": ["Oetz", "Silz"]}, "max_km": 3, "alliances": ["oetztal"]},
    {"id": "hochoetz", "kind": "sector", "parent": "hochoetz-kuehtai", "name": "Hochoetz", "osm": ["Hochoetz"],
     "gem": {"T": ["Oetz"]}, "max_km": 4},
    {"id": "kuehtai", "kind": "sector", "parent": "hochoetz-kuehtai", "name": "Kühtai", "osm": ["Kühtai"],
     "gem": {"T": ["Silz"]}, "max_km": 2, "alliances": ["ski-plus-city"]},
    {"id": "hoch-imst", "kind": "area", "name": "Hoch-Imst", "osm": [], "gem": {"T": ["Imst"]}, "max_km": 2,
     "lift_re": r"(?i)(hoch-?imst|untermarkter|alpine coaster|obermarkter|imster bergbahn|drischlsteig|alpjoch)"},

    # ---- Tirol: Außerfern / Zugspitz Arena / Tannheimer Tal ---------------------------------------------
    {"id": "ehrwalder-alm", "kind": "area", "name": "Ehrwalder Alm", "osm": ["Ehrwalder Almbahn"],
     "gem": {"T": ["Ehrwald"]}, "max_km": 3, "alliances": ["tiroler-zugspitz-arena"]},
    {"id": "wettersteinbahnen", "kind": "area", "name": "Ehrwalder Wettersteinbahnen",
     "osm": ["Ehrwald Wettersteinbahnen"], "gem": {"T": ["Ehrwald"]}, "max_km": 3,
     "alliances": ["tiroler-zugspitz-arena"]},
    {"id": "zugspitze", "kind": "area", "name": "Zugspitze (Gletscherskigebiet)", "osm": ["Gletscher-Skigebiet Zugspitze"],
     "gem": {"T": ["Ehrwald"]}, "max_km": 1, "glacier": True, "alliances": ["tiroler-zugspitz-arena"],
     "force_lift_re": r"(?i)^(tiroler zugspitzbahn|seilbahn zugspitze)$",
     "note": "Skigebiet liegt in Deutschland; Zugang aus Tirol mit der Tiroler Zugspitzbahn (Ehrwald)"},
    {"id": "grubigstein", "kind": "area", "name": "Grubigstein Lermoos", "osm": ["Lermoos - Grubigstein"],
     "gem": {"T": ["Lermoos"]}, "max_km": 3, "alliances": ["tiroler-zugspitz-arena"]},
    {"id": "marienberg", "kind": "area", "name": "Marienberg Biberwier", "osm": ["Biberwier - Marienberg"],
     "gem": {"T": ["Biberwier"]}, "max_km": 3, "alliances": ["tiroler-zugspitz-arena"]},
    {"id": "berwang", "kind": "area", "name": "Berwang", "osm": ["Berwang"],
     "gem": {"T": ["Berwang", "Bichlbach", "Heiterwang"]}, "max_km": 3, "alliances": ["tiroler-zugspitz-arena"]},
    {"id": "tannheimer-tal", "kind": "area", "name": "Tannheimer Tal",
     "osm": ["Tannheim-Zöblen-Schattwald", "Füssener Jöchle-Grän"],
     "gem": {"T": ["Tannheim", "Grän", "Nesselwängle", "Schattwald", "Zöblen"]}, "max_km": 4},
    {"id": "jungholz", "kind": "area", "name": "Jungholz–Oberjoch", "osm": ["Hindelang Oberjoch"],
     "gem": {"T": ["Jungholz"]}, "max_km": 3},
    {"id": "hahnenkamm-reutte", "kind": "area", "name": "Hahnenkamm Reutte-Höfen", "osm": ["Hahnenkamm Höfen"],
     "gem": {"T": ["Höfen", "Reutte"]}, "max_km": 3},
    {"id": "joechelspitze", "kind": "area", "name": "Jöchelspitze Lechtal", "osm": ["Jöchelspitze"],
     "gem": {"T": ["Bach"]}, "max_km": 3},

    # ---- Tirol: Innsbruck / Stubai / Seefeld -------------------------------------------------------------
    {"id": "stubaier-gletscher", "kind": "area", "name": "Stubaier Gletscher", "osm": ["Stubaier Gletscher"],
     "gem": {"T": ["Neustift im Stubaital"]}, "max_km": 2.5, "glacier": True, "alliances": ["ski-plus-city", "stubai"],
     "style": {"color": "#0E6FA8", "colorDark": "#5CB8EE", "glyph": "glacier", "sf": "snowflake", "mono": "STG"}},
    {"id": "schlick2000", "kind": "area", "name": "Schlick 2000", "osm": ["Schlick 2000"],
     "gem": {"T": ["Fulpmes", "Telfes im Stubai"]}, "max_km": 3, "alliances": ["ski-plus-city", "stubai"]},
    {"id": "serlesbahnen", "kind": "area", "name": "Serlesbahnen Mieders", "osm": ["Serlesbahnen"],
     "gem": {"T": ["Mieders"]}, "max_km": 2.5, "alliances": ["ski-plus-city", "stubai"]},
    {"id": "elferlifte", "kind": "area", "name": "Elferlifte Neustift", "osm": ["Elferlifte Neustift im Stubaital"],
     "gem": {"T": ["Neustift im Stubaital"]}, "max_km": 2, "alliances": ["ski-plus-city", "stubai"]},
    {"id": "nordkette", "kind": "area", "name": "Nordkette Innsbruck", "osm": ["Nordkette"],
     "gem": {"T": ["Innsbruck"]}, "max_km": 0.8, "alliances": ["ski-plus-city"]},
    {"id": "patscherkofel", "kind": "area", "name": "Patscherkofel", "osm": ["Patscherkofel"],
     "gem": {"T": ["Innsbruck", "Patsch"]}, "max_km": 1.5, "alliances": ["ski-plus-city"]},
    {"id": "glungezer", "kind": "area", "name": "Glungezer", "osm": ["Glungezer"], "gem": {"T": ["Tulfes"]},
     "max_km": 2.5, "alliances": ["ski-plus-city"]},
    {"id": "axamer-lizum", "kind": "area", "name": "Axamer Lizum", "osm": ["Axamer Lizum"],
     "gem": {"T": ["Axams"]}, "max_km": 2.5, "alliances": ["ski-plus-city"]},
    {"id": "muttereralm", "kind": "area", "name": "Muttereralm", "osm": ["Muttereralm - Mutters/Götzens"],
     "gem": {"T": ["Mutters", "Götzens"]}, "max_km": 2.5, "alliances": ["ski-plus-city"]},
    {"id": "rangger-koepfl", "kind": "area", "name": "Rangger Köpfl", "osm": ["Rangger Köpfl"],
     "gem": {"T": ["Oberperfuss"]}, "max_km": 2.5, "alliances": ["ski-plus-city"]},
    {"id": "bergeralm", "kind": "area", "name": "Bergeralm Steinach", "osm": ["Bergeralm"],
     "gem": {"T": ["Steinach am Brenner"]}, "max_km": 2.5, "alliances": ["ski-plus-city"]},
    {"id": "seefeld", "kind": "area", "name": "Seefeld – Rosshütte & Gschwandtkopf",
     "osm": ["Seefeld - Rosshütte", "Seefeld - Gschwandtkopf", "Seefeld / Birkenlift & Geigenbühellift"],
     "gem": {"T": ["Seefeld in Tirol", "Reith bei Seefeld"]}, "max_km": 2.5},
    # ---- Tirol: Achensee / Zillertal / Alpbachtal ---------------------------------------------------------
    {"id": "christlum", "kind": "area", "name": "Christlum Achenkirch", "osm": ["Christlum"],
     "gem": {"T": ["Achenkirch"]}, "max_km": 3},
    {"id": "rofan", "kind": "area", "name": "Rofan Maurach", "osm": ["Rofan Seilbahn"],
     "gem": {"T": ["Eben am Achensee"]}, "max_km": 2},
    {"id": "karwendel-pertisau", "kind": "area", "name": "Karwendel Bergbahn Pertisau", "osm": ["Karwendel Bergbahn"],
     "gem": {"T": ["Eben am Achensee"]}, "max_km": 1.5},
    {"id": "hochzillertal-hochfuegen", "kind": "area", "name": "Hochzillertal–Hochfügen",
     "osm": ["Hochfügen - Zillertal"], "gem": {"T": ["Kaltenbach", "Fügenberg", "Stumm", "Ried im Zillertal"]},
     "max_km": 4, "alliances": ["zillertal-superskipass"]},
    {"id": "spieljoch", "kind": "area", "name": "Spieljoch Fügen", "osm": ["Spieljoch - Fügen"],
     "gem": {"T": ["Fügen"]}, "max_km": 2.5, "alliances": ["zillertal-superskipass"]},
    {"id": "zillertal-arena", "kind": "area", "name": "Zillertal Arena", "osm": ["Zillertal Arena"],
     "gem": {"T": ["Zell am Ziller", "Gerlos", "Gerlosberg", "Rohrberg", "Hainzenberg"],
             "S": ["Wald im Pinzgau", "Krimml"]}, "max_km": 4, "alliances": ["zillertal-superskipass"],
     "style": {"color": "#C2185B", "colorDark": "#F06A9B", "glyph": "peaks3", "sf": "mountain.2.fill", "mono": "ZA"}},
    {"id": "mayrhofen", "kind": "area", "name": "Mayrhofen (Penken · Ahorn · Horberg · Rastkogel)",
     "short": "Mayrhofen", "osm": ["Mayrhofen Hippach"],
     "gem": {"T": ["Mayrhofen", "Finkenberg", "Hippach", "Schwendau", "Ramsau im Zillertal", "Tux"]}, "max_km": 3,
     "alliances": ["zillertal-superskipass", "zillertal-3000"],
     "style": {"color": "#E2001A", "colorDark": "#FF5C6C", "glyph": "peaks2", "sf": "mountain.2.fill", "mono": "MAY"}},
    {"id": "hintertuxer-gletscher", "kind": "area", "name": "Hintertuxer Gletscher", "osm": ["Hintertuxer Gletscher"],
     "gem": {"T": ["Tux"]}, "max_km": 4, "glacier": True, "alliances": ["zillertal-superskipass", "zillertal-3000"],
     "style": {"color": "#00739E", "colorDark": "#4CC3EE", "glyph": "glacier", "sf": "snowflake", "mono": "HTG"}},
    {"id": "ski-juwel", "kind": "area", "name": "Ski Juwel Alpbachtal Wildschönau",
     "osm": ["Ski Juwel Alpbachtal Wildschönau", "Niederau (Wildschönau)", "Ski Juwel - Reith im Alpbachtal"],
     "gem": {"T": ["Alpbach", "Reith im Alpbachtal", "Wildschönau"]}, "max_km": 4,
     "style": {"color": "#00796B", "colorDark": "#4DD8C7", "glyph": "peaks3", "sf": "mountain.2.fill", "mono": "SJ"}},
    # ---- Tirol: Kitzbüheler Alpen / Kaiser ----------------------------------------------------------------
    {"id": "skiwelt", "kind": "area", "name": "SkiWelt Wilder Kaiser–Brixental", "short": "SkiWelt",
     "osm": ["SkiWelt Wilder Kaiser Brixental"],
     "gem": {"T": ["Ellmau", "Going am Wilden Kaiser", "Scheffau am Wilden Kaiser", "Söll", "Itter",
                   "Hopfgarten im Brixental", "Brixen im Thale", "Westendorf"]}, "max_km": 4,
     "style": {"color": "#1565C0", "colorDark": "#64A8F5", "glyph": "peaks3", "sf": "mountain.2.fill", "mono": "SW"}},
    {"id": "kitzski", "kind": "area", "name": "KitzSki", "osm": ["KitzSki"],
     "gem": {"T": ["Kitzbühel", "Kirchberg in Tirol", "Jochberg", "Aurach bei Kitzbühel", "Reith bei Kitzbühel"],
             "S": ["Mittersill", "Hollersbach im Pinzgau"]}, "max_km": 4,
     "style": {"color": "#C62828", "colorDark": "#FF6B6B", "glyph": "peaks2", "sf": "mountain.2.fill", "mono": "KZ"}},
    {"id": "st-johann-tirol", "kind": "area", "name": "St. Johann in Tirol – Oberndorf", "osm": ["St. Johann in Tirol"],
     "gem": {"T": ["St. Johann in Tirol", "Oberndorf in Tirol"]}, "max_km": 3},
    {"id": "skicircus", "kind": "area", "name": "Skicircus Saalbach Hinterglemm Leogang Fieberbrunn",
     "short": "Skicircus", "osm": ["Skicircus Saalbach-Hinterglemm Leogang Fieberbrunn"],
     "gem": {"S": ["Saalbach-Hinterglemm", "Leogang", "Viehhofen"], "T": ["Fieberbrunn"]}, "max_km": 4,
     "alliances": ["alpin-card"],
     "style": {"color": "#C24400", "colorDark": "#FF9A4D", "glyph": "peaks3", "sf": "mountain.2.fill", "mono": "SC"}},
    {"id": "steinplatte", "kind": "area", "name": "Steinplatte Winklmoosalm", "osm": ["Steinplatte Waidring-Tirol"],
     "gem": {"T": ["Waidring"]}, "max_km": 4},
    {"id": "buchensteinwand", "kind": "area", "name": "Buchensteinwand Pillersee", "osm": ["Buchensteinwand (Pillersee)"],
     "gem": {"T": ["St. Jakob in Haus", "St. Ulrich am Pillersee"]}, "max_km": 3},
    {"id": "hochkoessen", "kind": "area", "name": "Hochkössen", "osm": ["Hochkössen - Unterberghorn"],
     "gem": {"T": ["Kössen"]}, "max_km": 3},
    {"id": "zahmer-kaiser", "kind": "area", "name": "Zahmer Kaiser Walchsee", "osm": ["Zahmer Kaiser"],
     "gem": {"T": ["Walchsee"]}, "max_km": 3},
    # ---- Osttirol -------------------------------------------------------------------------------------------
    {"id": "kals-matrei", "kind": "area", "name": "Großglockner Resort Kals-Matrei", "osm": ["Kals-Matrei"],
     "gem": {"T": ["Kals am Großglockner", "Matrei in Osttirol"]}, "max_km": 4},
    {"id": "lienzer-bergbahnen", "kind": "area", "name": "Lienzer Bergbahnen (Zettersfeld · Hochstein)",
     "short": "Lienzer Bergbahnen", "osm": ["Lienzer Bergbahnen", "Lienz - Zettersfeld", "Hochstein"],
     "gem": {"T": ["Lienz", "Thurn", "Oberlienz", "Gaimberg"]}, "max_km": 2},
    {"id": "hochpustertal", "kind": "area", "name": "Hochpustertal Sillian", "osm": ["Sillian - Hochpustertal"],
     "gem": {"T": ["Sillian", "Heinfels"]}, "max_km": 3},
    {"id": "st-jakob-defereggen", "kind": "area", "name": "Brunnalm St. Jakob im Defereggental",
     "osm": ["Brunnalm / St. Jakob"], "gem": {"T": ["St. Jakob in Defereggen"]}, "max_km": 3},
    {"id": "obertilliach", "kind": "area", "name": "Golzentipp Obertilliach", "osm": ["Golzentipp/Obertilliach"],
     "gem": {"T": ["Obertilliach"]}, "max_km": 3},

    # ---- Salzburg -----------------------------------------------------------------------------------------
    {"id": "snow-space-salzburg", "kind": "area", "name": "Snow Space Salzburg", "osm": ["Snow Space Salzburg"],
     "gem": {"S": ["Flachau", "Wagrain", "St. Johann im Pongau"]}, "max_km": 4, "alliances": ["ski-amade"],
     "style": {"color": "#6A1B9A", "colorDark": "#B57BE0", "glyph": "peaks3", "sf": "mountain.2.fill", "mono": "SSS"}},
    {"id": "flachau", "kind": "sector", "parent": "snow-space-salzburg", "name": "Flachau", "osm": ["Flachau"],
     "gem": {"S": ["Flachau"]}, "max_km": 3},
    {"id": "wagrain", "kind": "sector", "parent": "snow-space-salzburg", "name": "Wagrain", "osm": ["Wagrain"],
     "gem": {"S": ["Wagrain"]}, "max_km": 3},
    {"id": "alpendorf", "kind": "sector", "parent": "snow-space-salzburg", "name": "St. Johann-Alpendorf",
     "osm": ["St. Johann im Pongau"], "gem": {"S": ["St. Johann im Pongau"]}, "max_km": 2},
    {"id": "zauchensee", "kind": "area", "name": "Zauchensee–Flachauwinkl", "osm": ["Zauchensee-Flachauwinkl"],
     "gem": {"S": ["Altenmarkt im Pongau", "Flachau"]}, "max_km": 3, "alliances": ["ski-amade"]},
    {"id": "shuttleberg", "kind": "area", "name": "Shuttleberg Flachauwinkl–Kleinarl",
     "osm": ["Shuttleberg Flachauwinkl-Kleinarl"], "gem": {"S": ["Kleinarl", "Flachau"]}, "max_km": 3,
     "alliances": ["ski-amade"]},
    {"id": "radstadt-altenmarkt", "kind": "area", "name": "Radstadt–Altenmarkt", "osm": ["Radstadt-Altenmarkt"],
     "gem": {"S": ["Radstadt", "Altenmarkt im Pongau"]}, "max_km": 3, "alliances": ["ski-amade"]},
    {"id": "filzmoos", "kind": "area", "name": "Filzmoos", "osm": ["Filzmoos-Neuberg"], "gem": {"S": ["Filzmoos"]},
     "max_km": 3, "alliances": ["ski-amade"]},
    {"id": "monte-popolo", "kind": "area", "name": "Monte Popolo Eben", "osm": ["Monte Popolo - Eben im Pongau"],
     "gem": {"S": ["Eben im Pongau"]}, "max_km": 2, "alliances": ["ski-amade"]},
    {"id": "gastein", "kind": "area", "name": "Gastein (Schlossalm · Stubnerkogel · Graukogel · Sportgastein)",
     "short": "Gastein", "osm": ["Ski Gastein - Stubnerkogel/Schlossalm", "Graukogel", "Sportgastein"],
     "gem": {"S": ["Bad Gastein", "Bad Hofgastein"]}, "max_km": 4, "alliances": ["ski-amade"],
     "style": {"color": "#00838F", "colorDark": "#4DD0DC", "glyph": "peaks2", "sf": "mountain.2.fill", "mono": "GA"}},
    {"id": "grossarl-dorfgastein", "kind": "area", "name": "Großarltal–Dorfgastein", "osm": ["Großarltal-Dorfgastein"],
     "gem": {"S": ["Großarl", "Hüttschlag", "Dorfgastein"]}, "max_km": 4, "alliances": ["ski-amade"]},
    {"id": "hochkoenig", "kind": "area", "name": "Hochkönig", "osm": ["Hochkönig"],
     "gem": {"S": ["Maria Alm am Steinernen Meer", "Dienten am Hochkönig", "Mühlbach am Hochkönig"]}, "max_km": 4,
     "alliances": ["ski-amade"],
     "style": {"color": "#AD1457", "colorDark": "#F06292", "glyph": "peaks2", "sf": "mountain.2.fill", "mono": "HK"}},
    {"id": "obertauern", "kind": "area", "name": "Obertauern", "osm": ["Obertauern"],
     "gem": {"S": ["Untertauern", "Tweng"]}, "max_km": 2,
     "style": {"color": "#283593", "colorDark": "#7986CB", "glyph": "peaks3", "sf": "mountain.2.fill", "mono": "OT"}},
    {"id": "schmitten", "kind": "area", "name": "Schmitten Zell am See", "osm": ["Schmittenhöhe Zell am See"],
     "gem": {"S": ["Zell am See"]}, "max_km": 3, "alliances": ["alpin-card"]},
    {"id": "kitzsteinhorn", "kind": "area", "name": "Kitzsteinhorn Kaprun", "osm": ["Kitzsteinhorn"],
     "gem": {"S": ["Kaprun"]}, "max_km": 4, "glacier": True, "alliances": ["alpin-card"],
     "style": {"color": "#0D47A1", "colorDark": "#5E92F3", "glyph": "glacier", "sf": "snowflake", "mono": "KSH"}},
    {"id": "maiskogel", "kind": "sector", "parent": "kitzsteinhorn", "name": "Maiskogel", "osm": ["Maiskogel"],
     "gem": {"S": ["Kaprun"]}, "max_km": 2},
    {"id": "weissee", "kind": "area", "name": "Weißsee Gletscherwelt", "osm": ["Weißsee Gletscherwelt"],
     "gem": {"S": ["Uttendorf"]}, "max_km": 2, "glacier": True},
    {"id": "wildkogel", "kind": "area", "name": "Wildkogel-Arena Neukirchen & Bramberg", "short": "Wildkogel",
     "osm": ["Wildkogel"], "gem": {"S": ["Neukirchen am Großvenediger", "Bramberg am Wildkogel"]}, "max_km": 3},
    {"id": "rauris", "kind": "area", "name": "Rauriser Hochalmbahnen", "osm": ["Raurisertal"],
     "gem": {"S": ["Rauris"]}, "max_km": 3},
    {"id": "almenwelt-lofer", "kind": "area", "name": "Almenwelt Lofer", "osm": ["Almenwelt Lofer"],
     "gem": {"S": ["Lofer", "St. Martin bei Lofer"]}, "max_km": 3},
    {"id": "heutal", "kind": "area", "name": "Heutal Unken", "osm": ["Heutal"], "gem": {"S": ["Unken"]}, "max_km": 2},
    {"id": "dachstein-west", "kind": "area", "name": "Dachstein West", "osm": ["Skiregion Dachstein West"],
     "gem": {"S": ["Annaberg-Lungötz", "Rußbach am Paß Gschütt"], "OÖ": ["Gosau"]}, "max_km": 4},
    {"id": "werfenweng", "kind": "area", "name": "Werfenweng", "osm": ["Werfenweng"], "gem": {"S": ["Werfenweng"]},
     "max_km": 3},
    {"id": "katschberg", "kind": "area", "name": "Katschberg", "osm": ["Katschberg-Aineck"],
     "gem": {"S": ["St. Michael im Lungau"], "K": ["Rennweg am Katschberg"]}, "max_km": 2},
    {"id": "grosseck-speiereck", "kind": "area", "name": "Großeck-Speiereck", "osm": ["Großeck-Speiereck"],
     "gem": {"S": ["Mauterndorf", "St. Michael im Lungau"]}, "max_km": 2.5},
    {"id": "fanningberg", "kind": "area", "name": "Fanningberg", "osm": ["Fanningberg"],
     "gem": {"S": ["Mariapfarr", "Weißpriach"]}, "max_km": 3},

    # ---- Steiermark ---------------------------------------------------------------------------------------
    {"id": "planai-hochwurzen", "kind": "area", "name": "Planai & Hochwurzen", "osm": ["Planai & Hochwurzen",
                                                                                         "Horsefeathers Superpark Planai"],
     "gem": {"ST": ["Schladming"]}, "max_km": 3, "alliances": ["ski-amade", "4-berge"],
     "style": {"color": "#2E7D32", "colorDark": "#6FCF73", "glyph": "peaks3", "sf": "mountain.2.fill", "mono": "PL"}},
    {"id": "hauser-kaibling", "kind": "area", "name": "Hauser Kaibling", "osm": ["Hauser Kaibling"],
     "gem": {"ST": ["Haus", "Aich"]}, "max_km": 3, "alliances": ["ski-amade", "4-berge"]},
    {"id": "reiteralm", "kind": "area", "name": "Reiteralm", "osm": ["Reiteralm"], "gem": {"ST": ["Schladming"]},
     "max_km": 2.5, "alliances": ["ski-amade", "4-berge"]},
    {"id": "fageralm", "kind": "area", "name": "Fageralm", "osm": ["Fageralm"], "gem": {"S": ["Forstau"]},
     "max_km": 3, "alliances": ["ski-amade"]},
    {"id": "galsterberg", "kind": "area", "name": "Galsterberg", "osm": ["Galsterberg"],
     "gem": {"ST": ["Michaelerberg-Pruggern"]}, "max_km": 3, "alliances": ["ski-amade"]},
    {"id": "ramsau-dachstein", "kind": "area", "name": "Ramsau am Dachstein (Rittisberg · Dachstein Gletscher)",
     "short": "Ramsau/Dachstein", "osm": ["Ramsau am Dachstein"], "gem": {"ST": ["Ramsau am Dachstein"]},
     "max_km": 3, "glacier": True, "alliances": ["ski-amade"]},
    {"id": "tauplitz", "kind": "area", "name": "Tauplitz", "osm": ["Tauplitz / Bad Mitterndorf"],
     "gem": {"ST": ["Bad Mitterndorf"]}, "max_km": 3},
    {"id": "loser", "kind": "area", "name": "Loser Altaussee", "osm": ["Loser-Altaussee"],
     "gem": {"ST": ["Altaussee"]}, "max_km": 3},
    {"id": "riesneralm", "kind": "area", "name": "Riesneralm", "osm": ["Riesneralm - Donnersbachwald"],
     "gem": {"ST": ["Irdning-Donnersbachtal"]}, "max_km": 2},
    {"id": "planneralm", "kind": "area", "name": "Planneralm", "osm": ["Planneralm"],
     "gem": {"ST": ["Irdning-Donnersbachtal"]}, "max_km": 2},
    {"id": "kreischberg", "kind": "area", "name": "Kreischberg", "osm": ["Kreischberg"],
     "gem": {"ST": ["Sankt Georgen am Kreischberg", "Murau"]}, "max_km": 3},
    {"id": "lachtal", "kind": "area", "name": "Lachtal", "osm": ["Lachtal"], "gem": {"ST": ["Oberwölz"]},
     "max_km": 2.5},
    {"id": "turracher-hoehe", "kind": "area", "name": "Turracher Höhe", "osm": ["Turracher Höhe"],
     "gem": {"ST": ["Stadl-Predlitz"], "K": ["Reichenau"]}, "max_km": 2},
    {"id": "grebenzen", "kind": "area", "name": "Grebenzen", "osm": ["Grebenzen"], "gem": {"ST": ["Sankt Lambrecht"]},
     "max_km": 3},
    {"id": "praebichl", "kind": "area", "name": "Präbichl", "osm": ["Präbichl"],
     "gem": {"ST": ["Vordernberg", "Eisenerz"]}, "max_km": 2},
    {"id": "stuhleck", "kind": "area", "name": "Stuhleck", "osm": ["Stuhleck - Semmering"],
     "gem": {"ST": ["Spital am Semmering"]}, "max_km": 3},
    {"id": "aflenz", "kind": "area", "name": "Aflenzer Bürgeralm", "osm": ["Aflenzer Bürgeralm"],
     "gem": {"ST": ["Aflenz"]}, "max_km": 3},
    {"id": "mariazell", "kind": "area", "name": "Mariazeller Bürgeralpe", "osm": ["Mariazeller Bürgeralpe"],
     "gem": {"ST": ["Mariazell"]}, "max_km": 1.5},
    {"id": "kaiserau", "kind": "area", "name": "Kaiserau Admont", "osm": ["Kaiserau"], "gem": {"ST": ["Admont"]},
     "max_km": 2},

    # ---- Kärnten -------------------------------------------------------------------------------------------
    {"id": "nassfeld", "kind": "area", "name": "Nassfeld", "osm": ["Nassfeld"],
     "gem": {"K": ["Hermagor-Pressegger See"]}, "max_km": 3,
     "style": {"color": "#B85A00", "colorDark": "#FFB04D", "glyph": "peaks3", "sf": "mountain.2.fill", "mono": "NF"}},
    {"id": "bad-kleinkirchheim", "kind": "area", "name": "Bad Kleinkirchheim", "osm": ["Bad Kleinkirchheim"],
     "gem": {"K": ["Bad Kleinkirchheim"]}, "max_km": 3,
     "style": {"color": "#8E24AA", "colorDark": "#CE7BE6", "glyph": "peaks2", "sf": "mountain.2.fill", "mono": "BKK"}},
    {"id": "gerlitzen", "kind": "area", "name": "Gerlitzen Alpe", "osm": ["Gerlitzen Alpe"],
     "gem": {"K": ["Arriach", "Treffen am Ossiacher See", "Steindorf am Ossiacher See"]}, "max_km": 2},
    {"id": "moelltaler-gletscher", "kind": "area", "name": "Mölltaler Gletscher", "osm": ["Mölltaler Gletscher"],
     "gem": {"K": ["Flattach"]}, "max_km": 3, "glacier": True},
    {"id": "ankogel", "kind": "area", "name": "Ankogel Mallnitz", "osm": ["Ankogel Mallnitz"],
     "gem": {"K": ["Mallnitz"]}, "max_km": 3},
    {"id": "heiligenblut", "kind": "area", "name": "Großglockner Heiligenblut", "osm": ["Großglockner Heiligenblut"],
     "gem": {"K": ["Heiligenblut am Großglockner"]}, "max_km": 3},
    {"id": "goldeck", "kind": "area", "name": "Goldeck", "osm": ["Goldeck"],
     "gem": {"K": ["Spittal an der Drau", "Baldramsdorf"]}, "max_km": 1.5},
    {"id": "petzen", "kind": "area", "name": "Petzen", "osm": ["Petzen"], "gem": {"K": ["Feistritz ob Bleiburg"]},
     "max_km": 3},
    {"id": "dreilaendereck", "kind": "area", "name": "Dreiländereck Arnoldstein", "osm": ["Dreiländereck - Arnoldstein"],
     "gem": {"K": ["Arnoldstein"]}, "max_km": 2},
    {"id": "simonhoehe", "kind": "area", "name": "Simonhöhe", "osm": ["Simonhöhe"], "gem": {"K": ["St. Urban"]},
     "max_km": 2},
    {"id": "hochrindl", "kind": "area", "name": "Hochrindl", "osm": ["Hochrindl"], "gem": {"K": ["Albeck"]},
     "max_km": 2},
    {"id": "klippitztoerl", "kind": "area", "name": "Klippitztörl", "osm": ["Klippitztörl"],
     "gem": {"K": ["Bad St. Leonhard im Lavanttal"]}, "max_km": 2},
    {"id": "koralpe", "kind": "area", "name": "Koralpe", "osm": ["Koralpe"], "gem": {"K": ["Wolfsberg"]}, "max_km": 2},
    {"id": "weissensee-ski", "kind": "area", "name": "Bergbahn Weissensee", "osm": ["Bergbahn Weissensee"],
     "gem": {"K": ["Weißensee"]}, "max_km": 2},

    # ---- Oberösterreich -------------------------------------------------------------------------------------
    {"id": "hinterstoder", "kind": "area", "name": "Hinterstoder – Höss", "osm": ["Hinterstoder"],
     "gem": {"OÖ": ["Hinterstoder"]}, "max_km": 3},
    {"id": "wurzeralm", "kind": "area", "name": "Wurzeralm", "osm": ["Wurzeralm"], "gem": {"OÖ": ["Spital am Pyhrn"]},
     "max_km": 3},
    {"id": "feuerkogel", "kind": "area", "name": "Feuerkogel", "osm": ["Feuerkogel"],
     "gem": {"OÖ": ["Ebensee am Traunsee"]}, "max_km": 1.5},
    {"id": "krippenstein", "kind": "area", "name": "Dachstein Krippenstein", "osm": ["Freesports Arena Dachstein Krippenstein"],
     "gem": {"OÖ": ["Obertraun"]}, "max_km": 2},
    {"id": "hochficht", "kind": "area", "name": "Hochficht", "osm": ["Hochficht-Böhmerwald"],
     "gem": {"OÖ": ["Schwarzenberg am Böhmerwald", "Klaffer am Hochficht"]}, "max_km": 3},
    {"id": "forsteralm", "kind": "area", "name": "Forsteralm", "osm": ["Forsteralm"], "gem": {"OÖ": ["Gaflenz"]},
     "max_km": 2},

    # ---- Niederösterreich ---------------------------------------------------------------------------------
    {"id": "hochkar", "kind": "area", "name": "Hochkar", "osm": ["Hochkar"], "gem": {"NÖ": ["Göstling an der Ybbs"]},
     "max_km": 2,
     "style": {"color": "#1A5FB4", "colorDark": "#6AB7FF", "glyph": "peaks1", "sf": "mountain.2.fill", "mono": "HKR"}},
    {"id": "lackenhof", "kind": "area", "name": "Ötscher – Lackenhof", "osm": ["Lackenhof - Ötscher"],
     "gem": {"NÖ": ["Gaming"]}, "max_km": 2},
    {"id": "annaberg", "kind": "area", "name": "Annaberg", "osm": ["Annaberg"], "gem": {"NÖ": ["Annaberg"]},
     "max_km": 3},
    {"id": "moenichkirchen", "kind": "area", "name": "Mönichkirchen–Mariensee", "osm": ["Mönichkirchen - Mariensee"],
     "gem": {"NÖ": ["Mönichkirchen", "Aspangberg-St. Peter"]}, "max_km": 2.5},
    {"id": "semmering", "kind": "area", "name": "Zauberberg Semmering", "osm": ["Semmering Hirschenkogel",
                                                                              "Happylift – Semmering"],
     "gem": {"NÖ": ["Semmering"]}, "max_km": 2},
    {"id": "st-corona", "kind": "area", "name": "Wexl Arena St. Corona", "osm": ["Wexl Arena"],
     "gem": {"NÖ": ["St. Corona am Wechsel"]}, "max_km": 2},
    {"id": "schneeberg", "kind": "area", "name": "Schneeberg – Puchberg/Losenheim", "osm": ["Puchis Welt in Puchberg"],
     "gem": {"NÖ": ["Puchberg am Schneeberg"]}, "max_km": 3,
     "lift_re": r"(?i)(schneeberg|losenheim|salamander|puchi)"},
    {"id": "gemeindealpe", "kind": "area", "name": "Gemeindealpe Mitterbach", "osm": ["Gemeindealpe Mitterbach"],
     "gem": {"NÖ": ["Mitterbach am Erlaufsee"]}, "max_km": 2},
    {"id": "unterberg", "kind": "area", "name": "Unterberg", "osm": ["Unterberg"], "gem": {"NÖ": ["Muggendorf", "Pernitz"]},
     "max_km": 2},
    {"id": "koenigsberg", "kind": "area", "name": "Königsberg Hollenstein", "osm": ["Königsberg - Hollenstein"],
     "gem": {"NÖ": ["Hollenstein an der Ybbs"]}, "max_km": 2},
]

# Default style for ski areas without an explicit proposal: colour picked from this alpine palette by a stable
# hash of the id (all pass WCAG AA with white text in light mode; dark variants for dark mode).
SKI_PALETTE = [
    ("#1F5FA8", "#6FA6EE"), ("#2E7D6B", "#5FD0B6"), ("#5A2D91", "#A983E8"), ("#B1182F", "#FF6177"),
    ("#0E6FA8", "#5CB8EE"), ("#AD1457", "#F06292"), ("#00838F", "#4DD0DC"), ("#2E7D32", "#6FCF73"),
    ("#283593", "#7986CB"), ("#C2185B", "#F06A9B"), ("#6A1B9A", "#B57BE0"), ("#00695C", "#4DB6AC"),
    ("#37474F", "#B0BEC5"), ("#4527A0", "#9575CD"), ("#1565C0", "#64A8F5"), ("#8E24AA", "#CE7BE6"),
]
GLYPHS = {
    "peaks3": "drei Gipfel (große, verbundene Skischaukel) – eigene Pfad-Illustration, abgerundete Spitzen",
    "peaks2": "zwei Gipfel (mittleres Skigebiet)",
    "peaks1": "ein Gipfel (kleines/lokales Skigebiet)",
    "glacier": "Gipfel mit Eiskappe + Schneeflocke (Gletscherskigebiet, ganzjährig/fast ganzjährig)",
    "lift": "Gondel-Silhouette (nur Seilbahn/Bergbahn-Station)",
}

# ---------------------------------------------------------------------------------------------------------
# Tourism regions (Gemeinde based; Tourismusverband / Destination level). conf = confidence 0..1
# ---------------------------------------------------------------------------------------------------------
REGIONS = [
    # Vorarlberg
    {"id": "arlberg", "name": "Arlberg", "conf": 0.9,
     "gem": {"V": ["Lech", "Klösterle", "Warth", "Schröcken"], "T": ["St. Anton am Arlberg", "Pettneu am Arlberg",
                                                                     "Flirsch", "Strengen"]},
     "note": "Lech Zürs, Stuben, St. Anton/St. Christoph sowie Warth-Schröcken (Ski Arlberg)"},
    {"id": "bregenzerwald", "name": "Bregenzerwald", "conf": 0.9, "osm": "Bregenzerwald",
     "gem": {"V": ["Alberschwende", "Andelsbuch", "Au", "Bezau", "Bizau", "Damüls", "Doren", "Egg", "Hittisau",
                   "Krumbach", "Langenegg", "Lingenau", "Mellau", "Reuthe", "Riefensberg", "Schnepfau",
                   "Schoppernau", "Schröcken", "Schwarzenberg", "Sibratsgfäll", "Sulzberg", "Warth"]}},
    {"id": "montafon", "name": "Montafon", "conf": 0.95,
     "gem": {"V": ["Bartholomäberg", "Gaschurn", "Lorüns", "St. Anton im Montafon", "St. Gallenkirch", "Schruns",
                   "Silbertal", "Stallehr", "Tschagguns", "Vandans"]}},
    {"id": "kleinwalsertal", "name": "Kleinwalsertal", "conf": 0.95, "osm": "Kleinwalsertal",
     "gem": {"V": ["Mittelberg"]}},
    {"id": "brandnertal", "name": "Brandnertal", "conf": 0.9, "gem": {"V": ["Brand", "Bürserberg"]}},
    {"id": "klostertal", "name": "Klostertal", "conf": 0.9, "gem": {"V": ["Dalaas", "Innerbraz", "Klösterle"]}},
    {"id": "grosses-walsertal", "name": "Großes Walsertal", "conf": 0.9,
     "gem": {"V": ["Blons", "Fontanella", "Raggal", "St. Gerold", "Sonntag", "Thüringerberg"]},
     "note": "Biosphärenpark"},
    {"id": "bodensee-vorarlberg", "name": "Bodensee-Vorarlberg", "conf": 0.75,
     "gem": {"V": ["Bregenz", "Hard", "Lochau", "Fußach", "Gaißau", "Höchst", "Hörbranz", "Kennelbach", "Lauterach",
                   "Wolfurt", "Eichenberg", "Möggers", "Hohenweiler", "Lustenau", "Dornbirn", "Hohenems"]}},
    # Tirol
    {"id": "paznaun", "name": "Paznaun", "conf": 0.95, "gem": {"T": ["Ischgl", "Galtür", "Kappl", "See"]}},
    {"id": "oetztal", "name": "Ötztal", "conf": 0.95,
     "gem": {"T": ["Haiming", "Sautens", "Oetz", "Umhausen", "Längenfeld", "Sölden"]}},
    {"id": "pitztal", "name": "Pitztal", "conf": 0.95,
     "gem": {"T": ["Arzl im Pitztal", "Wenns", "Jerzens", "St. Leonhard im Pitztal"]}},
    {"id": "kaunertal", "name": "Kaunertal", "conf": 0.9,
     "gem": {"T": ["Kaunertal", "Kaunerberg", "Kauns", "Faggen"]}},
    {"id": "serfaus-fiss-ladis-reg", "name": "Serfaus-Fiss-Ladis", "conf": 0.95,
     "gem": {"T": ["Serfaus", "Fiss", "Ladis"]}},
    {"id": "tiroler-oberland", "name": "Tiroler Oberland – Nauders", "conf": 0.85,
     "gem": {"T": ["Nauders", "Pfunds", "Spiss", "Tösens", "Ried im Oberinntal", "Prutz", "Fendels"]}},
    {"id": "tirol-west", "name": "TirolWest (Landeck)", "conf": 0.8,
     "gem": {"T": ["Landeck", "Zams", "Fließ", "Schönwies", "Grins", "Stanz bei Landeck", "Tobadill", "Pians"]}},
    {"id": "imst", "name": "Imst", "conf": 0.8,
     "gem": {"T": ["Imst", "Imsterberg", "Karres", "Karrösten", "Mils bei Imst", "Nassereith", "Tarrenz", "Roppen",
                   "Mieming", "Obsteig", "Wildermieming", "Mötz", "Silz", "Stams", "Rietz"]},
     "note": "Imst Tourismus + Tirol Mitte/Mieminger Plateau (vereinfacht)"},
    {"id": "zillertal", "name": "Zillertal", "conf": 0.95,
     "gem": {"T": ["Strass im Zillertal", "Schlitters", "Bruck am Ziller", "Fügen", "Fügenberg", "Uderns",
                   "Hart im Zillertal", "Ried im Zillertal", "Kaltenbach", "Stumm", "Stummerberg",
                   "Aschau im Zillertal", "Zell am Ziller", "Zellberg", "Gerlos", "Gerlosberg", "Hainzenberg",
                   "Rohrberg", "Hippach", "Ramsau im Zillertal", "Schwendau", "Mayrhofen", "Brandberg",
                   "Finkenberg", "Tux"]}},
    {"id": "achensee", "name": "Achensee", "conf": 0.95,
     "gem": {"T": ["Achenkirch", "Eben am Achensee", "Steinberg am Rofan"]}},
    {"id": "stubaital", "name": "Stubaital", "conf": 0.95,
     "gem": {"T": ["Schönberg im Stubaital", "Mieders", "Telfes im Stubai", "Fulpmes", "Neustift im Stubaital"]}},
    {"id": "wipptal", "name": "Wipptal", "conf": 0.85,
     "gem": {"T": ["Matrei am Brenner", "Steinach am Brenner", "Gries am Brenner", "Gschnitz", "Trins", "Vals",
                   "Schmirn", "Navis", "Obernberg am Brenner", "Ellbögen", "Patsch"]}},
    {"id": "innsbruck-region", "name": "Region Innsbruck", "conf": 0.8,
     "gem": {"T": ["Innsbruck", "Axams", "Birgitz", "Götzens", "Grinzens", "Mutters", "Natters", "Völs", "Kematen in Tirol",
                   "Oberperfuss", "Ranggen", "Unterperfuss", "Sellrain", "Gries im Sellrain", "St. Sigmund im Sellrain",
                   "Zirl", "Inzing", "Hatting", "Polling in Tirol", "Flaurling", "Pettnau", "Oberhofen im Inntal",
                   "Pfaffenhofen", "Rum", "Thaur", "Aldrans", "Ampass", "Lans", "Sistrans", "Rinn", "Tulfes"]},
     "note": "Innsbruck und seine Feriendörfer (vereinfacht)"},
    {"id": "hall-wattens", "name": "Hall-Wattens", "conf": 0.85,
     "gem": {"T": ["Hall in Tirol", "Absam", "Mils", "Gnadenwald", "Baumkirchen", "Fritzens", "Wattens", "Wattenberg",
                   "Volders", "Kolsass", "Kolsassberg", "Weer", "Weerberg"]}},
    {"id": "seefeld-region", "name": "Region Seefeld", "conf": 0.95,
     "gem": {"T": ["Seefeld in Tirol", "Leutasch", "Reith bei Seefeld", "Scharnitz"]}},
    {"id": "silberregion-karwendel", "name": "Silberregion Karwendel", "conf": 0.85,
     "gem": {"T": ["Schwaz", "Vomp", "Stans", "Terfens", "Pill", "Gallzein", "Buch in Tirol", "Jenbach", "Wiesing"]}},
    {"id": "alpbachtal", "name": "Alpbachtal", "conf": 0.9,
     "gem": {"T": ["Alpbach", "Reith im Alpbachtal", "Brixlegg", "Kramsach", "Rattenberg", "Radfeld", "Münster",
                   "Breitenbach am Inn", "Brandenberg"]}},
    {"id": "wildschoenau", "name": "Wildschönau", "conf": 0.95, "gem": {"T": ["Wildschönau"]}},
    {"id": "kufsteinerland", "name": "Kufsteinerland", "conf": 0.9,
     "gem": {"T": ["Kufstein", "Ebbs", "Erl", "Niederndorf", "Niederndorferberg", "Bad Häring", "Langkampfen",
                   "Schwoich", "Thiersee", "Angerberg", "Mariastein", "Kirchbichl", "Wörgl", "Angath", "Kundl"]},
     "note": "Kufsteinerland + Region Hohe Salve/Wörgl (vereinfacht)"},
    {"id": "wilder-kaiser", "name": "Wilder Kaiser", "conf": 0.95,
     "gem": {"T": ["Ellmau", "Going am Wilden Kaiser", "Scheffau am Wilden Kaiser", "Söll"]}},
    {"id": "kaiserwinkl", "name": "Kaiserwinkl", "conf": 0.95, "osm": "Kaiserwinkl",
     "gem": {"T": ["Kössen", "Schwendt", "Walchsee", "Rettenschöss"]}},
    {"id": "brixental", "name": "Brixental", "conf": 0.9,
     "gem": {"T": ["Brixen im Thale", "Hopfgarten im Brixental", "Itter", "Westendorf", "Kirchberg in Tirol"]}},
    {"id": "kitzbuehel-region", "name": "Kitzbühel", "conf": 0.9,
     "gem": {"T": ["Kitzbühel", "Reith bei Kitzbühel", "Aurach bei Kitzbühel", "Jochberg"]}},
    {"id": "st-johann-region", "name": "Kitzbüheler Alpen – St. Johann in Tirol", "conf": 0.9,
     "gem": {"T": ["St. Johann in Tirol", "Oberndorf in Tirol", "Kirchdorf in Tirol"]}},
    {"id": "pillerseetal", "name": "PillerseeTal", "conf": 0.95,
     "gem": {"T": ["Fieberbrunn", "Hochfilzen", "St. Jakob in Haus", "St. Ulrich am Pillersee", "Waidring"]}},
    {"id": "tannheimer-tal-reg", "name": "Tannheimer Tal", "conf": 0.95,
     "gem": {"T": ["Tannheim", "Grän", "Nesselwängle", "Schattwald", "Zöblen", "Jungholz"]}},
    {"id": "lechtal", "name": "Lechtal", "conf": 0.9,
     "gem": {"T": ["Steeg", "Holzgau", "Bach", "Elbigenalp", "Häselgehr", "Elmen", "Stanzach", "Vorderhornbach",
                   "Hinterhornbach", "Forchach", "Kaisers", "Gramais", "Pfafflar", "Namlos"]}},
    {"id": "zugspitz-arena", "name": "Tiroler Zugspitz Arena", "conf": 0.95,
     "gem": {"T": ["Ehrwald", "Lermoos", "Biberwier", "Berwang", "Bichlbach", "Heiterwang", "Namlos"]}},
    {"id": "naturparkregion-reutte", "name": "Naturparkregion Reutte", "conf": 0.85,
     "gem": {"T": ["Reutte", "Breitenwang", "Ehenbichl", "Höfen", "Lechaschau", "Musau", "Pflach", "Pinswang", "Vils",
                   "Wängle", "Weißenbach am Lech"]}},
    {"id": "osttirol", "name": "Osttirol", "conf": 0.95, "bezirk": ["707"]},
    # Salzburg
    {"id": "gasteinertal", "name": "Gasteinertal", "conf": 0.95,
     "gem": {"S": ["Bad Gastein", "Bad Hofgastein", "Dorfgastein"]}},
    {"id": "grossarltal", "name": "Großarltal", "conf": 0.95, "gem": {"S": ["Großarl", "Hüttschlag"]}},
    {"id": "salzburger-sportwelt", "name": "Salzburger Sportwelt", "conf": 0.85,
     "gem": {"S": ["Flachau", "Wagrain", "St. Johann im Pongau", "Altenmarkt im Pongau", "Radstadt", "Eben im Pongau",
                   "Filzmoos", "Kleinarl", "Hüttau", "Forstau", "Untertauern", "St. Martin am Tennengebirge"]}},
    {"id": "hochkoenig-reg", "name": "Hochkönig", "conf": 0.95,
     "gem": {"S": ["Maria Alm am Steinernen Meer", "Dienten am Hochkönig", "Mühlbach am Hochkönig"]}},
    {"id": "saalbach-reg", "name": "Saalbach Hinterglemm", "conf": 0.95, "gem": {"S": ["Saalbach-Hinterglemm", "Viehhofen"]}},
    {"id": "saalfelden-leogang", "name": "Saalfelden Leogang", "conf": 0.95,
     "gem": {"S": ["Saalfelden am Steinernen Meer", "Leogang"]}},
    {"id": "zell-kaprun", "name": "Zell am See-Kaprun", "conf": 0.95,
     "gem": {"S": ["Zell am See", "Kaprun", "Maishofen", "Piesendorf", "Niedernsill"]}},
    {"id": "nationalpark-region-ht", "name": "Nationalpark Hohe Tauern Region (Oberpinzgau)", "conf": 0.85,
     "gem": {"S": ["Krimml", "Wald im Pinzgau", "Neukirchen am Großvenediger", "Bramberg am Wildkogel",
                   "Hollersbach im Pinzgau", "Mittersill", "Stuhlfelden", "Uttendorf"]}},
    {"id": "rauris-reg", "name": "Raurisertal", "conf": 0.9, "gem": {"S": ["Rauris", "Taxenbach"]}},
    {"id": "grossglockner-reg", "name": "Großglockner/Fuscher Tal", "conf": 0.8,
     "gem": {"S": ["Fusch an der Großglocknerstraße", "Bruck an der Großglocknerstraße"]}},
    {"id": "saalachtal", "name": "Salzburger Saalachtal", "conf": 0.9,
     "gem": {"S": ["Lofer", "Unken", "St. Martin bei Lofer", "Weißbach bei Lofer"]}},
    {"id": "lungau", "name": "Lungau", "conf": 0.95, "bezirk": ["505"]},
    {"id": "tennengau", "name": "Tennengau", "conf": 0.9, "bezirk": ["502"]},
    {"id": "obertauern-reg", "name": "Obertauern", "conf": 0.7, "gem": {"S": ["Untertauern", "Tweng"]},
     "only_with_ski": "obertauern"},
    {"id": "salzburger-seenland", "name": "Salzburger Seenland", "conf": 0.85,
     "gem": {"S": ["Seekirchen am Wallersee", "Mattsee", "Obertrum am See", "Seeham", "Berndorf bei Salzburg",
                   "Schleedorf", "Henndorf am Wallersee", "Neumarkt am Wallersee", "Köstendorf", "Straßwalchen"]}},
    {"id": "fuschlsee", "name": "Fuschlsee", "conf": 0.85,
     "gem": {"S": ["Fuschl am See", "Hof bei Salzburg", "Faistenau", "Hintersee", "Koppl", "Thalgau", "Ebenau",
                   "Plainfeld"]}},
    {"id": "wolfgangsee", "name": "Wolfgangsee", "conf": 0.95,
     "gem": {"S": ["St. Gilgen", "Strobl"], "OÖ": ["St. Wolfgang im Salzkammergut"]}},
    {"id": "stadt-salzburg", "name": "Salzburg Stadt", "conf": 0.95, "gem": {"S": ["Salzburg"]}},
    # Salzkammergut (spans OÖ / S / ST) - OSM polygon + Gemeinde list
    {"id": "salzkammergut", "name": "Salzkammergut", "conf": 0.85, "osm": "Salzkammergut",
     "gem": {"OÖ": ["Bad Ischl", "Gmunden", "Altmünster", "Traunkirchen", "Ebensee am Traunsee", "Bad Goisern am Hallstättersee",
                    "Gosau", "Hallstatt", "Obertraun", "St. Wolfgang im Salzkammergut", "Mondsee", "Unterach am Attersee",
                    "St. Lorenz", "Tiefgraben", "Innerschwand am Mondsee", "Oberwang", "Zell am Moos", "Attersee am Attersee",
                    "Nußdorf am Attersee", "Steinbach am Attersee", "Weyregg am Attersee", "Schörfling am Attersee",
                    "Seewalchen am Attersee", "Grünau im Almtal", "Scharnstein", "Pinsdorf", "Gschwandt", "Kirchham",
                    "St. Konrad"],
             "S": ["St. Gilgen", "Strobl", "Fuschl am See"],
             "ST": ["Bad Aussee", "Altaussee", "Grundlsee", "Bad Mitterndorf"]}},
    {"id": "ausseerland", "name": "Ausseerland", "conf": 0.95,
     "gem": {"ST": ["Bad Aussee", "Altaussee", "Grundlsee", "Bad Mitterndorf"]}},
    {"id": "dachstein-salzkammergut", "name": "Dachstein Salzkammergut", "conf": 0.9,
     "gem": {"OÖ": ["Hallstatt", "Gosau", "Obertraun", "Bad Goisern am Hallstättersee"]},
     "note": "UNESCO-Welterbe Hallstatt-Dachstein/Salzkammergut"},
    {"id": "attersee", "name": "Attersee-Attergau", "conf": 0.85, "osm": "Attergau",
     "gem": {"OÖ": ["Attersee am Attersee", "Nußdorf am Attersee", "Steinbach am Attersee", "Unterach am Attersee",
                    "Weyregg am Attersee", "Schörfling am Attersee", "Seewalchen am Attersee", "St. Georgen im Attergau",
                    "Berg im Attergau", "Straß im Attergau"]}},
    {"id": "mondseeland", "name": "Mondseeland", "conf": 0.9,
     "gem": {"OÖ": ["Mondsee", "Tiefgraben", "Innerschwand am Mondsee", "St. Lorenz", "Oberhofen am Irrsee",
                    "Zell am Moos"]}},
    {"id": "traunsee-almtal", "name": "Traunsee-Almtal", "conf": 0.85,
     "gem": {"OÖ": ["Gmunden", "Altmünster", "Traunkirchen", "Ebensee am Traunsee", "Grünau im Almtal", "Scharnstein",
                    "Pinsdorf", "Gschwandt", "Kirchham", "St. Konrad", "Vorchdorf"]}},
    # OÖ
    {"id": "pyhrn-priel", "name": "Pyhrn-Priel", "conf": 0.9,
     "gem": {"OÖ": ["Hinterstoder", "Vorderstoder", "Spital am Pyhrn", "Windischgarsten", "Roßleithen", "Edlbach",
                    "Rosenau am Hengstpaß"]}},
    {"id": "nationalpark-kalkalpen-region", "name": "Nationalpark Kalkalpen Region", "conf": 0.7,
     "gem": {"OÖ": ["Molln", "Reichraming", "Großraming", "Weyer", "Ternberg", "Losenstein", "Klaus an der Pyhrnbahn",
                    "St. Pankraz"]}},
    {"id": "boehmerwald", "name": "Böhmerwald", "conf": 0.8,
     "gem": {"OÖ": ["Schwarzenberg am Böhmerwald", "Klaffer am Hochficht", "Ulrichsberg", "Aigen-Schlägl",
                    "Julbach", "Nebelberg", "Peilstein im Mühlviertel", "Kollerschlag"]}},
    {"id": "linz", "name": "Linz", "conf": 0.95, "gem": {"OÖ": ["Linz"]}},
    # Steiermark
    {"id": "schladming-dachstein", "name": "Schladming-Dachstein", "conf": 0.9,
     "gem": {"ST": ["Schladming", "Ramsau am Dachstein", "Haus", "Aich", "Gröbming", "Michaelerberg-Pruggern",
                    "Mitterberg-Sankt Martin", "Sölk", "Öblarn", "Stainach-Pürgg", "Irdning-Donnersbachtal"],
             "S": ["Forstau"]}},
    {"id": "gesaeuse", "name": "Gesäuse", "conf": 0.9,
     "gem": {"ST": ["Admont", "Landl", "Sankt Gallen", "Altenmarkt bei Sankt Gallen", "Ardning", "Wildalpen"]}},
    {"id": "murau-kreischberg", "name": "Murau-Kreischberg / Murtal", "conf": 0.8, "bezirk": ["614"]},
    {"id": "hochsteiermark", "name": "Hochsteiermark", "conf": 0.75, "bezirk": ["621"],
     "note": "Mürztal, Mariazellerland, Hochschwab"},
    {"id": "mariazellerland", "name": "Mariazellerland", "conf": 0.9, "gem": {"ST": ["Mariazell"],
                                                                              "NÖ": ["Mitterbach am Erlaufsee"]}},
    {"id": "thermenland-steiermark", "name": "Thermenland Steiermark", "conf": 0.75,
     "gem": {"ST": ["Bad Waltersdorf", "Bad Blumau", "Bad Loipersdorf", "Fürstenfeld", "Bad Gleichenberg",
                    "Bad Radkersburg", "Feldbach", "Riegersburg", "Fehring", "Ilz", "Großwilfersdorf"]}},
    {"id": "suedsteiermark", "name": "Südsteiermark (Weinland)", "conf": 0.8, "bezirk": ["610"]},
    {"id": "schilcherland", "name": "Schilcherland", "conf": 0.75, "bezirk": ["603"]},
    {"id": "region-graz", "name": "Region Graz", "conf": 0.8, "bezirk": ["601", "606"]},
    {"id": "almenland", "name": "Almenland", "conf": 0.85,
     "gem": {"ST": ["Passail", "Fladnitz an der Teichalm", "Breitenau am Hochlantsch", "Gasen", "Naas",
                    "Sankt Kathrein am Offenegg"]}},
    {"id": "erzberg-leoben", "name": "Erzberg Leoben", "conf": 0.8, "bezirk": ["611"]},
    # Kärnten
    {"id": "woerthersee", "name": "Wörthersee", "conf": 0.9,
     "gem": {"K": ["Klagenfurt am Wörthersee", "Velden am Wörther See", "Pörtschach am Wörther See",
                   "Krumpendorf am Wörthersee", "Maria Wörth", "Schiefling am Wörthersee", "Techelsberg am Wörther See",
                   "Keutschach am See"]}},
    {"id": "millstaetter-see", "name": "Millstätter See", "conf": 0.9,
     "gem": {"K": ["Millstatt am See", "Seeboden am Millstätter See", "Radenthein", "Ferndorf", "Fresach"]}},
    {"id": "bad-kleinkirchheim-reg", "name": "Bad Kleinkirchheim / Nockberge", "conf": 0.85,
     "gem": {"K": ["Bad Kleinkirchheim", "Reichenau", "Feld am See", "Afritz am See"]}},
    {"id": "ossiacher-see", "name": "Ossiacher See / Region Villach", "conf": 0.85,
     "gem": {"K": ["Villach", "Ossiach", "Steindorf am Ossiacher See", "Treffen am Ossiacher See", "Arriach",
                   "Finkenstein am Faaker See", "Arnoldstein", "Wernberg", "Bad Bleiberg"]}},
    {"id": "nassfeld-region", "name": "Nassfeld-Pressegger See · Lesachtal · Weissensee", "conf": 0.9,
     "bezirk": ["203"], "gem": {"K": ["Weißensee"]}},
    {"id": "katschberg-lieser-maltatal", "name": "Katschberg-Lieser-Maltatal", "conf": 0.85,
     "gem": {"K": ["Rennweg am Katschberg", "Gmünd in Kärnten", "Malta", "Krems in Kärnten", "Trebesing"]}},
    {"id": "moelltal", "name": "Mölltal / Nationalpark Hohe Tauern Kärnten", "conf": 0.85,
     "gem": {"K": ["Mallnitz", "Obervellach", "Flattach", "Heiligenblut am Großglockner", "Winklern", "Rangersdorf",
                   "Stall", "Großkirchheim", "Mörtschach", "Reißeck"]}},
    {"id": "klopeiner-see", "name": "Klopeiner See – Südkärnten", "conf": 0.85,
     "gem": {"K": ["St. Kanzian am Klopeiner See", "Eberndorf", "Sittersdorf", "Bleiburg", "Feistritz ob Bleiburg",
                   "Globasnitz", "Eisenkappel-Vellach", "Gallizien", "Neuhaus"]}},
    {"id": "lavanttal", "name": "Lavanttal", "conf": 0.9, "bezirk": ["209"]},
    {"id": "carnica-rosental", "name": "Carnica Region Rosental", "conf": 0.8,
     "gem": {"K": ["Ferlach", "Feistritz im Rosental", "St. Jakob im Rosental", "Rosegg", "Ludmannsdorf",
                   "St. Margareten im Rosental", "Köttmannsdorf", "Zell"]}},
    {"id": "mittelkaernten", "name": "Mittelkärnten", "conf": 0.7, "bezirk": ["205"]},
    # Niederösterreich
    {"id": "wachau", "name": "Wachau", "conf": 0.9, "osm": "Wachau",
     "gem": {"NÖ": ["Krems an der Donau", "Dürnstein", "Weißenkirchen in der Wachau", "Spitz", "Mühldorf", "Aggsbach",
                    "Rossatz-Arnsdorf", "Mautern an der Donau", "Schönbühel-Aggsbach", "Emmersdorf an der Donau",
                    "Melk", "Bergern im Dunkelsteinerwald", "Furth bei Göttweig", "Maria Laach am Jauerling"]},
     "note": "UNESCO-Welterbe Kulturlandschaft Wachau"},
    {"id": "wiener-alpen", "name": "Wiener Alpen (Semmering · Rax · Schneeberg · Bucklige Welt)", "conf": 0.8,
     "bezirk": ["318"], "gem": {"NÖ": ["Puchberg am Schneeberg", "Gutenstein", "Hohe Wand", "Miesenbach",
                                     "Muggendorf", "Pernitz", "Rohr im Gebirge", "Waidmannsfeld"]}},
    {"id": "semmering-rax", "name": "Semmering-Rax", "conf": 0.9,
     "gem": {"NÖ": ["Semmering", "Breitenstein", "Reichenau an der Rax", "Payerbach", "Schottwien", "Gloggnitz"],
             "ST": ["Spital am Semmering"]}},
    {"id": "schneebergland", "name": "Schneebergland", "conf": 0.85,
     "gem": {"NÖ": ["Puchberg am Schneeberg", "Grünbach am Schneeberg", "Schwarzau im Gebirge", "Gutenstein",
                    "Rohr im Gebirge", "Höflein an der Hohen Wand", "Hohe Wand", "Willendorf", "Würflach"]}},
    {"id": "wienerwald", "name": "Wienerwald", "conf": 0.85,
     "gem": {"NÖ": ["Alland", "Altlengbach", "Bad Vöslau", "Baden", "Berndorf", "Breitenfurt bei Wien", "Brand-Laaben",
                    "Eichgraben", "Gablitz", "Gaaden", "Gießhübl", "Heiligenkreuz", "Hinterbrühl", "Kaltenleutgeben",
                    "Klausen-Leopoldsdorf", "Klosterneuburg", "Laab im Walde", "Maria Anzbach", "Mauerbach",
                    "Neulengbach", "Perchtoldsdorf", "Pfaffstätten", "Pressbaum", "Purkersdorf", "Tullnerbach",
                    "Wienerwald", "Wolfsgraben", "Mödling", "Maria Enzersdorf", "Pottenstein", "Furth an der Triesting",
                    "Weissenbach an der Triesting", "Altenmarkt an der Triesting", "Kaumberg", "Sooß", "Gumpoldskirchen",
                    "Hernstein", "Hainfeld", "Kirchstetten", "Kasten bei Böheimkirchen", "Stössing", "Michelbach"]},
     "note": "Biosphärenpark-/Tourismusregion Wienerwald (NÖ-Gemeinden, vereinfacht)"},
    {"id": "mostviertel-alpen", "name": "Ötscherland / Mostviertler Alpen", "conf": 0.8,
     "gem": {"NÖ": ["Gaming", "Lunz am See", "Göstling an der Ybbs", "Annaberg", "Mitterbach am Erlaufsee",
                    "Puchenstuben", "St. Anton an der Jeßnitz", "Scheibbs"]}},
    # Burgenland
    {"id": "neusiedler-see", "name": "Neusiedler See", "conf": 0.85, "bezirk": ["107", "102"],
     "gem": {"B": ["Mörbisch am See", "Oggau am Neusiedler See", "Purbach am Neusiedler See",
                   "Breitenbrunn am Neusiedler See", "Donnerskirchen", "Schützen am Gebirge", "Oslip",
                   "Sankt Margarethen im Burgenland"]}},
    {"id": "rosalia-eisenstadt", "name": "Leithaland & Rosalia (Eisenstadt)", "conf": 0.7, "bezirk": ["101", "103", "106"]},
    {"id": "mittelburgenland", "name": "Mittelburgenland – Blaufränkischland", "conf": 0.8, "bezirk": ["108"]},
    {"id": "suedburgenland", "name": "Südburgenland", "conf": 0.85, "bezirk": ["104", "105", "109"]},
    # Wien
    {"id": "wien", "name": "Wien", "conf": 1.0, "bezirk": ["900"]},
]

# Landscape / "Viertel" regions straight from OSM polygons (place=region / boundary=region)
OSM_VIERTEL = ["Marchfeld", "Tullnerfeld", "Bucklige Welt", "Joglland", "Eisenwurzen", "Seewinkel",
               "Weinviertel", "Waldviertel", "Mostviertel", "Industrieviertel", "Mühlviertel", "Innviertel",
               "Hausruckviertel", "Traunviertel", "Machland", "Jauntal", "Grazer Becken", "Oststeirisches Hügelland",
               "Obersteiermark", "Oberkärnten", "Unterkärnten"]

# National parks (OSM boundary=national_park / protect_class=2 named "Nationalpark ...")
NP_RE = r"^Nationalpark "

# ---------------------------------------------------------------------------------------------------------
# Place-type keyword rules (stop names)
# ---------------------------------------------------------------------------------------------------------
NAME_RULES = {
    "hospital": r"(?i)(krankenhaus|klinikum|\bklinik\b|\bklinik[ -]|\blkh\b|\bukh\b|\bakh\b|\bkh\b|spital\b|"
                r"landesklinikum|krankenanstalt|\bsmz\b|unfallkrankenhaus|kinderklinik|uniklinik|"
                r"universitätsklinik|\bk[ -]?h\.? |sanatorium|rehaklinik|\breha\b|rehabilitationszentrum)",
    "university": r"(?i)(universität|\buni\b|\buni[ -]|\btu\b|technische universität|fachhochschule|\bfh\b|"
                  r"hochschule|\bcampus\b|\bboku\b|\bwu\b|montanuni|\bph\b|pädagogische hochschule|"
                  r"universitätsstraße|unipark|universitätszentrum|\bjku\b)",
    "mall": r"(?i)(einkaufszentrum|\bekz\b|shopping|\bscs\b|fachmarktzentrum|\bfmz\b|einkaufspark|shoppingcenter|"
            r"\b[a-zäöü]*-?center\b|city ?park|europark|donauzentrum|murpark|messepark|\batrio\b|\bcyta\b|\bdez\b|"
            r"\bq19\b|huma eleven|millennium city|shopping city|west ?park|lentia city|\bauhof ?center|\bg3\b|outlet|plus[- ]?city)",
    "park_ride": r"(?i)(p ?\+ ?r\b|park ?(&|and|und) ?ride|p&r)",
    "bike_ride": r"(?i)(b ?\+ ?r\b|bike ?(&|and|und) ?ride)",
    "airport": r"(?i)(flughafen|airport|\bflugplatz\b)",
    "lift": r"(?i)(talstation|bergstation|seilbahn|gondelbahn|bergbahn|sesselbahn|sessellift|gletscherbahn|"
            r"[a-zäöü]+bahn\b(?<!bahnhof)|\blift\b|schilift|skilift|kabinenbahn|standseilbahn)",
    "main_station": r"(?i)(hauptbahnhof|\bhbf\b)",
    "station": r"(?i)(bahnhof|\bbf\b|\bbhf\b|bahnhst|haltestelle bahn|\bbahnhaltestelle\b)",
    "ferry": r"(?i)(schiffsanlegestelle|schiffstation|schiffsstation|anlegestelle|schiffländ|schifflände|"
             r"\bschiff\b|fähre|ferry|\bländ\b|landungssteg|schiffahrt|schifffahrt|\bsteg\b)",
    "glacier": r"(?i)(gletscher|ferner\b|\bkees\b)",
    "hut": r"(?i)(hütte\b|huette|\balm\b|\balpe\b|\balp\b|schutzhaus)",
}
# Generic rail words in a stop's own name that are NOT stations (e.g. "Bergbahn" etc. handled above)

# OSM winter_sports polygons that are not ski areas for the public badge (jumps, stadiums, schools, nordic only)
AUTO_SKI_EXCLUDE = (r"(?i)(schanze|skistadion|stadion|superpark|fun ?park|übungs|loipe|wintersportschule|"
                    r"winterwichtelland|kinderland|rodel)")


# ---------------------------------------------------------------------------------------------------------
# E5: ski-pass groups (kind "alliance") come from the curator's own knowledge. They stay `verified: false` in the
# shipped META – and the UI hides them – until each one is checked against the operator's own pages.
# Add an id here only with the date and URL of that check.
# ---------------------------------------------------------------------------------------------------------
ALLIANCES_VERIFIED = set()

# ---------------------------------------------------------------------------------------------------------
# SummitHue (BADGE_SPEC §2.3): the own palette of ski-area colours. Light colour per hue, used to map the curated
# design hints to the nearest hue angle; saturation < 0.15 → fels. Only the hue NAME is shipped.
# ---------------------------------------------------------------------------------------------------------
SUMMIT_HUES = {"enzian": "#3448C5", "gletscher": "#2A6FD1", "daemmerung": "#6A5ED6", "alpengluehen": "#D2456C",
               "zirbe": "#1F7A5E", "morgenrot": "#C9622C", "bergsee": "#138794", "fels": "#5E6E82"}
HUE_OVERRIDES = {"ski-arlberg": "enzian", "4-berge": "zirbe", "planai-hochwurzen": "zirbe", "hauser-kaibling": "zirbe",
                 "reiteralm": "zirbe", "ski-amade": "gletscher", "hochkar": "fels", "zillertal-3000": "gletscher",
                 "stubai": "bergsee"}
GLYPHS_ALLOWED = ("peaks3", "peaks2", "peaks1", "glacier")


def summit_hue(area_id, color):
    """SummitHue raw value for a ski area: curated override, else the hue with the nearest hue angle."""
    if area_id in HUE_OVERRIDES:
        return HUE_OVERRIDES[area_id]
    if not color:
        return "fels"
    import colorsys

    def hsv(c):
        h = c.lstrip("#")
        return colorsys.rgb_to_hsv(*(int(h[k:k + 2], 16) / 255 for k in (0, 2, 4)))
    h0, s0, _v = hsv(color)
    if s0 < 0.15:
        return "fels"
    best, bd = "fels", 9.0
    for name, c in SUMMIT_HUES.items():
        if name == "fels":
            continue
        h1 = hsv(c)[0]
        d = min(abs(h0 - h1), 1 - abs(h0 - h1))
        if d < bd:
            best, bd = name, d
    return best


# ---------------------------------------------------------------------------------------------------------
# E4: operator display names – the same table as KlimaCore OperatorNames.swift (live names map identically).
# (folded prefix or fragment, contains?, display). First match wins. Text only, no logos.
# ---------------------------------------------------------------------------------------------------------
OPERATOR_DISPLAY = [
    ("postbus", True, "Postbus"),
    ("obb-personenverkehr", False, "ÖBB"), ("obb personenverkehr", False, "ÖBB"), ("obb-pv", False, "ÖBB"),
    ("osterreichische bundesbahnen", False, "ÖBB"), ("austrian federal railways", False, "ÖBB"),
    ("wiener linien", False, "Wiener Linien"),
    ("wiener lokalbahnen", False, "Wiener Lokalbahnen"),
    ("holding graz", False, "Graz Linien"), ("graz linien", False, "Graz Linien"),
    ("linz linien", False, "Linz AG Linien"), ("linz ag", False, "Linz AG Linien"),
    ("innsbrucker verkehrsbetriebe", False, "IVB"),
    ("salzburg ag", False, "Salzburg AG"),
    ("salzburger lokalbahn", False, "Salzburger Lokalbahn"),
    ("stern & hafferl", False, "Stern & Hafferl"), ("stern und hafferl", False, "Stern & Hafferl"),
    ("montafonerbahn", False, "Montafonerbahn"),
    ("westbahn", False, "WESTbahn"),
    ("db fernverkehr", False, "DB"), ("db regio", False, "DB"), ("deutsche bahn", False, "DB"),
    ("steiermarkbahn", False, "Steiermarkbahn"),
    ("graz-koflacher", False, "GKB"), ("graz koflacher", False, "GKB"),
    ("raaberbahn", False, "Raaberbahn"), ("gysev", False, "Raaberbahn"),
    ("niederosterreichische verkehrsorganisation", False, "NÖVOG"),
    ("oberosterreichischer verkehrsverbund", False, "OÖVV"),
    ("klagenfurt mobil", False, "Klagenfurt Mobil"),
    ("dr. richard", False, "Dr. Richard"),
    ("blaguss", False, "Blaguss"),
    ("zillertaler verkehrsbetriebe", False, "Zillertaler Verkehrsbetriebe"),
]
OPERATOR_LEGAL_SUFFIXES = [" GmbH & Co. KG", " GmbH & Co KG", " Gesellschaft m.b.H.", " Gesellschaft mbH",
                           " Ges.m.b.H.", " Ges.m.b.H", " GesmbH", " Aktiengesellschaft", " Kundenservice",
                           " GmbH", " m.b.H.", " mbH", " s.r.o.", " s.r.o", " e.U.", " AG", " KG", " OG"]
_FOLD = {}
for _src, _dst in [("äàáâãåāăą", "a"), ("æ", "ae"), ("çćčĉċ", "c"), ("ďđ", "d"), ("èéêëēėęěĕ", "e"), ("ğĝģ", "g"),
                   ("ìíîïīįı", "i"), ("ĺľłļ", "l"), ("ñńňņ", "n"), ("öòóôõøōőŏ", "o"), ("œ", "oe"), ("ŕřŗ", "r"),
                   ("śšşŝș", "s"), ("ß", "ss"), ("ťţț", "t"), ("üùúûūůűųŭ", "u"), ("ýÿ", "y"), ("źżž", "z"),
                   ("’‘`´", "'")]:
    for _c in _src:
        _FOLD[_c] = _dst


def fold(s):
    """KlimaCore PlaceNormalizer.fold (= scripts/places_reference.py fold)."""
    out = []
    for ch in s.lower():
        if ch < "\x80":
            out.append(ch)
        elif ch in _FOLD:
            out.append(_FOLD[ch])
        else:
            out.append("".join(c for c in _ud.normalize("NFKD", ch) if not _ud.combining(c)))
    return "".join(out).replace("ae", "a").replace("oe", "o").replace("ue", "u")


def operator_display(legal):
    """„Österreichische Postbus AG“ → „Postbus“; „A;B“ → „A / B“ (≤ 2). Mirrors OperatorNames.display."""
    t = (legal or "").strip()
    if not t:
        return ""
    if ";" in t:
        out = []
        for part in t.split(";"):
            d = _operator_single(part)
            if d and d not in out:
                out.append(d)
        return " / ".join(out[:2])
    return _operator_single(t)


def _operator_single(raw):
    name = raw.strip()
    f = fold(name)
    if f in ("obb", "oebb"):
        return "ÖBB"
    for match, contains, display in OPERATOR_DISPLAY:
        if (match in f) if contains else f.startswith(match):
            return display
    s = name
    changed = True
    while changed:
        changed = False
        for suf in OPERATOR_LEGAL_SUFFIXES:
            if len(s) > len(suf) + 2 and s.endswith(suf):
                s = s[:-len(suf)].strip(" ,")
                changed = True
                break
    return s
