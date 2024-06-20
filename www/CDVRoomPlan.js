var exec = require('cordova/exec');

exports.openRoomPlan = function(success, error) {
    console.log("CDVRoomPlan.js: openRoomPlan");
    exec(success, error, "CDVRoomPlan", "openRoomPlan", []);
  };
