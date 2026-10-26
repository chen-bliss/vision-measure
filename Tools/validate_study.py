#!/usr/bin/env python3
"""Analyze exported sessions against masked clinical refraction. Python 3.10+, standard library only.

No dataset or passing numerical target constitutes clinical validation by itself.
"""
from __future__ import annotations
import argparse
import csv
import html
import json
import math
import statistics
from collections import Counter, defaultdict
from pathlib import Path

FIELDS = ["session_id", "participant_id", "eye", "ref_sphere", "ref_cylinder", "ref_axis",
          "reference_method", "examiner_masked", "same_day", "cohort", "synthetic"]
EYES = {"右眼": "R", "左眼": "L", "R": "R", "L": "L", "OD": "R", "OS": "L"}

def finite(value):
    x = float(value)
    if not math.isfinite(x): raise ValueError("Non-finite numeric input")
    return x

def vector(sphere, cylinder, axis):
    sphere, cylinder, axis = map(finite, (sphere, cylinder, axis))
    if not -30 <= sphere <= 20 or not -15 <= cylinder <= 15 or not 0 <= axis <= 180:
        raise ValueError("Reference refraction out of allowed data-entry range")
    return (sphere + cylinder/2, -cylinder/2*math.cos(math.radians(2*axis)),
            -cylinder/2*math.sin(math.radians(2*axis)))

def prescription(v):
    m, j0, j45 = map(finite, v)
    return m+math.hypot(j0,j45), -2*math.hypot(j0,j45), math.degrees(math.atan2(j45,j0))/2 % 180

def axial_error(a, b):
    d = abs(a-b) % 180
    return min(d, 180-d)

def display_key(session):
    context=session.get("displayContext")
    if context is None: return "UNKNOWN_DISPLAY"
    if not isinstance(context,dict): raise ValueError("Malformed display context")
    values=[finite(context[k]) for k in ("nativeWidthPixels","nativeHeightPixels","widthPoints","heightPoints","scale")]
    if any(x<=0 for x in values): raise ValueError("Invalid display geometry")
    pose=context.get("physicalOrientation") or 0
    if not isinstance(pose,int): raise ValueError("Invalid physical posture metadata")
    geometry="x".join(f"{x:.3f}" for x in values)
    if context.get("calibrationPolicy") == "geometry_interface_axis_v2":
        orientation=context.get("interfaceOrientation") or 0
        if not isinstance(orientation,int) or orientation not in range(5): raise ValueError("Invalid interface orientation")
        axis="portrait" if orientation in (1,2) else "landscape" if orientation in (3,4) else "unknown"
        return geometry+f":ui_axis={axis}"
    return geometry+f":pose={pose}"

def metrics(errors):
    if not errors: return {"n": 0}
    n = len(errors)
    mean = statistics.mean(errors)
    sd = statistics.stdev(errors) if n > 1 else None
    return {"n": n, "bias_D": mean, "mae_D": statistics.mean(map(abs, errors)),
            "sd_D": sd, "loa95_D": [mean-1.96*sd, mean+1.96*sd] if sd is not None else None,
            "within_0_25D": sum(abs(e) <= .25 for e in errors)/n,
            "within_0_50D": sum(abs(e) <= .5 for e in errors)/n,
            "small_sample_warning": n < 30}

def rate_ci(errors):
    """Wilson score interval, including all-success/all-failure boundary cases."""
    if not errors: return None
    n, z = len(errors), 1.959963984540054
    p = sum(abs(e) <= .5 for e in errors)/n
    denominator = 1+z*z/n
    center = (p+z*z/(2*n))/denominator
    margin = z*math.sqrt(p*(1-p)/n+z*z/(4*n*n))/denominator
    return [max(0,center-margin),min(1,center+margin)]

def load_sessions(paths):
    sessions, seen = [], set()
    for path in paths:
        data = json.loads(Path(path).read_text())
        for item in data if isinstance(data,list) else [data]:
            if not isinstance(item,dict) or item.get("schemaVersion") != 1:
                raise ValueError(f"{path}: unsupported session schema")
            if not item.get("id") or item["id"] in seen:
                raise ValueError(f"{path}: missing or duplicate session id")
            if item.get("eye") not in EYES or not item.get("participantID"):
                raise ValueError(f"{path}: missing participant or eye")
            seen.add(item["id"]); sessions.append(item)
    return sessions

