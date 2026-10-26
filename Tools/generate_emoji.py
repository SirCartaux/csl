#!/usr/bin/env python3
"""Builds Resources/emoji.json for CEP from Unicode + CLDR data.

Sources (downloaded on first run, cached in Tools/.cache):
  * https://unicode.org/Public/emoji/latest/emoji-test.txt
  * CLDR annotations + annotationsDerived, English and German

The output is deterministic: emoji keep the order of emoji-test.txt, symbols
are sorted by Unicode block and code point, and all keyword list are sorted.
"""

from __future__ import annotations

import json
import re
import subprocess
import unicodedata
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CACHE = Path(__file__).resolve().parent / ".cache"
OUTPUT = ROOT / "Resources" / "emoji.json"

SOURCES = {
    "emoji-test.txt": "https://unicode.org/Public/emoji/latest/emoji-test.txt",
    "en.xml": "https://raw.githubusercontent.com/unicode-org/cldr/main/common/annotations/en.xml",
    "de.xml": "https://raw.githubusercontent.com/unicode-org/cldr/main/common/annotations/de.xml",
    "en_derived.xml": "https://raw.githubusercontent.com/unicode-org/cldr/main/common/annotationsDerived/en.xml",
    "de_derived.xml": "https://raw.githubusercontent.com/unicode-org/cldr/main/common/annotationsDerived/de.xml",
}

SKIN_TONES = {0x1F3FB: 0, 0x1F3FC: 1, 0x1F3FD: 2, 0x1F3FE: 3, 0x1F3FF: 4}
VS16 = "\ufe0f"

GROUP_MAP = {
    "Smileys & Emotion": ("smileys", "smileys emotion gesichter gefühle emotionen"),
    "People & Body": ("people", "people body personen körper menschen"),
    "Animals & Nature": ("nature", "animals nature tiere natur pflanzen"),
    "Food & Drink": ("food", "food drink essen trinken lebensmittel getränke"),
    "Travel & Places": ("travel", "travel places reisen orte plätze"),
    "Activities": ("activity", "activities aktivitäten sport spiele freizeit"),
    "Objects": ("objects", "objects objekte dinge"),
    "Symbols": ("symbols", "symbols symbole zeichen"),
    "Flags": ("flags", "flags flaggen länder"),
}

