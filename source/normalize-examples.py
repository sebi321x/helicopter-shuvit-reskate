from pathlib import Path
import re
import sys


def normalize_paths(upstream_root):
    example = re.compile(r"""(?i)C:(\\{1,2})Users\1[^\\\r\n'"<>]+\1Music""")
    for relative, expected in (
        ("Extension/Music/setup_page.html", 2),
        ("Extension/Music/youtube_music.cpp", 1),
    ):
        path = upstream_root / relative
        previous = path.read_text(encoding="utf-8")
        updated, count = example.subn(r"C:\1Music", previous)
        if count != expected:
            raise ValueError(f"Expected {expected} example paths in {relative}, found {count}")
        path.write_text(updated, encoding="utf-8", newline="\n")


if __name__ == "__main__":
    normalize_paths(Path(sys.argv[1]))
