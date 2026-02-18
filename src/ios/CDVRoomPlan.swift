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
        
        // Constants from reference implementation
        let baseScalingFactor: CGFloat = 200
        let sceneSize = CGSize(width: 2048, height: 2048) // Increased size for better quality
        let floorPlanBackgroundColor = UIColor.white
        let floorPlanSurfaceColor = UIColor.black
        let surfaceWidth: CGFloat = 22.0
        let hideSurfaceWidth: CGFloat = 24.0
        let windowWidth: CGFloat = 8.0
        let doorArcWidth: CGFloat = 8.0
        let objectOutlineWidth: CGFloat = 8.0
        
        // zPositions
        let hideSurfaceZPosition: CGFloat = 1
        let windowZPosition: CGFloat = 10
        let doorZPosition: CGFloat = 20
        let doorArcZPosition: CGFloat = 21
        let objectZPosition: CGFloat = 30
        let objectOutlineZPosition: CGFloat = 31
        
        // Combine all surfaces
        let surfaces = capturedRoom.doors + capturedRoom.openings + capturedRoom.walls + capturedRoom.windows
        
        // If no surfaces or objects, return nil
        if surfaces.isEmpty && capturedRoom.objects.isEmpty {
            return nil
        }
        
        // Calculate bounds of all content to determine proper scaling and centering
        var minX: Float = Float.greatestFiniteMagnitude
        var maxX: Float = -Float.greatestFiniteMagnitude
        var minZ: Float = Float.greatestFiniteMagnitude
        var maxZ: Float = -Float.greatestFiniteMagnitude
        
        // Calculate bounds from surfaces
        for surface in surfaces {
            let position = surface.transform.position
            let dimensions = surface.dimensions
            let halfLength = dimensions.x / 2.0
            let forward = simd_float3(surface.transform.columns.0.x, surface.transform.columns.0.y, surface.transform.columns.0.z)
            
            let start = position - forward * halfLength
            let end = position + forward * halfLength
            
            minX = min(minX, start.x, end.x)
            maxX = max(maxX, start.x, end.x)
            minZ = min(minZ, start.z, end.z)
            maxZ = max(maxZ, start.z, end.z)
        }
        
        // Calculate bounds from objects
        for object in capturedRoom.objects {
            let position = object.transform.position
            let dimensions = object.dimensions
            let halfWidth = dimensions.x / 2.0
            let halfDepth = dimensions.z / 2.0
            let forward = simd_float3(object.transform.columns.0.x, object.transform.columns.0.y, object.transform.columns.0.z)
            let right = simd_float3(object.transform.columns.1.x, object.transform.columns.1.y, object.transform.columns.1.z)
            
            // Calculate corners separately to help compiler type-check
            let forwardHalfDepth = forward * halfDepth
            let rightHalfWidth = right * halfWidth
            
            let corner1 = position - forwardHalfDepth - rightHalfWidth
            let corner2 = position + forwardHalfDepth + rightHalfWidth
            let corner3 = position - forwardHalfDepth + rightHalfWidth
            let corner4 = position + forwardHalfDepth - rightHalfWidth
            
            let corners = [corner1, corner2, corner3, corner4]
            
            for corner in corners {
                minX = min(minX, corner.x)
                maxX = max(maxX, corner.x)
                minZ = min(minZ, corner.z)
                maxZ = max(maxZ, corner.z)
            }
        }
        
        // If no content, return nil
        if minX == Float.greatestFiniteMagnitude {
            return nil
        }
        
        // Calculate content dimensions (in meters from RoomPlan)
        let contentWidth = maxX - minX
        let contentHeight = maxZ - minZ
        let maxContentDimension = max(contentWidth, contentHeight)
        
        // Calculate scale to fit content in scene with padding
        // maxContentDimension is in meters, we need pixels per meter
        let padding: CGFloat = 0.15 // 15% padding on each side
        let availableWidth = sceneSize.width * (1 - padding * 2)
        let availableHeight = sceneSize.height * (1 - padding * 2)
        
        // Calculate pixels per meter needed to fit content
        let pixelsPerMeterX = availableWidth / CGFloat(maxContentDimension)
        let pixelsPerMeterY = availableHeight / CGFloat(maxContentDimension)
        let pixelsPerMeter = min(pixelsPerMeterX, pixelsPerMeterY)
        
        // Use the calculated scale, but don't go below base scaling for quality
        let scalingFactor = max(baseScalingFactor, pixelsPerMeter)
        
        // Calculate center offset to center all content
        let centerX = (minX + maxX) / 2.0
        let centerZ = (minZ + maxZ) / 2.0
        
        // Create SpriteKit scene for 2D floor plan
        let scene = SKScene(size: sceneSize)
        scene.scaleMode = .aspectFit
        scene.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        scene.backgroundColor = floorPlanBackgroundColor
        
        // Draw surfaces (as per FloorPlanSurface implementation)
        // Offset positions to center content
        for surface in surfaces {
            let surfaceNode = createSurfaceNode(surface: surface, scalingFactor: scalingFactor,
                                                centerOffsetX: centerX, centerOffsetZ: centerZ,
                                                floorPlanBackgroundColor: floorPlanBackgroundColor,
                                                floorPlanSurfaceColor: floorPlanSurfaceColor,
                                                surfaceWidth: surfaceWidth,
                                                hideSurfaceWidth: hideSurfaceWidth,
                                                windowWidth: windowWidth,
                                                doorArcWidth: doorArcWidth,
                                                hideSurfaceZPosition: hideSurfaceZPosition,
                                                windowZPosition: windowZPosition,
                                                doorZPosition: doorZPosition,
                                                doorArcZPosition: doorArcZPosition)
            scene.addChild(surfaceNode)
        }
        
        // Draw objects (as per FloorPlanObject implementation)
        // Offset positions to center content
        for object in capturedRoom.objects {
            let objectNode = createObjectNode(object: object, scalingFactor: scalingFactor,
                                             centerOffsetX: centerX, centerOffsetZ: centerZ,
                                             floorPlanSurfaceColor: floorPlanSurfaceColor,
                                             objectOutlineWidth: objectOutlineWidth,
                                             objectZPosition: objectZPosition,
                                             objectOutlineZPosition: objectOutlineZPosition)
            scene.addChild(objectNode)
        }
        
        // Render the SpriteKit scene to an image
        let imageFile = outputDirectory.appendingPathComponent(uuid + "_floorplan.png")
        
        // Create SKView to render the scene
        let skView = SKView(frame: CGRect(origin: .zero, size: sceneSize))
        skView.ignoresSiblingOrder = true
        skView.allowsTransparency = true
        skView.presentScene(scene)
        
        // Wait a moment for the scene to render
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        
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
    
    // Helper function to create surface node (based on FloorPlanSurface)
    private func createSurfaceNode(surface: CapturedRoom.Surface, scalingFactor: CGFloat,
                                  centerOffsetX: Float, centerOffsetZ: Float,
                                  floorPlanBackgroundColor: UIColor, floorPlanSurfaceColor: UIColor,
                                  surfaceWidth: CGFloat, hideSurfaceWidth: CGFloat, windowWidth: CGFloat,
                                  doorArcWidth: CGFloat, hideSurfaceZPosition: CGFloat,
                                  windowZPosition: CGFloat, doorZPosition: CGFloat,
                                  doorArcZPosition: CGFloat) -> SKNode {
        let surfaceNode = SKNode()
        
        // Set the surface's position using the transform matrix, offset by center to center content
        let surfacePositionX = -CGFloat(surface.transform.position.x - centerOffsetX) * scalingFactor
        let surfacePositionY = CGFloat(surface.transform.position.z - centerOffsetZ) * scalingFactor
        surfaceNode.position = CGPoint(x: surfacePositionX, y: surfacePositionY)
        
        // Set the surface's zRotation using the transform matrix (as per reference)
        surfaceNode.zRotation = -CGFloat(surface.transform.eulerAngles.z - surface.transform.eulerAngles.y)
        
        // Calculate half length
        let halfLength = CGFloat(surface.dimensions.x) * scalingFactor / 2
        
        // Points A and B for the line
        let pointA = CGPoint(x: -halfLength, y: 0)
        let pointB = CGPoint(x: halfLength, y: 0)
        
        // Draw based on surface category
        switch surface.category {
        case .door:
            // Hide the wall underneath the door
            let hideWallPath = createPath(from: pointA, to: pointB)
            let hideWallShape = createShapeNode(from: hideWallPath, strokeColor: floorPlanBackgroundColor,
                                              lineWidth: hideSurfaceWidth, zPosition: hideSurfaceZPosition)
            
            // The door itself (arc from pointA to pointC)
            let pointC = pointB.rotateAround(point: pointA, by: 0.25 * .pi)
            let doorPath = createPath(from: pointA, to: pointC)
            let doorShape = createShapeNode(from: doorPath, strokeColor: floorPlanSurfaceColor,
                                          lineWidth: surfaceWidth, zPosition: doorZPosition)
            doorShape.lineCap = .square
            
            // The door's arc
            let doorArcPath = CGMutablePath()
            doorArcPath.addArc(center: pointA, radius: halfLength * 2,
                              startAngle: 0.25 * .pi, endAngle: 0, clockwise: true)
            let dashPattern: [CGFloat] = [24.0, 8.0]
            let dashedArcPath = doorArcPath.copy(dashingWithPhase: 1, lengths: dashPattern)
            let doorArcShape = createShapeNode(from: dashedArcPath, strokeColor: floorPlanSurfaceColor,
                                             lineWidth: doorArcWidth, zPosition: doorArcZPosition)
            
            surfaceNode.addChild(hideWallShape)
            surfaceNode.addChild(doorShape)
            surfaceNode.addChild(doorArcShape)
            
        case .opening:
            // Hide the wall underneath the opening
            let openingPath = createPath(from: pointA, to: pointB)
            let hideWallShape = createShapeNode(from: openingPath, strokeColor: floorPlanBackgroundColor,
                                              lineWidth: hideSurfaceWidth, zPosition: hideSurfaceZPosition)
            surfaceNode.addChild(hideWallShape)
            
        case .wall:
            // Draw wall
            let wallPath = createPath(from: pointA, to: pointB)
            let wallShape = createShapeNode(from: wallPath, strokeColor: floorPlanSurfaceColor,
                                         lineWidth: surfaceWidth, zPosition: 0)
            wallShape.lineCap = .square
            surfaceNode.addChild(wallShape)
            
        case .window:
            // Hide the wall underneath the window
            let windowPath = createPath(from: pointA, to: pointB)
            let hideWallShape = createShapeNode(from: windowPath, strokeColor: floorPlanBackgroundColor,
                                              lineWidth: hideSurfaceWidth, zPosition: hideSurfaceZPosition)
            
            // The window itself
            let windowShape = createShapeNode(from: windowPath, strokeColor: floorPlanSurfaceColor,
                                             lineWidth: windowWidth, zPosition: windowZPosition)
            
            surfaceNode.addChild(hideWallShape)
            surfaceNode.addChild(windowShape)
            
        @unknown default:
            // Default to wall
            let wallPath = createPath(from: pointA, to: pointB)
            let wallShape = createShapeNode(from: wallPath, strokeColor: floorPlanSurfaceColor,
                                         lineWidth: surfaceWidth, zPosition: 0)
            wallShape.lineCap = .square
            surfaceNode.addChild(wallShape)
        }
        
        return surfaceNode
    }
    
    // Helper function to create object node (based on FloorPlanObject)
    private func createObjectNode(object: CapturedRoom.Object, scalingFactor: CGFloat,
                                  centerOffsetX: Float, centerOffsetZ: Float,
                                  floorPlanSurfaceColor: UIColor, objectOutlineWidth: CGFloat,
                                  objectZPosition: CGFloat, objectOutlineZPosition: CGFloat) -> SKNode {
        let objectNode = SKNode()
        
        // Set the object's position using the transform matrix, offset by center to center content
        let objectPositionX = -CGFloat(object.transform.position.x - centerOffsetX) * scalingFactor
        let objectPositionY = CGFloat(object.transform.position.z - centerOffsetZ) * scalingFactor
        objectNode.position = CGPoint(x: objectPositionX, y: objectPositionY)
        
        // Set the object's zRotation using the transform matrix (as per reference)
        objectNode.zRotation = -CGFloat(object.transform.eulerAngles.z - object.transform.eulerAngles.y)
        
        // Calculate the object's dimensions
        let objectWidth = CGFloat(object.dimensions.x) * scalingFactor
        let objectHeight = CGFloat(object.dimensions.z) * scalingFactor
        
        // Create the object's rectangle
        let objectRect = CGRect(x: -objectWidth / 2, y: -objectHeight / 2,
                               width: objectWidth, height: objectHeight)
        
        // A shape to fill the object
        let objectShape = SKShapeNode(rect: objectRect)
        objectShape.strokeColor = .clear
        objectShape.fillColor = floorPlanSurfaceColor
        objectShape.alpha = 0.3
        objectShape.zPosition = objectZPosition
        
        // And another shape for the outline
        let objectOutlineShape = SKShapeNode(rect: objectRect)
        objectOutlineShape.strokeColor = floorPlanSurfaceColor
        objectOutlineShape.lineWidth = objectOutlineWidth
        objectOutlineShape.lineJoin = .miter
        objectOutlineShape.zPosition = objectOutlineZPosition
        
        objectNode.addChild(objectShape)
        objectNode.addChild(objectOutlineShape)
        
        return objectNode
    }
    
    // Helper function to create path
    private func createPath(from pointA: CGPoint, to pointB: CGPoint) -> CGMutablePath {
        let path = CGMutablePath()
        path.move(to: pointA)
        path.addLine(to: pointB)
        return path
    }
    
    // Helper function to create shape node
    private func createShapeNode(from path: CGPath, strokeColor: UIColor, lineWidth: CGFloat, zPosition: CGFloat) -> SKShapeNode {
        let shapeNode = SKShapeNode(path: path)
        shapeNode.strokeColor = strokeColor
        shapeNode.lineWidth = lineWidth
        shapeNode.zPosition = zPosition
        return shapeNode
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

// Extension for simd_float4x4 to extract position and euler angles (as per reference implementation)
extension simd_float4x4 {
    var position: simd_float3 {
        simd_float3(
            x: self.columns.3.x,
            y: self.columns.3.y,
            z: self.columns.3.z
        )
    }
    
    var eulerAngles: simd_float3 {
        simd_float3(
            x: asin(-self[2][1]),
            y: atan2(self[2][0], self[2][2]),
            z: atan2(self[0][1], self[1][1])
        )
    }
}

// Extension for CGPoint rotation (as per reference implementation)
extension CGPoint {
    func rotateAround(point: CGPoint, by angle: CGFloat) -> CGPoint {
        // Translate to origin
        let x1 = self.x - point.x
        let y1 = self.y - point.y
        
        // Apply rotation
        let x2 = x1 * cos(angle) - y1 * sin(angle)
        let y2 = x1 * sin(angle) + y1 * cos(angle)
        
        // Translate back
        let newX = x2 + point.x
        let newY = y2 + point.y
        
        return CGPoint(x: newX, y: newY)
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
