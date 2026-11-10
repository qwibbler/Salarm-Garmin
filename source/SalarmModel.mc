import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

//! Model and state machine for SalarmWatch
class SalarmModel {

    // Alarm states
    public enum AlarmState {
        STATE_IDLE,             // No active or upcoming alarm
        STATE_UPCOMING,         // Alarm scheduled in future
        STATE_RINGING,          // Active ringing alarm
        STATE_ACTION_PENDING,   // Snooze/Dismiss sent, awaiting phone confirmation
        STATE_ACTION_CONFIRMED, // Action confirmed by phone
        STATE_ACTION_FAILED     // Phone timed out or rejected action
    }

    // Pending action types
    public enum ActionType {
        ACTION_NONE,
        ACTION_SNOOZE,
        ACTION_DISMISS
    }

    // Alarm attributes
    private var _state as AlarmState = STATE_IDLE;
    private var _previousState as AlarmState = STATE_IDLE;
    private var _alarmId as String = "";
    private var _title as String = "Alarm";
    private var _triggerTime as Number = 0;       // Epoch seconds (UTC)
    private var _snoozeDuration as Number = 540;   // Default 9 minutes (seconds)
    private var _lastConfirmedTime as Number = 0;

    // Action tracking
    private var _pendingAction as ActionType = ACTION_NONE;
    private var _pendingRequestId as String = "";
    private var _statusText as String = "Waiting for phone";
    private var _timeoutTimer as Timer.Timer?;
    private const ACTION_TIMEOUT_MS as Number = 10000; // 10 seconds timeout

    // Reference to alert manager
    private var _alertManager as SalarmAlertManager?;

    //! Constructor
    public function initialize() {
        _timeoutTimer = new Timer.Timer();
    }

    //! Set reference to alert manager
    public function setAlertManager(mgr as SalarmAlertManager) as Void {
        _alertManager = mgr;
    }

    // -------------------------------------------------------------
    // Getters
    // -------------------------------------------------------------

    public function getState() as AlarmState {
        return _state;
    }

    public function getTitle() as String {
        return _title;
    }

    public function getTriggerTime() as Number {
        return _triggerTime;
    }

    public function getSnoozeDuration() as Number {
        return _snoozeDuration;
    }

    public function getAlarmId() as String {
        return _alarmId;
    }

    public function getPendingAction() as ActionType {
        return _pendingAction;
    }

    public function getStatusText() as String {
        return _statusText;
    }

    public function isPhoneConnected() as Boolean {
        var settings = System.getDeviceSettings();
        return (settings.phoneConnected != null && settings.phoneConnected);
    }

    // -------------------------------------------------------------
    // Message Processing & Validation
    // -------------------------------------------------------------

    //! Safely processes incoming data from phone app
    //! @param rawData Payload from PhoneAppMessage.data
    //! @return true if payload was recognized and handled
    public function processIncomingMessage(rawData as Object?) as Boolean {
        if (rawData == null) {
            System.println("[SalarmModel] Received null message data.");
            return false;
        }

        var dict = null;

        if (rawData instanceof Dictionary) {
            dict = rawData as Dictionary;
        } else if (rawData instanceof Array) {
            var arr = rawData as Array;
            if (arr.size() > 0 && arr[0] instanceof Dictionary) {
                dict = arr[0] as Dictionary;
            }
        }

        if (dict == null) {
            System.println("[SalarmModel] Unsupported message format: " + rawData.toString());
            return false;
        }

        System.println("[SalarmModel] Processing message: " + dict.toString());

        // Extract message type or default to ALARM_UPDATE
        var msgType = "";
        var rawType = dict.get("type");
        if (rawType != null) {
            msgType = rawType.toString();
        }

        // Handle Confirmation / Rejection
        if (msgType.equals("ACTION_CONFIRM")) {
            handleActionConfirm(dict);
            return true;
        } else if (msgType.equals("ACTION_REJECT")) {
            handleActionReject(dict);
            return true;
        } else if (msgType.equals("CLEAR")) {
            clearAlarm();
            return true;
        }

        // Handle Alarm state updates
        handleAlarmStateUpdate(dict);
        return true;
    }

