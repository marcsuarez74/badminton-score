import Toybox.Lang;
using Toybox.WatchUi;

class ButtonTestDelegate extends WatchUi.BehaviorDelegate {

    var mView;

    function initialize(view) {
        BehaviorDelegate.initialize();
        mView = view;
    }

    function onSelect() as Boolean {
        if (mView.mMode == 1) { return mView.menuSelect(); }
        mView.record("START");
        return true;
    }

    function onBack() as Boolean {
        if (mView.mMode == 1) { mView.closeMenu(); return true; }
        mView.record("BACK");
        return true;
    }

    function onPreviousPage() as Boolean {
        if (mView.mMode == 1) { return mView.menuUp(); }
        mView.record("UP");
        return true;
    }

    function onNextPage() as Boolean {
        if (mView.mMode == 1) { return mView.menuDown(); }
        mView.record("DOWN");
        return true;
    }

    function onMenu() as Boolean {
        if (mView.mMode == 1) { return true; }
        mView.record("UP-LONG");
        mView.openMenu();
        return true;
    }
}
