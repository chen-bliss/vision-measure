import unittest
import copy
from validate_study import vector, prescription, axial_error, metrics, analyze, rate_ci, display_key

def fixtures(n=1):
    sessions, refs = [], {}
    for i in range(n):
        p = f"SYNTHETIC_{i}"
        sid = f"synthetic-session-{i}"
        m,j0,j45 = vector(-2,-1,179)
        sessions.append(dict(id=sid,participantID=p,eye="右眼",schemaVersion=1,
            startedAt="2026-10-26T01:00:00Z",algorithmVersion="test",device="SIMULATED",
            appVersion="0.2.0",displayContext=dict(displayID="test",nativeWidthPixels=1200,nativeHeightPixels=2100,widthPoints=400,heightPoints=700,scale=3),
            screenPointsPerMillimeter=4,gapArcMinutes=1,thresholds=[{}]*12,
            trials=[{"distance":{"source":"manual"}}]*200,
            estimate={"clinicalValidation":"UNVALIDATED_RESEARCH_ONLY","vector":dict(m=m,j0=j0,j45=j45)}))
        refs[sid]=dict(session_id=sid,participant_id=p,eye="R",ref_sphere="-2",ref_cylinder="-1",ref_axis="179",
                       reference_method="subjective",examiner_masked="1",same_day="1",cohort="validation",synthetic="1")
    return sessions,refs

class ValidationTests(unittest.TestCase):
    def test_transposition_and_axis_wrap(self):
        self.assertEqual(axial_error(179,1),2)
        a,b = vector(-2,-1,20), vector(-3,1,110)
        for x,y in zip(a,b): self.assertAlmostEqual(x,y)
        s,c,a = prescription(vector(-2,-1,179))
        self.assertAlmostEqual(s,-2); self.assertAlmostEqual(c,-1); self.assertAlmostEqual(a,179)
    def test_bias_loa_and_absolute_error(self):
        m = metrics([-1,0,1])
        self.assertEqual(m["bias_D"],0)
        self.assertAlmostEqual(m["mae_D"],2/3)
        self.assertEqual(m["loa95_D"],[-1.96,1.96])
    def test_empty_never_validates(self):
        r = analyze([],{})
        self.assertFalse(r["numerical_targets_met"])
        self.assertEqual(r["clinical_validation"],"NOT_ESTABLISHED")
    def test_synthetic_never_satisfies_targets(self):
        s,r = fixtures(50)
        report = analyze(s,r)
        self.assertFalse(report["numerical_targets_met"])
        self.assertFalse(report["proposed_engineering_gates"]["real_data_only"])
        self.assertEqual(report["metrics"]["M"]["mae_D"],0)
    def test_mismatched_patient_rejected(self):
        s,r = fixtures(); r[s[0]["id"]]["participant_id"]="OTHER"
        with self.assertRaises(ValueError): analyze(s,r)
    def test_training_leakage_rejected(self):
        s,r = fixtures(); extra = copy.deepcopy(next(iter(r.values())))
        extra["cohort"]="development"; r["extra"]=extra
        with self.assertRaises(ValueError): analyze(s,r)
    def test_missing_raw_data_excluded(self):
        s,r = fixtures(); s[0]["trials"]=[]
        report = analyze(s,r)
        self.assertEqual(report["independent_participants"],0)
        self.assertEqual(report["exclusions"]["incomplete_raw_record"],1)
    def test_one_eye_and_earliest_session_selection(self):
        s,r = fixtures()
        left = copy.deepcopy(s[0]); left["id"]="left"; left["eye"]="左眼"
        later = copy.deepcopy(s[0]); later["id"]="later"; later["startedAt"]="2026-10-26T02:00:00Z"
        s += [left,later]
        for item in s[1:]:
            ref = copy.deepcopy(r[s[0]["id"]]); ref["session_id"]=item["id"]; ref["eye"]="L" if item["id"]=="left" else "R"; r[item["id"]]=ref
        report = analyze(s,r)
        self.assertEqual(report["independent_participants"],1)
        self.assertEqual(report["paired_rows"][0]["session_id"],s[0]["id"])
        self.assertEqual(report["repeatability"]["n_participants"],1)
    def test_unmasked_reference_excluded(self):
        s,r = fixtures(); r[s[0]["id"]]["examiner_masked"]="0"
        self.assertEqual(analyze(s,r)["independent_participants"],0)
    def test_single_sample_no_fake_loa(self):
        self.assertIsNone(metrics([0])["loa95_D"])
    def test_nonfinite_rejected(self):
        with self.assertRaises(ValueError): vector("nan",0,0)
    def test_all_success_still_has_uncertain_population_rate(self):
        ci = rate_ci([0]*50)
        self.assertAlmostEqual(ci[0],0.9286524,places=6)
        self.assertAlmostEqual(ci[1],1)
        self.assertIsNone(rate_ci([]))
    def test_session_synthetic_flag_cannot_be_overridden_by_csv(self):
        s,r = fixtures(); s[0]["sessionKind"]="SYNTHETIC_MODEL"
        r[s[0]["id"]]["synthetic"]="0"
        self.assertTrue(analyze(s,r)["synthetic_data_present"])
    def test_different_panels_do_not_count_as_same_screen_repeats(self):
        s,r=fixtures()
        other=copy.deepcopy(s[0]); other["id"]="inner"; other["startedAt"]="2026-10-26T02:00:00Z"
        other["displayContext"]["nativeWidthPixels"]=2100
        ref=copy.deepcopy(r[s[0]["id"]]); ref["session_id"]="inner"
        r["inner"]=ref; s.append(other)
        report=analyze(s,r)
        self.assertEqual(report["repeatability"]["n_participants"],0)
    def test_invalid_display_geometry_refused_and_legacy_marked_unknown(self):
        s,r=fixtures(); s[0]["displayContext"]["scale"]=0
        with self.assertRaises(ValueError): analyze(s,r)
        del s[0]["displayContext"]
        self.assertFalse(analyze(s,r)["proposed_engineering_gates"]["display_context_recorded"])
    def test_new_display_policy_ignores_gravity_but_keeps_interface_axis(self):
        sessions,_=fixtures(); a=sessions[0]
        a["displayContext"].update(calibrationPolicy="geometry_interface_axis_v2",interfaceOrientation=1,physicalOrientation=1)
        b=copy.deepcopy(a); b["displayContext"]["physicalOrientation"]=5
        self.assertEqual(display_key(a),display_key(b))
        b["displayContext"]["interfaceOrientation"]=3
        self.assertNotEqual(display_key(a),display_key(b))
    def test_legacy_pose_grouping_retained_and_bad_interface_rejected(self):
        sessions,_=fixtures(); a=sessions[0]; b=copy.deepcopy(a)
        a["displayContext"]["physicalOrientation"]=1; b["displayContext"]["physicalOrientation"]=5
        self.assertNotEqual(display_key(a),display_key(b))
        a["displayContext"].update(calibrationPolicy="geometry_interface_axis_v2",interfaceOrientation=8)
        with self.assertRaises(ValueError): display_key(a)

if __name__ == "__main__": unittest.main()