# Additional hand-written German search terms for very common concepts.
EXTRA_KEYWORDS = {
    "😀": "lachen lächeln grinsen smiley",
    "😂": "lachen tränen freude lol",
    "🤣": "lachen rollen lol",
    "😊": "lächeln freundlich",
    "😍": "liebe herzaugen verliebt",
    "😘": "kuss liebe",
    "😎": "cool sonnenbrille",
    "🤔": "denken nachdenken hmm",
    "😭": "weinen traurig heulen",
    "😡": "wütend sauer zornig",
    "👍": "daumen hoch ok gut like",
    "👎": "daumen runter schlecht dislike",
    "👏": "applaus klatschen",
    "🙏": "beten danke bitte",
    "👋": "winken hallo tschüss",
    "❤️": "herz liebe rot",
    "🧡": "herz liebe orange",
    "💛": "herz liebe gelb",
    "💚": "herz liebe grün",
    "💙": "herz liebe blau",
    "💜": "herz liebe lila",
    "🖤": "herz liebe schwarz",
    "🤍": "herz liebe weiß",
    "🤎": "herz liebe braun",
    "💔": "herz gebrochen liebeskummer",
    "🔥": "feuer heiß brand",
    "✨": "funken magie glitzer",
    "🎉": "party feiern konfetti",
    "🎊": "party konfetti feiern",
    "✅": "haken richtig erledigt ja",
    "❌": "kreuz falsch nein",
    "⚠️": "warnung achtung",
    "⭐": "stern favorit",
    "🌟": "stern glanz",
    "🚀": "rakete start schnell",
    "💻": "laptop computer",
    "🖥️": "computer monitor",
    "📱": "handy smartphone",
    "⌨️": "tastatur",
    "🖱️": "maus",
    "💡": "idee glühbirne licht",
    "📌": "pin anpinnen",
    "📎": "büroklammer anhang",
    "🔗": "link kette",
    "📁": "ordner",
    "📄": "datei dokument",
    "📝": "notiz schreiben",
    "📅": "kalender datum",
    "⏰": "wecker uhrzeit",
    "⏳": "sanduhr warten",
    "☕": "kaffee",
    "🍕": "pizza",
    "🍔": "burger hamburger",
    "🍟": "pommes",
    "🍺": "bier",
    "🍷": "wein",
    "🌍": "erde welt globus",
    "🌙": "mond nacht",
    "☀️": "sonne",
    "🌧️": "regen",
    "❄️": "schnee kalt",
    "🐶": "hund",
    "🐱": "katze",
    "🦊": "fuchs",
    "🐻": "bär",
    "🐼": "panda",
    "⚽": "fußball",
    "🏀": "basketball",
    "🎮": "gaming spiel",
    "🎵": "musik note",
    "🎧": "kopfhörer",
    "🚗": "auto",
    "🚲": "fahrrad",
    "✈️": "flugzeug reise",
    "🏠": "haus zuhause",
    "💶": "euro geld",
    "💵": "dollar geld",
    "💯": "hundert perfekt",
    "🆗": "ok",
    "🆒": "cool",
    "🤷": "schulterzucken keine ahnung",
    "🤦": "facepalm",
    "😴": "schlafen müde",
    "🤯": "schockiert kopf explodiert",
    "🥳": "party feiern",
    "🤝": "handschlag deal",
    "🙌": "hände hoch jubel",
    "💪": "muskel stark",
    "🧠": "gehirn denken",
    "👀": "augen schauen",
    "💬": "sprechblase chat",
    "💭": "gedanke",
    "🔔": "glocke benachrichtigung",
    "🔕": "stumm",
    "🔒": "schloss sicher",
    "🔓": "offen",
    "🔑": "schlüssel",
    "🛠️": "werkzeug",
    "⚙️": "einstellungen zahnrad",
    "🧲": "magnet",
    "🧪": "labor test",
    "🧬": "dna",
    "🩺": "arzt gesundheit",
    "💊": "medizin pille",
    "🏆": "trophäe gewinn",
    "🥇": "gold medaille",
    "🎯": "ziel treffer",
    "🧩": "puzzle teil",
    "🎨": "kunst palette",
    "🖌️": "pinsel",
    "📸": "kamera foto",
    "🎬": "film klappe",
    "🎤": "mikrofon",
    "🔊": "lautstärke laut",
    "🔇": "stumm",
}

