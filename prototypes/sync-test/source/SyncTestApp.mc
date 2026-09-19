import Toybox.Application;
import Toybox.Communications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// POC Phase 4a : 1 bouton = 1 POST vers l'Edge Function sync. Le code
// d'affichage du responseCode est la sortie du test (cf. spec sync §15).
const BACKEND_URL = "https://bzdbnptnubkkagmmxhyi.supabase.co/functions/v1/sync";

class SyncTestDelegate extends WatchUi.BehaviorDelegate {
    hidden var mResult = "SELECT = POST";

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onSelect() as Boolean {
        _send();
        return true;
    }

    hidden function _send() as Void {
        var body = {
            "deviceId" => "poc-device",
            "config" => { "targetScore" => 11, "winBy" => 2, "cap" => 0, "setsToWin" => 2 },
            "snapshot" => { "status" => "active", "currentSet" => 1, "scoreMe" => 1,
                            "scoreOpp" => 0, "setsMe" => 0, "setsOpp" => 0, "lastSequence" => 1 },
            "events" => [ { "type" => 0, "arg" => 0, "sequence" => 1, "ts" => 0, "prevMe" => 0, "prevOpp" => 0 } ]
        };
        var options = {
            "method" => Communications.HTTP_REQUEST_METHOD_POST,
            "headers" => { "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON },
            "responseType" => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        mResult = "envoi...";
        Communications.makeWebRequest(BACKEND_URL + "/matches/POCTEST1/events", body, options, method(:_onResponse));
        WatchUi.requestUpdate();
    }

    hidden function _onResponse(responseCode as Number, data as Dictionary or String or Null) as Void {
        if (responseCode == 200 && data != null && data instanceof Dictionary) {
            mResult = "HTTP 200 las=" + data["lastAcceptedSequence"];
        } else {
            mResult = "ERR " + responseCode;
        }
        System.println("[sync-test] " + mResult);
        WatchUi.requestUpdate();
    }

    // BACK = sortie (prototype).
    function onBack() as Boolean {
        System.exit();
    }
}

class SyncTestView extends WatchUi.View {
    hidden var mDelegate;

    function initialize() {
        View.initialize();
        mDelegate = new SyncTestDelegate();
    }

    function getDelegate() as WatchUi.InputDelegate or Null {
        return mDelegate;
    }

    function onUpdate(dc as Dc) as Void {
        dc.clear();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawText(dc.getWidth() / 2, dc.getHeight() / 4, Graphics.FONT_MEDIUM, "SYNC POC", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(dc.getWidth() / 2, dc.getHeight() / 2, Graphics.FONT_SMALL, mDelegate.mResult, Graphics.TEXT_JUSTIFY_CENTER);
    }
}

class SyncTestApp extends Application.AppBase {
    function initialize() {
        AppBase.initialize();
    }
    function getInitialView() {
        var view = new SyncTestView();
        return [view, view.getDelegate()];
    }
}

function getApp() as Application.AppBase {
    return new SyncTestApp();
}
