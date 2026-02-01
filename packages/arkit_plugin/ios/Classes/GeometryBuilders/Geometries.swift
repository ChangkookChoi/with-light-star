import ARKit

func createSphere(_ arguments: [String: Any]) -> SCNSphere {
    let radius = arguments["radius"] as! Double
    return SCNSphere(radius: CGFloat(radius))
}

func createPlane(_ arguments: [String: Any]) -> SCNPlane {
    let width = arguments["width"] as! Double
    let height = arguments["height"] as! Double
    let widthSegmentCount = arguments["widthSegmentCount"] as! Int
    let heightSegmentCount = arguments["heightSegmentCount"] as! Int

    let plane = SCNPlane(width: CGFloat(width), height: CGFloat(height))
    plane.widthSegmentCount = widthSegmentCount
    plane.heightSegmentCount = heightSegmentCount
    return plane
}

// [수정됨] 폰트(fontName)와 모서리 둥글기(chamferRadius) 기능 추가
func createText(_ arguments: [String: Any]) -> SCNText {
    let extrusionDepth = arguments["extrusionDepth"] as! Double
    let text = arguments["text"]
    
    // 기본 텍스트 생성
    let scnText = SCNText(string: text, extrusionDepth: CGFloat(extrusionDepth))
    
    // 1. 모서리 둥글기 적용 (값이 있는 경우에만)
    if let chamferRadius = arguments["chamferRadius"] as? Double {
        scnText.chamferRadius = CGFloat(chamferRadius)
    }
    
    // 2. 폰트 적용 (값이 있는 경우에만)
    if let fontName = arguments["fontName"] as? String {
        // 사이즈는 Node Scale로 조절하므로 기본 1.0으로 설정
        if let font = UIFont(name: fontName, size: 1.0) {
            scnText.font = font
        }
    }
    
    return scnText
}

func createBox(_ arguments: [String: Any]) -> SCNBox {
    let width = arguments["width"] as! Double
    let height = arguments["height"] as! Double
    let length = arguments["length"] as! Double
    let chamferRadius = arguments["chamferRadius"] as! Double

    return SCNBox(width: CGFloat(width), height: CGFloat(height), length: CGFloat(length), chamferRadius: CGFloat(chamferRadius))
}

func createLine(_ arguments: [String: Any]) -> SCNGeometry {
    // 원본 라이브러리의 오타(deserizlieVector3)를 그대로 유지합니다.
    let fromVector = deserizlieVector3(arguments["fromVector"] as! [Double])
    let toVector = deserizlieVector3(arguments["toVector"] as! [Double])
    let source = SCNGeometrySource(vertices: [fromVector, toVector])

    let indices: [UInt8] = [0, 1]
    let element = SCNGeometryElement(indices: indices, primitiveType: .line)

    return SCNGeometry(sources: [source], elements: [element])
}

func createCylinder(_ arguments: [String: Any]) -> SCNCylinder {
    let radius = arguments["radius"] as! Double
    let height = arguments["height"] as! Double
    return SCNCylinder(radius: CGFloat(radius), height: CGFloat(height))
}

func createCone(_ arguments: [String: Any]) -> SCNCone {
    let topRadius = arguments["topRadius"] as! Double
    let bottomRadius = arguments["bottomRadius"] as! Double
    let height = arguments["height"] as! Double
    return SCNCone(topRadius: CGFloat(topRadius), bottomRadius: CGFloat(bottomRadius), height: CGFloat(height))
}

func createPyramid(_ arguments: [String: Any]) -> SCNPyramid {
    let width = arguments["width"] as! Double
    let height = arguments["height"] as! Double
    let length = arguments["length"] as! Double
    return SCNPyramid(width: CGFloat(width), height: CGFloat(height), length: CGFloat(length))
}

func createTube(_ arguments: [String: Any]) -> SCNTube {
    let innerRadius = arguments["innerRadius"] as! Double
    let outerRadius = arguments["outerRadius"] as! Double
    let height = arguments["height"] as! Double
    return SCNTube(innerRadius: CGFloat(innerRadius), outerRadius: CGFloat(outerRadius), height: CGFloat(height))
}

func createTorus(_ arguments: [String: Any]) -> SCNTorus {
    let ringRadius = arguments["ringRadius"] as! Double
    let pipeRadius = arguments["pipeRadius"] as! Double
    return SCNTorus(ringRadius: CGFloat(ringRadius), pipeRadius: CGFloat(pipeRadius))
}

func createCapsule(_ arguments: [String: Any]) -> SCNCapsule {
    let capRadius = arguments["capRadius"] as! Double
    let height = arguments["height"] as! Double
    return SCNCapsule(capRadius: CGFloat(capRadius), height: CGFloat(height))
}

#if !DISABLE_TRUEDEPTH_API
    func createFace(_ device: MTLDevice?) -> ARSCNFaceGeometry {
        return ARSCNFaceGeometry(device: device!)!
    }
#endif