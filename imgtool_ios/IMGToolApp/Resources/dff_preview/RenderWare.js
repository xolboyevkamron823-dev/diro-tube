/**
 * RenderWare DFF & TXD Binary Stream Parser & Serializer for GTA San Andreas (RW 3.6 / 3.4).
 * Developed for Diro 3D Studio (ZModeler iOS).
 */

const RW_CHUNKS = {
    STRUCT: 0x0001,
    STRING: 0x0002,
    EXTENSION: 0x0003,
    TEXTURE: 0x0006,
    MATERIAL: 0x0007,
    MATERIALLIST: 0x0008,
    ATOMICSECTION: 0x0009,
    FRAMELIST: 0x000E,
    GEOMETRY: 0x000F,
    CLUMP: 0x0010,
    LIGHT: 0x0012,
    ATOMIC: 0x0014,
    TEXTURENATIVE: 0x0015,
    TEXDICTIONARY: 0x0016,
    GEOMETRYLIST: 0x001A,
    EFFECT2D: 0x001F,
    RIGHTTORENDER: 0x0025,
    HANIM: 0x0116,
    USERDATA: 0x011E,
    MATFX: 0x0120,
    BINMESH: 0x050E,
    FRAMENAME: 0x0253F2FE,
    COLLISION: 0x0253F2FE
};

class BinaryReader {
    constructor(buffer) {
        if (buffer instanceof ArrayBuffer) {
            this.buffer = buffer;
            this.view = new DataView(buffer);
        } else if (buffer.buffer instanceof ArrayBuffer) {
            this.buffer = buffer.buffer;
            this.view = new DataView(buffer.buffer, buffer.byteOffset, buffer.byteLength);
        } else {
            throw new Error("Invalid buffer type");
        }
        this.offset = 0;
        this.length = this.view.byteLength;
    }

    readUint8() {
        const val = this.view.getUint8(this.offset);
        this.offset += 1;
        return val;
    }

    readInt8() {
        const val = this.view.getInt8(this.offset);
        this.offset += 1;
        return val;
    }

    readUint16() {
        const val = this.view.getUint16(this.offset, true);
        this.offset += 2;
        return val;
    }

    readInt16() {
        const val = this.view.getInt16(this.offset, true);
        this.offset += 2;
        return val;
    }

    readUint32() {
        const val = this.view.getUint32(this.offset, true);
        this.offset += 4;
        return val;
    }

    readInt32() {
        const val = this.view.getInt32(this.offset, true);
        this.offset += 4;
        return val;
    }

    readFloat32() {
        const val = this.view.getFloat32(this.offset, true);
        this.offset += 4;
        return val;
    }

    readString(length) {
        let str = "";
        for (let i = 0; i < length; i++) {
            const code = this.view.getUint8(this.offset + i);
            if (code === 0) break;
            str += String.fromCharCode(code);
        }
        this.offset += length;
        return str;
    }

    readBytes(length) {
        const slice = new Uint8Array(this.view.buffer, this.view.byteOffset + this.offset, length);
        this.offset += length;
        return new Uint8Array(slice);
    }

    readHeader() {
        if (this.offset + 12 > this.length) return null;
        const type = this.readUint32();
        const size = this.readUint32();
        const libId = this.readUint32();
        return { type, size, libId, payloadStart: this.offset, payloadEnd: this.offset + size };
    }

    skip(bytes) {
        this.offset += bytes;
    }

    seek(pos) {
        this.offset = pos;
    }
}

class BinaryWriter {
    constructor(initialSize = 1024 * 1024) {
        this.buffer = new Uint8Array(initialSize);
        this.view = new DataView(this.buffer.buffer);
        this.offset = 0;
    }

    ensureCapacity(additionalBytes) {
        if (this.offset + additionalBytes > this.buffer.length) {
            let newSize = Math.max(this.buffer.length * 2, this.offset + additionalBytes + 65536);
            const newBuf = new Uint8Array(newSize);
            newBuf.set(this.buffer);
            this.buffer = newBuf;
            this.view = new DataView(this.buffer.buffer);
        }
    }

    writeUint8(val) {
        this.ensureCapacity(1);
        this.view.setUint8(this.offset, val);
        this.offset += 1;
    }

    writeInt8(val) {
        this.ensureCapacity(1);
        this.view.setInt8(this.offset, val);
        this.offset += 1;
    }

    writeUint16(val) {
        this.ensureCapacity(2);
        this.view.setUint16(this.offset, val, true);
        this.offset += 2;
    }

    writeInt16(val) {
        this.ensureCapacity(2);
        this.view.setInt16(this.offset, val, true);
        this.offset += 2;
    }

    writeUint32(val) {
        this.ensureCapacity(4);
        this.view.setUint32(this.offset, val, true);
        this.offset += 4;
    }

    writeInt32(val) {
        this.ensureCapacity(4);
        this.view.setInt32(this.offset, val, true);
        this.offset += 4;
    }

    writeFloat32(val) {
        this.ensureCapacity(4);
        this.view.setFloat32(this.offset, val, true);
        this.offset += 4;
    }

    writeBytes(bytes) {
        this.ensureCapacity(bytes.length);
        this.buffer.set(bytes, this.offset);
        this.offset += bytes.length;
    }

    writeString(str, fixedLength = null) {
        const len = fixedLength !== null ? fixedLength : str.length + 1;
        this.ensureCapacity(len);
        for (let i = 0; i < len; i++) {
            if (i < str.length) {
                this.view.setUint8(this.offset + i, str.charCodeAt(i));
            } else {
                this.view.setUint8(this.offset + i, 0);
            }
        }
        this.offset += len;
    }

