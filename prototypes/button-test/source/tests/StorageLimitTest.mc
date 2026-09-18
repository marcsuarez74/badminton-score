import Toybox.Lang;
import Toybox.Test;
using Toybox.Application.Storage;
using Toybox.System;

// Roundtrip basique (prérequis Phase 3)
(:test)
function test_set_get_roundtrip(logger as Logger) as Boolean {
    var key = "bt_roundtrip";
    var data = {"me" => 12, "opponent" => 8, "label" => "score"};
    Storage.setValue(key, data);
    var read = Storage.getValue(key) as Dictionary;
    Storage.deleteValue(key);
    Test.assertEqualMessage(12, read.get("me"), "roundtrip me");
    Test.assertEqualMessage(8, read.get("opponent"), "roundtrip opponent");
    Test.assertEqualMessage("score", read.get("label"), "roundtrip label");
    return true;
}

// U5a : la limite documentée « 8 Ko par valeur » est-elle réelle ?
(:test)
function test_single_value_at_least_8k(logger as Logger) as Boolean {
    var key = "bt_single_8k";
    var stored = false;
    try {
        Storage.setValue(key, repeatString("x", 8192));
        stored = true;
    } catch (e) {
        System.println("single 8K store failed: " + e.getErrorMessage());
    }
    if (stored) {
        var check = Storage.getValue(key);
        Storage.deleteValue(key);
        Test.assertEqualMessage(8192, check.length(), "8K value stored intact");
    }
    return stored;
}

// U5b : la limite documentée « 128 Ko au total » est-elle réelle ?
(:test)
function test_total_capacity_at_least_128k(logger as Logger) as Boolean {
    for (var j = 0; j < 160; j += 1) {
        Storage.deleteValue("bt_total_" + j);
    }
    var stored = 0;
    for (var i = 0; i < 160; i += 1) {
        try {
            Storage.setValue("bt_total_" + i, repeatString("y", 1024));
            stored += 1;
        } catch (e) {
            System.println("total probe stopped at " + stored + " Ko");
            break;
        }
    }
    System.println("[probe-storage] total stored = " + stored + " Ko (cible >= 128)");
    for (var j = 0; j < stored; j += 1) {
        Storage.deleteValue("bt_total_" + j);
    }
    return stored >= 128;
}

// Sérialisation compacte (préfiguration spec §7.2 : tableaux positionnels)
(:test)
function test_compact_array_roundtrip(logger as Logger) as Boolean {
    var key = "bt_compact";
    // [sequence, typeCode, set, scoreMe, scoreOpp]
    var event = [7, 0, 2, 11, 8];
    Storage.setValue(key, event);
    var read = Storage.getValue(key);
    Storage.deleteValue(key);
    Test.assertEqualMessage(7, read[0], "compact sequence");
    Test.assertEqualMessage(0, read[1], "compact typeCode");
    Test.assertEqualMessage(2, read[2], "compact set");
    Test.assertEqualMessage(11, read[3], "compact scoreMe");
    Test.assertEqualMessage(8, read[4], "compact scoreOpp");
    return true;
}

function repeatString(c as String, n as Number) as String {
    var out = "";
    for (var i = 0; i < n; i += 1) {
        out += c;
    }
    return out;
}
