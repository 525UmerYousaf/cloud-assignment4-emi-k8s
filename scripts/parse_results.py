#!/usr/bin/env python3
"""Turn raw httperf logs into CSV summaries.

    python3 scripts/parse_results.py fixed       -> results/fixed/summary.csv
    python3 scripts/parse_results.py autoscale   -> results/autoscale/phases.csv
    python3 scripts/parse_results.py             -> both

Standard library only.
"""
import csv
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "results")

PATTERNS = {
    "connections": r"Total: connections (\d+)",
    "requests": r"Total: connections \d+ requests (\d+)",
    "replies": r"Total: connections \d+ requests \d+ replies (\d+)",
    "duration_s": r"test-duration ([\d.]+) s",
    "request_rate": r"Request rate: ([\d.]+) req/s",
    "avg_response_ms": r"Reply time \[ms\]: response ([\d.]+)",
    "status_2xx": r"Reply status: 1xx=\d+ 2xx=(\d+)",
    "status_4xx": r"Reply status:.* 4xx=(\d+)",
    "status_5xx": r"Reply status:.* 5xx=(\d+)",
    "httperf_errors": r"Errors: total (\d+)",
    "client_timeouts": r"Errors: total \d+ client-timo (\d+)",
    "conn_refused": r"connrefused (\d+)",
    "conn_reset": r"connreset (\d+)",
}
FIELDS = list(PATTERNS) + ["total_errors"]


def parse_block(text):
    out = {}
    for key, pat in PATTERNS.items():
        m = re.search(pat, text)
        out[key] = float(m.group(1)) if m and "." in m.group(1) else (int(m.group(1)) if m else "")
    # An "error" is any request that did not get a 2xx: transport errors
    # (timeouts, refused, reset ...) plus 4xx/5xx replies.
    try:
        out["total_errors"] = int(out["httperf_errors"]) + int(out["status_4xx"]) + int(out["status_5xx"])
    except (TypeError, ValueError):
        out["total_errors"] = ""
    return out


def split_phases(text):
    """Split a job log at the '=== PHASE' markers written by run_httperf_job."""
    phases = []
    for m in re.finditer(r"=== PHASE rate=(\d+) seconds=(\d+) sessions=\d+ start=(\d+)(.*?)=== END rate=\d+ end=(\d+)", text, re.S):
        p = parse_block(m.group(4))
        p.update(rate=int(m.group(1)), seconds=int(m.group(2)), start_epoch=int(m.group(3)), end_epoch=int(m.group(5)))
        phases.append(p)
    return phases


def fixed():
    d = os.path.join(RES, "fixed")
    runs = os.path.join(d, "runs.csv")
    if not os.path.exists(runs):
        print("no results/fixed/runs.csv yet")
        return
    rows = []
    with open(runs) as fh:
        for r in csv.DictReader(fh):
            log = os.path.join(d, r["log"])
            if not os.path.exists(log):
                continue
            ph = split_phases(open(log).read())
            if not ph:
                print(f"warning: no httperf output in {r['log']}")
                continue
            p = ph[0]
            rows.append({"replicas": int(r["replicas"]), "rate": int(r["rate"]),
                         "start_epoch": r["start_epoch"], "end_epoch": r["end_epoch"],
                         **{k: p[k] for k in FIELDS}})
    rows.sort(key=lambda x: (x["replicas"], x["rate"]))
    out = os.path.join(d, "summary.csv")
    with open(out, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=["replicas", "rate", "start_epoch", "end_epoch"] + FIELDS)
        w.writeheader()
        w.writerows(rows)
    print(f"{'replicas':>8} {'rate':>5} {'avg ms':>9} {'2xx':>6} {'errors':>7} {'achieved':>9}")
    for x in rows:
        print(f"{x['replicas']:>8} {x['rate']:>5} {x['avg_response_ms']:>9} {x['status_2xx']:>6} {x['total_errors']:>7} {x['request_rate']:>9}")
    print(f"-> {out}")


def autoscale():
    d = os.path.join(RES, "autoscale")
    log = os.path.join(d, "httperf_autoscale.log")
    if not os.path.exists(log):
        print("no results/autoscale/httperf_autoscale.log yet")
        return
    ph = split_phases(open(log).read())
    out = os.path.join(d, "phases.csv")
    with open(out, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=["rate", "seconds", "start_epoch", "end_epoch"] + FIELDS)
        w.writeheader()
        for p in ph:
            w.writerow({k: p[k] for k in w.fieldnames})
    for p in ph:
        print(f"phase {p['rate']:>4} req/s x {p['seconds']} s: avg {p['avg_response_ms']} ms, 2xx {p['status_2xx']}, errors {p['total_errors']}")
    print(f"-> {out}")


if __name__ == "__main__":
    which = sys.argv[1] if len(sys.argv) > 1 else "all"
    if which in ("fixed", "all"):
        fixed()
    if which in ("autoscale", "all"):
        autoscale()