    writeHeader(type, size, libId = 0x1803ffff) {
        this.writeUint32(type);
        this.writeUint32(size);
        this.writeUint32(libId);
    }

    getBuffer() {
        return this.buffer.slice(0, this.offset);
    }
}

class DFFModel {
    /**
     * Unpacks RenderWare BinMeshPLG indices handling both triangle strips (flags & 1)
     * and triangle lists (flags == 0), safely skipping degenerate connector triangles.
     */
    static unpackBinMesh(binMesh) {
        if (!binMesh || !binMesh.meshes) return [];
        const isStrip = (binMesh.flags & 1) !== 0;
        const result = [];

        for (const mesh of binMesh.meshes) {
            const raw = mesh.indices;
            const triList = [];
            if (isStrip) {
                for (let k = 0; k < raw.length - 2; k++) {
                    const a = raw[k];
                    const b = (k % 2 === 0) ? raw[k + 1] : raw[k + 2];
                    const c = (k % 2 === 0) ? raw[k + 2] : raw[k + 1];
                    // Skip degenerate connector triangles (used in hardware tristrips)
                    if (a === b || b === c || a === c) continue;
                    triList.push(a, b, c);
                }
            } else {
                for (let k = 0; k < raw.length; k++) {
                    triList.push(raw[k]);
                }
            }
            result.push({
                matIndex: mesh.matIndex,
                indices: triList
            });
        }
        return result;
    }

    /**
     * Retrieves all triangle triplets for a geometry, grouped by material index.
     * Compatible with both BinMesh and legacy geometry triangle chunks.
     */
    static getGeometryTriangles(geom) {
        if (geom.binMesh && geom.binMesh.meshes && geom.binMesh.meshes.length > 0) {
            return DFFModel.unpackBinMesh(geom.binMesh);
        }

        if (geom.triangles && geom.triangles.length > 0) {
            const groups = {};
            for (const t of geom.triangles) {
                const m = t.matIndex || 0;
                if (!groups[m]) groups[m] = [];
                groups[m].push(t.v1, t.v2, t.v3);
            }
            const result = [];
            for (const m in groups) {
                result.push({
                    matIndex: parseInt(m),
                    indices: groups[m]
                });
            }
            return result;
        }

        return [];
    }

    constructor() {
        this.version = 0x1803ffff;
        this.frames = [];
        this.geometries = [];
        this.atomics = [];
        this.clumpExtensions = [];
    }

    parse(arrayBuffer) {
        const reader = new BinaryReader(arrayBuffer);
        const rootHeader = reader.readHeader();
        if (!rootHeader || rootHeader.type !== RW_CHUNKS.CLUMP) {
            throw new Error("Fayl RenderWare Clump (DFF) emas!");
        }
        this.version = rootHeader.libId;

        while (reader.offset < rootHeader.payloadEnd) {
            const h = reader.readHeader();
            if (!h) break;

            if (h.type === RW_CHUNKS.STRUCT) {
                const numAtomics = reader.readUint32();
                const numLights = (h.size >= 8) ? reader.readUint32() : 0;
                const numCameras = (h.size >= 12) ? reader.readUint32() : 0;
                reader.seek(h.payloadEnd);
            } else if (h.type === RW_CHUNKS.FRAMELIST) {
                this.parseFrameList(reader, h);
            } else if (h.type === RW_CHUNKS.GEOMETRYLIST) {
                this.parseGeometryList(reader, h);
            } else if (h.type === RW_CHUNKS.ATOMIC) {
                this.parseAtomic(reader, h);
            } else if (h.type === RW_CHUNKS.EXTENSION) {
                this.clumpExtensions.push(reader.readBytes(h.size));
            } else {
                reader.skip(h.size);
            }
        }
    }

    parseFrameList(reader, frameListHeader) {
        const end = frameListHeader.payloadEnd;
        const structHeader = reader.readHeader();
        if (structHeader.type !== RW_CHUNKS.STRUCT) {
            throw new Error("FrameList ichida Struct topilmadi!");
        }

        const numFrames = reader.readUint32();
        this.frames = [];

        for (let i = 0; i < numFrames; i++) {
            const rot = [
                reader.readFloat32(), reader.readFloat32(), reader.readFloat32(),
                reader.readFloat32(), reader.readFloat32(), reader.readFloat32(),
                reader.readFloat32(), reader.readFloat32(), reader.readFloat32()
            ];
            const pos = [
                reader.readFloat32(),
                reader.readFloat32(),
                reader.readFloat32()
            ];
            const parentIndex = reader.readInt32();
            const matrixFlags = reader.readUint32();

            this.frames.push({
                index: i,
                name: `Frame_${i}`,
                rot: rot,
                pos: pos,
                parentIndex: parentIndex,
                matrixFlags: matrixFlags,
                extensions: []
            });
        }

        for (let i = 0; i < numFrames; i++) {
            if (reader.offset >= end) break;
            const extHeader = reader.readHeader();
            if (!extHeader || extHeader.type !== RW_CHUNKS.EXTENSION) break;

            const extEnd = extHeader.payloadEnd;
            while (reader.offset < extEnd) {
                const subHeader = reader.readHeader();
                if (!subHeader) break;

                if (subHeader.type === RW_CHUNKS.FRAMENAME || subHeader.type === RW_CHUNKS.USERDATA) {
                    const rawName = reader.readString(subHeader.size);
                    if (rawName && rawName.length > 0) {
                        this.frames[i].name = rawName;
                    }
                } else {
                    const extraData = reader.readBytes(subHeader.size);
                    this.frames[i].extensions.push({
                        type: subHeader.type,
                        libId: subHeader.libId,
                        data: extraData
                    });
                }
            }
            reader.seek(extEnd);
        }
        reader.seek(end);
    }

