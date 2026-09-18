using Toybox.Application;
using Toybox.System;

class ButtonTestApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() {
        var view = new ButtonTestView();
        return [view, new ButtonTestDelegate(view)];
    }

    function onStart(state) {
        System.println("=== ButtonTest onStart ===");
        DeviceProbe.run();
    }

    function onStop(state) {
        System.println("=== ButtonTest onStop ===");
    }
}
