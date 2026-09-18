using Toybox.System;

module DeviceProbe {

    function run() as Void {
        var s = System.getDeviceSettings();
        System.println("[probe] screenWidth=" + s.screenWidth);
        System.println("[probe] screenHeight=" + s.screenHeight);
        System.println("[probe] screenShape=" + s.screenShape);
        if (s has :isTouchScreen) {
            System.println("[probe] isTouchScreen=" + s.isTouchScreen);
        } else {
            System.println("[probe] isTouchScreen ABSENT");
        }
        if (s has :isTouch) {
            System.println("[probe] isTouch=" + s.isTouch);
        } else {
            System.println("[probe] isTouch ABSENT");
        }
    }
}
