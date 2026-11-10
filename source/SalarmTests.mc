import Toybox.Lang;
import Toybox.Test;
import Toybox.Time;

//! Unit tests for SalarmWatch model, message validation, and state logic
(:test)
class SalarmTests {

    //! Test message validation for upcoming alarm
    (:test)
    public static function testMessageValidationUpcoming(logger as Test.Logger) as Boolean {
        var model = new SalarmModel();
        var testTrigger = Time.now().value() + 3600;

        var msgData = {
            "type" => "ALARM_UPDATE",
            "state" => "upcoming",
            "title" => "Morning Run",
            "id" => "alarm_42",
            "triggerTime" => testTrigger,
            "snoozeDuration" => 600
        };

        var handled = model.processIncomingMessage(msgData);
        Test.assertMessage(handled, "Message should be handled successfully");
        Test.assertEqualMessage(model.getState(), SalarmModel.STATE_UPCOMING, "State should be upcoming");
        Test.assertEqualMessage(model.getTitle(), "Morning Run", "Title should match");
        Test.assertEqualMessage(model.getAlarmId(), "alarm_42", "Alarm ID should match");
        Test.assertEqualMessage(model.getTriggerTime(), testTrigger, "Trigger time should match");
        Test.assertEqualMessage(model.getSnoozeDuration(), 600, "Snooze duration should match");

        return true;
    }

    //! Test active ringing state triggered by phone
    (:test)
    public static function testMessageValidationRinging(logger as Test.Logger) as Boolean {
        var model = new SalarmModel();

        var msgData = {
            "type" => "ALARM_TRIGGER",
            "title" => "Wake Up Now",
            "id" => "alarm_99"
        };

        var handled = model.processIncomingMessage(msgData);
        Test.assertMessage(handled, "Trigger message should be handled");
        Test.assertEqualMessage(model.getState(), SalarmModel.STATE_RINGING, "State should be ringing");
        Test.assertEqualMessage(model.getTitle(), "Wake Up Now", "Title should match");

        return true;
    }

    //! Test resilience against null and malformed payloads
    (:test)
    public static function testMalformedPayloads(logger as Test.Logger) as Boolean {
        var model = new SalarmModel();

        // Null payload
        var handledNull = model.processIncomingMessage(null);
        Test.assertMessage(!handledNull, "Null message should return false without exception");

        // Empty dictionary
        var handledEmpty = model.processIncomingMessage({});
        Test.assertMessage(handledEmpty, "Empty dict should be processed safely");
        Test.assertEqualMessage(model.getState(), SalarmModel.STATE_IDLE, "Default state should remain idle");

        // Wrapped Array containing Dictionary (Android SDK format)
        var arrayMsg = [
            {
                "state" => "ringing",
                "title" => "Wrapped Alarm"
            }
        ];
        var handledArray = model.processIncomingMessage(arrayMsg);
        Test.assertMessage(handledArray, "Array-wrapped dict should be extracted and handled");
        Test.assertEqualMessage(model.getState(), SalarmModel.STATE_RINGING, "State should be ringing");

        // String payload (unsupported format)
        var handledString = model.processIncomingMessage("Random String");
        Test.assertMessage(!handledString, "Arbitrary string should safely return false");

        return true;
    }

    //! Test action confirmation flow (Snooze & Dismiss)
    (:test)
    public static function testActionConfirmationFlow(logger as Test.Logger) as Boolean {
        var model = new SalarmModel();

        // First put in ringing state
        model.processIncomingMessage({
            "type" => "ALARM_TRIGGER",
            "id" => "alarm_1"
        });
        Test.assertEqualMessage(model.getState(), SalarmModel.STATE_RINGING, "Should be ringing");

        // Phone confirms snooze
        var newTrigger = Time.now().value() + 540;
        model.processIncomingMessage({
            "type" => "ACTION_CONFIRM",
            "action" => "snooze",
            "triggerTime" => newTrigger
        });

        Test.assertEqualMessage(model.getState(), SalarmModel.STATE_ACTION_CONFIRMED, "State should be action confirmed");
        Test.assertEqualMessage(model.getTriggerTime(), newTrigger, "Trigger time should update to snooze time");

        // Test dismiss confirmation
        model.processIncomingMessage({
            "type" => "ACTION_CONFIRM",
            "action" => "dismiss"
        });
        Test.assertEqualMessage(model.getState(), SalarmModel.STATE_ACTION_CONFIRMED, "State should be confirmed");
        Test.assertEqualMessage(model.getTriggerTime(), 0, "Trigger time should be cleared");

        return true;
    }

    //! Test action rejection handling
    (:test)
    public static function testActionRejection(logger as Test.Logger) as Boolean {
        var model = new SalarmModel();

        model.processIncomingMessage({
            "type" => "ACTION_REJECT",
            "message" => "Alarm already stopped on phone"
        });

        Test.assertEqualMessage(model.getState(), SalarmModel.STATE_ACTION_FAILED, "State should be failed");
        Test.assertEqualMessage(model.getStatusText(), "Alarm already stopped on phone", "Error message should match");

        return true;
    }

    //! Test action timeout handling
    (:test)
    public static function testActionTimeout(logger as Test.Logger) as Boolean {
        var model = new SalarmModel();

        // Simulate ringing then pending request
        model.processIncomingMessage({
            "type" => "ALARM_TRIGGER",
            "id" => "alarm_1"
        });

        // Trigger timeout manually
        model.onActionTimeout();

        // Since it wasn't in STATE_ACTION_PENDING yet, timeout doesn't fire prematurely
        Test.assertEqualMessage(model.getState(), SalarmModel.STATE_RINGING, "Should remain ringing if not pending");

        return true;
    }

    //! Test clear alarm
    (:test)
    public static function testClearAlarm(logger as Test.Logger) as Boolean {
        var model = new SalarmModel();
        model.processIncomingMessage({
            "type" => "ALARM_TRIGGER",
            "title" => "Test",
            "id" => "alarm_1"
        });

        model.clearAlarm();
        Test.assertEqualMessage(model.getState(), SalarmModel.STATE_IDLE, "State should be idle");
        Test.assertEqualMessage(model.getAlarmId(), "", "Alarm id should be cleared");
        Test.assertEqualMessage(model.getTriggerTime(), 0, "Trigger time should be 0");

        return true;
    }
}
