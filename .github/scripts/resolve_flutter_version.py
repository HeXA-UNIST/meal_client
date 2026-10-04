"""pub_semver 2.2.0의 파싱·비교 규칙으로 최신 stable Flutter를 선택한다.

원본: https://github.com/dart-lang/pub_semver/tree/2.2.0/lib/src
라이선스: pub_semver.LICENSE
"""

from dataclasses import dataclass, field, replace
from functools import total_ordering
import json
import re
import sys
from urllib.request import urlopen


VERSION = re.compile(
    r"([0-9]+)\.([0-9]+)\.([0-9]+)"
    r"(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?"
    r"(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?"
)


def identifiers(text):
    def parse(part):
        # Dart의 int.tryParse처럼 부호·16진수·64비트 범위를 처리한다.
        if re.fullmatch(r"-?[0-9]+", part):
            number = int(part)
        elif re.fullmatch(r"-?0[xX][0-9a-fA-F]+", part):
            number = int(part, 16)
            if not part.startswith("-") and 2**63 <= number < 2**64:
                number -= 2**64
        else:
            return part
        return number if -(2**63) <= number < 2**63 else part
    return tuple(parse(part) for part in text.split(".")) if text else ()


@total_ordering
@dataclass(frozen=True)
class Version:
    core: tuple
    pre: tuple = ()
    build: tuple = ()
    text: str = field(default="", compare=False)

    @classmethod
    def parse(cls, text):
        match = VERSION.fullmatch(text)
        if not match:
            raise ValueError(f"잘못된 버전: {text!r}")
        core = tuple(map(int, match.group(1, 2, 3)))
        if any(number >= 2**63 for number in core):
            raise ValueError(f"버전 숫자가 Dart 정수 범위를 벗어났습니다: {text!r}")
        return cls(core,
                   identifiers(match[4]), identifiers(match[5]), text)

    def key(self):
        def parts(values):
            return tuple((0, value) if isinstance(value, int) else (1, value)
                         for value in values)
        # Dart는 build 식별자도 버전 순서와 동등성에 반영한다.
        return self.core, not self.pre, parts(self.pre), parts(self.build)

    def __lt__(self, other):
        return self.key() < other.key()


@dataclass
class Constraint:
    minimum: Version | None = None
    maximum: Version | None = None
    include_min: bool = False
    include_max: bool = False
    empty: bool = False

    @classmethod
    def parse(cls, text):
        original = text
        text = text.strip()
        if text == "any":
            return cls()
        if text.startswith("^"):
            match = VERSION.match(text[1:].strip())
            if not match or match.end() != len(text[1:].strip()):
                raise ValueError(f"잘못된 caret 조건: {original!r}")
            version = Version.parse(match[0])
            major, minor, _ = version.core
            # Dart는 major가 0이면 patch 값과 관계없이 다음 minor가 상한이다.
            upper = (major + 1, 0, 0) if major else (0, minor + 1, 0)
            return cls(version, Version(upper, (0,)), True, False)

        result = cls()
        while text:
            operator = re.match(r"[<>]=?", text)
            op = operator[0] if operator else ""
            if operator:
                text = text[operator.end():].strip()
            match = VERSION.match(text)
            if not match:
                raise ValueError(f"잘못된 버전 조건: {original!r}")
            version = Version.parse(match[0])
            text = text[match.end():].strip()
            if op in ("", ">", ">="):
                inclusive = op != ">"
                if result.minimum is None or version > result.minimum:
                    result.minimum, result.include_min = version, inclusive
                elif version == result.minimum:
                    result.include_min &= inclusive
            if op in ("", "<", "<="):
                inclusive = op != "<"
                if result.maximum is None or version < result.maximum:
                    result.maximum, result.include_max = version, inclusive
                elif version == result.maximum:
                    result.include_max &= inclusive

        if result.minimum is None and result.maximum is None:
            raise ValueError("빈 버전 조건은 허용하지 않습니다.")
        if result.minimum is not None and result.maximum is not None:
            if result.minimum > result.maximum:
                return cls(empty=True)
            if result.minimum == result.maximum:
                result.empty = not (result.include_min and result.include_max)
                return result

        # VersionRange의 기본 규칙: 배타적 상한의 prerelease도 제외한다.
        upper, lower = result.maximum, result.minimum
        if (upper is not None and not result.include_max
                and not upper.pre and not upper.build
                and not (lower is not None and lower.pre
                         and lower.core == upper.core)):
            result.maximum = replace(upper, pre=(0,))
        return result

    def allows(self, version):
        if self.empty:
            return False
        if self.minimum is not None:
            if version < self.minimum or (version == self.minimum and not self.include_min):
                return False
        if self.maximum is not None:
            if version > self.maximum or (version == self.maximum and not self.include_max):
                return False
        return True


def resolve(constraint_text, manifest):
    constraint = Constraint.parse(constraint_text)
    # 액션과 동일하게 과거 릴리스의 v 접두사를 제거한다.
    candidates = [Version.parse(release["version"].removeprefix("v"))
                  for release in manifest["releases"] if release["channel"] == "stable"]
    selected = max((version for version in candidates if constraint.allows(version)),
                   default=None)
    if selected is None:
        raise ValueError(f"조건에 맞는 stable Flutter 릴리스가 없습니다: {constraint_text}")
    return selected.text


def main():
    if len(sys.argv) != 3:
        sys.exit("사용법: resolve_flutter_version.py <버전 조건> <runner OS>")
    try:
        os_name = sys.argv[2].lower()
        if os_name not in ("linux", "macos", "windows"):
            raise ValueError(f"지원하지 않는 runner OS: {sys.argv[2]}")
        url = (
            "https://storage.googleapis.com/flutter_infra_release/releases/"
            f"releases_{os_name}.json"
        )
        with urlopen(url, timeout=30) as response:
            manifest = json.load(response)
        print(resolve(sys.argv[1], manifest))
    except (ValueError, KeyError, TypeError, OSError) as error:
        sys.exit(f"Flutter 버전 선택 실패: {error}")


if __name__ == "__main__":
    main()