KAOMOJI = [
    ("(＾▽＾)", "happy", "happy smile freude lächeln glücklich"),
    ("(＾ω＾)", "happy cat", "happy smile freude"),
    ("(◕‿◕)", "cute smile", "cute smile süß lächeln"),
    ("(｡◕‿◕｡)", "cute shy", "cute shy süß schüchtern"),
    ("(✿◠‿◠)", "flower smile", "flower smile blume lächeln"),
    ("(≧▽≦)", "excited", "excited happy freude jubel"),
    ("(★^O^★)", "star happy", "star happy stern freude"),
    ("(⌒‿⌒)", "gentle smile", "gentle smile sanft lächeln"),
    ("(￣▽￣)", "smug", "smug grin grinsen"),
    ("(¬‿¬)", "smirk", "smirk grin grinsen"),
    ("(￣ω￣)", "relaxed", "relaxed entspannt"),
    ("(´｡• ω •｡`)", "soft smile", "soft smile sanft lächeln"),
    ("(｡•́︿•̀｡)", "sad", "sad traurig"),
    ("(╥﹏╥)", "crying", "crying weinen traurig"),
    ("(っ˘̩╭╮˘̩)っ", "hug me", "hug umarmung traurig"),
    ("(ಥ﹏ಥ)", "teary", "teary weinen"),
    ("(╯°□°）╯︵ ┻━┻", "table flip", "table flip wütend sauer tisch"),
    ("┬─┬ノ( º _ ºノ)", "table restore", "table restore tisch"),
    ("(ノಠ益ಠ)ノ彡┻━┻", "rage flip", "rage wütend sauer"),
    ("(ﾉ◕ヮ◕)ﾉ*:･ﾟ✧", "magic sparkle", "magic sparkle zauber funken"),
    ("(•_•) ( •_•)>⌐■-■ (⌐■_■)", "deal with it", "deal sunglasses cool"),
    ("ಠ_ಠ", "disapproval", "disapproval skeptisch"),
    ("ಠ‿ಠ", "mischief", "mischief schelmisch"),
    ("(¬_¬)", "side eye", "side eye skeptisch"),
    ("(・_・)", "confused", "confused verwirrt"),
    ("(゜-゜)", "puzzled", "puzzled verwirrt"),
    ("(O_O)", "shocked", "shocked schockiert"),
    ("(o_O)", "confused confused", "confused verwirrt"),
    ("(°ロ°)", "surprised", "surprised überrascht"),
    ("Σ(°△°|||)", "shock", "shock schock"),
    ("(╬ Ò﹏Ó)", "angry", "angry wütend"),
    ("(＃`Д´)", "angry shout", "angry shout wütend schreien"),
    ("(；一_一)", "annoyed", "annoyed genervt"),
    ("(￣ヘ￣)", "grumpy", "grumpy mürrisch"),
    ("(´-ω-`)", "tired", "tired müde"),
    ("(－_－) zzZ", "sleepy", "sleepy müde schlafen"),
    ("(￣o￣) zzZZzz", "sleeping", "sleeping schlafen"),
    ("(๑•̀ㅂ•́)و✧", "determined", "determined entschlossen"),
    ("(ง'̀-'́)ง", "fight", "fight kampf boxen"),
    ("ᕦ(ò_óˇ)ᕤ", "strong", "strong stark muskel"),
    ("(•̀ᴗ•́)و", "yes", "yes ja"),
    ("(・∀・)", "nice", "nice gut"),
    ("(☞ﾟヮﾟ)☞", "point", "point zeigen"),
    ("☜(ﾟヮﾟ☜)", "point left", "point zeigen links"),
    ("( ͡° ͜ʖ ͡°)", "lenny", "lenny meme"),
    ("( ͡~ ͜ʖ ͡°)", "lenny smirk", "lenny smirk"),
    ("¯\\_(ツ)_/¯", "shrug", "shrug schulterzucken keine ahnung"),
    ("(ツ)", "smile japanese", "smile japanese lächeln"),
    ("(ヘ)_／¯", "shrug alt", "shrug schulterzucken"),
    ("(¬_¬)ﾉ", "wave bye", "wave bye tschüss"),
    ("( ˘ ³˘)♥", "kiss", "kiss kuss liebe"),
    ("(♥ω♥*)", "love", "love liebe herz"),
    ("(´∀｀)♡", "love happy", "love happy liebe"),
    ("(≧◡≦) ♡", "love excited", "love excited liebe"),
    ("(｡♥‿♥｡)", "heart eyes", "heart eyes verliebt"),
    ("(◍•ᴗ•◍)❤", "warm hug", "warm hug umarmung liebe"),
    ("(づ｡◕‿‿◕｡)づ", "hug", "hug umarmung"),
    ("ʕ•ᴥ•ʔ", "bear", "bear bär"),
    ("ʕっ•ᴥ•ʔっ", "bear hug", "bear hug bär umarmung"),
    ("(=^･ω･^=)", "cat", "cat katze"),
    ("ฅ^•ﻌ•^ฅ", "cat paws", "cat katze pfoten"),
    ("(•ө•)♡", "cat love", "cat love katze liebe"),
    ("UwU", "uwu", "uwu cute süß"),
    ("OwO", "owo", "owo cute süß"),
    ("(・ω・)ノ", "hello", "hello hallo winken"),
    ("(￣▽￣)ノ", "bye", "bye tschüss"),
    ("(๑˃ᴗ˂)ﻭ", "cheer", "cheer jubel"),
    ("(ﾉ´ヮ`)ﾉ*: ･ﾟ", "celebrate", "celebrate feiern"),
    ("ヽ(•‿•)ノ", "yay", "yay jubel"),
    ("＼(＾▽＾)／", "hooray", "hooray jubel"),
    ("(´･ω･`)", "sad small", "sad traurig"),
    ("(╯︵╰,)", "cry", "cry weinen"),
    ("(个_个)", "crying eyes", "crying weinen"),
    ("(ಥ_ಥ)", "sobbing", "sobbing weinen"),
    ("(っ- ‸ - ς)", "comfort", "comfort trost"),
    ("(￣^￣)ゞ", "salute", "salute salut"),
    ("(•_•)ゞ", "salute cool", "salute salut"),
    ("(☞ﾟ∀ﾟ)☞", "point happy", "point zeigen"),
    ("(ﾉ◕ヮ◕)ﾉ", "wave happy", "wave winken"),
    ("(°◡°)", "content", "content zufrieden"),
    ("(◡‿◡✿)", "peaceful", "peaceful friedlich"),
    ("(✧∀✧)", "amazed", "amazed erstaunt"),
    ("(✪㉨✪)", "excited eyes", "excited eyes begeistert"),
    ("(◉‿◉)", "curious", "curious neugierig"),
    ("(◎_◎;)", "dizzy", "dizzy schwindelig"),
    ("(x_x)", "dead", "dead tot"),
    ("(T_T)", "crying classic", "crying weinen"),
    ("(;_;)", "crying tears", "crying weinen"),
    ("(╯°□°)╯︵ ʞooqǝɔɐɟ", "flip facebook", "flip facebook"),
    ("(ง ͠° ͟ل͜ ͡°)ง", "fight ready", "fight kampf"),
    ("ᕕ( ᐛ )ᕗ", "run", "run rennen"),
    ("(┛◉Д◉)┛彡┻━┻", "flip angry", "flip angry wütend"),
    ("(╯ರ ~ ರ）╯︵ ┻━┻", "flip rage", "flip wütend"),
    ("( ˘▽˘)っ♨", "tea", "tea tee"),
    ("( ^_^)／", "high five", "high five"),
    ("(￣▽￣)／", "goodbye", "goodbye tschüss"),
    ("(ﾉ*ﾟｰﾟ)ﾉ", "wave", "wave winken"),
    ("(•̀o•́)ง", "determined fight", "determined fight"),
    ("(๑•́ ₃ •̀๑)", "pout", "pout schmollen"),
    ("(￣3￣)", "kiss face", "kiss kuss"),
    ("(´ε｀ )", "kiss lips", "kiss kuss"),
    ("(っ˘з(˘⌣˘ )", "kiss couple", "kiss kuss paar"),
    ("(づ￣ ³￣)づ", "kiss hug", "kiss hug kuss umarmung"),
    ("(¬‿¬)☞", "point smirk", "point zeigen"),
    ("(｡•̀ᴗ-)✧", "wink", "wink zwinkern"),
    ("(≖‿≖)", "smug smile", "smug schadenfreude"),
    ("(◔_◔)", "skeptical", "skeptical skeptisch"),
    ("(•_•)?", "question", "question frage"),
    ("(???)", "unknown", "unknown keine ahnung"),
    ("(￣～￣)", "chewing", "chewing kauen"),
    ("(∪｡∪)｡｡｡zzz", "sleepy bear", "sleep bear schlafen"),
    ("(－ω－) zzZ", "sleep", "sleep schlafen"),
    ("(っ˘ω˘ς )", "cozy", "cozy gemütlich"),
    ("(•ω•)", "calm", "calm ruhig"),
    ("(◕ᴗ◕✿)", "flower girl", "flower blume"),
    ("(◍•ᴗ•◍)", "warm smile", "warm smile"),
    ("(✯ᴗ✯)", "dreamy", "dreamy verträumt"),
    ("(☆▽☆)", "star eyes", "star eyes sterne"),
    ("(☉_☉)", "stare", "stare starren"),
    ("(◣_◢)", "evil", "evil böse"),
    ("(｀∀´)Ψ", "villain", "villain böse"),
    ("(•̀ᴗ•́)و ̑̑", "yes determined", "yes ja"),
    ("٩(◕‿◕)۶", "cheer up", "cheer jubel"),
    ("ヽ(￣ω￣(￣ω￣〃)ゝ", "hug group", "hug group umarmung"),
    ("(ノ*°▽°*)", "excited wave", "excited wave"),
    ("(ﾉ≧∀≦)ﾉ", "excited hands", "excited freude"),
]


