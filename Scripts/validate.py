"""Checks the bundled content, interface texts, assets and App Store texts. Standard library
only; it is not a Swift build (the verify workflow compiles and tests on a Mac).

- course.json: 18 lessons of 6 phrases, 108 phrases, 22 letters, every meaning and title in
  all ten languages.
- ui.json: the same keys in all ten languages, none empty, and every key the Swift screens
  read (t("..."), text("..."), error = "...", the navigation and exercise keys) exists.
- AppIcon 1024 x 1024 PNG without transparency; asset catalog and privacy manifest parse;
  one InfoPlist.strings per language listed in project.yml.
- App Store texts within Apple's limits (name and subtitle 30, keywords 100, description 4000,
  promotional text 170, what's new 4000).
"""
import json
import plistlib
import re
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LANGUAGES = ["en", "ru", "uk", "fr", "es", "pt", "ar", "am", "de", "he"]
LIMITS = [("name.txt", 30), ("subtitle.txt", 30), ("keywords.txt", 100), ("description.txt", 4000),
          ("promotional_text.txt", 170), ("whats_new.txt", 4000)]
problems = []


def check(condition, message):
    if not condition:
        problems.append(message)


def swift_keys():
    source = "\n".join(path.read_text(encoding="utf-8") for path in sorted((ROOT / "Sources").glob("*.swift")))
    keys = set()
    for match in re.finditer(r"\b(?:t|text)\(", source):
        depth, index = 0, match.end() - 1
        while index < len(source):
            if source[index] == "(":
                depth += 1
            elif source[index] == ")":
                depth -= 1
                if depth == 0:
                    break
            index += 1
        keys.update(re.findall(r'"([a-z_]+)"', source[match.end():index]))
    keys.update(re.findall(r'error = "([a-z_]+)"', source))
    keys.update(re.findall(r'case \.\w+: return "([a-z_]+)"', source))
    keys.update(re.findall(r'TabDestination\(id: "([a-z_]+)"', source))
    keys.add("tab_words")
    keys.discard("en")  # the fallback language code inside t(), not a key
    return keys


def png_info(path):
    data = path.read_bytes()
    check(data[:8] == b"\x89PNG\r\n\x1a\n", f"{path.name} is not a PNG")
    width, height, depth, colour = struct.unpack(">IIBB", data[16:26])
    return width, height, colour, b"tRNS" in data


course = json.loads((ROOT / "Resources/course.json").read_text(encoding="utf-8"))
check(course.get("version") == 1, "course.json version is not 1")
check(course.get("languages") == LANGUAGES, "course.json languages differ from the app's list")
lessons = course["lessons"]
phrases = [phrase for lesson in lessons for phrase in lesson["phrases"]]
check(len(lessons) == 18, f"{len(lessons)} lessons instead of 18")
check(len(phrases) == 108, f"{len(phrases)} phrases instead of 108")
check(len(course["alphabet"]) == 22, f"{len(course['alphabet'])} letters instead of 22")
check(len({phrase["id"] for phrase in phrases}) == len(phrases), "duplicate phrase ids")
for lesson in lessons:
    check(len(lesson["phrases"]) == 6, f"lesson {lesson['id']} has {len(lesson['phrases'])} phrases")
    for code in LANGUAGES:
        check(bool(lesson["titles"].get(code, "").strip()), f"lesson {lesson['id']} has no {code} title")
for phrase in phrases:
    for field in ("id", "he", "translit", "plain"):
        check(bool(str(phrase.get(field, "")).strip()), f"phrase {phrase.get('id')} has no {field}")
    for code in LANGUAGES:
        check(bool(phrase["meanings"].get(code, "").strip()), f"phrase {phrase['id']} has no {code} meaning")

ui = json.loads((ROOT / "Resources/ui.json").read_text(encoding="utf-8"))
check(sorted(ui) == sorted(LANGUAGES), f"ui.json languages: {sorted(ui)}")
all_keys = set().union(*(set(values) for values in ui.values()))
for code in LANGUAGES:
    values = ui.get(code, {})
    missing = sorted(all_keys - set(values))
    check(not missing, f"ui.json {code} misses {missing}")
    empty = sorted(key for key, value in values.items() if not value.strip())
    check(not empty, f"ui.json {code} has empty {empty}")
used = swift_keys()
unknown = sorted(key for key in used if key not in all_keys)
check(not unknown, f"Swift reads keys that ui.json lacks: {unknown}")

assets = ROOT / "Resources/Assets.xcassets"
for contents in assets.rglob("Contents.json"):
    try:
        json.loads(contents.read_text(encoding="utf-8"))
    except ValueError as error:
        problems.append(f"{contents.relative_to(ROOT)}: {error}")
icon = assets / "AppIcon.appiconset/AppIcon-1024.png"
width, height, colour, transparency = png_info(icon)
check((width, height) == (1024, 1024), f"AppIcon is {width} x {height}")
check(colour in (0, 2) and not transparency, "AppIcon must have no alpha channel or transparency")
check((assets / "Neighborhood.imageset/neighborhood.png").exists(), "Neighborhood image missing")
for name in ("LaunchBackground", "AccentColor"):
    check((assets / f"{name}.colorset/Contents.json").exists(), f"{name} colour missing")
plistlib.loads((ROOT / "Resources/PrivacyInfo.xcprivacy").read_bytes())

project = (ROOT / "project.yml").read_text(encoding="utf-8")
listed = re.search(r"CFBundleLocalizations: \[([^\]]+)\]", project)
check(listed is not None and [item.strip() for item in listed.group(1).split(",")] == LANGUAGES,
      "CFBundleLocalizations in project.yml differs from the ten languages")
for code in LANGUAGES:
    strings = ROOT / f"Resources/Localization/{code}.lproj/InfoPlist.strings"
    check(strings.exists() and "CFBundleDisplayName" in strings.read_text(encoding="utf-8"),
          f"{strings.relative_to(ROOT)} missing")

lengths = {}
for locale in ("en-US", "he"):
    for name, limit in LIMITS:
        path = ROOT / "app-store" / locale / name
        if not path.exists():
            problems.append(f"app-store/{locale}/{name} missing")
            continue
        value = path.read_text(encoding="utf-8").strip()
        lengths[f"{locale}/{name}"] = len(value)
        check(0 < len(value) <= limit, f"app-store/{locale}/{name}: {len(value)} characters, limit {limit}")
        check("Android" not in value and "Google Play" not in value, f"app-store/{locale}/{name} names another platform")
    keywords = (ROOT / "app-store" / locale / "keywords.txt").read_text(encoding="utf-8").strip().split(",")
    check(all(word.strip() == word and word for word in keywords), f"app-store/{locale}/keywords.txt has empty or padded keywords")

if problems:
    print("Problems:")
    for problem in problems:
        print(" - " + problem)
    sys.exit(1)
print(json.dumps({
    "lessons": len(lessons), "phrases": len(phrases), "letters": len(course["alphabet"]),
    "interfaceKeys": len(all_keys), "keysReadBySwift": len(used), "storeTextLengths": lengths,
    "swiftCompilation": "not performed by this script",
}, ensure_ascii=False, indent=1))