    parseGeometryList(reader, geomListHeader) {
        const end = geomListHeader.payloadEnd;
        const structHeader = reader.readHeader();
        const numGeoms = reader.readUint32();
        this.geometries = [];

        while (reader.offset < end) {
            const h = reader.readHeader();
            if (!h) break;

            if (h.type === RW_CHUNKS.GEOMETRY) {
                this.geometries.push(this.parseGeometry(reader, h));
            } else {
                reader.skip(h.size);
            }
        }
        reader.seek(end);
    }

    parseGeometry(reader, geomHeader) {
        const end = geomHeader.payloadEnd;
        const structHeader = reader.readHeader();

        const formatFlags = reader.readUint32();
        const numTriangles = reader.readUint32();
        const numVertices = reader.readUint32();
        const numMorphTargets = reader.readUint32();

        const hasPrelit = (formatFlags & 0x0008) !== 0;
        const hasTexCoords = (formatFlags & 0x0004) !== 0;
        const hasNormals = (formatFlags & 0x0010) !== 0;

        let numTexCoordSets = (formatFlags >> 16) & 0xFF;
        if (numTexCoordSets === 0 && hasTexCoords) {
            numTexCoordSets = 1;
        }

        let colors = [];
        if (hasPrelit) {
            for (let i = 0; i < numVertices; i++) {
                colors.push({
                    r: reader.readUint8(),
                    g: reader.readUint8(),
                    b: reader.readUint8(),
                    a: reader.readUint8()
                });
            }
        }

        let texCoordSets = [];
        for (let s = 0; s < numTexCoordSets; s++) {
            let set = [];
            for (let i = 0; i < numVertices; i++) {
                set.push({
                    u: reader.readFloat32(),
                    v: reader.readFloat32()
                });
            }
            texCoordSets.push(set);
        }

        let triangles = [];
        for (let i = 0; i < numTriangles; i++) {
            const v2 = reader.readUint16();
            const v1 = reader.readUint16();
            const matIndex = reader.readUint16();
            const v3 = reader.readUint16();
            triangles.push({ v1, v2, v3, matIndex });
        }

        const sphere = {
            x: reader.readFloat32(),
            y: reader.readFloat32(),
            z: reader.readFloat32(),
            radius: reader.readFloat32()
        };
        const hasVerts = reader.readUint32();
        const hasNorms = reader.readUint32();

        let vertices = [];
        if (hasVerts) {
            for (let i = 0; i < numVertices; i++) {
                vertices.push({
                    x: reader.readFloat32(),
                    y: reader.readFloat32(),
                    z: reader.readFloat32()
                });
            }
        }

        let normals = [];
        if (hasNorms) {
            for (let i = 0; i < numVertices; i++) {
                normals.push({
                    x: reader.readFloat32(),
                    y: reader.readFloat32(),
                    z: reader.readFloat32()
                });
            }
        }

        reader.seek(structHeader.payloadEnd);

        let materials = [];
        const matListHeader = reader.readHeader();
        if (matListHeader && matListHeader.type === RW_CHUNKS.MATERIALLIST) {
            const matStructHeader = reader.readHeader();
            const numMaterials = reader.readUint32();
            reader.skip(numMaterials * 4);

            for (let i = 0; i < numMaterials; i++) {
                const matH = reader.readHeader();
                if (!matH || matH.type !== RW_CHUNKS.MATERIAL) break;
                const matStruct = reader.readHeader();
                const flags = reader.readUint32();
                const color = {
                    r: reader.readUint8(),
                    g: reader.readUint8(),
                    b: reader.readUint8(),
                    a: reader.readUint8()
                };
                reader.readUint32();
                const hasTexture = reader.readInt32();
                const ambient = reader.readFloat32();
                const specular = reader.readFloat32();
                const diffuse = reader.readFloat32();

                reader.seek(matStruct.payloadEnd);

                let textureName = "";
                let maskName = "";

                if (hasTexture) {
                    const texH = reader.readHeader();
                    if (texH && texH.type === RW_CHUNKS.TEXTURE) {
                        const texStruct = reader.readHeader();
                        reader.seek(texStruct.payloadEnd);

                        const nameH = reader.readHeader();
                        if (nameH && nameH.type === RW_CHUNKS.STRING) {
                            textureName = reader.readString(nameH.size);
                        }

                        const maskH = reader.readHeader();
                        if (maskH && maskH.type === RW_CHUNKS.STRING) {
                            maskName = reader.readString(maskH.size);
                        }
                        reader.seek(texH.payloadEnd);
                    }
                }

                const matExt = reader.readHeader();
                if (matExt && matExt.type === RW_CHUNKS.EXTENSION) {
                    reader.seek(matExt.payloadEnd);
                }

                materials.push({
                    color,
                    hasTexture,
                    textureName,
                    maskName,
                    ambient,
                    specular,
                    diffuse
                });
            }
            reader.seek(matListHeader.payloadEnd);
        }

        let binMesh = null;
        let extensions = [];
        const geomExtH = reader.readHeader();
        if (geomExtH && geomExtH.type === RW_CHUNKS.EXTENSION) {
            const extEnd = geomExtH.payloadEnd;
            while (reader.offset < extEnd) {
                const subH = reader.readHeader();
                if (!subH) break;

                if (subH.type === RW_CHUNKS.BINMESH) {
                    const flags = reader.readUint32();
                    const numMeshes = reader.readUint32();
                    const totalIndices = reader.readUint32();
                    let meshes = [];
                    for (let m = 0; m < numMeshes; m++) {
                        const numIndices = reader.readUint32();
                        const matIndex = reader.readUint32();
                        let indices = [];
                        for (let idx = 0; idx < numIndices; idx++) {
                            indices.push(reader.readUint32());
                        }
                        meshes.push({ matIndex, indices });
                    }
                    binMesh = { flags, numMeshes, totalIndices, meshes };
                } else {
                    extensions.push({
                        type: subH.type,
                        libId: subH.libId,
                        data: reader.readBytes(subH.size)
                    });
                }
            }
            reader.seek(extEnd);
        }

        reader.seek(end);

        return {
            formatFlags,
            numTexCoordSets,
            numTriangles,
            numVertices,
            colors,
            texCoordSets,
            triangles,
            sphere,
            vertices,
            normals,
            materials,
            binMesh,
            extensions
        };
    }

