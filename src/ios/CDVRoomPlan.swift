//
//  CDVRoomPlan.swift
//  SharinPix
//
//  Created by Zafir Sk Heerah on 18/06/2024.
//

import Foundation
import UIKit
import RoomPlan
import ARKit
import SpriteKit
import simd

@objc(CDVRoomPlan)
class CDVRoomPlan: CDVPlugin, RoomCaptureSessionDelegate, RoomCaptureViewDelegate, UIDocumentPickerDelegate {
    @IBOutlet var doneButton: UIButton?
    @IBOutlet var cancelButton: UIButton?
    @IBOutlet var activityIndicator: UIActivityIndicatorView?
    
    private var state: String = "loaded"
    private var roomCaptureView: RoomCaptureView!
    private var roomCaptureSessionConfig: RoomCaptureSession.Configuration = RoomCaptureSession.Configuration()
    private var processedResult: CapturedRoom?
    
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
    
    @objc(open:)
    func open(command: CDVInvokedUrlCommand) {
        self.command = command
        roomCaptureView = RoomCaptureView(frame: viewController.view.bounds)
        roomCaptureView.captureSession.delegate = self
        roomCaptureView.delegate = self
        viewController.view.addSubview(roomCaptureView)
        roomCaptureView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            roomCaptureView.topAnchor.constraint(equalTo: viewController.view.topAnchor),
            roomCaptureView.leftAnchor.constraint(equalTo: viewController.view.leftAnchor),
            roomCaptureView.bottomAnchor.constraint(equalTo: viewController.view.bottomAnchor),
            roomCaptureView.rightAnchor.constraint(equalTo: viewController.view.rightAnchor)
        ]);
        NotificationCenter.default.addObserver(self, selector: #selector(cancelScanning), name: UIApplication.willResignActiveNotification, object: nil)
        startSession()
    }
    
    @objc(isSupported:)
    func isSupported(command: CDVInvokedUrlCommand) {
        let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh))
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
            self.commandDelegate.send(pluginResult, callbackId: self.command.callbackId)
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
        let result = ["message": "Scanning cancelled"]
        let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: result)
        pluginResult?.keepCallback = true
        self.commandDelegate.send(pluginResult, callbackId: self.command.callbackId)
        dismissCaptureView()
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
                // Generate 2D floor plan
                let floorPlanImagePath = generate2DFloorPlan(capturedRoom: self.processedResult!, outputDirectory: documentsDirectory, uuid: uuid)
                
                var result: [String: Any] = [
                    "model": modelFile.absoluteString,
                    "json": jsonFile.absoluteString,
                    "message": "Scanning completed successfully"
                ]
                
                if let floorPlanPath = floorPlanImagePath {
                    result["floorPlan"] = floorPlanPath.absoluteString
                }
                
                let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: result)
                pluginResult?.keepCallback = true
                self.commandDelegate.send(pluginResult, callbackId: self.command.callbackId)
            } else {
                let result = ["message": "No results captured"]
                let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: result)
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
    
    func generate2DFloorPlan(capturedRoom: CapturedRoom, outputDirectory: URL, uuid: String) -> URL? {
        guard #available(iOS 17.0, *) else {
            return nil
        }
        
        // Create SpriteKit scene for 2D floor plan
        let sceneSize = CGSize(width: 2048, height: 2048)
        let scene = SKScene(size: sceneSize)
        scene.backgroundColor = .white
        
        // Calculate bounds to center the floor plan
        var minX: Float = Float.greatestFiniteMagnitude
        var maxX: Float = -Float.greatestFiniteMagnitude
        var minZ: Float = Float.greatestFiniteMagnitude
        var maxZ: Float = -Float.greatestFiniteMagnitude
        
        // Collect all points to determine bounds
        var allPoints: [(x: Float, z: Float)] = []
        
        // Extract all surfaces to calculate bounds
        for wall in capturedRoom.walls {
            let transform = wall.transform
            let position = transform.position
            let dimensions = wall.dimensions
            let halfLength = dimensions.x / 2.0
            let forward = simd_float3(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z)
            let wallStart = position - forward * halfLength
            let wallEnd = position + forward * halfLength
            allPoints.append((x: wallStart.x, z: wallStart.z))
            allPoints.append((x: wallEnd.x, z: wallEnd.z))
        }
        
        for door in capturedRoom.doors {
            let transform = door.transform
            let position = transform.position
            allPoints.append((x: position.x, z: position.z))
        }
        
        for window in capturedRoom.windows {
            let transform = window.transform
            let position = transform.position
            allPoints.append((x: position.x, z: position.z))
        }
        
        for obj in capturedRoom.objects {
            let transform = obj.transform
            let position = transform.position
            allPoints.append((x: position.x, z: position.z))
        }
        
        // Calculate bounds
        for point in allPoints {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minZ = min(minZ, point.z)
            maxZ = max(maxZ, point.z)
        }
        
        if allPoints.isEmpty {
            return nil
        }
        
        // Calculate scale and offset to fit in the scene
        let width = maxX - minX
        let height = maxZ - minZ
        let maxDimension = max(width, height)
        let scale: Float = maxDimension > 0 ? 1800.0 / maxDimension : 1.0
        let offsetX = (minX + maxX) / 2.0
        let offsetZ = (minZ + maxZ) / 2.0
        
        // Helper function to convert 3D coordinates to 2D scene coordinates
        func convertToScene(x: Float, z: Float) -> CGPoint {
            let sceneX = CGFloat((x - offsetX) * scale) + sceneSize.width / 2
            let sceneY = CGFloat((z - offsetZ) * scale) + sceneSize.height / 2
            return CGPoint(x: sceneX, y: sceneY)
        }
        
        // Draw walls using SpriteKit
        for wall in capturedRoom.walls {
            let transform = wall.transform
            let position = transform.position
            let dimensions = wall.dimensions
            let eulerAngles = transform.eulerAngles
            
            let halfLength = dimensions.x / 2.0
            let forward = simd_float3(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z)
            
            let wallStart = position - forward * halfLength
            let wallEnd = position + forward * halfLength
            
            let startPoint = convertToScene(x: wallStart.x, z: wallStart.z)
            let endPoint = convertToScene(x: wallEnd.x, z: wallEnd.z)
            
            // Create path for wall
            let path = CGMutablePath()
            path.move(to: startPoint)
            path.addLine(to: endPoint)
            
            // Create SKShapeNode for wall
            let wallNode = SKShapeNode(path: path)
            wallNode.strokeColor = .black
            wallNode.lineWidth = max(2, CGFloat(dimensions.y * scale * 0.1))
            wallNode.lineCap = .round
            scene.addChild(wallNode)
        }
        
        // Draw doors using SpriteKit
        for door in capturedRoom.doors {
            let transform = door.transform
            let position = transform.position
            let dimensions = door.dimensions
            let eulerAngles = transform.eulerAngles
            
            let scenePoint = convertToScene(x: position.x, z: position.z)
            let width = CGFloat(dimensions.x * scale)
            let depth = CGFloat(dimensions.z * scale)
            
            // Create rectangle path for door
            let doorRect = CGRect(
                x: scenePoint.x - width / 2,
                y: scenePoint.y - depth / 2,
                width: width,
                height: depth
            )
            let path = CGPath(rect: doorRect, transform: nil)
            
            // Create SKShapeNode for door
            let doorNode = SKShapeNode(path: path)
            doorNode.fillColor = .lightGray
            doorNode.strokeColor = .blue
            doorNode.lineWidth = 2
            doorNode.zRotation = CGFloat(eulerAngles.y) // Rotate based on Y-axis rotation
            scene.addChild(doorNode)
        }
        
        // Draw windows using SpriteKit
        for window in capturedRoom.windows {
            let transform = window.transform
            let position = transform.position
            let dimensions = window.dimensions
            let eulerAngles = transform.eulerAngles
            
            let scenePoint = convertToScene(x: position.x, z: position.z)
            let width = CGFloat(dimensions.x * scale)
            let depth = CGFloat(dimensions.z * scale)
            
            // Create rectangle path for window
            let windowRect = CGRect(
                x: scenePoint.x - width / 2,
                y: scenePoint.y - depth / 2,
                width: width,
                height: depth
            )
            let path = CGPath(rect: windowRect, transform: nil)
            
            // Create SKShapeNode for window
            let windowNode = SKShapeNode(path: path)
            windowNode.fillColor = .white
            windowNode.strokeColor = .cyan
            windowNode.lineWidth = 2
            windowNode.zRotation = CGFloat(eulerAngles.y)
            scene.addChild(windowNode)
        }
        
        // Draw objects using SpriteKit
        for obj in capturedRoom.objects {
            let transform = obj.transform
            let position = transform.position
            let dimensions = obj.dimensions
            let eulerAngles = transform.eulerAngles
            
            let scenePoint = convertToScene(x: position.x, z: position.z)
            let width = CGFloat(dimensions.x * scale)
            let depth = CGFloat(dimensions.z * scale)
            
            // Create rectangle path for object
            let objectRect = CGRect(
                x: scenePoint.x - width / 2,
                y: scenePoint.y - depth / 2,
                width: width,
                height: depth
            )
            let path = CGPath(rect: objectRect, transform: nil)
            
            // Create SKShapeNode for object
            let objectNode = SKShapeNode(path: path)
            objectNode.fillColor = .lightGray
            objectNode.strokeColor = .brown
            objectNode.lineWidth = 2
            objectNode.zRotation = CGFloat(eulerAngles.y)
            scene.addChild(objectNode)
        }
        
        // Render the SpriteKit scene to an image
        let imageFile = outputDirectory.appendingPathComponent(uuid + "_floorplan.png")
        
        // Create SKView to render the scene
        let skView = SKView(frame: CGRect(origin: .zero, size: sceneSize))
        skView.presentScene(scene)
        
        // Get texture from the scene
        guard let texture = skView.texture(from: scene) else {
            return nil
        }
        
        // Convert texture to UIImage
        let cgImage = texture.cgImage()
        let uiImage = UIImage(cgImage: cgImage)
        
        // Save the image
        guard let imageData = uiImage.pngData() else {
            return nil
        }
        
        do {
            try imageData.write(to: imageFile)
            return imageFile
        } catch {
            return nil
        }
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
    
    func isCapturedRoomNil(capturedRoom: CapturedRoom) -> Bool {
        if #available(iOS 17.0, *) {
            return capturedRoom.walls.count != 0 || capturedRoom.doors.count != 0 || capturedRoom.windows.count != 0 || capturedRoom.sections.count != 0 || capturedRoom.floors.count != 0 || capturedRoom.objects.count != 0 || capturedRoom.openings.count != 0
        } else {
            return false
        }
    }
}

// Extension for simd_float4x4 to extract position and euler angles (as per article reference)
extension simd_float4x4 {
    var position: simd_float3 {
        return simd_float3(self.columns.3.x, self.columns.3.y, self.columns.3.z)
    }
    
    var eulerAngles: simd_float3 {
        // Extract rotation angles from the transform matrix
        let sy = sqrt(self.columns.0.x * self.columns.0.x + self.columns.1.x * self.columns.1.x)
        let singular = sy < 1e-6
        
        var x: Float, y: Float, z: Float
        
        if !singular {
            x = atan2(self.columns.2.y, self.columns.2.z)
            y = atan2(-self.columns.2.x, sy)
            z = atan2(self.columns.1.x, self.columns.0.x)
        } else {
            x = atan2(-self.columns.1.z, self.columns.1.y)
            y = atan2(-self.columns.2.x, sy)
            z = 0
        }
        
        return simd_float3(x, y, z)
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
