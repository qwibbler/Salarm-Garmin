import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;

//! Connection listener for BLE transmissions to the Android companion app
class SalarmCommListener extends Communications.ConnectionListener {

    private var _model as SalarmModel;

    //! Constructor
    //! @param model The data model to notify of transmit events
    public function initialize(model as SalarmModel) {
        Communications.ConnectionListener.initialize();
        _model = model;
    }

    //! Called when transmission completes successfully
    public function onComplete() as Void {
        System.println("[SalarmCommListener] Transmit to phone completed.");
    }

    //! Called when transmission fails
    public function onError() as Void {
        System.println("[SalarmCommListener] Transmit to phone failed.");
        _model.onTransmitError();
    }
}
