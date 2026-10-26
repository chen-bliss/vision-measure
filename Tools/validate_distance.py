#!/usr/bin/env python3
"""Audit hardware distance readings against independently measured references.

Engineering check only. Does not establish clinical refraction validity.
All units are metres except the explicitly named vergence errors (dioptres).
"""
from __future__ import annotations
import argparse
import csv
import html
import json
import statistics
from collections import defaultdict
from pathlib import Path
from validate_study import finite, metrics

FIELDS = ["observation_id", "participant_id", "device", "source", "condition", "calibration_id",
          "role", "reference_m", "reference_bound_m", "observed_m", "observed_bound_m",
          "repeat_index", "status", "synthetic"]
SOURCES = {"manual", "calibratedCamera", "depth"}

def normalize(row):
    row = dict(row)
    for key in FIELDS:
        if key not in row: raise ValueError("Missing column: "+key)
    for key in ("observation_id", "participant_id", "device", "condition", "calibration_id"):
        if not str(row[key]).strip(): raise ValueError("Empty "+key)
        row[key] = str(row[key]).strip()
    if row["source"] not in SOURCES: raise ValueError("Unknown distance source")
    if row["role"] not in ("calibration", "verification"): raise ValueError("Unknown data role")
    if row["status"] not in ("ok", "unavailable", "rejected"): raise ValueError("Unknown observation status")
    if str(row["synthetic"]) not in ("0", "1"): raise ValueError("synthetic must be 0 or 1")
    row["synthetic"] = str(row["synthetic"]) == "1" or row["participant_id"].startswith("SYNTHETIC")
    row["reference_m"] = finite(row["reference_m"])
    row["reference_bound_m"] = finite(row["reference_bound_m"])
    if not 0.2 <= row["reference_m"] <= 3:
        raise ValueError("Reference distance must be within the app's 0.20–3.00 m research range")
    if not 0 < row["reference_bound_m"] < row["reference_m"]:
        raise ValueError("Reference measurement needs a positive uncertainty bound")
    repeat = finite(row["repeat_index"])
    if repeat < 0 or int(repeat) != repeat: raise ValueError("repeat_index must be a non-negative integer")
    row["repeat_index"] = int(repeat)
    if row["status"] == "ok":
        row["observed_m"] = finite(row["observed_m"])
        row["observed_bound_m"] = finite(row["observed_bound_m"])
        if not 0.2 <= row["observed_m"] <= 3 or not 0 < row["observed_bound_m"] < row["observed_m"]:
            raise ValueError("Valid app reading and a positive reported uncertainty are required")
    elif str(row["observed_m"]).strip() or str(row["observed_bound_m"]).strip():
        raise ValueError("Unavailable/rejected readings must remain blank, not be replaced by guessed values")
    return row

def load_rows(path):
    if path is None: return []
    with Path(path).open(newline="", encoding="utf-8-sig") as stream:
        reader = csv.DictReader(stream)
        if not set(FIELDS).issubset(reader.fieldnames or []): raise ValueError("Missing distance CSV columns")
        return list(reader)

