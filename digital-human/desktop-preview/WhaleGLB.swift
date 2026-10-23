import AppKit
import SceneKit
import simd

// Deliberately limited to our bundled Blender export: embedded buffers, triangle meshes,
// float attributes, one skin per mesh and linear/step skeletal animation.
final class WhaleGLB {
    enum LoadError: Error { case invalid(String) }
    struct Track {
        let node: SCNNode
        let path: String
        let times: [Float]
        let values: [Float]
        let width: Int
        let step: Bool
        func apply(_ time: Float) {
            guard !times.isEmpty else { return }
            var lo = 0, hi = times.count - 1
            while lo < hi { let mid = (lo + hi + 1) / 2; if times[mid] <= time { lo = mid } else { hi = mid - 1 } }
            let next = min(lo+1,times.count-1)
            let span = times[next]-times[lo]
            let t: Float = step || span <= 0 ? 0 : max(0,min(1,(time-times[lo])/span))
            let a = lo*width, b = next*width
            if path == "rotation" {
                let qa = simd_quatf(ix:values[a],iy:values[a+1],iz:values[a+2],r:values[a+3])
                let qb = simd_quatf(ix:values[b],iy:values[b+1],iz:values[b+2],r:values[b+3])
                node.simdOrientation = simd_slerp(qa,qb,t)
            } else {
                let v = SIMD3<Float>(values[a],values[a+1],values[a+2])*(1-t) + SIMD3<Float>(values[b],values[b+1],values[b+2])*t
                if path == "translation" { node.simdPosition = v }
                if path == "scale" { node.simdScale = v }
            }
        }
    }
    let scene = SCNScene()
    var nodes: [SCNNode] = []
    var clips: [String:[Track]] = [:]
    var rest: [simd_float4x4] = []
    private var doc: [String:Any] = [:]
    private var buffer = Data()
    private var accessors: [[String:Any]] = []
    private var views: [[String:Any]] = []
    private var images: [Int:NSImage] = [:]
    private var materials: [SCNMaterial] = []