def load_references(path):
    if path is None: return {}
    result = {}
    with Path(path).open(newline="") as stream:
        reader = csv.DictReader(stream)
        if not set(FIELDS).issubset(reader.fieldnames or []):
            raise ValueError("Reference CSV missing required columns: "+", ".join(FIELDS))
        for row in reader:
            sid = row["session_id"].strip()
            if not sid or sid in result: raise ValueError("Missing/duplicate reference session_id")
            if row["eye"] not in EYES: raise ValueError("Unknown eye in reference")
            for field in ("examiner_masked", "same_day", "synthetic"):
                if row[field] not in ("0","1"): raise ValueError(field+" must be 0 or 1")
            if row["cohort"] not in ("development", "validation"): raise ValueError("Unknown cohort")
            vector(row["ref_sphere"],row["ref_cylinder"],row["ref_axis"])
            result[sid] = row
    return result

def analyze(sessions, references):
    exclusions = Counter()
    paired, repeats = [], defaultdict(list)
    stop_reasons = Counter(s.get("stopReason") or "completed" for s in sessions)
    synthetic = any(s.get("sessionKind", "").startswith("SYNTHETIC") for s in sessions) or any(r["synthetic"] == "1" for r in references.values())
    development_subjects = {r["participant_id"] for r in references.values() if r["cohort"] == "development"}
    for s in sessions:
        estimate = s.get("estimate")
        if not estimate:
            exclusions["no_estimate"] += 1; continue
        if estimate.get("clinicalValidation") != "UNVALIDATED_RESEARCH_ONLY":
            raise ValueError("Unknown/altered validation status in session "+s["id"])
        v = estimate["vector"]
        app_v = tuple(finite(v[k]) for k in ("m","j0","j45"))
        if len(s.get("thresholds",[])) < 12 or len(s.get("trials",[])) < 200:
            exclusions["incomplete_raw_record"] += 1; continue
        r = references.get(s["id"])
        if r is None:
            exclusions["no_clinical_reference"] += 1; continue
        if r["participant_id"] != s["participantID"] or EYES[r["eye"]] != EYES[s["eye"]]:
            raise ValueError("Participant/eye mismatch for "+s["id"])
        synthetic |= r["synthetic"] == "1"
        if r["cohort"] != "validation": exclusions["development_cohort"] += 1; continue
        if s["participantID"] in development_subjects:
            raise ValueError("Development/validation participant leakage: "+s["participantID"])
        if r["reference_method"] != "subjective" or r["examiner_masked"] != "1" or r["same_day"] != "1":
            exclusions["reference_not_masked_same_day_subjective"] += 1; continue
        ref_v = vector(r["ref_sphere"],r["ref_cylinder"],r["ref_axis"])
        a, b = prescription(app_v), prescription(ref_v)
        row = {"participant_id": s["participantID"], "eye": EYES[s["eye"]], "session_id": s["id"],
               "started_at": s["startedAt"], "algorithm": s["algorithmVersion"], "device": s["device"],
               "display":display_key(s),"app_version":s.get("appVersion") or "UNKNOWN_BUILD",
               "sphere_error": a[0]-b[0], "cylinder_error": a[1]-b[1],
               "M_error": app_v[0]-ref_v[0], "J0_error": app_v[1]-ref_v[1], "J45_error": app_v[2]-ref_v[2],
               "axis_error": axial_error(a[2],b[2]) if abs(b[1]) >= .75 else None,
               "app_vector": app_v, "ref_vector": ref_v,
               "source": "+".join(sorted({t["distance"]["source"] for t in s["trials"]}))}
        repeats[(row["participant_id"],row["eye"],row["algorithm"],row["device"],row["source"],
                 s["screenPointsPerMillimeter"],s["gapArcMinutes"],row["display"],row["app_version"])].append(row)
        paired.append(row)
    # Use earliest session per eye, then right eye if both: never select the better result.
    first_per_eye = {}
    for row in sorted(paired,key=lambda x:(x["started_at"],x["session_id"])):
        first_per_eye.setdefault((row["participant_id"],row["eye"]),row)
    by_subject = defaultdict(dict)
    for (subject,eye), row in first_per_eye.items(): by_subject[subject][eye] = row
    independent = [eyes.get("R",eyes.get("L")) for _,eyes in sorted(by_subject.items())]
    summary = {name: metrics([r[key] for r in independent]) for name,key in
               [("sphere","sphere_error"),("cylinder","cylinder_error"),("M","M_error"),("J0","J0_error"),("J45","J45_error")]}
    for name,key in [("sphere","sphere_error"),("cylinder","cylinder_error"),("M","M_error")]:
        summary[name]["within_0_50D_Wilson95"] = rate_ci([r[key] for r in independent])
    axes = [r["axis_error"] for r in independent if r["axis_error"] is not None]
    axis = {"n":len(axes), "mean_absolute_error_degrees": statistics.mean(axes) if axes else None,
            "within_10_degrees": sum(e <= 10 for e in axes)/len(axes) if axes else None,
            "reference_cylinder_min_D": .75}
    repeat_rows = []
    for key, values in repeats.items():
        values.sort(key=lambda x:(x["started_at"],x["session_id"]))
        if len(values) >= 2:
            a,b = values[:2]
            if a["started_at"][:10] != b["started_at"][:10]: continue
            if max(abs(x-y) for x,y in zip(a["ref_vector"],b["ref_vector"])) > .01: continue
            repeat_rows.append({"participant_id":key[0],"eye":key[1], "M_difference":b["app_vector"][0]-a["app_vector"][0]})
    repeat_subjects = {}
    for row in sorted(repeat_rows,key=lambda x:(x["participant_id"],0 if x["eye"] == "R" else 1)):
        repeat_subjects.setdefault(row["participant_id"],row)
    diffs = [row["M_difference"] for row in repeat_subjects.values()]
    repeatability = {"n_participants":len(diffs),"M_repeatability_coefficient_D":1.96*statistics.stdev(diffs) if len(diffs)>1 else None,
                     "M_bias_D":statistics.mean(diffs) if diffs else None}
    strata = {}
    for field in ("device","source","algorithm","display","app_version"):
        groups = defaultdict(list)
        for row in independent: groups[row[field]].append(row["M_error"])
        strata[field] = {key:metrics(errors) for key,errors in groups.items()}
    # Proposed engineering targets, not a medical standard, and not a clinical approval.
    gates = {
        "real_data_only": not synthetic and bool(independent),
        "independent_participants_at_least_50": len(independent)>=50,
        "M_within_half_D_at_least_90pct": summary["M"].get("within_0_50D",0)>=.90,
        "sphere_within_half_D_at_least_90pct": summary["sphere"].get("within_0_50D",0)>=.90,
        "cylinder_within_half_D_at_least_90pct": summary["cylinder"].get("within_0_50D",0)>=.90,
        "M_95LoA_within_three_quarter_D": bool(summary["M"].get("loa95_D")) and max(map(abs,summary["M"]["loa95_D"]))<=.75,
        "axis_at_least_15_and_90pct_within_10deg": len(axes)>=15 and (axis["within_10_degrees"] or 0)>=.90,
        "repeat_at_least_30_and_coefficient_below_half_D": len(diffs)>=30 and repeatability["M_repeatability_coefficient_D"] is not None and repeatability["M_repeatability_coefficient_D"]<=.5,
        "each_device_stratum_at_least_20": bool(strata["device"]) and all(m["n"]>=20 for m in strata["device"].values()),
        "failure_rate_at_most_10pct": bool(sessions) and sum(not s.get("estimate") for s in sessions)/len(sessions)<=.1,
        "single_frozen_algorithm":len(strata["algorithm"])==1,
        "single_frozen_app_version":len(strata["app_version"])==1 and not any(k in ("UNKNOWN_BUILD","development") for k in strata["app_version"]),
        "display_context_recorded":bool(independent) and "UNKNOWN_DISPLAY" not in strata["display"],
        "each_display_stratum_at_least_20":bool(strata["display"]) and all(m["n"]>=20 for m in strata["display"].values()),
        "iphone_and_mac_represented":any(r["device"].startswith("iPhone") for r in independent) and any(r["device"].startswith("Mac") for r in independent),
        "all_shipped_distance_modes_represented":all(sum(mode in r["source"].split("+") for r in independent)>=20 for mode in ("manual","calibratedCamera","depth")),
    }
    return {"clinical_validation":"NOT_ESTABLISHED", "numerical_targets_met":all(gates.values()),
            "synthetic_data_present":synthetic, "session_count":len(sessions),"paired_sessions":len(paired),
            "independent_participants":len(independent),"sessions_without_estimate":sum(not s.get("estimate") for s in sessions),
            "exclusions":dict(exclusions),"stop_reasons":dict(stop_reasons), "metrics":summary,"axis":axis,
            "repeatability":repeatability,"strata":strata,"proposed_engineering_gates":gates,
            "selection_rule":"earliest session per eye; right eye preferred; one eye per participant",
            "limitations":["Targets are prospective proposals, not clinical or regulatory standards.",
                "CSV provenance, informed consent, masking and comprehensive enrollment require external audit.",
                "No evidence for unrepresented devices, populations or out-of-range refraction.",
                "Reference/fit numerical agreement does not establish safe spectacle prescribing."],
            "paired_rows":independent}