    //! Handles state updates (upcoming, ringing, snoozed, dismissed, idle)
    private function handleAlarmStateUpdate(dict as Dictionary) as Void {
        // Extract Alarm ID safely
        var rawId = dict.get("id");
        if (rawId != null) {
            _alarmId = rawId.toString();
        }

        // Extract Title safely
        var rawTitle = dict.get("title");
        if (rawTitle != null) {
            var t = rawTitle.toString();
            if (t.length() > 0) {
                _title = t;
            }
        }

        // Extract Trigger Time safely
        var rawTrigger = dict.get("triggerTime");
        if (rawTrigger != null) {
            if (rawTrigger instanceof Number) {
                _triggerTime = rawTrigger as Number;
            } else if (rawTrigger instanceof Long) {
                _triggerTime = (rawTrigger as Long).toNumber();
            } else if (rawTrigger instanceof String) {
                try {
                    var parsed = (rawTrigger as String).toNumber();
                    if (parsed != null) {
                        _triggerTime = parsed;
                    }
                } catch (e) {
                    System.println("[SalarmModel] Invalid triggerTime string: " + rawTrigger);
                }
            }
        }

        // Extract Snooze Duration safely
        var rawSnooze = dict.get("snoozeDuration");
        if (rawSnooze != null) {
            if (rawSnooze instanceof Number) {
                _snoozeDuration = rawSnooze as Number;
            } else if (rawSnooze instanceof Long) {
                _snoozeDuration = (rawSnooze as Long).toNumber();
            }
        }

        // Determine target state
        var stateStr = "";
        var rawState = dict.get("state");
        if (rawState != null) {
            stateStr = rawState.toString().toLower();
        } else {
            var rawType = dict.get("type");
            if (rawType != null && rawType.toString().equals("ALARM_TRIGGER")) {
                stateStr = "ringing";
            }
        }

        if (stateStr.equals("ringing")) {
            transitionToState(STATE_RINGING, "Alarm is ringing");
        } else if (stateStr.equals("upcoming")) {
            transitionToState(STATE_UPCOMING, "Upcoming alarm");
        } else if (stateStr.equals("snoozed")) {
            transitionToState(STATE_UPCOMING, "Alarm snoozed");
        } else if (stateStr.equals("dismissed") || stateStr.equals("idle") || stateStr.equals("none")) {
            clearAlarm();
        } else {
            // If triggerTime is present and in the future, set upcoming
            var now = Time.now().value();
            if (_triggerTime > now) {
                transitionToState(STATE_UPCOMING, "Upcoming alarm");
            } else if (_triggerTime > 0 && (now - _triggerTime) < 300) {
                // If within 5 min past trigger time, ringing
                transitionToState(STATE_RINGING, "Alarm is ringing");
            } else {
                transitionToState(STATE_IDLE, "No upcoming alarms");
            }
        }
    }

    //! Handles explicit action confirmation from Android
    private function handleActionConfirm(dict as Dictionary) as Void {
        // Stop timeout timer
        if (_timeoutTimer != null) {
            _timeoutTimer.stop();
        }

        var confirmedAction = "";
        var rawAction = dict.get("action");
        if (rawAction != null) {
            confirmedAction = rawAction.toString().toLower();
        }

        System.println("[SalarmModel] Confirmed action: " + confirmedAction);

        // Stop active ringing and vibrations immediately
        if (_alertManager != null) {
            _alertManager.stopAlert();
        }

        _pendingAction = ACTION_NONE;
        _pendingRequestId = "";

        if (confirmedAction.equals("snooze")) {
            _statusText = "Snoozed successfully";
            transitionToState(STATE_ACTION_CONFIRMED, "Alarm Snoozed");
            // If new triggerTime is sent, update it
            var rawNewTrigger = dict.get("triggerTime");
            if (rawNewTrigger != null && rawNewTrigger instanceof Number) {
                _triggerTime = rawNewTrigger as Number;
            } else {
                _triggerTime = Time.now().value() + _snoozeDuration;
            }
        } else if (confirmedAction.equals("dismiss")) {
            _statusText = "Dismissed successfully";
            transitionToState(STATE_ACTION_CONFIRMED, "Alarm Dismissed");
            _triggerTime = 0;
        }

        // After 2 seconds, transition to updated upcoming or idle
        var delayTimer = new Timer.Timer();
        delayTimer.start(method(:onConfirmDisplayComplete), 2000, false);
    }

    //! Completion of confirmed action display
    public function onConfirmDisplayComplete() as Void {
        var now = Time.now().value();
        if (_triggerTime > now) {
            transitionToState(STATE_UPCOMING, "Upcoming alarm");
        } else {
            transitionToState(STATE_IDLE, "No upcoming alarm");
        }
        WatchUi.requestUpdate();
    }

    //! Handles explicit action rejection from Android
    private function handleActionReject(dict as Dictionary) as Void {
        if (_timeoutTimer != null) {
            _timeoutTimer.stop();
        }

        var reason = "Phone rejected action";
        var rawMsg = dict.get("message");
        if (rawMsg != null) {
            reason = rawMsg.toString();
        }

        System.println("[SalarmModel] Action rejected: " + reason);
        _pendingAction = ACTION_NONE;
        _pendingRequestId = "";
        _statusText = reason;

        transitionToState(STATE_ACTION_FAILED, reason);

        // Resume ringing if alarm was previously ringing
        if (_previousState == STATE_RINGING) {
            if (_alertManager != null) {
                _alertManager.startAlert();
            }
        }
    }

