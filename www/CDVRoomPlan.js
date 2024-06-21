var exec = require("cordova/exec");

exports.open = function (success, error) {
  console.log("CDVRoomPlan.js: open");
  exec(success, error, "CDVRoomPlan", "open", []);
};

exports.isSupported = function (success, error) {
  console.log("CDVRoomPlan.js: isSupported");
  exec(success, error, "CDVRoomPlan", "isSupported", []);
}
