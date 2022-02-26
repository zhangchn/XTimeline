//
//  DetectionObservationCompositor.swift
//  yolo2
//
//  Created by ZhangChen on 2022/2/12.
//

import AVFoundation
import Foundation
import Vision


class DetectionObservationCompositor: NSObject {
    var compositionRequest: AVAsynchronousVideoCompositionRequest!
    var requests = Set<VNCoreMLRequest>()
    let requestsSema = DispatchSemaphore(value: 1)

    var detectionModel: VNCoreMLModel! {
        didSet {
            if let m = detectionModel {
                requests.removeAll()
                for _ in 0..<8 {
                    requests.insert(VNCoreMLRequest(model: m))
                }
            }
        }
    }
    var categoryLabels: [String] = []
    
    override init() {
        
        /*
        let url = Bundle.main.url(forResource: "coco_category", withExtension: nil)!
        if let categoryLabelText = try? String(contentsOf: url) {
            categoryLabels = categoryLabelText.split(separator: "\n")
        } else {
            categoryLabels = []
        }
         */
    }
    
    var featureName = "var_944"
    //var detectionRequest: VNCoreMLRequest!
    unowned var renderContex: AVVideoCompositionRenderContext!
    //var srcFrame: [CVPixelBuffer: CVPixelBuffer] = [:]
    func handleResult(for request: VNRequest, srcFrame: CVPixelBuffer, dstFrame: CVPixelBuffer, compositionRequest: AVAsynchronousVideoCompositionRequest) {

        if let baseAddr = CVPixelBufferGetBaseAddress(dstFrame),
            let srcAddr = CVPixelBufferGetBaseAddress(srcFrame) {
            let size = renderContex.size
            let srcWidth = CVPixelBufferGetWidth(srcFrame)
            let dstWidth = CVPixelBufferGetWidth(dstFrame)
            let srcHeight = CVPixelBufferGetHeight(srcFrame)
            let dstHeight = CVPixelBufferGetHeight(dstFrame)
            let srcStride = CVPixelBufferGetBytesPerRow(srcFrame)
            let dstStride = CVPixelBufferGetBytesPerRow(dstFrame)
            let categoryLabels = self.categoryLabels
            // let minWidth = min(srcWidth, dstWidth)
            let minHeight = min(srcHeight, dstHeight)
            let minStride = min(srcStride, dstStride)
            if srcWidth == dstWidth && srcHeight == dstHeight && srcStride == dstStride {
                memmove(baseAddr, srcAddr, CVPixelBufferGetDataSize(srcFrame))
            } else {
                for i in 0 ..< minHeight {
                    memmove(baseAddr + i * dstStride, srcAddr + i * srcStride, minStride)
                }
            }
            
            // DEBUG
//            compositionRequest.finish(withComposedVideoFrame: dstFrame)
//            return
            guard let results = request.results else {return}
            DispatchQueue.global().async() {
                let context = CGContext(data: baseAddr,
                                        width: dstWidth,
                                        height: dstHeight,
                                        bitsPerComponent: 8,
                                        bytesPerRow: dstStride,
                                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGImageByteOrderInfo.order32Little.rawValue)
                context?.setStrokeColor(CGColor.white)
                context?.setFillColor(CGColor.init(gray: 1.0, alpha: 0.4))
                for r in results {
                    if let pred = r as? VNCoreMLFeatureValueObservation,
                        let mvPred = pred.featureValue.multiArrayValue {
                        
                        guard #available(macOS 10.15, *), pred.featureName == self.featureName else {
                            continue
                        }
                        let itemSize = mvPred.shape[2].intValue
                        guard mvPred.shape.count == 3 && mvPred.shape[0] == 1 && itemSize >= 6 else {
                            print("mysterious shape: \(mvPred.shape)")
                            continue
                        }
                        let categoryCount = itemSize - 5
                        let predThreshold = Float32(0.3)
                        var bboxCandidates = [[BBox]](repeating: [], count: categoryCount)
                        let mvPredData = mvPred.dataPointer
                        // Calculate
                        for a in 0 ..< mvPred.shape[1].intValue {
                            let itemOffset = a * itemSize
                            for categoryIdx in 0..<categoryCount {
                                let objectness = mvPredData.load(fromByteOffset: 4 * (itemOffset + 4),
                                                                 as: Float32.self)
                                let categoryScore = mvPredData.load(fromByteOffset: 4 * (itemOffset + 5 + categoryIdx),
                                                                    as: Float32.self)
                                let bboxConf = objectness * categoryScore
                                if bboxConf > predThreshold {
                                    let width = mvPred[itemOffset + 2].doubleValue / 640 * size.width
                                    let height = mvPred[itemOffset + 3].doubleValue / 640 * size.height
                                    
                                    let x = mvPred[itemOffset].doubleValue / 640 * size.width - width / 2 // cx -> xmin
                                    let y = size.height - mvPred[itemOffset + 1].doubleValue / 640 * size.height - height / 2 // flip y, then cy -> ymin
                                    //print("[\(x), \(y), \(width), \(height)]: \(bboxConf)")
                                    bboxCandidates[categoryIdx].append(BBox(rect: CGRect(x: x,
                                                                                             y: y, // flip?
                                                                                             width: width,
                                                                                             height: height),
                                                                                confidence: Float(bboxConf)))
                                    
                                }
                            }
                        }
                        // NMS
                        for categoryIdx in 0..<(itemSize - 5) {
                            bboxCandidates[categoryIdx].sort(by: > )
                            let iouThreshold = 0.45
                            for idx in 0 ..< bboxCandidates[categoryIdx].count {
                                let a = bboxCandidates[categoryIdx][idx]
                                if a.status == .dropped {
                                    continue
                                }
                                for b in idx + 1 ..< bboxCandidates[categoryIdx].count {
                                    if a.iou(bboxCandidates[categoryIdx][b]) > iouThreshold {
                                        bboxCandidates[categoryIdx][b].status = .dropped
                                    }
                                }
                                bboxCandidates[categoryIdx][idx].status = .accepted
                            }
                            
                            
                            for c in bboxCandidates[categoryIdx].filter({ $0.status == .accepted }) {
                                
                                context?.beginPath()
                                let categoryFactor = CGFloat(categoryIdx) / (max(2.0, CGFloat(categoryCount)) - 1)
                                context?.setStrokeColor(CGColor(red: categoryFactor, green: 0.0, blue: 1 - categoryFactor, alpha: 1.0))
                                context?.setFillColor(CGColor(gray: 1.0, alpha: CGFloat(c.confidence) / 2.0))

                                context?.setLineWidth(CGFloat(srcWidth) / 600 * 3.0)
                                context?.addRect(c.rect)
                                context?.drawPath(using: .fillStroke)
                                
                                if categoryIdx < categoryLabels.count {
                                    print("NMS: category \(categoryLabels[categoryIdx])(\(categoryIdx) [\(c.rect.origin.x), \(c.rect.origin.y), \(c.rect.size.width), \(c.rect.size.height)]: \(c.confidence)")
                                } else {
                                    print("NMS: category \(categoryIdx) [\(c.rect.origin.x), \(c.rect.origin.y), \(c.rect.size.width), \(c.rect.size.height)]: \(c.confidence)")
                                }
                            }
                        }
                        
                    }
                }
                CVPixelBufferUnlockBaseAddress(dstFrame, [])
                compositionRequest.finish(withComposedVideoFrame: dstFrame)

            }
            // DEBUG
            /*
            context?.addRect(CGRect(x: size.width / 4, y: size.height / 4, width: size.width / 2, height: size.height / 2))
            context?.drawPath(using: .fillStroke)
             */
            
        }
    }
}

