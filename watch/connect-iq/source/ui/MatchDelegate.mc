import Toybox.Lang;
using Toybox.WatchUi;

// BehaviorDelegate (spec §3.1) : traduit les boutons en appels de la vue.
// Aucune logique ici. onKeyPressed/onKeyReleased non utilisés (§3.2).
class MatchDelegate extends WatchUi.BehaviorDelegate {

    var mView;

    function initialize(view) {
        BehaviorDelegate.initialize();
        mView = view;
    }

    function onSelect() as Boolean {
        return mView.onSelect();
    }

    function onBack() as Boolean {
        return mView.onBack();
    }

    function onPreviousPage() as Boolean {
        return mView.onUp();
    }

    function onNextPage() as Boolean {
        return mView.onDown();
    }

    function onMenu() as Boolean {
        return mView.onMenuButton();
    }
}
