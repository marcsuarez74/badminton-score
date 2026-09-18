using Toybox.Application;
import Toybox.Graphics;
using Toybox.WatchUi;

// Stub de squelette (Task 1) : fournit l'entry point exige par monkeyc.
// Remplace par la vraie app en Task 5 (getInitialView -> MatchView/MatchDelegate).
class BadmintonApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() {
        return [new StubView(), new StubDelegate()];
    }
}

class StubView extends WatchUi.View {

    function initialize() {
        View.initialize();
    }

    function onUpdate(dc as Dc) as Void {
    }
}

class StubDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }
}
