//
//  CDVRoomPlan.swift
//  SharinPix
//
//  Created by Zafir Sk Heerah on 18/06/2024.
//

import Foundation
import UIKit
import RoomPlan

@objc(CDVRoomPlan)
class CDVRoomPlan: CDVPlugin, RoomCaptureSessionDelegate, RoomCaptureViewDelegate, UIDocumentPickerDelegate {
    @IBOutlet var doneButton: UIButton?
    @IBOutlet var cancelButton: UIButton?
    @IBOutlet var activityIndicator: UIActivityIndicatorView?
    
    private var state: String = "loaded"
    private var roomCaptureView: RoomCaptureView!
    private var roomCaptureSessionConfig: RoomCaptureSession.Configuration = RoomCaptureSession.Configuration()
    private var finalResults: CapturedRoom?
    
    var command: CDVInvokedUrlCommand!
    
    func encode(with coder: NSCoder) {
        fatalError("Not Needed")
    }
    
    required init?(coder: NSCoder) {
        fatalError("Not Needed")
    }
    
    override init() {
        super.init()
    }
    
    @objc(openRoomPlan:)
    func openRoomPlan(command: CDVInvokedUrlCommand) {
        self.command = command
        roomCaptureView = RoomCaptureView(frame: viewController.view.bounds)
        roomCaptureView.captureSession.delegate = self
        roomCaptureView.delegate = self
        viewController.view.addSubview(roomCaptureView)
        startSession()
    }
    
    private func startSession() {
        state = "scanning"
        roomCaptureView?.captureSession.run(configuration: roomCaptureSessionConfig)
        addButtons()
    }
    
    private func stopSession() {
        state = "scanned"
        roomCaptureView?.captureSession.stop()
    }
    
    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: (Error)?) -> Bool {
        state = "done"
        return true
    }
    
    func captureView(didPresent processedResult: CapturedRoom, error: (any Error)?) {
        if let error = error {
            let result = ["message": error.localizedDescription]
            let pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: result)
            pluginResult?.keepCallback = true
            self.commandDelegate.send(pluginResult, callbackId: self.command.callbackId)
            return
        }
        finalResults = processedResult
        self.activityIndicator?.stopAnimating()
    }
    
    // Action for the 'Done' button
    @objc func doneScanning(_ sender: UIButton) {
        if state == "scanning" {
            stopSession()
            self.activityIndicator?.startAnimating()
        } else if state == "done" {
            exportResults()
            cancelScanning(sender)
        }
    }
    
    @objc func cancelScanning(_ sender: UIButton) {
        self.activityIndicator?.stopAnimating()
        stopSession()
        roomCaptureView.removeFromSuperview()
        let result = ["message": "Scanning cancelled"]
        let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: result)
        pluginResult?.keepCallback = true
        self.commandDelegate.send(pluginResult, callbackId: self.command.callbackId)
    }
    
    func exportResults() {
        let documentsDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("cordova-room-plan")
        let uuid = NSUUID().uuidString
        let usdzFile = documentsDirectory.appendingPathComponent(uuid + ".usdz")
        let jsonFile = documentsDirectory.appendingPathComponent(uuid + ".json")
        do {
            try FileManager.default.createDirectory(at: documentsDirectory, withIntermediateDirectories: true, attributes: nil)
            let jsonEncoder = JSONEncoder()
            let jsonData = try jsonEncoder.encode(finalResults)
            try jsonData.write(to: jsonFile)
            try finalResults?.export(to: usdzFile, exportOptions: .parametric)
            if finalResults != nil {
                let result = ["usdz": usdzFile.absoluteString, "json": jsonFile.absoluteString, "message": "Scanning completed successfully"]
                let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: usdzFile.absoluteString)
                pluginResult?.keepCallback = true
                self.commandDelegate.send(pluginResult, callbackId: self.command.callbackId)
            }
        } catch {
            let result = ["message": "Error exporting results"]
            let pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: result)
            pluginResult?.keepCallback = true
            self.commandDelegate.send(pluginResult, callbackId: self.command.callbackId)
        }
    }
    
    
    private func addButtons() {
        cancelButton = createButton(title: "Cancel", backgroundColor: UIColor.red)
        doneButton = createButton(title: "Done", backgroundColor: UIColor.blue)
        
        cancelButton!.addTarget(self, action: #selector(cancelScanning), for: .touchUpInside)
        roomCaptureView.addSubview(cancelButton!)
        doneButton!.addTarget(self, action: #selector(doneScanning), for: .touchUpInside)
        roomCaptureView.addSubview(doneButton!)
        
        setupConstraints()
    }
    
    func setupConstraints() {
        NSLayoutConstraint.activate([
            cancelButton!.leadingAnchor.constraint(equalTo: viewController.view.leadingAnchor, constant: 20),
            cancelButton!.bottomAnchor.constraint(equalTo: viewController.view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            cancelButton!.widthAnchor.constraint(equalToConstant: 100),
            cancelButton!.heightAnchor.constraint(equalToConstant: 50),
            
            doneButton!.trailingAnchor.constraint(equalTo: viewController.view.trailingAnchor, constant: -20),
            doneButton!.bottomAnchor.constraint(equalTo: viewController.view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            doneButton!.widthAnchor.constraint(equalToConstant: 100),
            doneButton!.heightAnchor.constraint(equalToConstant: 50)
        ])
    }
    
    func createButton(title: String, backgroundColor: UIColor) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.backgroundColor = backgroundColor
        button.tintColor = .white
        button.layer.cornerRadius = 5
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }
}