    parseAtomic(reader, atomicHeader) {
        const end = atomicHeader.payloadEnd;
        const structHeader = reader.readHeader();
        const frameIndex = reader.readUint32();
        const geometryIndex = reader.readUint32();
        const flags = reader.readUint32();
        const unused = reader.readUint32();
        reader.seek(structHeader.payloadEnd);

        let extensions = [];
        const extH = reader.readHeader();
        if (extH && extH.type === RW_CHUNKS.EXTENSION) {
            extensions.push(reader.readBytes(extH.size));
            reader.seek(extH.payloadEnd);
        }

        this.atomics.push({
            frameIndex,
            geometryIndex,
            flags,
            unused,
            extensions
        });

        reader.seek(end);
    }

    mergeModel(otherDff, targetParentIndex = 0) {
        const baseFrameIndex = this.frames.length;
        const baseGeomIndex = this.geometries.length;

        for (let i = 0; i < otherDff.frames.length; i++) {
            const f = JSON.parse(JSON.stringify(otherDff.frames[i]));
            f.index = baseFrameIndex + i;
            if (f.parentIndex < 0) {
                f.parentIndex = targetParentIndex;
            } else {
                f.parentIndex = baseFrameIndex + f.parentIndex;
            }
            this.frames.push(f);
        }

        for (let i = 0; i < otherDff.geometries.length; i++) {
            const g = JSON.parse(JSON.stringify(otherDff.geometries[i]));
            this.geometries.push(g);
        }

        for (let i = 0; i < otherDff.atomics.length; i++) {
            const a = JSON.parse(JSON.stringify(otherDff.atomics[i]));
            a.frameIndex = baseFrameIndex + a.frameIndex;
            a.geometryIndex = baseGeomIndex + a.geometryIndex;
            this.atomics.push(a);
        }
    }

    serialize() {
        const writer = new BinaryWriter();
        const libId = this.version;

        const frameListBuf = this.serializeFrameList(libId);
        const geomListBuf = this.serializeGeometryList(libId);
        const atomicsBuf = this.serializeAtomics(libId);

        const clumpStructBuf = new BinaryWriter();
        clumpStructBuf.writeUint32(this.atomics.length);
        clumpStructBuf.writeUint32(0);
        clumpStructBuf.writeUint32(0);
        const clumpStructBytes = clumpStructBuf.getBuffer();

        const clumpExtBuf = new BinaryWriter();
        for (const ext of this.clumpExtensions) {
            clumpExtBuf.writeBytes(ext);
        }
        const clumpExtBytes = clumpExtBuf.getBuffer();

        const totalSize = (12 + clumpStructBytes.length) +
                          (12 + frameListBuf.length) +
                          (12 + geomListBuf.length) +
                          atomicsBuf.length +
                          (12 + clumpExtBytes.length);

        writer.writeHeader(RW_CHUNKS.CLUMP, totalSize, libId);
        writer.writeHeader(RW_CHUNKS.STRUCT, clumpStructBytes.length, libId);
        writer.writeBytes(clumpStructBytes);
        writer.writeHeader(RW_CHUNKS.FRAMELIST, frameListBuf.length, libId);
        writer.writeBytes(frameListBuf);
        writer.writeHeader(RW_CHUNKS.GEOMETRYLIST, geomListBuf.length, libId);
        writer.writeBytes(geomListBuf);
        writer.writeBytes(atomicsBuf);
        writer.writeHeader(RW_CHUNKS.EXTENSION, clumpExtBytes.length, libId);
        writer.writeBytes(clumpExtBytes);

        return writer.getBuffer();
    }

    serializeFrameList(libId) {
        const writer = new BinaryWriter();
        const numFrames = this.frames.length;
        const structSize = 4 + numFrames * 56;
        writer.writeHeader(RW_CHUNKS.STRUCT, structSize, libId);
        writer.writeUint32(numFrames);

        for (let i = 0; i < numFrames; i++) {
            const f = this.frames[i];
            for (let r = 0; r < 9; r++) {
                writer.writeFloat32(f.rot[r]);
            }
            writer.writeFloat32(f.pos[0]);
            writer.writeFloat32(f.pos[1]);
            writer.writeFloat32(f.pos[2]);
            writer.writeInt32(f.parentIndex);
            writer.writeUint32(f.matrixFlags || 0x00020003);
        }

        for (let i = 0; i < numFrames; i++) {
            const f = this.frames[i];
            const extWriter = new BinaryWriter();

            if (f.name && f.name.length > 0) {
                const nameBytes = new TextEncoder().encode(f.name);
                const nameLen = nameBytes.length + 1;
                extWriter.writeHeader(RW_CHUNKS.FRAMENAME, nameLen, libId);
                extWriter.writeBytes(nameBytes);
                extWriter.writeUint8(0);
            }

            if (f.extensions) {
                for (const sub of f.extensions) {
                    extWriter.writeHeader(sub.type, sub.data.length, sub.libId || libId);
                    extWriter.writeBytes(sub.data);
                }
            }

            const extBytes = extWriter.getBuffer();
            writer.writeHeader(RW_CHUNKS.EXTENSION, extBytes.length, libId);
            writer.writeBytes(extBytes);
        }

        return writer.getBuffer();
    }

