#!/usr/bin/env python3
"""Milestone 04 graphs (PNG, in results/graphs/):

  graph1_response_time.png   avg response time vs request rate, one line per replica count
  graph2_pod_cpu.png         CPU of each web pod over time, 100 req/s run with 3 replicas
  graph3_autoscaling.png     request rate, average CPU and replicas over the 10-minute HPA test

Needs matplotlib (pip3 install matplotlib).
"""
import csv
import os
from collections import defaultdict

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "results")
OUT = os.path.join(RES, "graphs")
os.makedirs(OUT, exist_ok=True)

CPU_REQUEST_M = 100   # requests.cpu of a web pod (100m)
CPU_LIMIT_M = 250     # limits.cpu of a web pod (250m)
COLORS = ["#2a6fdb", "#e8590c", "#2b8a3e", "#ae3ec9", "#c92a2a", "#868e96"]

plt.rcParams.update({"figure.dpi": 150, "axes.grid": True, "grid.alpha": 0.3,
                     "axes.spines.top": False, "axes.spines.right": False, "font.size": 10})


def read_csv(path):
    with open(path) as fh:
        return list(csv.DictReader(fh))


def num(x):
    try:
        return float(x)
    except (TypeError, ValueError):
        return None


def graph1():
    path = os.path.join(RES, "fixed", "summary.csv")
    if not os.path.exists(path):
        print("graph 1 skipped: run scripts/run-fixed.sh first")
        return
    rows = read_csv(path)
    by_rep = defaultdict(list)
    for r in rows:
        if num(r["avg_response_ms"]) is not None:
            by_rep[int(r["replicas"])].append((int(r["rate"]), num(r["avg_response_ms"]), int(num(r["total_errors"]) or 0)))
    fig, ax = plt.subplots(figsize=(8, 4.8))
    ys = []
    for i, rep in enumerate(sorted(by_rep)):
        pts = sorted(by_rep[rep])
        x = [p[0] for p in pts]; y = [p[1] for p in pts]; ys += y
        ax.plot(x, y, marker="o", lw=2, color=COLORS[i], label=f"{rep} replica{'s' if rep > 1 else ''}")
        for xi, yi, err in pts:
            if err:
                ax.annotate(f"{err} err", (xi, yi), textcoords="offset points", xytext=(4, 6), fontsize=7, color=COLORS[i])
    if ys and max(ys) / max(min(ys), 0.1) > 30:
        ax.set_yscale("log")
    ax.set_xlabel("Request rate (req/s)")
    ax.set_ylabel("Average response time (ms)")
    ax.set_title("Graph 1 - Average response time vs request rate", loc="left", fontweight="bold")
    ax.set_xticks(sorted({p[0] for v in by_rep.values() for p in v}))
    ax.legend(frameon=False)
    fig.tight_layout()
    fig.savefig(os.path.join(OUT, "graph1_response_time.png"))
    plt.close(fig)
    print("graph 1 -> results/graphs/graph1_response_time.png")


def graph2(replicas=3, rate=100):
    tag = f"{replicas}r_{rate}rps"
    pods = os.path.join(RES, "fixed", f"pods_{tag}.csv")
    runs = os.path.join(RES, "fixed", "runs.csv")
    if not (os.path.exists(pods) and os.path.exists(runs)):
        print(f"graph 2 skipped: no results/fixed/pods_{tag}.csv")
        return
    start = end = None
    for r in read_csv(runs):
        if int(r["replicas"]) == replicas and int(r["rate"]) == rate:
            start, end = int(r["start_epoch"]), int(r["end_epoch"])
    series = defaultdict(list)
    for r in read_csv(pods):
        if r["pod"].startswith("emi-web-") and num(r["cpu_millicores"]) is not None:
            t = int(r["epoch"]) - (start or 0)
            series[r["pod"]].append((t, 100.0 * num(r["cpu_millicores"]) / CPU_REQUEST_M))
    fig, ax = plt.subplots(figsize=(8, 4.8))
    for i, pod in enumerate(sorted(series)):
        pts = sorted(series[pod])
        ax.plot([p[0] for p in pts], [p[1] for p in pts], marker="o", lw=2, color=COLORS[i % len(COLORS)], label=pod)
    if start and end:
        ax.axvspan(0, end - start, color="#ffd43b", alpha=0.15, label=f"httperf {rate} req/s")
    ax.axhline(100.0 * CPU_LIMIT_M / CPU_REQUEST_M, ls="--", color="#c92a2a", lw=1, label="CPU limit (250m)")
    ax.axhline(50, ls=":", color="#495057", lw=1, label="HPA target (50%)")
    ax.set_xlabel("Time since the run started (s)")
    ax.set_ylabel("CPU utilisation (% of the 100m request)")
    ax.set_title(f"Graph 2 - CPU per web pod, {rate} req/s with {replicas} replicas", loc="left", fontweight="bold")
    ax.set_ylim(bottom=0)
    ax.legend(frameon=False, fontsize=8)
    fig.tight_layout()
    fig.savefig(os.path.join(OUT, "graph2_pod_cpu.png"))
    plt.close(fig)
    print("graph 2 -> results/graphs/graph2_pod_cpu.png")


