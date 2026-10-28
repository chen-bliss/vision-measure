import shutil
import tempfile
import unittest
from pathlib import Path

import check_localization as checker


class LocalizationCheckTests(unittest.TestCase):
    def test_repository_is_fully_translated(self):
        errors, keys = checker.check()
        self.assertEqual(errors, [])
        self.assertGreater(len(keys), 200)

    def test_placeholders_ignore_order_and_percent_literals(self):
        self.assertEqual(checker.placeholders("%1$ld次 · %2$ld个"), checker.placeholders("%2$ld x · %1$ld y"))
        self.assertEqual(checker.placeholders("%.0f%%"), [(1, "f")])
        self.assertNotEqual(checker.placeholders("%@"), checker.placeholders("%ld"))
        self.assertNotEqual(checker.placeholders("%ld"), checker.placeholders("%d"))
        self.assertNotEqual(checker.placeholders("%lld"), checker.placeholders("%d"))
        self.assertEqual(checker.placeholders("3 % d’erreur"), [(1, "d")])

    def test_detects_missing_translation_and_unwrapped_text(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            shutil.copytree(checker.ROOT / "Resources", root / "Resources")
            (root / "Sources/App").mkdir(parents=True)
            (root / "Sources/App/View.swift").write_text('Text(L("新增文字"))\nlet raw = "未包装"\n', encoding="utf-8")
            errors, _ = checker.check(root)
            self.assertTrue(any("missing translation" in e and "新增文字" in e for e in errors))
            self.assertTrue(any("unlocalized literal" in e and "未包装" in e for e in errors))

    def test_parser_rejects_duplicates(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Localizable.strings"
            path.write_text('"a" = "1";\n"a" = "2";\n', encoding="utf-8")
            with self.assertRaises(ValueError):
                checker.parse_strings(path)


if __name__ == "__main__":
    unittest.main()
