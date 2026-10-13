// Build once: swiftc -O cutout.swift -o "$SCRATCH/cutout"   Usage: cutout <in.png> <out.png>
// Removes background with Vision's foreground instance mask (macOS 14+).
import Foundation
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

let args = CommandLine.arguments
let input = CIImage(contentsOf: URL(fileURLWithPath: args[1]))!
let req = VNGenerateForegroundInstanceMaskRequest()
let handler = VNImageRequestHandler(ciImage: input)
try handler.perform([req])
guard let obs = req.results?.first else { fputs("no foreground: \(args[1])\n", stderr); exit(1) }
let maskBuf = try obs.generateScaledMaskForImage(forInstances: obs.allInstances, from: handler)
let mask = CIImage(cvPixelBuffer: maskBuf)
let blend = CIFilter.blendWithMask()
blend.inputImage = input
blend.backgroundImage = CIImage.empty()
blend.maskImage = mask
let ctx = CIContext()
try ctx.writePNGRepresentation(of: blend.outputImage!, to: URL(fileURLWithPath: args[2]),
                               format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