def graph3():
    d = os.path.join(RES, "autoscale")
    hpa_p, ph_p = os.path.join(d, "hpa.csv"), os.path.join(d, "phases.csv")
    if not (os.path.exists(hpa_p) and os.path.exists(ph_p)):
        print("graph 3 skipped: run scripts/run-autoscale.sh first")
        return
    phases = read_csv(ph_p)
    if not phases:
        print("graph 3 skipped: no phases parsed")
        return
    t0 = int(phases[0]["start_epoch"])
    mins = lambda e: (int(e) - t0) / 60.0  # noqa: E731

    hpa = [r for r in read_csv(hpa_p) if r["epoch"]]
    t = [mins(r["epoch"]) for r in hpa]
    cpu = [num(r["cpu_pct"]) for r in hpa]
    rep = [num(r["current_replicas"]) for r in hpa]

    fig, axes = plt.subplots(3, 1, figsize=(9, 7.5), sharex=True)
    ax = axes[0]
    xs, ys, ach_x, ach_y = [], [], [], []
    for p in phases:
        a, b = mins(p["start_epoch"]), mins(p["end_epoch"])
        xs += [a, b]; ys += [int(p["rate"])] * 2
        if num(p["request_rate"]) is not None:
            ach_x += [a, b, None]; ach_y += [num(p["request_rate"])] * 2 + [None]
    ax.plot(xs, ys, color=COLORS[0], lw=2, label="offered (httperf --rate)")
    if ach_x:
        ax.plot(ach_x, ach_y, color=COLORS[0], lw=1.5, ls="--", label="achieved (phase average)")
    ax.set_ylabel("Request rate\n(req/s)")
    ax.legend(frameon=False, fontsize=8, loc="upper right")

    ax = axes[1]
    ax.plot(t, cpu, color=COLORS[1], lw=2, marker=".", label="average CPU across web pods (HPA)")
    ax.axhline(50, ls=":", color="#495057", lw=1, label="target 50%")
    ax.set_ylabel("CPU\n(% of request)")
    ax.set_ylim(bottom=0)
    ax.legend(frameon=False, fontsize=8, loc="upper right")

    ax = axes[2]
    ax.step(t, rep, where="post", color=COLORS[2], lw=2, label="web replicas")
    ax.set_ylabel("Replicas")
    ax.set_ylim(0, 5.8)
    ax.set_yticks(range(0, 6))
    ax.set_xlabel("Time since the load started (minutes)")
    ax.legend(frameon=False, fontsize=8, loc="upper right")

    for a in axes:
        for p in phases[1:]:
            a.axvline(mins(p["start_epoch"]), color="#adb5bd", lw=0.8, ls="--")
    axes[0].set_title("Graph 3 - Autoscaling test: load, CPU and replicas", loc="left", fontweight="bold")
    fig.tight_layout()
    fig.savefig(os.path.join(OUT, "graph3_autoscaling.png"))
    plt.close(fig)
    print("graph 3 -> results/graphs/graph3_autoscaling.png")


if __name__ == "__main__":
    graph1()
    graph2()
    graph3()