def write_report(report, directory):
    directory.mkdir(parents=True,exist_ok=True)
    (directory/"report.json").write_text(json.dumps(report,ensure_ascii=False,indent=2,allow_nan=False))
    def f(value): return "—" if value is None else f"{value:.3f}"
    rows = ""
    for k,v in report["metrics"].items():
        loa = v.get("loa95_D")
        limits = " 至 ".join(map(f,loa)) if loa else "—"
        ci = v.get("within_0_50D_Wilson95")
        rate = f"{100*v['within_0_50D']:.1f}%" if v["n"] else "—"
        if ci: rate += f" ({100*ci[0]:.1f}%–{100*ci[1]:.1f}%)"
        rows += f"<tr><td>{html.escape(k)}</td><td>{v['n']}</td><td>{f(v.get('bias_D'))}</td><td>{f(v.get('mae_D'))}</td><td>{limits}</td><td>{rate}</td></tr>"
    gates = "".join(f"<li>{'✓' if value else '待满足'} · {html.escape(key)}</li>" for key,value in report["proposed_engineering_gates"].items())
    title = "模拟数据报告 · 不能作为临床证据" if report["synthetic_data_present"] else "验光对照分析 · 尚未建立临床有效性"
    (directory/"report.html").write_text(f'''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>视界对照分析</title>
<style>body{{font:16px system-ui;max-width:1000px;margin:48px auto;padding:24px;background:#f4f7fc;color:#182b49}}table{{border-collapse:collapse;width:100%;background:white}}th,td{{padding:14px;border-bottom:1px solid #dde3ee;text-align:left}}h1{{color:#244eb4}}li{{margin:10px 0}}aside{{background:#fff4d6;padding:20px;border-radius:12px}}</style>
<h1>{title}</h1><aside>本工具计算统计指标。通过数值目标也不等于达到可配镜或可诊断水平，仍需真实数据、独立审查和适用范围验证。</aside>
<p>全部测试 {report['session_count']} 次 · 已配对测试 {report['paired_sessions']} 次 · 独立受试者 {report['independent_participants']} 人 · 无结果测试 {report['sessions_without_estimate']} 次</p>
<table><tr><th>分量</th><th>人数</th><th>平均偏差 D</th><th>平均绝对误差 D</th><th>95%一致性界限 D</th><th>±0.50D比例（95% Wilson区间）</th></tr>{rows}</table>
<h2>预先拟定的工程目标</h2><ul>{gates}</ul><p>当前临床验证状态：NOT_ESTABLISHED。完整数据、排除原因、轴位、重复性及机型分层见同目录 report.json。</p></html>''')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sessions",nargs="*")
    parser.add_argument("--references",type=Path)
    parser.add_argument("--out",type=Path,default=Path("Build/validation"))
    parser.add_argument("--template",type=Path)
    args = parser.parse_args()
    if args.template:
        args.template.parent.mkdir(parents=True,exist_ok=True)
        with args.template.open("w",newline="") as f: csv.writer(f).writerow(FIELDS)
        return
    try:
        report = analyze(load_sessions(args.sessions),load_references(args.references))
        write_report(report,args.out)
        print(json.dumps({k:report[k] for k in ("clinical_validation","session_count","independent_participants","numerical_targets_met")},ensure_ascii=False))
        print(args.out/"report.html")
    except (ValueError,KeyError,TypeError,OSError) as error:
        parser.exit(2,"Analysis refused: "+str(error)+"\n")

if __name__ == "__main__": main()
