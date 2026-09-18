using Toybox.Application;
using Toybox.WatchUi;

// Persistance onStart/onStop : Phase 3 (spec §16). Phase 1 = session volatile.
class BadmintonApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() {
        var view = new MatchView();
        return [view, new MatchDelegate(view)];
    }
}
