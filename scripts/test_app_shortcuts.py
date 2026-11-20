"""App Shortcuts budget (run by CI: python3 -m unittest discover -s scripts -p 'test_*.py').

iOS takes at most 10 App Shortcuts per app; the rest are dropped without a warning. docs/SIRI_QUESTIONS.md §5 keeps the 10th slot
free. Every phrase names the app and at most one parameter (an App Shortcut phrase can carry only one)."""
import os
import re
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHORTCUTS = os.path.join(ROOT, "App", "Sources", "Core", "Shortcuts.swift")
MAX_SHORTCUTS = 10
BUDGET = 9   # the 10th stays free (plan2: „siri adds 1, the 10th stays free“)


def source():
    with open(SHORTCUTS, encoding="utf-8") as f:
        text = f.read()
    # Comments do not count.
    return "\n".join(line.split("//", 1)[0] for line in text.splitlines())


def shortcut_blocks(text):
    """The text of every `AppShortcut(` … `)` call (balanced parentheses)."""
    blocks = []
    for match in re.finditer(r"\bAppShortcut\(", text):
        depth, i = 0, match.end() - 1
        while i < len(text):
            if text[i] == "(":
                depth += 1
            elif text[i] == ")":
                depth -= 1
                if depth == 0:
                    break
            i += 1
        blocks.append(text[match.start():i + 1])
    return blocks


def phrases(block):
    inner = re.search(r"phrases:\s*\[(.*?)\]\s*,\s*shortTitle", block, re.S)
    return re.findall(r'"((?:[^"\\]|\\.)*)"', inner.group(1)) if inner else []


class AppShortcutsTests(unittest.TestCase):
    def test_budget(self):
        blocks = shortcut_blocks(source())
        self.assertGreater(len(blocks), 0)
        self.assertLessEqual(len(blocks), MAX_SHORTCUTS, "iOS drops App Shortcuts beyond 10")
        self.assertLessEqual(len(blocks), BUDGET, "the 10th App Shortcut slot stays free (docs/SIRI_QUESTIONS.md §5)")

    def test_phrases_name_the_app_and_at_most_one_parameter(self):
        for block in shortcut_blocks(source()):
            found = phrases(block)
            self.assertTrue(found, block[:80])
            for phrase in found:
                self.assertIn(r"\(.applicationName)", phrase, phrase)
                self.assertLessEqual(len(re.findall(r"\\\(\\\.\$", phrase)), 1, phrase)

    def test_ask_klima_is_one_shortcut(self):
        blocks = [b for b in shortcut_blocks(source()) if "AskKlimaIntent" in b]
        self.assertLessEqual(len(blocks), 1, "„Frag KlimaBilanz“ has one App Shortcut with several phrases")


if __name__ == "__main__":
    unittest.main()