def analyze(rows):
    rows = [normalize(row) for row in rows]
    ids = [row["observation_id"] for row in rows]
    if len(ids) != len(set(ids)): raise ValueError("Duplicate observation_id")
    unique = [(r["device"],r["source"],r["condition"],r["participant_id"],r["calibration_id"],r["role"],r["reference_m"],r["repeat_index"]) for r in rows]
    if len(unique) != len(set(unique)): raise ValueError("Duplicate repeated observation")
    groups = defaultdict(list)
    for row in rows: groups[(row["device"], row["source"], row["condition"])].append(row)
    reports = []
    for (device,source,condition), items in sorted(groups.items()):
        calibration_points = defaultdict(list)
        for row in items:
            if row["role"] == "calibration" and row["status"] == "ok":
                calibration_points[(row["participant_id"],row["calibration_id"])].append(row["reference_m"])
        verification = [r for r in items if r["role"] == "verification"]
        # Primary accuracy uses verification positions not used to create that individual's calibration.
        held_out = [r for r in verification if not any(abs(r["reference_m"]-d) < .01 for d in calibration_points[(r["participant_id"],r["calibration_id"])])]
        ok = [r for r in held_out if r["status"] == "ok"]
        errors, detailed, reference_errors, bound_coverage = [], [], [], []
        for r in ok:
            reference, observed = r["reference_m"],r["observed_m"]
            error = 1/observed-1/reference
            low,high = reference-r["reference_bound_m"],reference+r["reference_bound_m"]
            worst_error = max(abs(1/observed-1/low),abs(1/observed-1/high))
            reference_error = max(abs(1/low-1/reference),abs(1/high-1/reference))
            errors.append(error); reference_errors.append(reference_error)
            covered = abs(observed-reference) <= r["observed_bound_m"]+r["reference_bound_m"]
            bound_coverage.append(covered)
            detailed.append({"observation_id":r["observation_id"],"participant_id":r["participant_id"],
                "reference_m":reference,"observed_m":observed,"error_m":observed-reference,
                "vergence_error_D":error,"worst_case_vergence_error_D":worst_error,
                "reference_bound_vergence_D":reference_error,"reported_distance_bound_compatible":covered})
        sessions = defaultdict(list)
        for r in held_out: sessions[(r["participant_id"],r["calibration_id"])].append(r)
        repeat_ranges = []
        session_coverage = []
        for key, observations in sessions.items():
            positions = defaultdict(list)
            for row in observations: positions[row["reference_m"]].append(row)
            complete_positions = 0
            for position, readings in positions.items():
                valid = [r for r in readings if r["status"] == "ok"]
                if len(valid) >= 3:
                    complete_positions += 1
                    powers = [1/r["observed_m"] for r in valid]
                    repeat_ranges.append(max(powers)-min(powers))
            session_coverage.append({"participant_id":key[0],"calibration_id":key[1],"positions_with_three_valid_repeats":complete_positions})
        completion = len(ok)/len(held_out) if held_out else None
        worst_errors = [r["worst_case_vergence_error_D"] for r in detailed]
        synthetic = any(r["synthetic"] for r in items)
        camera_calibration_valid = source != "calibratedCamera" or bool(sessions) and all(
            len(set(calibration_points[key])) >= 2 and max(calibration_points[key])-min(calibration_points[key]) >= .15
            for key in sessions)
        camera_interval_valid = source != "calibratedCamera" or camera_calibration_valid and all(
            min(calibration_points[(r["participant_id"],r["calibration_id"])]) <= r["reference_m"] <=
            max(calibration_points[(r["participant_id"],r["calibration_id"])]) for r in held_out)
        gates = {
            "real_measurements_only":bool(ok) and not synthetic,
            "at_least_three_participants":len({r["participant_id"] for r in held_out}) >= 3,
            "at_least_three_independent_calibrations":len(sessions) >= 3,
            "five_held_out_positions_three_repeats_per_calibration":bool(session_coverage) and all(r["positions_with_three_valid_repeats"]>=5 for r in session_coverage),
            "reference_error_bound_at_most_0_05D":bool(reference_errors) and max(reference_errors)<=.05,
            "at_least_90pct_available":completion is not None and completion>=.9,
            "at_least_95pct_within_0_10D_including_reference_bound":bool(worst_errors) and sum(e<=.1 for e in worst_errors)/len(worst_errors)>=.95,
            "no_error_over_0_25D_including_reference_bound":bool(worst_errors) and max(worst_errors)<=.25,
            "bias_within_0_05D":bool(errors) and abs(statistics.mean(errors))<=.05,
            "repeat_range_at_most_0_10D":bool(repeat_ranges) and max(repeat_ranges)<=.1,
            "camera_has_two_successful_reference_calibration_positions":camera_calibration_valid,
            "camera_verification_within_calibrated_interval":camera_interval_valid,
        }
        # Coverage of an estimated uncertainty is descriptive, not a statistical confidence claim.
        reports.append({"device":device,"source":source,"condition":condition,"rows":len(items),"verification_rows":len(verification),
            "failed_calibration_rows":sum(r["role"]=="calibration" and r["status"]!="ok" for r in items),
            "held_out_rows":len(held_out),"held_out_ok":len(ok),"held_out_unavailable_or_rejected":len(held_out)-len(ok),
            "calibration_position_verification_rows_excluded":len(verification)-len(held_out),
            "completion_rate":completion,"vergence_error":metrics(errors),
            "max_worst_case_vergence_error_D":max(worst_errors) if worst_errors else None,
            "max_repeat_range_D":max(repeat_ranges) if repeat_ranges else None,
            "reported_bound_compatibility_fraction":statistics.mean(bound_coverage) if bound_coverage else None,
            "synthetic_data_present":synthetic,"proposed_engineering_gates":gates,
            "proposed_targets_met":all(gates.values()),"session_coverage":session_coverage,"observations":detailed})
    return {"hardware_accuracy_established":False,"clinical_validation":"NOT_ESTABLISHED",
        "observation_count":len(rows),"device_source_reports":reports,
        "proposed_targets_met":bool(reports) and all(r["proposed_targets_met"] for r in reports),
        "limitations":["Targets are prospective engineering proposals, not a medical standard.",
            "The tool cannot verify that reference distances were physically measured independently.",
            "Passing these targets does not validate refraction or prescribing; unrepresented distances, people, poses and devices remain unverified."]}