def fetch(name: str, url: str) -> Path:
    CACHE.mkdir(parents=True, exist_ok=True)
    path = CACHE / name
    if not path.exists():
        print(f"download {url}")
        try:
            urllib.request.urlretrieve(url, path)
        except Exception as error:
            print(f"urllib failed ({error}); trying curl")
            subprocess.run(["curl", "-sSL", "-o", str(path), url], check=True)
    return path


def strip_vs16(text: str) -> str:
    return text.replace(VS16, "")


def load_annotations(path: Path) -> dict[str, dict[str, list[str] | str]]:
    """Returns {cp: {"name": str, "keywords": [str]}} keyed by VS16-free text."""
    result: dict[str, dict[str, list[str] | str]] = {}
    root = ET.parse(path).getroot()
    for annotation in root.iter("annotation"):
        cp = annotation.get("cp")
        if not cp:
            continue
        key = strip_vs16(cp)
        text = (annotation.text or "").strip()
        if not text:
            continue
        entry = result.setdefault(key, {"name": "", "keywords": []})
        if annotation.get("type") == "tts":
            entry["name"] = text
        else:
            entry["keywords"].extend(part.strip() for part in text.split("|") if part.strip())
    return result


def merge_annotations(base: dict, extra: dict) -> None:
    for key, value in extra.items():
        entry = base.setdefault(key, {"name": "", "keywords": []})
        if not entry.get("name") and value.get("name"):
            entry["name"] = value["name"]
        entry["keywords"].extend(value.get("keywords", []))