    serializeGeometryList(libId) {
        const writer = new BinaryWriter();
        writer.writeHeader(RW_CHUNKS.STRUCT, 4, libId);
        writer.writeUint32(this.geometries.length);

        for (const geom of this.geometries) {
            const geomBuf = this.serializeGeometry(geom, libId);
            writer.writeHeader(RW_CHUNKS.GEOMETRY, geomBuf.length, libId);
            writer.writeBytes(geomBuf);
        }

        return writer.getBuffer();
    }

    serializeGeometry(geom, libId) {
        const writer = new BinaryWriter();

        const structWriter = new BinaryWriter();
        structWriter.writeUint32(geom.formatFlags);
        structWriter.writeUint32(geom.numTriangles);
        structWriter.writeUint32(geom.numVertices);
        structWriter.writeUint32(1);

        if ((geom.formatFlags & 0x0008) && geom.colors) {
            for (let i = 0; i < geom.numVertices; i++) {
                const c = geom.colors[i] || { r: 255, g: 255, b: 255, a: 255 };
                structWriter.writeUint8(c.r);
                structWriter.writeUint8(c.g);
                structWriter.writeUint8(c.b);
                structWriter.writeUint8(c.a);
            }
        }

        if (geom.texCoordSets) {
            for (const set of geom.texCoordSets) {
                for (let i = 0; i < geom.numVertices; i++) {
                    const uv = set[i] || { u: 0, v: 0 };
                    structWriter.writeFloat32(uv.u);
                    structWriter.writeFloat32(uv.v);
                }
            }
        }

        for (let i = 0; i < geom.numTriangles; i++) {
            const t = geom.triangles[i];
            structWriter.writeUint16(t.v2 % 65536);
            structWriter.writeUint16(t.v1 % 65536);
            structWriter.writeUint16(t.matIndex);
            structWriter.writeUint16(t.v3 % 65536);
        }

        const sp = geom.sphere || { x: 0, y: 0, z: 0, radius: 1.0 };
        structWriter.writeFloat32(sp.x);
        structWriter.writeFloat32(sp.y);
        structWriter.writeFloat32(sp.z);
        structWriter.writeFloat32(sp.radius);

        structWriter.writeUint32(geom.vertices ? 1 : 0);
        structWriter.writeUint32((geom.formatFlags & 0x0010 && geom.normals) ? 1 : 0);

        if (geom.vertices) {
            for (let i = 0; i < geom.numVertices; i++) {
                const v = geom.vertices[i];
                structWriter.writeFloat32(v.x);
                structWriter.writeFloat32(v.y);
                structWriter.writeFloat32(v.z);
            }
        }

        if (geom.formatFlags & 0x0010 && geom.normals) {
            for (let i = 0; i < geom.numVertices; i++) {
                const n = geom.normals[i] || { x: 0, y: 0, z: 1 };
                structWriter.writeFloat32(n.x);
                structWriter.writeFloat32(n.y);
                structWriter.writeFloat32(n.z);
            }
        }

        const structBytes = structWriter.getBuffer();
        writer.writeHeader(RW_CHUNKS.STRUCT, structBytes.length, libId);
        writer.writeBytes(structBytes);

        const matListBytes = this.serializeMaterialList(geom.materials, libId);
        writer.writeHeader(RW_CHUNKS.MATERIALLIST, matListBytes.length, libId);
        writer.writeBytes(matListBytes);

        const extWriter = new BinaryWriter();
        if (geom.binMesh) {
            const bmWriter = new BinaryWriter();
            bmWriter.writeUint32(geom.binMesh.flags);
            bmWriter.writeUint32(geom.binMesh.numMeshes);
            bmWriter.writeUint32(geom.binMesh.totalIndices);
            for (const mesh of geom.binMesh.meshes) {
                bmWriter.writeUint32(mesh.indices.length);
                bmWriter.writeUint32(mesh.matIndex);
                for (const idx of mesh.indices) {
                    bmWriter.writeUint32(idx);
                }
            }
            const bmBytes = bmWriter.getBuffer();
            extWriter.writeHeader(RW_CHUNKS.BINMESH, bmBytes.length, libId);
            extWriter.writeBytes(bmBytes);
        }

        if (geom.extensions) {
            for (const sub of geom.extensions) {
                extWriter.writeHeader(sub.type, sub.data.length, sub.libId || libId);
                extWriter.writeBytes(sub.data);
            }
        }

        const extBytes = extWriter.getBuffer();
        writer.writeHeader(RW_CHUNKS.EXTENSION, extBytes.length, libId);
        writer.writeBytes(extBytes);

        return writer.getBuffer();
    }

    serializeMaterialList(materials, libId) {
        const writer = new BinaryWriter();
        const numMats = materials ? materials.length : 0;

        const structSize = 4 + numMats * 4;
        writer.writeHeader(RW_CHUNKS.STRUCT, structSize, libId);
        writer.writeUint32(numMats);
        for (let i = 0; i < numMats; i++) {
            writer.writeInt32(-1);
        }

        if (materials) {
            for (const mat of materials) {
                const matBytes = this.serializeMaterial(mat, libId);
                writer.writeHeader(RW_CHUNKS.MATERIAL, matBytes.length, libId);
                writer.writeBytes(matBytes);
            }
        }

        return writer.getBuffer();
    }

