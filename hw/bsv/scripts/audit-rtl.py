#!/usr/bin/env python3
import re
import sys
from pathlib import Path


PORTS: dict[str, tuple[str, str]] = {
    "mkSchedulerSynthTop": (
        "EN_start start_descriptor EN_publishStripe publishStripe_stripe "
        "EN_completeWork EN_consumeCompletion",
        "startReady publishReady workValid currentWork completionValid completion",
    ),
    "mkLoopMatmulSynthTop": (
        "EN_start start_descriptor EN_publishStripe publishStripe_stripe "
        "EN_consumeLoadWork EN_putLoadCompletion putLoadCompletion_completion "
        "EN_consumeExecuteWork EN_putExecuteCompletion putExecuteCompletion_completion "
        "EN_consumeStoreWork EN_putStoreCompletion putStoreCompletion_completion "
        "EN_consumeStripeCompletion",
        "loadWorkValid loadWork executeWorkValid executeWork storeWorkValid storeWork "
        "stripeCompletionValid stripeCompletion",
    ),
    "mkMemorySubsystemSynthTop": (
        "EN_scheduleLoad scheduleLoad_work EN_consumeLoadCompletion "
        "EN_scheduleStore scheduleStore_work EN_consumeStoreCompletion "
        "EN_activationPort_requests_consume EN_activationPort_responses_put "
        "EN_weightPort_requests_consume EN_weightPort_responses_put "
        "EN_blockShiftPort_requests_consume EN_blockShiftPort_responses_put "
        "EN_rowShiftPort_requests_consume EN_rowShiftPort_responses_put "
        "EN_outputPort_requests_consume EN_outputPort_responses_put",
        "loadReady loadCompletionValid loadCompletion storeReady "
        "storeCompletionValid storeCompletion "
        "activationPort_requests_first weightPort_requests_first "
        "blockShiftPort_requests_first rowShiftPort_requests_first "
        "outputPort_requests_first",
    ),
}


def audit_ports(path: Path) -> None:
    source = re.sub(r"//[^\n]*|/\*.*?\*/", "", path.read_text(), flags=re.S)
    ports: dict[str, str] = {}
    for direction, names in re.findall(
        r"\b(input|output)\s+(?:\[[^\]]+\]\s*)?([^;]+);", source
    ):
        ports.update((name.strip(), direction) for name in names.split(","))
    inputs, outputs = PORTS[path.stem]
    missing = [
        name
        for direction, names in (("input", "CLK RST_N " + inputs), ("output", outputs))
        for name in names.split()
        if ports.get(name) != direction
    ]
    if missing:
        raise SystemExit(f"{path}: missing public ports: {', '.join(missing)}")
    print(f"PASS: {path.stem} public ports ({len(ports)})")


if __name__ == "__main__":
    audit_ports(Path(sys.argv[1]))