def dedupe(values: list[str]) -> list[str]:
    seen: set[str] = set()
    out: list[str] = []
    for value in values:
        value = " ".join(value.split())
        if not value:
            continue
        key = value.casefold()
        if key in seen:
            continue
        seen.add(key)
        out.append(value)
    return out


def title_case_subgroup(raw: str) -> str:
    return raw.replace("-", " ").replace("_", " ").strip().capitalize()


def build_emoji(emoji_path: Path, annotations_en: dict, annotations_de: dict) -> tuple[list[dict], int]:
    lines = emoji_path.read_text(encoding="utf-8").splitlines()
    entries: list[dict] = []
    by_text: dict[str, dict] = {}
    tone_sources: list[tuple[str, str, int]] = []
    tone_variants: dict[str, dict[int, str]] = {}

    for line in lines:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if ";" not in line or "#" not in line:
            continue
        left, right = line.split("#", 1)
        codepoints_part, status_part = left.split(";", 1)
        status = status_part.strip()
        if status != "fully-qualified":
            continue
        codepoints = codepoints_part.strip().split()
        if not codepoints:
            continue
        # Skip emoji components (skin tone swatches, hair components, ...)
        if any(int(cp, 16) in SKIN_TONES for cp in codepoints):
            text = "".join(chr(int(cp, 16)) for cp in codepoints)
            base_text = "".join(chr(int(cp, 16)) for cp in codepoints if int(cp, 16) not in SKIN_TONES)
            tones = [SKIN_TONES[int(cp, 16)] for cp in codepoints if int(cp, 16) in SKIN_TONES]
            if base_text and tones and len(set(tones)) == 1:
                tone_sources.append((strip_vs16(base_text), text, tones[0]))
            continue
        if any(int(cp, 16) == 0x200D for cp in codepoints) and not any(
            int(cp, 16) not in SKIN_TONES for cp in codepoints
        ):
            continue

        emoji = "".join(chr(int(cp, 16)) for cp in codepoints)
        # Comments look like: "😀 E1.0 grinning face"
        comment = right.strip()
        match = re.match(r"^(\S+)\s+E[\d.]+\s+(.*)$", comment)
        if not match:
            continue
        fallback_name = match.group(2).strip()
        raw_group = ""
        raw_subgroup = ""
        # emoji-test stores groups as "# group: ..." and "# subgroup: ..."
        # We resolve them while iterating below.
        entries.append(
            {
                "emoji": emoji,
                "fallback": fallback_name,
                "codepoints": codepoints,
            }
        )
        by_text[emoji] = entries[-1]

    # Second pass to attach groups/subgroups (comments are separate lines).
    group = ""
    subgroup = ""
    index = 0
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("# group: "):
            group = stripped[len("# group: "):]
        elif stripped.startswith("# subgroup: "):
            subgroup = stripped[len("# subgroup: "):]
        elif stripped and not stripped.startswith("#") and ";" in stripped:
            _, status_part = stripped.split(";", 1)
            if status_part.strip().split("#")[0].strip() != "fully-qualified":
                continue
            left = stripped.split(";", 1)[0].strip()
            codepoints = left.split()
            if not codepoints or any(int(cp, 16) in SKIN_TONES for cp in codepoints):
                continue
            emoji = "".join(chr(int(cp, 16)) for cp in codepoints)
            entry = by_text.get(emoji)
            if entry is None:
                continue
            entry["group"] = group
            entry["subgroup"] = subgroup
            index += 1

    for base_text, tone_text, tone_index in tone_sources:
        tone_variants.setdefault(base_text, {})[tone_index] = tone_text

    output: list[dict] = []
    for entry in entries:
        emoji = entry["emoji"]
        group = entry.get("group", "")
        subgroup = entry.get("subgroup", "")
        slug, extra_group_keywords = GROUP_MAP.get(group, ("symbols", group.casefold()))
        en = annotations_en.get(strip_vs16(emoji), {})
        de = annotations_de.get(strip_vs16(emoji), {})
        name_en = en.get("name") or entry["fallback"]
        name_de = de.get("name") or ""
        keywords = []
        keywords.extend(en.get("keywords", []))
        keywords.extend(de.get("keywords", []))
        if name_en:
            keywords.append(name_en)
        if name_de:
            keywords.append(name_de)
        keywords.extend(entry["fallback"].split())
        if name_de:
            keywords.extend(name_de.split())
        keywords.extend(extra_group_keywords.split())
        keywords.extend(title_case_subgroup(subgroup).split())
        keywords.extend(EXTRA_KEYWORDS.get(emoji, "").split())
        keywords = dedupe(keywords)
        record = {
            "e": emoji,
            "n": name_en.strip(),
            "k": "|".join(keywords),
            "g": slug,
            "sg": title_case_subgroup(subgroup),
        }
        if name_de.strip() and name_de.strip().casefold() != name_en.strip().casefold():
            record["d"] = name_de.strip()
        tones = tone_variants.get(strip_vs16(emoji), {})
        if tones:
            record["t"] = [tones.get(i, emoji) for i in range(5)]
        output.append(record)
    return output, len(tone_variants)