    serializeMaterial(mat, libId) {
        const writer = new BinaryWriter();

        const structWriter = new BinaryWriter();
        structWriter.writeUint32(0);
        const col = mat.color || { r: 255, g: 255, b: 255, a: 255 };
        structWriter.writeUint8(col.r);
        structWriter.writeUint8(col.g);
        structWriter.writeUint8(col.b);
        structWriter.writeUint8(col.a);
        structWriter.writeUint32(0);
        structWriter.writeInt32(mat.hasTexture ? 1 : 0);
        structWriter.writeFloat32(mat.ambient || 1.0);
        structWriter.writeFloat32(mat.specular || 1.0);
        structWriter.writeFloat32(mat.diffuse || 1.0);

        const structBytes = structWriter.getBuffer();
        writer.writeHeader(RW_CHUNKS.STRUCT, structBytes.length, libId);
        writer.writeBytes(structBytes);

        if (mat.hasTexture) {
            const texWriter = new BinaryWriter();
            texWriter.writeHeader(RW_CHUNKS.STRUCT, 4, libId);
            texWriter.writeUint32(0x1102);

            const nameBytes = new TextEncoder().encode(mat.textureName || "");
            const nameLen = nameBytes.length + 1;
            texWriter.writeHeader(RW_CHUNKS.STRING, nameLen, libId);
            texWriter.writeBytes(nameBytes);
            texWriter.writeUint8(0);

            const maskBytes = new TextEncoder().encode(mat.maskName || "");
            const maskLen = maskBytes.length + 1;
            texWriter.writeHeader(RW_CHUNKS.STRING, maskLen, libId);
            texWriter.writeBytes(maskBytes);
            texWriter.writeUint8(0);

            texWriter.writeHeader(RW_CHUNKS.EXTENSION, 0, libId);

            const texBytes = texWriter.getBuffer();
            writer.writeHeader(RW_CHUNKS.TEXTURE, texBytes.length, libId);
            writer.writeBytes(texBytes);
        }

        writer.writeHeader(RW_CHUNKS.EXTENSION, 0, libId);

        return writer.getBuffer();
    }

    serializeAtomics(libId) {
        const writer = new BinaryWriter();

        for (const at of this.atomics) {
            const atWriter = new BinaryWriter();
            atWriter.writeHeader(RW_CHUNKS.STRUCT, 16, libId);
            atWriter.writeUint32(at.frameIndex);
            atWriter.writeUint32(at.geometryIndex);
            atWriter.writeUint32(at.flags || 5);
            atWriter.writeUint32(at.unused || 0);

            const extLen = at.extensions ? at.extensions.reduce((acc, e) => acc + e.length, 0) : 0;
            atWriter.writeHeader(RW_CHUNKS.EXTENSION, extLen, libId);
            if (at.extensions) {
                for (const e of at.extensions) {
                    atWriter.writeBytes(e);
                }
            }

            const atBytes = atWriter.getBuffer();
            writer.writeHeader(RW_CHUNKS.ATOMIC, atBytes.length, libId);
            writer.writeBytes(atBytes);
        }

        return writer.getBuffer();
    }
}

/**
 * TXD (Texture Dictionary) Parser and DXT Decompressor
 */
class TXDParser {
    static parse(arrayBuffer) {
        const view = new DataView(arrayBuffer);
        let offset = 0;

        function readHeader() {
            if (offset + 12 > view.byteLength) return null;
            const type = view.getUint32(offset, true);
            const size = view.getUint32(offset + 4, true);
            const libId = view.getUint32(offset + 8, true);
            offset += 12;
            return { type, size, libId, payloadStart: offset, payloadEnd: offset + size };
        }

        const rootH = readHeader();
        if (!rootH || rootH.type !== RW_CHUNKS.TEXDICTIONARY) {
            throw new Error("Fayl RenderWare TXD emas!");
        }

        const structH = readHeader();
        const numTextures = view.getUint16(offset, true);
        offset = structH.payloadEnd;

        const textures = {};

        for (let i = 0; i < numTextures; i++) {
            if (offset >= rootH.payloadEnd) break;
            const texH = readHeader();
            if (!texH || texH.type !== RW_CHUNKS.TEXTURENATIVE) break;

            const texStructH = readHeader();
            offset += 8;

            let name = "";
            for (let c = 0; c < 32; c++) {
                const b = view.getUint8(offset + c);
                if (b === 0) break;
                name += String.fromCharCode(b);
            }
            offset += 32;

            let maskName = "";
            for (let c = 0; c < 32; c++) {
                const b = view.getUint8(offset + c);
                if (b === 0) break;
                maskName += String.fromCharCode(b);
            }
            offset += 32;

            const rasterFormat = view.getUint32(offset, true);
            offset += 4;

            let dxtStr = "";
            for (let d = 0; d < 4; d++) {
                dxtStr += String.fromCharCode(view.getUint8(offset + d));
            }
            offset += 4;

            const width = view.getUint16(offset, true);
            const height = view.getUint16(offset + 2, true);
            const depth = view.getUint8(offset + 4);
            const numMipmaps = view.getUint8(offset + 5);
            offset += 8;

            const dataSize = view.getUint32(offset, true);
            offset += 4;

            const pixelData = new Uint8Array(arrayBuffer, offset, dataSize);
            offset += dataSize;

            for (let m = 1; m < numMipmaps; m++) {
                if (offset + 4 > view.byteLength) break;
                const mipSize = view.getUint32(offset, true);
                offset += 4 + mipSize;
            }

            if (offset < texH.payloadEnd) {
                const extH = readHeader();
                if (extH) offset = extH.payloadEnd;
            }

            textures[name.toLowerCase()] = {
                name,
                maskName,
                width,
                height,
                depth,
                dxt: dxtStr.trim(),
                dataSize,
                pixelData
            };
        }

        return textures;
    }