extension DetectionObservationCompositor: AVVideoCompositing {
    var sourcePixelBufferAttributes: [String : Any]? {
        return [
            kCVPixelBufferPixelFormatTypeKey as String: [
                kCVPixelFormatType_32BGRA
            ]
        ]
    }
    
    var requiredPixelBufferAttributesForRenderContext: [String : Any] {
        return [
            kCVPixelBufferPixelFormatTypeKey as String: [
                kCVPixelFormatType_32BGRA
            ]
        ]
    }
    
    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        self.renderContex = newRenderContext
    }
    
    func startRequest(_ asyncVideoCompositionRequest: AVAsynchronousVideoCompositionRequest) {
        if let trackId = asyncVideoCompositionRequest.sourceTrackIDs.first, let frame = asyncVideoCompositionRequest.sourceFrame(byTrackID: trackId.int32Value), let dstBuf = self.renderContex.newPixelBuffer(), kCVReturnSuccess == CVPixelBufferLockBaseAddress(dstBuf, []), kCVReturnSuccess == CVPixelBufferLockBaseAddress(frame, .readOnly) {
            let requestHandler = VNImageRequestHandler(cvPixelBuffer: frame)
            self.requestsSema.wait()
            let detectionRequest = self.requests.popFirst() ?? VNCoreMLRequest(model: self.detectionModel)
            self.requestsSema.signal()
            detectionRequest.imageCropAndScaleOption = .scaleFill
            //let t0 = Date()
            try? requestHandler.perform([detectionRequest])
            //let t1 = Date()
            //print("\((t1.timeIntervalSinceReferenceDate - t0.timeIntervalSinceReferenceDate) * 1000)")
            self.handleResult(for: detectionRequest,
                              srcFrame: frame,
                              dstFrame: dstBuf,
                              compositionRequest: asyncVideoCompositionRequest)
            self.requestsSema.wait()
            self.requests.insert(detectionRequest)
            self.requestsSema.signal()
            CVPixelBufferUnlockBaseAddress(frame, .readOnly)
        }
    }
}