    //! Clears the alarm state
    public function clearAlarm() as Void {
        if (_alertManager != null) {
            _alertManager.stopAlert();
        }
        if (_timeoutTimer != null) {
            _timeoutTimer.stop();
        }
        _alarmId = "";
        _triggerTime = 0;
        _pendingAction = ACTION_NONE;
        _pendingRequestId = "";
        transitionToState(STATE_IDLE, "No active alarms");
    }

    // -------------------------------------------------------------
    // Watch-to-Phone Actions (Snooze / Dismiss)
    // -------------------------------------------------------------

    //! Requests Snooze action to phone
    //! @return true if request was sent, false if rejected/busy
    public function requestSnooze() as Boolean {
        return sendActionRequest(ACTION_SNOOZE, "snooze");
    }

    //! Requests Dismiss action to phone
    //! @return true if request was sent, false if rejected/busy
    public function requestDismiss() as Boolean {
        return sendActionRequest(ACTION_DISMISS, "dismiss");
    }

    //! Sends action request over BLE transmit
    private function sendActionRequest(actionType as ActionType, actionName as String) as Boolean {
        if (_state == STATE_ACTION_PENDING) {
            System.println("[SalarmModel] Request already pending. Ignoring duplicate.");
            return false;
        }

        var now = Time.now().value();
        _pendingAction = actionType;
        _pendingRequestId = "req_" + actionName + "_" + now.toString();
        _previousState = _state;

        transitionToState(STATE_ACTION_PENDING, "Contacting phone...");

        var payload = {
            "action" => actionName,
            "alarmId" => _alarmId,
            "requestId" => _pendingRequestId,
            "timestamp" => now,
            "snoozeDuration" => _snoozeDuration
        };

        System.println("[SalarmModel] Transmitting to phone: " + payload.toString());

        // Start timeout timer (10 seconds)
        if (_timeoutTimer != null) {
            _timeoutTimer.start(method(:onActionTimeout), ACTION_TIMEOUT_MS, false);
        }

        // Transmit via Communications
        var listener = new SalarmCommListener(self);
        try {
            Communications.transmit(payload, null, listener);
        } catch (e) {
            System.println("[SalarmModel] Transmit exception: " + e.getErrorMessage());
            onTransmitError();
            return false;
        }

        WatchUi.requestUpdate();
        return true;
    }

    //! Called when transmission fails at BLE layer
    public function onTransmitError() as Void {
        if (_timeoutTimer != null) {
            _timeoutTimer.stop();
        }
        System.println("[SalarmModel] Transmit failed.");
        _pendingAction = ACTION_NONE;
        _statusText = "Bluetooth transmit failed";
        transitionToState(STATE_ACTION_FAILED, "Phone unreachable");

        // Keep alert sounding if alarm is ringing
        if (_previousState == STATE_RINGING && _alertManager != null) {
            _alertManager.startAlert();
        }
        WatchUi.requestUpdate();
    }

    //! Called when action confirmation times out
    public function onActionTimeout() as Void {
        if (_state != STATE_ACTION_PENDING) {
            return;
        }
        System.println("[SalarmModel] Action timed out waiting for phone confirmation.");
        _pendingAction = ACTION_NONE;
        _pendingRequestId = "";
        _statusText = "No response from phone";
        transitionToState(STATE_ACTION_FAILED, "No phone response");

        // Resume ringing if it was ringing
        if (_previousState == STATE_RINGING && _alertManager != null) {
            _alertManager.startAlert();
        }
        WatchUi.requestUpdate();
    }

    //! Retries the previous action or clears failure state
    public function retryOrDismissFailure() as Void {
        if (_previousState == STATE_RINGING) {
            transitionToState(STATE_RINGING, "Alarm is ringing");
            if (_alertManager != null) {
                _alertManager.startAlert();
            }
        } else {
            var now = Time.now().value();
            if (_triggerTime > now) {
                transitionToState(STATE_UPCOMING, "Upcoming alarm");
            } else {
                transitionToState(STATE_IDLE, "No upcoming alarms");
            }
        }
        WatchUi.requestUpdate();
    }

    //! State transition handler
    private function transitionToState(newState as AlarmState, status as String) as Void {
        _state = newState;
        _statusText = status;

        if (_state == STATE_RINGING) {
            if (_alertManager != null) {
                _alertManager.startAlert();
            }
        } else if (_state != STATE_ACTION_PENDING && _state != STATE_ACTION_FAILED) {
            if (_alertManager != null) {
                _alertManager.stopAlert();
            }
        }

        WatchUi.requestUpdate();
    }
}