    static decodeToRGBA(texObj) {
        if (texObj.dxt === 'DXT1') {
            return this.decodeDXT1(texObj.pixelData, texObj.width, texObj.height);
        } else if (texObj.dxt === 'DXT3') {
            return this.decodeDXT3(texObj.pixelData, texObj.width, texObj.height);
        } else if (texObj.dxt === 'DXT5') {
            return this.decodeDXT5(texObj.pixelData, texObj.width, texObj.height);
        } else {
            // Uncompressed 32-bit BGRA or RGBA
            const rgba = new Uint8ClampedArray(texObj.width * texObj.height * 4);
            const data = texObj.pixelData;
            for (let i = 0; i < rgba.length; i += 4) {
                rgba[i] = data[i + 2];     // R
                rgba[i + 1] = data[i + 1]; // G
                rgba[i + 2] = data[i];     // B
                rgba[i + 3] = data[i + 3]; // A
            }
            return rgba;
        }
    }

    static decodeDXT1(data, width, height) {
        const rgba = new Uint8ClampedArray(width * height * 4);
        let dataOffset = 0;
        const blocksX = Math.max(1, Math.floor((width + 3) / 4));
        const blocksY = Math.max(1, Math.floor((height + 3) / 4));

        for (let by = 0; by < blocksY; by++) {
            for (let bx = 0; bx < blocksX; bx++) {
                if (dataOffset + 8 > data.length) break;

                const c0 = data[dataOffset] | (data[dataOffset + 1] << 8);
                const c1 = data[dataOffset + 2] | (data[dataOffset + 3] << 8);
                const code = data[dataOffset + 4] | (data[dataOffset + 5] << 8) | (data[dataOffset + 6] << 16) | (data[dataOffset + 7] << 24);
                dataOffset += 8;

                const r0 = ((c0 >> 11) & 0x1f) * 255 / 31;
                const g0 = ((c0 >> 5) & 0x3f) * 255 / 63;
                const b0 = (c0 & 0x1f) * 255 / 31;

                const r1 = ((c1 >> 11) & 0x1f) * 255 / 31;
                const g1 = ((c1 >> 5) & 0x3f) * 255 / 63;
                const b1 = (c1 & 0x1f) * 255 / 31;

                for (let py = 0; py < 4; py++) {
                    for (let px = 0; px < 4; px++) {
                        const x = bx * 4 + px;
                        const y = by * 4 + py;
                        if (x < width && y < height) {
                            const bitIdx = (py * 4 + px) * 2;
                            const idx = (code >> bitIdx) & 0x03;
                            let r, g, b, a = 255;

                            if (c0 > c1) {
                                if (idx === 0) { r = r0; g = g0; b = b0; }
                                else if (idx === 1) { r = r1; g = g1; b = b1; }
                                else if (idx === 2) { r = (2 * r0 + r1) / 3; g = (2 * g0 + g1) / 3; b = (2 * b0 + b1) / 3; }
                                else { r = (r0 + 2 * r1) / 3; g = (g0 + 2 * g1) / 3; b = (b0 + 2 * b1) / 3; }
                            } else {
                                if (idx === 0) { r = r0; g = g0; b = b0; }
                                else if (idx === 1) { r = r1; g = g1; b = b1; }
                                else if (idx === 2) { r = (r0 + r1) / 2; g = (g0 + g1) / 2; b = (b0 + b1) / 2; }
                                else { r = 0; g = 0; b = 0; a = 0; }
                            }

                            const destIdx = (y * width + x) * 4;
                            rgba[destIdx] = Math.round(r);
                            rgba[destIdx + 1] = Math.round(g);
                            rgba[destIdx + 2] = Math.round(b);
                            rgba[destIdx + 3] = a;
                        }
                    }
                }
            }
        }
        return rgba;
    }

