import Foundation
import AppKit
import AVFoundation
import CoreText

public struct AudioEnvelope: Codable, Sendable {
    public var levels: [Double]
    public var shape: [Double]
}
public enum AudioPresentation {
    public static func envelope(samples: [Float], sampleRate: Int) -> AudioEnvelope {
        let frames = Int(ceil(Double(samples.count)/Double(sampleRate)*30))
        let shape = (0..<120).map { bar -> Double in
            let a = bar*samples.count/120, b = (bar+1)*samples.count/120
            return samples[a..<b].reduce(0) { max($0,Double(abs($1))) }
        }
        let peak = shape.max() ?? 0
        var rms: [Double] = []
        for frame in 0..<frames {
            let center = frame*sampleRate/30, half = sampleRate/40
            let a = max(0,center-half), b = min(samples.count,center+half)
            let sum = samples[a..<b].reduce(0.0) { $0+Double($1)*Double($1) }
            rms.append(b>a ? sqrt(sum/Double(b-a)) : 0)
        }
        let audible = rms.filter {$0 > 1e-8}.sorted()
        let normalizer = audible.isEmpty ? 1 : audible[min(audible.count-1,Int(Double(audible.count)*0.95))]
        var previous = 0.0
        let levels = rms.map { value -> Double in
            let target = pow(min(1,value/max(normalizer,1e-8)),0.75)
            let tau = target > previous ? 0.025 : 0.08
            previous = value < 1e-8 ? 0 : previous+(1-exp(-1/(30*tau)))*(target-previous)
            return previous
        }
        return AudioEnvelope(levels:levels,shape:shape.map {peak > 0 ? $0/peak : 0})
    }
    public static func samples(_ url: URL) throws -> [Float] {
        let data = try Data(contentsOf:url,options:.mappedIfSafe)
        guard data.count%4 == 0, !data.isEmpty else { throw JoeyError.failed("Invalid waveform PCM") }
        let values = data.withUnsafeBytes { Array($0.bindMemory(to:Float.self)) }
        guard values.allSatisfy(\.isFinite) else { throw JoeyError.failed("Nonfinite waveform PCM") }
        return values
    }
    public static func waveBox(owner: Owner, width: Int) -> CGRect {
        let s = Double(width)/1080
        let box = owner == .dub ? CGRect(x:70,y:1490,width:940,height:200) : CGRect(x:90,y:1400,width:900,height:180)
        return CGRect(x:box.minX*s,y:box.minY*s,width:box.width*s,height:box.height*s)
    }
    public static func background(artwork: Artwork, title: String, width: Int, height: Int) throws -> CGImage {
        try artwork.file.validate()
        guard let image = NSImage(contentsOfFile:artwork.file.path)?.cgImage(forProposedRect:nil,context:nil,hints:nil),
              let context = CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,
                                      space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue) else { throw JoeyError.failed("Cannot decode approved artwork") }
        context.setFillColor(NSColor.black.cgColor); context.fill(CGRect(x:0,y:0,width:width,height:height))
        let scale = Double(width)/1080
        let top = artwork.owner == .dub ? CGRect(x:0,y:0,width:width,height:height) : CGRect(x:90*scale,y:120*scale,width:900*scale,height:900*scale)
        let fit = min(top.width/Double(image.width),top.height/Double(image.height))
        let w = Double(image.width)*fit, h = Double(image.height)*fit
        context.interpolationQuality = .high
        context.draw(image,in:CGRect(x:top.minX+(top.width-w)/2,y:Double(height)-top.minY-(top.height+h)/2,width:w,height:h))
        if artwork.owner == .dub {
            let box = CGRect(x:70*scale,y:Double(height)-(1100+168)*scale,width:940*scale,height:168*scale)
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center; paragraph.lineSpacing = 4*scale
            var fontSize = 52.5*scale
            var fitted: NSAttributedString?
            while fontSize >= 20*scale {
                let text = NSAttributedString(string:title,attributes:[.font:NSFont.systemFont(ofSize:fontSize,weight:.regular),
                    .foregroundColor:NSColor(calibratedRed:1,green:245.0/255,blue:223.0/255,alpha:1),.paragraphStyle:paragraph])
                let setter = CTFramesetterCreateWithAttributedString(text)
                let size = CTFramesetterSuggestFrameSizeWithConstraints(setter,CFRange(location:0,length:text.length),nil,CGSize(width:box.width,height:10000),nil)
                if size.height <= box.height { fitted = text; break }; fontSize -= 2*scale
            }
            guard let text = fitted else { throw JoeyError.invalid("Source-grounded title does not fit approved DUB title area") }
            let setter = CTFramesetterCreateWithAttributedString(text)
            let size = CTFramesetterSuggestFrameSizeWithConstraints(setter,CFRange(location:0,length:text.length),nil,box.size,nil)
            let textBox = CGRect(x:box.minX,y:box.midY-size.height/2,width:box.width,height:size.height+2)
            let frame = CTFramesetterCreateFrame(setter,CFRange(location:0,length:text.length),CGPath(rect:textBox,transform:nil),nil)
            CTFrameDraw(frame,context)
        }
        guard let result = context.makeImage() else { throw JoeyError.failed("Artwork composition failed") }
        return result
    }
    public static func writePNG(_ image: CGImage, to url: URL) throws {
        let rep = NSBitmapImageRep(cgImage:image)
        guard let data = rep.representation(using:.png,properties:[:]) else { throw JoeyError.failed("Cannot encode artwork reference") }
        try data.write(to:url,options:.atomic)
    }
    public static func render(background: CGImage, envelope: AudioEnvelope, owner: Owner, duration: Double, output: URL) async throws {
        let writer = try AVAssetWriter(outputURL:output,fileType:.mp4)
        let width = background.width, height = background.height
        let input = AVAssetWriterInput(mediaType:.video,outputSettings:[AVVideoCodecKey:AVVideoCodecType.h264,
            AVVideoWidthKey:width,AVVideoHeightKey:height,AVVideoCompressionPropertiesKey:[AVVideoAverageBitRateKey:4_000_000,
            AVVideoMaxKeyFrameIntervalKey:60,AVVideoProfileLevelKey:AVVideoProfileLevelH264HighAutoLevel]])
        input.expectsMediaDataInRealTime = false
        let adapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:input,sourcePixelBufferAttributes:[
            kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String:width,kCVPixelBufferHeightKey as String:height,
            kCVPixelBufferCGImageCompatibilityKey as String:true,kCVPixelBufferCGBitmapContextCompatibilityKey as String:true])
        guard writer.canAdd(input) else { throw JoeyError.failed("H.264 writer unavailable") }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? JoeyError.failed("Cannot start native encoder") }
        writer.startSession(atSourceTime:.zero)
        let box = waveBox(owner:owner,width:width)
        let color = owner == .dub ? NSColor(calibratedRed:230.0/255,green:174.0/255,blue:57.0/255,alpha:1).cgColor : NSColor.white.cgColor
        let count = max(1,Int(ceil(duration*30-1e-8)))
        do {
            for frame in 0..<count {
                try Task.checkCancellation()
                while !input.isReadyForMoreMediaData {
                    guard writer.status == .writing else { throw writer.error ?? JoeyError.failed("Native encoder stopped") }
                    try await Task.sleep(nanoseconds:5_000_000)
                }
                guard let pool = adapter.pixelBufferPool else { throw JoeyError.failed("Native encoder pixel pool unavailable") }
                var pixel: CVPixelBuffer?
                guard CVPixelBufferPoolCreatePixelBuffer(nil,pool,&pixel) == kCVReturnSuccess, let pixel else { throw JoeyError.failed("Cannot allocate bounded video frame") }
                CVPixelBufferLockBaseAddress(pixel,[])
                guard let context = CGContext(data:CVPixelBufferGetBaseAddress(pixel),width:width,height:height,bitsPerComponent:8,
                    bytesPerRow:CVPixelBufferGetBytesPerRow(pixel),space:CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo:CGImageAlphaInfo.noneSkipFirst.rawValue) else { CVPixelBufferUnlockBaseAddress(pixel,[]); throw JoeyError.failed("Cannot draw video frame") }
                context.draw(background,in:CGRect(x:0,y:0,width:width,height:height))
                context.setFillColor(color)
                let center = Double(height)-box.midY
                context.fill(CGRect(x:box.minX,y:center-0.5,width:box.width,height:1))
                let level = envelope.levels.isEmpty ? 0 : envelope.levels[min(frame,envelope.levels.count-1)]
                for bar in 0..<envelope.shape.count {
                    let extent = envelope.shape[bar]*level*box.height*0.46
                    let x = box.minX+(Double(bar)+0.5)*box.width/Double(envelope.shape.count)
                    context.fill(CGRect(x:x,y:center-extent,width:max(1,box.width/250),height:extent*2))
                }
                CVPixelBufferUnlockBaseAddress(pixel,[])
                guard adapter.append(pixel,withPresentationTime:CMTime(value:Int64(frame),timescale:30)) else { throw writer.error ?? JoeyError.failed("Native frame append failed") }
            }
            input.markAsFinished()
            await writer.finishWriting()
            guard writer.status == .completed else { throw writer.error ?? JoeyError.failed("Native audio-video render incomplete") }
        } catch { writer.cancelWriting(); throw error }
    }
}
