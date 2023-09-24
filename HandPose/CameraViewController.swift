/*
See LICENSE folder for this sample’s licensing information.

Abstract:
The app's main view controller object.
*/

import UIKit
import AVFoundation
import Vision

class CameraViewController: UIViewController {

    private var cameraView: CameraView { view as! CameraView }
    
    private let videoDataOutputQueue = DispatchQueue(label: "CameraFeedDataOutput", qos: .userInteractive)
    private var cameraFeedSession: AVCaptureSession?
    private var handPoseRequest = VNDetectHumanHandPoseRequest()
    
    private let drawOverlay = CAShapeLayer()
    private let drawPath = UIBezierPath()
    private var allPoints = [CGPoint]()
    private var lastDrawPoint: CGPoint?
    private var isFirstSegment = true
    private var lastObservationTimestamp = Date()
        
    override func viewDidLoad() {
        super.viewDidLoad()
        drawOverlay.frame = view.layer.bounds
        drawOverlay.lineWidth = 5
        drawOverlay.backgroundColor = #colorLiteral(red: 0.9999018312, green: 1, blue: 0.9998798966, alpha: 0.5).cgColor
        drawOverlay.strokeColor = #colorLiteral(red: 0.6, green: 0.1, blue: 0.3, alpha: 1).cgColor
        drawOverlay.fillColor = #colorLiteral(red: 0.9999018312, green: 1, blue: 0.9998798966, alpha: 0).cgColor
        drawOverlay.lineCap = .round
        view.layer.addSublayer(drawOverlay)

        handPoseRequest.maximumHandCount = 2
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        do {
            if cameraFeedSession == nil {
                cameraView.previewLayer.videoGravity = .resizeAspectFill
                try setupAVSession()
                cameraView.previewLayer.session = cameraFeedSession
            }
            cameraFeedSession?.startRunning()
        } catch {
            AppError.display(error, inViewController: self)
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        cameraFeedSession?.stopRunning()
        super.viewWillDisappear(animated)
    }
    
    func setupAVSession() throws {
        var webcam: AVCaptureDevice?
        webcam = nil
        let devices = AVCaptureDevice.devices(for: AVMediaType.video)
        for device in devices {
            if device.localizedName == "Razer Kiyo Pro" {
                webcam = device;
            }
        }

        if webcam == nil {
            guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
                throw AppError.captureSessionSetup(reason: "Could not find a front facing camera.")
            }
            webcam = videoDevice
        }
        
        guard let deviceInput = try? AVCaptureDeviceInput(device: webcam!) else {
            throw AppError.captureSessionSetup(reason: "Could not create video device input.")
        }
        
        let session = AVCaptureSession()
        session.beginConfiguration()
        session.sessionPreset = AVCaptureSession.Preset.high
        
        // Add a video input.
        guard session.canAddInput(deviceInput) else {
            throw AppError.captureSessionSetup(reason: "Could not add video device input to the session")
        }
        session.addInput(deviceInput)
        
        let dataOutput = AVCaptureVideoDataOutput()
        if session.canAddOutput(dataOutput) {
            session.addOutput(dataOutput)
            // Add a video data output.
            dataOutput.alwaysDiscardsLateVideoFrames = true
            dataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)]
            dataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        } else {
            throw AppError.captureSessionSetup(reason: "Could not add video data output to the session")
        }
        session.commitConfiguration()
        cameraFeedSession = session
    }
    
    func processAllPoints(points: [CGPoint]) {
        let previewLayer = cameraView.previewLayer
        var converted = [CGPoint]()
        for point in points {
            converted.append(previewLayer.layerPointConverted(fromCaptureDevicePoint: point))
        }
        
        cameraView.showPoints(converted, color: .orange)
    }
}

extension CameraViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        var myPoints = [CGPoint]()
        
        defer {
            DispatchQueue.main.sync {
                self.processAllPoints(points: myPoints)
            }
        }
        
        var scaled: CIImage
        if let pixelBuffer = sampleBuffer.imageBuffer {
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let transform = CGAffineTransform.init(scaleX: 0.5, y: 0.5)
            scaled = ciImage.transformed(by: transform).cropped(to: CGRect(x: 0, y: 0, width: 640, height: 480))
        } else {
            return
        }
        
        let handler = VNImageRequestHandler(ciImage: scaled, orientation: .up, options: [:])
        do {
            // Perform VNDetectHumanHandPoseRequest
            try handler.perform([handPoseRequest])
            // Continue only when a hand was detected in the frame.
            // Since we set the maximumHandCount property of the request to 1, there will be at most one observation.
            guard let observations = handPoseRequest.results else {
                return
            }
            for obsv in observations {
                let avPoints = try obsv.recognizedPoints(.all)
                for avPoint in avPoints {
                    myPoints.append(CGPoint(x: avPoint.value.location.x, y: 1 - avPoint.value.location.y))
                }
            }
        } catch {
            cameraFeedSession?.stopRunning()
            let error = AppError.visionError(error: error)
            DispatchQueue.main.async {
                error.displayInViewController(self)
            }
        }
    }
}