    static decodeDXT3(data, width, height) {
        const rgba = new Uint8ClampedArray(width * height * 4);
        let dataOffset = 0;
        const blocksX = Math.max(1, Math.floor((width + 3) / 4));
        const blocksY = Math.max(1, Math.floor((height + 3) / 4));

        for (let by = 0; by < blocksY; by++) {
            for (let bx = 0; bx < blocksX; bx++) {
                if (dataOffset + 16 > data.length) break;

                const alphaBytes = data.slice(dataOffset, dataOffset + 8);
                dataOffset += 8;

                const c0 = data[dataOffset] | (data[dataOffset + 1] << 8);
                const c1 = data[dataOffset + 2] | (data[dataOffset + 3] << 8);
                const code = data[dataOffset + 4] | (data[dataOffset + 5] << 8) | (data[dataOffset + 6] << 16) | (data[dataOffset + 7] << 24);
                dataOffset += 8;

                const r0 = ((c0 >> 11) & 0x1f) * 255 / 31;
                const g0 = ((c0 >> 5) & 0x3f) * 255 / 63;
                const b0 = (c0 & 0x1f) * 255 / 31;

                const r1 = ((c1 >> 11) & 0x1f) * 255 / 31;
                const g1 = ((c1 >> 5) & 0x3f) * 255 / 63;
                const b1 = (c1 & 0x1f) * 255 / 31;

                for (let py = 0; py < 4; py++) {
                    for (let px = 0; px < 4; px++) {
                        const x = bx * 4 + px;
                        const y = by * 4 + py;
                        if (x < width && y < height) {
                            const bitIdx = (py * 4 + px) * 2;
                            const idx = (code >> bitIdx) & 0x03;
                            let r, g, b;

                            if (idx === 0) { r = r0; g = g0; b = b0; }
                            else if (idx === 1) { r = r1; g = g1; b = b1; }
                            else if (idx === 2) { r = (2 * r0 + r1) / 3; g = (2 * g0 + g1) / 3; b = (2 * b0 + b1) / 3; }
                            else { r = (r0 + 2 * r1) / 3; g = (g0 + 2 * g1) / 3; b = (b0 + 2 * b1) / 3; }

                            const pixelIndex = py * 4 + px;
                            const alphaByte = alphaBytes[Math.floor(pixelIndex / 2)];
                            const a4 = (pixelIndex % 2 === 0) ? (alphaByte & 0x0F) : ((alphaByte >> 4) & 0x0F);
                            const a = Math.round(a4 * 255 / 15);

                            const destIdx = (y * width + x) * 4;
                            rgba[destIdx] = Math.round(r);
                            rgba[destIdx + 1] = Math.round(g);
                            rgba[destIdx + 2] = Math.round(b);
                            rgba[destIdx + 3] = a;
                        }
                    }
                }
            }
        }
        return rgba;
    }

    static decodeDXT5(data, width, height) {
        const rgba = new Uint8ClampedArray(width * height * 4);
        let dataOffset = 0;
        const blocksX = Math.max(1, Math.floor((width + 3) / 4));
        const blocksY = Math.max(1, Math.floor((height + 3) / 4));

        for (let by = 0; by < blocksY; by++) {
            for (let bx = 0; bx < blocksX; bx++) {
                if (dataOffset + 16 > data.length) break;

                const a0 = data[dataOffset];
                const a1 = data[dataOffset + 1];
                const aBits = data[dataOffset + 2] | (data[dataOffset + 3] << 8) | (data[dataOffset + 4] << 16);
                const aBits2 = data[dataOffset + 5] | (data[dataOffset + 6] << 8) | (data[dataOffset + 7] << 16);
                dataOffset += 8;

                const alphas = [a0, a1];
                if (a0 > a1) {
                    for (let i = 1; i <= 6; i++) {
                        alphas.push(Math.round(((7 - i) * a0 + i * a1) / 7));
                    }
                } else {
                    for (let i = 1; i <= 4; i++) {
                        alphas.push(Math.round(((5 - i) * a0 + i * a1) / 5));
                    }
                    alphas.push(0);
                    alphas.push(255);
                }

                const c0 = data[dataOffset] | (data[dataOffset + 1] << 8);
                const c1 = data[dataOffset + 2] | (data[dataOffset + 3] << 8);
                const code = data[dataOffset + 4] | (data[dataOffset + 5] << 8) | (data[dataOffset + 6] << 16) | (data[dataOffset + 7] << 24);
                dataOffset += 8;

                const r0 = ((c0 >> 11) & 0x1f) * 255 / 31;
                const g0 = ((c0 >> 5) & 0x3f) * 255 / 63;
                const b0 = (c0 & 0x1f) * 255 / 31;

                const r1 = ((c1 >> 11) & 0x1f) * 255 / 31;
                const g1 = ((c1 >> 5) & 0x3f) * 255 / 63;
                const b1 = (c1 & 0x1f) * 255 / 31;

                for (let py = 0; py < 4; py++) {
                    for (let px = 0; px < 4; px++) {
                        const x = bx * 4 + px;
                        const y = by * 4 + py;
                        if (x < width && y < height) {
                            const pIdx = py * 4 + px;
                            const bitIdx = pIdx * 2;
                            const idx = (code >> bitIdx) & 0x03;
                            let r, g, b;

                            if (idx === 0) { r = r0; g = g0; b = b0; }
                            else if (idx === 1) { r = r1; g = g1; b = b1; }
                            else if (idx === 2) { r = (2 * r0 + r1) / 3; g = (2 * g0 + g1) / 3; b = (2 * b0 + b1) / 3; }
                            else { r = (r0 + 2 * r1) / 3; g = (g0 + 2 * g1) / 3; b = (b0 + 2 * b1) / 3; }

                            let aIdx = 0;
                            if (pIdx < 8) {
                                aIdx = (aBits >> (pIdx * 3)) & 0x07;
                            } else {
                                aIdx = (aBits2 >> ((pIdx - 8) * 3)) & 0x07;
                            }
                            const a = alphas[aIdx];

                            const destIdx = (y * width + x) * 4;
                            rgba[destIdx] = Math.round(r);
                            rgba[destIdx + 1] = Math.round(g);
                            rgba[destIdx + 2] = Math.round(b);
                            rgba[destIdx + 3] = a;
                        }
                    }
                }
            }
        }
        return rgba;
    }
}

if (typeof window !== 'undefined') {
    window.DFFModel = DFFModel;
    window.TXDParser = TXDParser;
    window.BinaryReader = BinaryReader;
    window.BinaryWriter = BinaryWriter;
} else if (typeof global !== 'undefined') {
    global.DFFModel = DFFModel;
    global.TXDParser = TXDParser;
}

if (typeof module !== 'undefined' && module.exports) {
    module.exports = { DFFModel, TXDParser, RW_CHUNKS, BinaryReader, BinaryWriter };
}
