#!/usr/bin/env python3
import re
import sys
from pathlib import Path
from typing import Final


# Prefix, configured entries per RegFile, number of lanes/banks in each fixture.
MEMORIES: Final[dict[str, tuple[tuple[str, int, int], ...]]] = {
    "mkMemorySynthTop": (
        ("scratchpad_laneMemories_", 8, 4),
        ("accumulator_memories_", 8, 2),
    ),
    "mkMemorySubsystemSynthTop": (
        ("subsystem_staging_activations_bankVector_", 16, 32),
        ("subsystem_staging_weights_bankVector_", 32, 64),
        ("subsystem_staging_metadata_blockScales_", 24, 16),
        ("subsystem_staging_metadata_rowShifts_", 12, 16),
        ("subsystem_accumulators_memories_", 12, 16),
    ),
}


def verilog_integer(value: str) -> int:
    width, separator, digits = value.replace("_", "").partition("'")
    if not separator:
        return int(width)
    digits = digits.lower().removeprefix("s")
    return int(digits[1:], {"b": 2, "o": 8, "d": 10, "h": 16}[digits[0]])


def audit_memory(path: Path) -> None:
    source = re.sub(r"//[^\n]*|/\*.*?\*/", "", path.read_text(), flags=re.S)
    instances = re.findall(
        r"\bRegFile\s*#\s*\((.*?)\)\s+([\w$]+)\s*\(", source, flags=re.S
    )
    checked = 0
    for prefix, depth, count in MEMORIES[path.stem]:
        group = [
            (parameters, name)
            for parameters, name in instances
            if name.startswith(prefix)
        ]
        if len(group) != count:
            raise SystemExit(f"{path}: {prefix}: expected {count} RegFiles, got {len(group)}")
        for parameters, name in group:
            values = {
                key: verilog_integer(value.strip())
                for key, value in re.findall(r"\.(\w+)\s*\(([^)]+)\)", parameters)
            }
            if values.get("lo") != 0 or values.get("hi") != depth - 1:
                raise SystemExit(
                    f"{path}: {name}: expected range 0..{depth - 1}, "
                    f"got {values.get('lo')}..{values.get('hi')}"
                )
            checked += 1
        print(f"PASS: {prefix} {count} RegFiles x {depth} entries")
    if checked != len(instances):
        raise SystemExit(f"{path}: unaudited RegFile instances")


if __name__ == "__main__":
    for argument in sys.argv[1:]:
        audit_memory(Path(argument))
