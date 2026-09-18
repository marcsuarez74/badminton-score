using Toybox.Application;
import Toybox.Lang;
using Toybox.WatchUi;

// Persistance : sauvegarde à chaque mutation (MatchView.syncScreen) + filet
// onStop (§7.2). Reprise au lancement : MatchView.initialize (§5 Démarrage).
class BadmintonApp extends Application.AppBase {

    var mView = null;

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() {
        mView = new MatchView();
        return [mView, new MatchDelegate(mView)];
    }

    function onStop(state as Dictionary or Null) as Void {
        if (mView != null) {
            mView.persist();
        }
    }
}
