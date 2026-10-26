import unittest
from validate_distance import analyze

def row(**changes):
    r=dict(observation_id="O1",participant_id="SYNTHETIC_P1",device="SYNTHETIC_DEVICE",source="calibratedCamera",condition="frontal_stable",
        calibration_id="C1",role="verification",reference_m="0.5",reference_bound_m="0.001",
        observed_m="0.5",observed_bound_m="0.005",repeat_index="0",status="ok",synthetic="1")
    r.update(changes); return r

class DistanceValidationTests(unittest.TestCase):
    def test_short_distance_one_centimetre_can_exceed_twenty_degrees(self):
        result=analyze([row(reference_m="0.2",observed_m="0.21")])["device_source_reports"][0]
        self.assertAlmostEqual(result["vergence_error"]["mae_D"],5-1/.21)
        self.assertGreater(result["max_worst_case_vergence_error_D"],.25)
    def test_unavailable_rows_remain_in_denominator(self):
        result=analyze([row(),row(observation_id="O2",repeat_index="1",status="unavailable",observed_m="",observed_bound_m="")])["device_source_reports"][0]
        self.assertEqual(result["completion_rate"],.5)
        self.assertEqual(result["held_out_unavailable_or_rejected"],1)
    def test_calibration_positions_do_not_validate_themselves(self):
        result=analyze([row(role="calibration"),row(observation_id="O2")])["device_source_reports"][0]
        self.assertEqual(result["held_out_rows"],0)
        self.assertEqual(result["calibration_position_verification_rows_excluded"],1)
        self.assertFalse(result["proposed_targets_met"])
    def test_duplicates_and_guessed_failed_readings_rejected(self):
        with self.assertRaises(ValueError): analyze([row(),row()])
        with self.assertRaises(ValueError): analyze([row(status="unavailable")])
        with self.assertRaises(ValueError): analyze([row(),row(observation_id="OTHER")])
    def test_nonfinite_and_unknown_source_rejected(self):
        with self.assertRaises(ValueError): analyze([row(observed_m="nan")])
        with self.assertRaises(ValueError): analyze([row(source="imaginedDepth")])
        with self.assertRaises(ValueError): analyze([row(reference_bound_m="0")])
    def test_empty_does_not_establish_accuracy(self):
        report=analyze([])
        self.assertFalse(report["proposed_targets_met"])
        self.assertFalse(report["hardware_accuracy_established"])
    def test_independent_calibrations_and_positions_counted(self):
        data=[]
        for person in range(3):
            for position in [.4,.6,1,1.5,2.5]:
                for repeat in range(3):
                    data.append(row(observation_id=f"{person}-{position}-{repeat}",participant_id=f"SYNTHETIC_{person}",
                        calibration_id=f"C{person}",reference_m=str(position),observed_m=str(position),repeat_index=str(repeat)))
        result=analyze(data)["device_source_reports"][0]
        gates=result["proposed_engineering_gates"]
        self.assertTrue(gates["five_held_out_positions_three_repeats_per_calibration"])
        self.assertTrue(gates["at_least_three_participants"])
        self.assertFalse(gates["real_measurements_only"])
        self.assertFalse(result["proposed_targets_met"])
    def test_synthetic_marker_cannot_be_cleared_by_flag(self):
        result=analyze([row(synthetic="0")])["device_source_reports"][0]
        self.assertTrue(result["synthetic_data_present"])
    def test_reference_uncertainty_contributes_to_error_bound(self):
        result=analyze([row(reference_m="0.2",observed_m="0.2",reference_bound_m="0.01")])["device_source_reports"][0]
        self.assertEqual(result["vergence_error"]["mae_D"],0)
        self.assertGreater(result["max_worst_case_vergence_error_D"],.25)
        self.assertFalse(result["proposed_engineering_gates"]["reference_error_bound_at_most_0_05D"])
    def test_camera_values_outside_personal_calibration_range_are_not_accepted(self):
        rows=[row(role="calibration",reference_m="0.4",observed_m="0.4"),
              row(observation_id="C2",role="calibration",reference_m="1.0",observed_m="1.0"),
              row(observation_id="V1",reference_m="2.0",observed_m="2.0")]
        gates=analyze(rows)["device_source_reports"][0]["proposed_engineering_gates"]
        self.assertTrue(gates["camera_has_two_successful_reference_calibration_positions"])
        self.assertFalse(gates["camera_verification_within_calibrated_interval"])

if __name__ == "__main__": unittest.main()
