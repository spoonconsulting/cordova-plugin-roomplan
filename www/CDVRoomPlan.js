var exec = require("cordova/exec");

exports.openRoomPlan = function (success, error) {
  console.log("CDVRoomPlan.js: openRoomPlan");
  exec(success, error, "CDVRoomPlan", "openRoomPlan", []);
};

exports.isSupported = function (success, error) {
  console.log("CDVRoomPlan.js: isSupported");
  exec(success, error, "CDVRoomPlan", "isSupported", []);
}
