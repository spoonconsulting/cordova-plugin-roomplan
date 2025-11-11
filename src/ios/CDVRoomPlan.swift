//
//  CDVRoomPlan.swift
//  SharinPix
//
//  Created by Zafir Sk Heerah on 18/06/2024.
//

import Cordova
import UIKit
import RoomPlan
import ARKit
import WebKit

@objc(CDVRoomPlan) class CDVRoomPlan: CDVPlugin, RoomCaptureSessionDelegate, RoomCaptureViewDelegate {
    private var doneButton: UIButton?
    private var cancelButton: UIButton?
    private var activityIndicator: UIActivityIndicatorView?
    
    private var state: String = "loaded"
    private var roomCaptureView: RoomCaptureView!
    private var roomCaptureSessionConfig: RoomCaptureSession.Configuration = RoomCaptureSession.Configuration()
    private var processedResult: CapturedRoom?
    
    private var currentCommand: CDVInvokedUrlCommand?
    
    // Required initializer for CDVPlugin
    @objc required override init(webViewEngine: WKWebView) {
        super.init(webViewEngine: webViewEngine)
    }
    
    required init?(coder: NSCoder) {
        fatalError("Not Needed")
    }
    
    func encode(with coder: NSCoder) {
        fatalError("Not Needed")
    }
    
    @objc(open:)
    func open(command: CDVInvokedUrlCommand) {
        self.currentCommand = command
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let viewController = self.viewController else { return }
            
            self.roomCaptureView = RoomCaptureView(frame: viewController.view.bounds)
            self.roomCaptureView.captureSession.delegate = self
            self.roomCaptureView.delegate = self
            viewController.view.addSubview(self.roomCaptureView)
            self.roomCaptureView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                self.roomCaptureView.topAnchor.constraint(equalTo: viewController.view.topAnchor),
                self.roomCaptureView.leftAnchor.constraint(equalTo: viewController.view.leftAnchor),
                self.roomCaptureView.bottomAnchor.constraint(equalTo: viewController.view.bottomAnchor),
                self.roomCaptureView.rightAnchor.constraint(equalTo: viewController.view.rightAnchor)
            ])
            
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.handleAppWillResignActive),
                name: UIApplication.willResignActiveNotification,
                object: nil
            )
            
            self.startSession()
        }
    }
    
    @objc(isSupported:)
    func isSupported(command: CDVInvokedUrlCommand) {
        let supported = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: supported)
        self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
    }
    
    private func startSession() {
        state = "scanning"
        roomCaptureView?.captureSession.run(configuration: roomCaptureSessionConfig)
        addButtons()
    }
    
    private func stopSession() {
        state = "scanned"
        roomCaptureView?.captureSession.stop()
        updateButtons()
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
            self.commandDelegate.send(pluginResult, callbackId: self.currentCommand?.callbackId)
            return
        }
        self.processedResult = processedResult
        self.activityIndicator?.stopAnimating()
    }
    
    func dismissCaptureView() {
        self.activityIndicator?.stopAnimating()
        stopSession()
        roomCaptureView.removeFromSuperview()
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc func doneScanning(_ sender: UIButton) {
        if state == "scanning" {
            stopSession()
            self.activityIndicator?.startAnimating()
        } else if state == "done" {
            exportResults()
            dismissCaptureView()
        }
    }
    
    @objc func cancelScanning(_ sender: UIButton) {
        dismissCaptureView()
        let result = ["message": "Scanning cancelled"]
        let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: result)
        pluginResult?.keepCallback = true
        self.commandDelegate.send(pluginResult, callbackId: self.currentCommand?.callbackId)
        currentCommand = nil
    }
    
    @objc func handleAppWillResignActive() {
        // Called from notification observer when app goes to background
        if let button = cancelButton {
            cancelScanning(button)
        }
    }
    
    func exportResults() {
        let documentsDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("cordova-room-plan")
        let uuid = NSUUID().uuidString
        let modelFile = documentsDirectory.appendingPathComponent(uuid + ".usdz")
        let jsonFile = documentsDirectory.appendingPathComponent(uuid + ".json")
        
        do {
            try FileManager.default.createDirectory(at: documentsDirectory, withIntermediateDirectories: true, attributes: nil)
            let jsonEncoder = JSONEncoder()
            let jsonData = try jsonEncoder.encode(self.processedResult)
            try jsonData.write(to: jsonFile)
            try self.processedResult?.export(to: modelFile, exportOptions: .parametric)
            
            if (self.processedResult != nil) && isCapturedRoomNil(capturedRoom: self.processedResult!) {
                let result = ["model": modelFile.absoluteString, "json": jsonFile.absoluteString, "message": "Scanning completed successfully"]
                let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: result)
                pluginResult?.keepCallback = true
                self.commandDelegate.send(pluginResult, callbackId: self.currentCommand?.callbackId)
            } else {
                let result = ["message": "No results captured"]
                let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: result)
                pluginResult?.keepCallback = true
                self.commandDelegate.send(pluginResult, callbackId: self.currentCommand?.callbackId)
            }
        } catch {
            let result = ["message": "Error exporting results"]
            let pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: result)
            pluginResult?.keepCallback = true
            self.commandDelegate.send(pluginResult, callbackId: self.currentCommand?.callbackId)
        }
        
        currentCommand = nil
    }
    
    private func addButtons() {
        cancelButton = createButton(title: "Cancel", backgroundColor: UIColor(hex: "#D65745"))
        doneButton = createButton(title: "Done", backgroundColor: UIColor(hex: "#00A885"))
        
        cancelButton!.addTarget(self, action: #selector(cancelScanning), for: .touchUpInside)
        roomCaptureView.addSubview(cancelButton!)
        doneButton!.addTarget(self, action: #selector(doneScanning), for: .touchUpInside)
        roomCaptureView.addSubview(doneButton!)
        
        setupConstraints()
    }
    
    private func updateButtons() {
        if state == "scanned" {
            cancelButton?.removeFromSuperview()
        }
    }
    
    func setupConstraints() {
        guard let viewController = self.viewController,
              let cancelButton = cancelButton,
              let doneButton = doneButton else { return }
        
        NSLayoutConstraint.activate([
            cancelButton.leadingAnchor.constraint(equalTo: viewController.view.leadingAnchor, constant: 20),
            cancelButton.bottomAnchor.constraint(equalTo: viewController.view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            cancelButton.widthAnchor.constraint(equalToConstant: 100),
            cancelButton.heightAnchor.constraint(equalToConstant: 50),
            
            doneButton.trailingAnchor.constraint(equalTo: viewController.view.trailingAnchor, constant: -20),
            doneButton.bottomAnchor.constraint(equalTo: viewController.view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            doneButton.widthAnchor.constraint(equalToConstant: 100),
            doneButton.heightAnchor.constraint(equalToConstant: 50)
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
    
    func isCapturedRoomNil(capturedRoom: CapturedRoom) -> Bool {
        if #available(iOS 17.0, *) {
            return capturedRoom.walls.count != 0 || capturedRoom.doors.count != 0 || capturedRoom.windows.count != 0 || capturedRoom.sections.count != 0 || capturedRoom.floors.count != 0 || capturedRoom.objects.count != 0 || capturedRoom.openings.count != 0
        } else {
            return false
        }
    }
}

extension UIColor {
    convenience init(hex: String, alpha: CGFloat = 1.0) {
        let hexString = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hexString).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hexString.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    }
}