    init(url: URL) throws {
        let raw = try Data(contentsOf:url,options:.mappedIfSafe)
        func u32(_ offset: Int) -> UInt32 { raw.withUnsafeBytes { $0.loadUnaligned(fromByteOffset:offset,as:UInt32.self).littleEndian } }
        guard raw.count >= 20, u32(0) == 0x46546c67, u32(4) == 2, Int(u32(8)) == raw.count else { throw LoadError.invalid("GLB header") }
        var offset = 12
        while offset+8 <= raw.count {
            let size = Int(u32(offset)), kind = u32(offset+4); offset += 8
            guard size >= 0, offset+size <= raw.count else { throw LoadError.invalid("GLB chunk") }
            let data = raw.subdata(in:offset..<offset+size)
            if kind == 0x4e4f534a { doc = try JSONSerialization.jsonObject(with:data) as? [String:Any] ?? [:] }
            if kind == 0x004e4942 { buffer = data }
            offset += size
        }
        accessors = doc["accessors"] as? [[String:Any]] ?? []
        views = doc["bufferViews"] as? [[String:Any]] ?? []
        try loadMaterials()
        let descriptions = doc["nodes"] as? [[String:Any]] ?? []
        nodes = descriptions.map { _ in SCNNode() }
        for (i,d) in descriptions.enumerated() {
            let node = nodes[i]; node.name = d["name"] as? String
            if let m = d["matrix"] as? [Float], m.count == 16 { node.simdTransform = matrix(m) }
            else {
                if let p = d["translation"] as? [Float], p.count == 3 { node.simdPosition = SIMD3(p[0],p[1],p[2]) }
                if let q = d["rotation"] as? [Float], q.count == 4 { node.simdOrientation = simd_quatf(ix:q[0],iy:q[1],iz:q[2],r:q[3]) }
                if let s = d["scale"] as? [Float], s.count == 3 { node.simdScale = SIMD3(s[0],s[1],s[2]) }
            }
            for child in d["children"] as? [Int] ?? [] { guard nodes.indices.contains(child) else { throw LoadError.invalid("Child index") }; node.addChildNode(nodes[child]) }
        }
        for node in nodes where node.parent == nil { scene.rootNode.addChildNode(node) }
        rest = nodes.map(\.simdTransform)
        let meshes = doc["meshes"] as? [[String:Any]] ?? []
        let skins = doc["skins"] as? [[String:Any]] ?? []
        for (i,d) in descriptions.enumerated() {
            guard let m = d["mesh"] as? Int, meshes.indices.contains(m) else { continue }
            let primitives = meshes[m]["primitives"] as? [[String:Any]] ?? []
            for primitive in primitives {
                guard (primitive["mode"] as? Int ?? 4) == 4,
                      let attributes = primitive["attributes"] as? [String:Int], let position = attributes["POSITION"],
                      let indices = primitive["indices"] as? Int else { throw LoadError.invalid("Triangle geometry") }
                var sources = [try source(position,.vertex)]
                if let a = attributes["NORMAL"] { sources.append(try source(a,.normal)) }
                if let a = attributes["TEXCOORD_0"] { sources.append(try source(a,.texcoord)) }
                let index = try packed(indices)
                let element = SCNGeometryElement(data:index.data,primitiveType:.triangles,primitiveCount:index.count/3,bytesPerIndex:index.bytes)
                let geometry = SCNGeometry(sources:sources,elements:[element])
                if let material = primitive["material"] as? Int, materials.indices.contains(material) { geometry.materials = [materials[material]] }
                let meshNode = SCNNode(geometry:geometry); nodes[i].addChildNode(meshNode)
                if let skinIndex = d["skin"] as? Int, skins.indices.contains(skinIndex),
                   let joints = skins[skinIndex]["joints"] as? [Int], let bind = skins[skinIndex]["inverseBindMatrices"] as? Int,
                   let weights = attributes["WEIGHTS_0"], let boneIndices = attributes["JOINTS_0"] {
                    guard joints.allSatisfy({nodes.indices.contains($0)}) else { throw LoadError.invalid("Skin joints") }
                    let inverse = try floats(bind)
                    guard inverse.count == joints.count*16 else { throw LoadError.invalid("Bind matrices") }
                    let transforms = joints.indices.map { NSValue(scnMatrix4:SCNMatrix4(matrix(Array(inverse[$0*16..<$0*16+16])))) }
                    meshNode.skinner = SCNSkinner(baseGeometry:geometry,bones:joints.map{nodes[$0]},boneInverseBindTransforms:transforms,
                        boneWeights:try source(weights,.boneWeights),boneIndices:try source(boneIndices,.boneIndices))
                }
                // Additive SceneKit targets and glTF morphs both store position deltas.
                if let targets = primitive["targets"] as? [[String:Int]], !targets.isEmpty {
                    let basis = try floats(position)
                    let morpher = SCNMorpher(); morpher.calculationMode = .additive
                    let names = (meshes[m]["extras"] as? [String:Any])?["targetNames"] as? [String] ?? []
                    for (j,target) in targets.enumerated() {
                        guard let p = target["POSITION"] else { throw LoadError.invalid("Morph position") }
                        let delta = try floats(p)
                        guard delta.count == basis.count else { throw LoadError.invalid("Morph size") }
                        let data = delta.withUnsafeBytes { Data($0) }
                        let s = SCNGeometrySource(data:data,semantic:.vertex,vectorCount:delta.count/3,usesFloatComponents:true,componentsPerVector:3,bytesPerComponent:4,dataOffset:0,dataStride:12)
                        var targetSources = [s]
                        if let normal = target["NORMAL"] { targetSources.append(try source(normal,.normal)) }
                        let targetGeometry = SCNGeometry(sources:targetSources,elements:[element]); targetGeometry.name = j < names.count ? names[j] : "Morph\(j)"
                        morpher.targets.append(targetGeometry)
                    }
                    meshNode.morpher = morpher
                }
            }
        }
        for animation in doc["animations"] as? [[String:Any]] ?? [] {
            guard let name = animation["name"] as? String else { continue }
            let samplers = animation["samplers"] as? [[String:Any]] ?? []
            var tracks: [Track] = []
            for channel in animation["channels"] as? [[String:Any]] ?? [] {
                guard let s = channel["sampler"] as? Int, samplers.indices.contains(s),
                      let target = channel["target"] as? [String:Any], let n = target["node"] as? Int, nodes.indices.contains(n),
                      let path = target["path"] as? String, ["translation","rotation","scale"].contains(path),
                      let input = samplers[s]["input"] as? Int, let output = samplers[s]["output"] as? Int else { throw LoadError.invalid("Animation channel") }
                let interpolation = samplers[s]["interpolation"] as? String ?? "LINEAR"
                guard ["LINEAR","STEP"].contains(interpolation) else { throw LoadError.invalid("Interpolation") }
                let times = try floats(input), values = try floats(output), width = path == "rotation" ? 4 : 3
                guard !times.isEmpty, values.count == times.count*width else { throw LoadError.invalid("Animation samples") }
                tracks.append(Track(node:nodes[n],path:path,times:times,values:values,width:width,step:interpolation == "STEP"))
            }
            clips[name] = tracks
        }
        guard nodes.count > 0, clips["Wave"] != nil, clips["Turn_360"] != nil else { throw LoadError.invalid("Missing character clips") }
        // Geometry sources own their data after decoding.
        buffer = Data(); doc = [:]; accessors = []; views = []
    }

