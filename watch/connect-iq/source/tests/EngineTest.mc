import Toybox.Lang;
import Toybox.Test;

// ---- MatchConfig / presets ----

(:test)
function test_presets_values(logger as Logger) as Boolean {
    var c11 = MatchPresets.get(0);
    Test.assertEqualMessage(11, c11.mTargetScore, "11 pts target");
    Test.assertEqualMessage(0, c11.mCap, "11 pts sans plafond");
    var c15 = MatchPresets.get(1);
    Test.assertEqualMessage(15, c15.mTargetScore, "15 pts target");
    Test.assertEqualMessage(21, c15.mCap, "15 pts cap 21");
    var c21 = MatchPresets.get(2);
    Test.assertEqualMessage(21, c21.mTargetScore, "21 pts target");
    Test.assertEqualMessage(30, c21.mCap, "21 pts cap 30");
    Test.assertEqualMessage(3, MatchPresets.count(), "3 presets");
    Test.assertEqualMessage(2, c21.mWinBy, "winBy 2");
    Test.assertEqualMessage(2, c21.mSetsToWin, "setsToWin 2");
    return true;
}

// ---- Rules.isSetOver (spec §4.2) ----

(:test)
function test_rules_21_points(logger as Logger) as Boolean {
    var c = MatchPresets.get(2);
    Test.assertEqualMessage(false, Rules.isSetOver(c, 20, 19), "20-19 non fini");
    Test.assertEqualMessage(false, Rules.isSetOver(c, 20, 20), "20-20 non fini");
    Test.assertEqualMessage(false, Rules.isSetOver(c, 21, 20), "21-20 non fini (deuce)");
    Test.assertEqualMessage(true, Rules.isSetOver(c, 21, 19), "21-19 fini");
    Test.assertEqualMessage(false, Rules.isSetOver(c, 29, 29), "29-29 non fini");
    Test.assertEqualMessage(true, Rules.isSetOver(c, 30, 29), "30-29 fini (cap)");
    Test.assertEqualMessage(true, Rules.isSetOver(c, 19, 21), "19-21 fini (adversaire)");
    return true;
}

(:test)
function test_rules_15_points(logger as Logger) as Boolean {
    var c = MatchPresets.get(1);
    Test.assertEqualMessage(false, Rules.isSetOver(c, 14, 14), "14-14 non fini");
    Test.assertEqualMessage(false, Rules.isSetOver(c, 15, 14), "15-14 non fini (deuce)");
    Test.assertEqualMessage(true, Rules.isSetOver(c, 15, 13), "15-13 fini");
    Test.assertEqualMessage(false, Rules.isSetOver(c, 20, 20), "20-20 non fini");
    Test.assertEqualMessage(true, Rules.isSetOver(c, 21, 20), "21-20 fini (cap 21)");
    return true;
}

(:test)
function test_rules_11_points(logger as Logger) as Boolean {
    var c = MatchPresets.get(0);
    Test.assertEqualMessage(false, Rules.isSetOver(c, 10, 10), "10-10 non fini");
    Test.assertEqualMessage(false, Rules.isSetOver(c, 11, 10), "11-10 non fini (deuce)");
    Test.assertEqualMessage(true, Rules.isSetOver(c, 11, 9), "11-9 fini");
    Test.assertEqualMessage(false, Rules.isSetOver(c, 15, 14), "15-14 non fini (sans cap)");
    Test.assertEqualMessage(true, Rules.isSetOver(c, 16, 14), "16-14 fini (sans cap, ecart 2)");
    return true;
}
