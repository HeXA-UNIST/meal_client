"""Dart 버전 제약과 Flutter 릴리스 선택의 회귀 테스트."""

import unittest

from resolve_flutter_version import Constraint, Version, resolve


class ConstraintTest(unittest.TestCase):
    def test_단일버전과_caret_상한(self):
        cases = [
            ("3.47.0", ["3.47.0"], ["3.47.1", "3.47.0+1"]),
            ("^3.47.0", ["3.47.0", "3.48.0"], ["3.46.9", "4.0.0-rc.1"]),
            ("^0.3.0", ["0.3.0", "0.3.9"], ["0.4.0"]),
            ("^0.0.3", ["0.0.3", "0.0.9"], ["0.1.0"]),
            ("any", ["0.0.0", "9.0.0-rc.1+2"], []),
        ]
        for text, allowed, rejected in cases:
            with self.subTest(조건=text):
                constraint = Constraint.parse(text)
                for version in allowed:
                    self.assertTrue(constraint.allows(Version.parse(version)))
                for version in rejected:
                    self.assertFalse(constraint.allows(Version.parse(version)))

    def test_비교연산자와_교집합(self):
        cases = [
            (">3.47.0 <=3.48.0", "3.47.0", False),
            (">3.47.0 <=3.48.0", "3.48.0", True),
            (" < 3.48.0 >= 3.47.0 ", "3.47.10", True),
            (">=3.47.0>=3.47.2<3.48.0", "3.47.1", False),
            (">=3.48.0 <3.47.0", "3.47.5", False),
            (">=3.47.0 <3.47.0", "3.47.0", False),
            ("3.47.0 >3.47.0", "3.47.0", False),
        ]
        for text, version, expected in cases:
            with self.subTest(조건=text, 버전=version):
                self.assertEqual(Constraint.parse(text).allows(Version.parse(version)), expected)

    def test_prerelease와_build의_Dart_비교규칙(self):
        cases = [
            ("<3.48.0", "3.48.0-beta.1", False),
            (">=3.48.0-beta.1 <3.48.0", "3.48.0-beta.2", True),
            ("^3.47.0-beta.1", "3.47.0-beta.2", True),
            (">3.47.0", "3.47.0+1", True),
            ("3.47.0+01", "3.47.0+1", True),
            ("3.47.0-beta.-1", "3.47.0-beta.0xffffffffffffffff", True),
            ("3.47.0+16", "3.47.0+0x10", True),
            (">=3.47.0-beta.2 <3.48.0", "3.47.0-beta.10", True),
        ]
        for text, version, expected in cases:
            with self.subTest(조건=text, 버전=version):
                self.assertEqual(Constraint.parse(text).allows(Version.parse(version)), expected)

    def test_잘못된_문법을_거부한다(self):
        for text in ["", "null", "3.47.x", "~3.47.0", "=3.47.0",
                     "^", "^3.47.0 <4.0.0", ">=3.47", "3.47.0 || 3.48.0"]:
            with self.subTest(조건=text), self.assertRaises(ValueError):
                Constraint.parse(text)

    def test_버전숫자의_Dart_정수범위를_검사한다(self):
        with self.assertRaises(ValueError):
            Version.parse("9223372036854775808.0.0")


class ResolveTest(unittest.TestCase):
    def test_stable중_숫자로_가장_최신버전을_선택한다(self):
        manifest = {"releases": [
            {"channel": "stable", "version": "v1.12.13+hotfix.9"},
            {"channel": "stable", "version": "3.47.9"},
            {"channel": "stable", "version": "3.47.10"},
            {"channel": "beta", "version": "3.47.99"},
            {"channel": "stable", "version": "3.48.0"},
            {"channel": "stable", "version": "3.47.10", "dart_sdk_arch": "arm64"},
        ]}
        self.assertEqual(resolve(">=3.47.0 <3.48.0", manifest), "3.47.10")
        self.assertEqual(resolve("3.47.9", manifest), "3.47.9")
        self.assertEqual(resolve("^3.47.0", manifest), "3.48.0")
        with self.assertRaises(ValueError):
            resolve("3.47.11", manifest)


if __name__ == "__main__":
    unittest.main()