    private func matrix(_ a: [Float]) -> simd_float4x4 {
        simd_float4x4(columns:(SIMD4(a[0],a[1],a[2],a[3]),SIMD4(a[4],a[5],a[6],a[7]),SIMD4(a[8],a[9],a[10],a[11]),SIMD4(a[12],a[13],a[14],a[15])))
    }
    private func packed(_ index: Int) throws -> (data:Data,count:Int,width:Int,bytes:Int,float:Bool) {
        guard accessors.indices.contains(index) else { throw LoadError.invalid("Accessor index") }
        let a = accessors[index]
        guard a["sparse"] == nil, let v = a["bufferView"] as? Int, views.indices.contains(v),
              let count = a["count"] as? Int, let type = a["type"] as? String, let component = a["componentType"] as? Int,
              let width = ["SCALAR":1,"VEC2":2,"VEC3":3,"VEC4":4,"MAT4":16][type],
              let bytes = [5121:1,5123:2,5125:4,5126:4][component] else { throw LoadError.invalid("Accessor format") }
        let view = views[v], size = width*bytes
        let start = (view["byteOffset"] as? Int ?? 0)+(a["byteOffset"] as? Int ?? 0)
        let stride = view["byteStride"] as? Int ?? size
        guard count > 0, stride >= size, start >= 0, start+(count-1)*stride+size <= buffer.count else { throw LoadError.invalid("Accessor bounds") }
        if stride == size { return (buffer.subdata(in:start..<start+count*size),count,width,bytes,component == 5126) }
        var data = Data(capacity:count*size)
        for row in 0..<count { data.append(buffer.subdata(in:start+row*stride..<start+row*stride+size)) }
        return (data,count,width,bytes,component == 5126)
    }
    private func source(_ index: Int, _ semantic: SCNGeometrySource.Semantic) throws -> SCNGeometrySource {
        let a = try packed(index)
        return SCNGeometrySource(data:a.data,semantic:semantic,vectorCount:a.count,usesFloatComponents:a.float,componentsPerVector:a.width,bytesPerComponent:a.bytes,dataOffset:0,dataStride:a.width*a.bytes)
    }
    private func floats(_ index: Int) throws -> [Float] {
        let a = try packed(index)
        guard a.float else { throw LoadError.invalid("Expected float") }
        return a.data.withUnsafeBytes { raw in (0..<a.count*a.width).map { raw.loadUnaligned(fromByteOffset:$0*4,as:Float.self) } }
    }
    private func texture(_ index: Int) throws -> NSImage {
        let textures = doc["textures"] as? [[String:Any]] ?? [], descriptions = doc["images"] as? [[String:Any]] ?? []
        guard textures.indices.contains(index), let id = textures[index]["source"] as? Int, descriptions.indices.contains(id) else { throw LoadError.invalid("Texture index") }
        if let cached = images[id] { return cached }
        guard let v = descriptions[id]["bufferView"] as? Int, views.indices.contains(v), let length = views[v]["byteLength"] as? Int else { throw LoadError.invalid("Embedded texture") }
        let start = views[v]["byteOffset"] as? Int ?? 0
        guard start >= 0, length > 0, start+length <= buffer.count,
              let image = NSImage(data:buffer.subdata(in:start..<start+length)) else { throw LoadError.invalid("Texture data") }
        images[id] = image; return image
    }
    private func loadMaterials() throws {
        for description in doc["materials"] as? [[String:Any]] ?? [] {
            let material = SCNMaterial(); material.name = description["name"] as? String
            material.lightingModel = .physicallyBased; material.isDoubleSided = description["doubleSided"] as? Bool ?? false
            let pbr = description["pbrMetallicRoughness"] as? [String:Any] ?? [:]
            if let i = (pbr["baseColorTexture"] as? [String:Any])?["index"] as? Int { material.diffuse.contents = try texture(i) }
            if let i = (description["normalTexture"] as? [String:Any])?["index"] as? Int { material.normal.contents = try texture(i) }
            if let i = (pbr["metallicRoughnessTexture"] as? [String:Any])?["index"] as? Int {
                let image = try texture(i)
                material.metalness.contents = image; material.metalness.textureComponents = .blue
                material.roughness.contents = image; material.roughness.textureComponents = .green
            } else { material.metalness.contents = pbr["metallicFactor"] as? Double ?? 1; material.roughness.contents = pbr["roughnessFactor"] as? Double ?? 1 }
            materials.append(material)
        }
    }
    func apply(_ clip: String, time: TimeInterval, loop: Bool = true) {
        for (i,node) in nodes.enumerated() { node.simdTransform = rest[i] }
        guard let tracks = clips[clip] else { return }
        let duration = tracks.compactMap { $0.times.last }.max() ?? 0
        let t = duration <= 0 ? Float(0) : loop ? Float(max(0,time)).truncatingRemainder(dividingBy:duration) : min(duration,Float(max(0,time)))
        for track in tracks { track.apply(t) }
    }
    func morph(_ name: String, value: Double) {
        scene.rootNode.enumerateChildNodes { node,_ in
            guard let morpher = node.morpher else { return }
            for (i,target) in morpher.targets.enumerated() where target.name == name { morpher.setWeight(CGFloat(max(0,min(1,value))),forTargetAt:i) }
        }
    }
}
