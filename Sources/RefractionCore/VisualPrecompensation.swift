import Foundation
import Darwin

/// A bounded, ordinary-screen prefilter experiment. This is not a model of a measured eye.
public enum VisualPrecompensation {
    public struct Settings: Sendable {
        public var sphere: Double
        public var cylinder: Double
        public var axis: Double
        public var distanceMeters: Double
        public var pupilMillimeters: Double
        public var imageWidthMillimeters: Double
        public var strength: Double
        public init(sphere:Double,cylinder:Double,axis:Double,distanceMeters:Double,
                    pupilMillimeters:Double,imageWidthMillimeters:Double,strength:Double) {
            self.sphere=sphere; self.cylinder=cylinder; self.axis=axis
            self.distanceMeters=distanceMeters; self.pupilMillimeters=pupilMillimeters
            self.imageWidthMillimeters=imageWidthMillimeters; self.strength=strength
        }
    }
    public struct Result: Sendable {
        public let pixels: [Double]
        public let predictedOriginal: [Double]
        public let predictedProcessed: [Double]
        public let clippedFraction: Double
        public let maximumBlurRadiusPixels: Double
    }
    private struct Complex {
        var r:Double
        var i:Double = 0
    }
    public static func render(target:[Double],size:Int,settings:Settings) throws -> Result {
        guard size >= 16, size <= 512, size.nonzeroBitCount == 1, target.count == size*size,
              target.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
              [settings.sphere,settings.cylinder,settings.axis,settings.distanceMeters,settings.pupilMillimeters,
               settings.imageWidthMillimeters,settings.strength].allSatisfy({$0.isFinite}),
              (-20...0).contains(settings.sphere),(-10...0).contains(settings.cylinder),
              (0...180).contains(settings.axis),(0.2...3).contains(settings.distanceMeters),
              (2...8).contains(settings.pupilMillimeters),settings.imageWidthMillimeters > 0,
              (0...1).contains(settings.strength) else {
            throw MeasurementError.invalid(L("请填写有效的近视、散光、轴位、观看距离和屏幕尺寸。"))
        }
        // Geometric ellipse approximation, with assumed best spherical accommodation.
        // Real accommodation, diffraction, pupil shape and higher-order aberrations are unknown.
        let vergence=1/settings.distanceMeters
        let accommodation=max(0,vergence+settings.sphere+settings.cylinder/2)
        let density=Double(size)/settings.imageWidthMillimeters
        let factor=settings.pupilMillimeters/2*settings.distanceMeters*density
        let rx=factor*abs(vergence+settings.sphere-accommodation)
        let ry=factor*abs(vergence+settings.sphere+settings.cylinder-accommodation)
        guard max(rx,ry) <= Double(size)/3 else {
            throw MeasurementError.invalid(L("此组度数与距离下，估计模糊范围太大。请缩短观看距离或使用更大的屏幕，再尝试预处理；本实验不能补回已丢失的细节。"))
        }
        // Zero-padding prevents the test content wrapping from one edge into the opposite edge.
        let n=size*2, origin=size/2
        var spectrum=[Complex](repeating:Complex(r:0.5),count:n*n)
        for y in 0..<size { for x in 0..<size { spectrum[(y+origin)*n+x+origin]=Complex(r:target[y*size+x]) } }
        transform2D(&spectrum,size:n,inverse:false)
        let theta=settings.axis * .pi/180, c=cos(theta), s=sin(theta)
        var transfer=[Double](repeating:0,count:n*n)
        for y in 0..<n { for x in 0..<n {
            let fx=Double(x <= n/2 ? x : x-n)/Double(n)
            let fy=Double(y <= n/2 ? y : y-n)/Double(n)
            // Image coordinates point down, whereas clinical axis angles point up.
            let u=fx*c-fy*s, v=fx*s+fy*c
            let q=2 * Double.pi * hypot(rx*u,ry*v)
            transfer[y*n+x]=q < 1e-8 ? 1 : 2*j1(q)/q
        } }
        // Preserve Hermitian symmetry at the discrete Nyquist boundary.
        for y in 0..<n { for x in 0..<n {
            let a=y*n+x,b=((n-y)%n)*n+(n-x)%n
            if a <= b { let h=(transfer[a]+transfer[b])/2; transfer[a]=h; transfer[b]=h }
        } }
        let lambda=pow(10,-0.5-2.0*settings.strength)
        var prefiltered=spectrum
        for k in prefiltered.indices {
            let h=transfer[k]
            let inverse=(1+lambda)*h/(h*h+lambda)
            let gain=1+settings.strength*(inverse-1)
            prefiltered[k].r *= gain; prefiltered[k].i *= gain
        }
        transform2D(&prefiltered,size:n,inverse:true)
        var clipped=0
        var displayed=[Double](repeating:0.5,count:n*n)
        var pixels=[Double](repeating:0,count:size*size)
        for y in 0..<size { for x in 0..<size {
            let index=(y+origin)*n+x+origin, value=prefiltered[index].r
            if value < 0 || value > 1 { clipped += 1 }
            let bounded=min(1,max(0,value))
            pixels[y*size+x]=bounded; displayed[index]=bounded
        } }
        var processedSpectrum=displayed.map{Complex(r:$0)}
        transform2D(&processedSpectrum,size:n,inverse:false)
        var originalPrediction=spectrum
        for k in transfer.indices {
            originalPrediction[k].r *= transfer[k]; originalPrediction[k].i *= transfer[k]
            processedSpectrum[k].r *= transfer[k]; processedSpectrum[k].i *= transfer[k]
        }
        transform2D(&originalPrediction,size:n,inverse:true)
        transform2D(&processedSpectrum,size:n,inverse:true)
        func crop(_ image:[Complex]) -> [Double] {
            (0..<size).flatMap { y in (0..<size).map { x in min(1,max(0,image[(y+origin)*n+x+origin].r)) } }
        }
        return Result(pixels:pixels,predictedOriginal:crop(originalPrediction),predictedProcessed:crop(processedSpectrum),
            clippedFraction:Double(clipped)/Double(size*size),maximumBlurRadiusPixels:max(rx,ry))
    }
    private static func transform2D(_ values:inout [Complex],size:Int,inverse:Bool) {
        for y in 0..<size {
            var row=Array(values[y*size..<(y+1)*size]); fft(&row,inverse:inverse)
            values.replaceSubrange(y*size..<(y+1)*size,with:row)
        }
        for x in 0..<size {
            var column=(0..<size).map{values[$0*size+x]}; fft(&column,inverse:inverse)
            for y in 0..<size { values[y*size+x]=column[y] }
        }
    }
    private static func fft(_ values:inout [Complex],inverse:Bool) {
        let n=values.count
        var j=0
        for i in 1..<n {
            var bit=n>>1
            while j & bit != 0 { j ^= bit; bit >>= 1 }
            j ^= bit
            if i < j { values.swapAt(i,j) }
        }
        var length=2
        while length <= n {
            let angle=(inverse ? 2.0 : -2.0) * Double.pi/Double(length)
            let wr=cos(angle),wi=sin(angle)
            for base in stride(from:0,to:n,by:length) {
                var r=1.0,i=0.0
                for offset in 0..<length/2 {
                    let a=values[base+offset],b=values[base+offset+length/2]
                    let br=b.r*r-b.i*i,bi=b.r*i+b.i*r
                    values[base+offset]=Complex(r:a.r+br,i:a.i+bi)
                    values[base+offset+length/2]=Complex(r:a.r-br,i:a.i-bi)
                    let next=r*wr-i*wi; i=r*wi+i*wr; r=next
                }
            }
            length *= 2
        }
        if inverse { for k in values.indices { values[k].r /= Double(n); values[k].i /= Double(n) } }
    }
}