def write_report(report,directory):
    directory.mkdir(parents=True,exist_ok=True)
    (directory/"distance-report.json").write_text(json.dumps(report,ensure_ascii=False,indent=2,allow_nan=False))
    rows = ""
    for r in report["device_source_reports"]:
        def number(value): return "—" if value is None else f"{value:.3f}"
        rows += f"<tr><td>{html.escape(r['device'])}</td><td>{html.escape(r['source'])}</td><td>{html.escape(r['condition'])}</td><td>{r['held_out_ok']}/{r['held_out_rows']}</td><td>{number(r['vergence_error'].get('bias_D'))}</td><td>{number(r['max_worst_case_vergence_error_D'])}</td><td>{'数值目标满足，仍需核实' if r['proposed_targets_met'] else '待验证／未达到目标'}</td></tr>"
    (directory/"distance-report.html").write_text(f'''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>视界测距核验</title>
<style>body{{font:16px system-ui;max-width:1100px;margin:40px auto;padding:20px;background:#f4f7fc;color:#182b49}}table{{border-collapse:collapse;background:white;width:100%}}th,td{{padding:12px;border-bottom:1px solid #ddd;text-align:left}}aside{{background:#fff4d6;padding:18px;border-radius:12px}}</style>
<h1>测距与实测距离对照</h1><aside>当前不构成硬件精度或临床有效性证明。需要实际、独立测量的参考距离；模拟数据、校准点和无法读数的情况不能充当成功验证。</aside>
<p>共{report['observation_count']}条记录。误差D表示距离误差引入的光焦度差，1D相当于通常所说的100度。</p>
<table><tr><th>设备</th><th>方式</th><th>条件</th><th>有效／验证记录</th><th>平均偏差D</th><th>最坏误差D（含参考误差）</th><th>工程目标</th></tr>{rows}</table>
<p>完整距离覆盖、失败记录数、重复性与逐条误差见 distance-report.json。数值目标通过仍不代表准确验光或可配镜。</p></html>''')

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("csv",nargs="?",type=Path)
    p.add_argument("--template",type=Path)
    p.add_argument("--out",type=Path,default=Path("Build/distance-validation"))
    a=p.parse_args()
    try:
        if a.template:
            a.template.parent.mkdir(parents=True,exist_ok=True)
            with a.template.open("w",newline="") as stream: csv.writer(stream).writerow(FIELDS)
            return
        report=analyze(load_rows(a.csv)); write_report(report,a.out)
        print(json.dumps({"observations":report["observation_count"],"proposed_targets_met":report["proposed_targets_met"],"hardware_accuracy_established":False}))
        print(a.out/"distance-report.html")
    except (ValueError,KeyError,TypeError,OSError) as e: p.exit(2,"Distance analysis refused: "+str(e)+"\n")

if __name__ == "__main__": main()
