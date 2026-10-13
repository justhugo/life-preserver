import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let folder = root.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor { NSColor(srgbRed:r, green:g, blue:b, alpha:a) }
func circle(_ radius: CGFloat) -> NSBezierPath { NSBezierPath(ovalIn: NSRect(x: -radius, y: -radius, width: radius*2, height: radius*2)) }
func drawIcon(size: Int, tile: Bool = true) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil, pixelsWide:size, pixelsHigh:size, bitsPerSample:8,
        samplesPerPixel:4, hasAlpha:true, isPlanar:false, colorSpaceName:.deviceRGB, bytesPerRow:0, bitsPerPixel:0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:bitmap)!
    let c = NSGraphicsContext.current!.cgContext
    c.scaleBy(x: CGFloat(size)/1024, y: CGFloat(size)/1024)
    if tile {
        let background = NSBezierPath(roundedRect:NSRect(x:58,y:58,width:908,height:908),xRadius:203,yRadius:203)
        c.saveGState(); c.setShadow(offset:CGSize(width:0,height:-10),blur:22,color:color(0,0,0,0.2).cgColor)
        color(0.92,0.94,0.88).setFill(); background.fill(); c.restoreGState()
        NSGradient(starting:color(0.99,0.985,0.95),ending:color(0.80,0.88,0.83))!.draw(in:background,angle:-65)
        c.saveGState(); background.addClip()
        for i in 0..<5 {
            let y=CGFloat(88+i*30); let p=NSBezierPath(); p.move(to:NSPoint(x:0,y:y))
            p.curve(to:NSPoint(x:1050,y:y+20),controlPoint1:NSPoint(x:340,y:y+100),controlPoint2:NSPoint(x:590,y:y-85))
            p.lineWidth=2; color(0.23,0.40,0.35,0.07).setStroke(); p.stroke()
        }
        c.restoreGState()
    }
    c.translateBy(x:512,y:tile ? 525 : 512)
    let scale: CGFloat = tile ? 42 : 54
    c.scaleBy(x:scale,y:scale)
    // Identical radii, band angles and proportions to the 18-point menu-bar mark.
    c.saveGState(); c.setShadow(offset:CGSize(width:0,height:-0.32),blur:0.38,color:color(0.12,0.22,0.19,0.36).cgColor)
    let rope=circle(8.1); rope.lineWidth=0.30; color(0.69,0.65,0.52).setStroke(); rope.stroke(); c.restoreGState()
    rope.lineWidth=0.13; color(0.96,0.92,0.78).setStroke(); rope.stroke()
    let braid=circle(8.1); braid.lineWidth=0.23; braid.setLineDash([0.035,0.092],count:2,phase:0)
    color(0.46,0.44,0.34,0.35).setStroke(); braid.stroke()
    c.saveGState(); c.setShadow(offset:CGSize(width:0,height:-0.28),blur:0.4,color:color(0.08,0.15,0.12,0.35).cgColor)
    let base=circle(5.5); base.lineWidth=3.7; color(0.83,0.82,0.74).setStroke(); base.stroke(); c.restoreGState()
    // A rounded rubber cross-section, lit from above-left, with warm woven panels.
    for step in 0..<210 {
        let radius=3.65+CGFloat(step)*3.7/209
        let t=(radius-5.5)/1.85
        let bulge=sqrt(max(0,1-t*t))
        for sector in 0..<120 {
            let angle=CGFloat(sector)*3
            let local=(angle+360).truncatingRemainder(dividingBy:90)
            let red=local >= 12 && local < 56
            let directional=cos((angle-125) * .pi / 180)*t*0.10
            let light=0.72+0.26*bulge+directional
            (red ? color(0.90*light,0.34*light,0.25*light) : color(0.995*light,0.98*light,0.90*light)).setStroke()
            let arc=NSBezierPath(); arc.appendArc(withCenter:.zero,radius:radius,startAngle:angle,endAngle:angle+3.15)
            arc.lineWidth=0.040; arc.stroke()
        }
    }
    for i in 0..<4 {
        for angle in [CGFloat(i*90+12), CGFloat(i*90+56)] {
            let a=angle * .pi/180; let seam=NSBezierPath()
            seam.move(to:NSPoint(x:cos(a)*3.76,y:sin(a)*3.76)); seam.line(to:NSPoint(x:cos(a)*7.25,y:sin(a)*7.25))
            seam.lineWidth=0.018; color(0.30,0.13,0.10,0.22).setStroke(); seam.stroke()
            let stitches=NSBezierPath(); let b=a+0.013
            stitches.move(to:NSPoint(x:cos(b)*3.88,y:sin(b)*3.88)); stitches.line(to:NSPoint(x:cos(b)*7.14,y:sin(b)*7.14))
            stitches.lineWidth=0.014; stitches.setLineDash([0.045,0.035],count:2,phase:0)
            color(1,0.85,0.65,0.55).setStroke(); stitches.stroke()
        }
    }
    for radius: CGFloat in [3.66,7.34] { let edge=circle(radius); edge.lineWidth=0.025; color(0.25,0.26,0.21,0.25).setStroke(); edge.stroke() }
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using:.png,properties:[:])!
}
for size in [16,32,128,256,512] {
    try drawIcon(size:size).write(to:folder.appendingPathComponent("icon_\(size)x\(size).png"))
    try drawIcon(size:size*2).write(to:folder.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
try drawIcon(size:1024).write(to:root.appendingPathComponent("AppIcon.png"))
let assets=root.deletingLastPathComponent().appendingPathComponent("Sources/LifePreserver/Assets")
try drawIcon(size:512,tile:false).write(to:assets.appendingPathComponent("Preserver.png"))
print("Created matching application and in-app artwork")