def in_ranges(cp: int, ranges: list[tuple[int, int]]) -> bool:
    return any(start <= cp <= end for start, end in ranges)


SYMBOL_BLOCKS = [
    ("Arrows", [(0x2190, 0x21FF), (0x27F0, 0x27FF), (0x2900, 0x297F), (0x2B00, 0x2BFF)]),
    ("Math", [(0x2200, 0x22FF), (0x2A00, 0x2AFF), (0x27C0, 0x27EF), (0x2980, 0x29FF)]),
    ("Currency", [(0x20A0, 0x20CF)]),
    ("Punctuation", [(0x2000, 0x206F), (0x2E00, 0x2E7F)]),
    ("Letterlike", [(0x2100, 0x214F)]),
    ("Numbers", [(0x2150, 0x218F), (0x2460, 0x24FF), (0x2070, 0x209F)]),
    ("Technical", [(0x2300, 0x23FF)]),
    ("Box Drawing", [(0x2500, 0x257F), (0x2580, 0x259F)]),
    ("Shapes", [(0x25A0, 0x25FF)]),
    ("Misc", [(0x2600, 0x26FF), (0x2700, 0x27BF)]),
    ("Enclosed", [(0x1F100, 0x1F1FF)]),
]

SKIP_WORDS = (
    "VARIATION SELECTOR",
    "ZERO WIDTH",
    "COMBINING",
    "TAG",
    "CANCEL TAG",
    "CONTROL",
    "PRIVATE USE",
    "SURROGATE",
    "NO-BREAK",
    "SOFT HYPHEN",
    "JOINER",
    "FILLER",
    "WORD JOINER",
    "OBJECT REPLACEMENT",
    "REPLACEMENT CHARACTER",
)


def build_symbols(emoji: list[dict]) -> list[dict]:
    emoji_chars = set()
    for item in emoji:
        for char in item["e"]:
            emoji_chars.add(char)
    output: list[dict] = []
    seen: set[str] = set()
    for group, ranges in SYMBOL_BLOCKS:
        for start, end in ranges:
            for cp in range(start, end + 1):
                char = chr(cp)
                if char in seen or char in emoji_chars:
                    continue
                name = unicodedata.name(char, "")
                if not name or any(word in name for word in SKIP_WORDS):
                    continue
                category = unicodedata.category(char)
                if category in ("Cc", "Cf", "Cs", "Co", "Cn", "Zs", "Zl", "Zp"):
                    continue
                if char.isspace():
                    continue
                seen.add(char)
                keywords = dedupe([name.casefold(), group.casefold()] + name.casefold().split())
                output.append(
                    {
                        "e": char,
                        "n": name.casefold(),
                        "k": "|".join(keywords),
                        "g": "symbols",
                        "sg": group,
                    }
                )
    output.sort(key=lambda item: (item["sg"], item["n"]))
    return output


def build_kaomoji() -> list[dict]:
    return [
        {
            "e": text,
            "n": name,
            "k": "|".join(dedupe([name.casefold()] + keywords.casefold().split() + ["kaomoji", "text", "gesicht"])),
            "g": "kaomoji",
            "sg": "Kaomoji",
        }
        for text, name, keywords in KAOMOJI
    ]


def main() -> None:
    paths = {name: fetch(name, url) for name, url in SOURCES.items()}
    annotations_en = load_annotations(paths["en.xml"])
    annotations_de = load_annotations(paths["de.xml"])
    derived_en = load_annotations(paths["en_derived.xml"])
    derived_de = load_annotations(paths["de_derived.xml"])
    merge_annotations(annotations_en, derived_en)
    merge_annotations(annotations_de, derived_de)

    emoji, tone_count = build_emoji(paths["emoji-test.txt"], annotations_en, annotations_de)
    symbols = build_symbols(emoji)
    kaomoji = build_kaomoji()

    payload = {
        "version": 1,
        "emoji": emoji,
        "symbols": symbols,
        "kaomoji": kaomoji,
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")

    groups: dict[str, int] = {}
    for item in emoji:
        groups[item["g"]] = groups.get(item["g"], 0) + 1
    print(f"wrote {OUTPUT} ({OUTPUT.stat().st_size / 1024:.1f} KiB)")
    print(f"emoji={len(emoji)} toneBases={tone_count} symbols={len(symbols)} kaomoji={len(kaomoji)}")
    print("groups: " + ", ".join(f"{key}={value}" for key, value in groups.items()))


if __name__ == "__main__":
    main()
