/**
 * Diro 3D Studio (ZModeler iOS) - Core Application Logic
 * Supports:
 * - 3D Viewport with Orbit & Transform Gizmos (Z-up)
 * - DFF Import & Export with 100% GTA SA binary compatibility
 * - Merge / Append external DFF models into hierarchy
 * - Rename parts & frames
 * - Reorder & Reparent nodes in hierarchy (Move Up, Move Down, Reparent)
 * - Quick Stance / Posadka tuning
 * - Full Material Editor (Color picker, Ambient/Specular, Texture rename & PNG preview)
 */

// Configure Three.js for GTA SA coordinate system (Z is UP)
THREE.Object3D.DefaultUp.set(0, 0, 1);

let scene, camera, renderer, orbitControls, transformControls;
let currentDFF = null;
let currentRootGroup = null;
let frameGroups = [];
let selectedNode = null;
let selectedMesh = null;
let selectedMaterialIndex = 0;
let initialWheelPositions = {};
let isWireframe = false;
let showDummies = true;
let isShaderMode = false;
let isUVFlipped = false;
let studioEnvMap = null;

function init() {
    const container = document.getElementById('viewport-container');

    // 1. Scene
    scene = new THREE.Scene();
    scene.background = new THREE.Color(0x0f1117);

    // 2. Camera (Z is UP)
    camera = new THREE.PerspectiveCamera(45, window.innerWidth / window.innerHeight, 0.1, 500);
    camera.up.set(0, 0, 1);
    camera.position.set(-5, -6, 3);

    // 3. Renderer with Antialiasing
    renderer = new THREE.WebGLRenderer({ antialias: true, alpha: false });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    renderer.setSize(window.innerWidth, window.innerHeight);
    renderer.shadowMap.enabled = false;
    container.appendChild(renderer.domElement);

    // 4. Lighting
    const ambientLight = new THREE.AmbientLight(0xffffff, 0.7);
    scene.add(ambientLight);

    const dirLight1 = new THREE.DirectionalLight(0xffffff, 0.85);
    dirLight1.position.set(10, 10, 20);
    scene.add(dirLight1);

    const dirLight2 = new THREE.DirectionalLight(0xffffff, 0.45);
    dirLight2.position.set(-10, -10, -5);
    scene.add(dirLight2);

    // 5. Grid Helper (XY Plane for Z-up)
    const grid = new THREE.GridHelper(20, 20, 0x3b82f6, 0x1e293b);
    grid.rotation.x = Math.PI / 2;
    scene.add(grid);

    // 6. OrbitControls
    orbitControls = new THREE.OrbitControls(camera, renderer.domElement);
    orbitControls.enableDamping = true;
    orbitControls.dampingFactor = 0.08;
    orbitControls.target.set(0, 0, 0.5);

    // 7. TransformControls (Gizmo)
    transformControls = new THREE.TransformControls(camera, renderer.domElement);
    transformControls.size = 0.85;
    transformControls.setSpace('local');
    transformControls.addEventListener('dragging-changed', function (event) {
        orbitControls.enabled = !event.value;
    });
    transformControls.addEventListener('change', function () {
        if (selectedNode) {
            updateInspectorCoordinates(selectedNode);
        }
    });
    scene.add(transformControls);

    // 8. Event Listeners
    window.addEventListener('resize', onWindowResize);
    setupRaycaster();
    setupUIEvents();

    // 9. Animation Loop
    animate();
}

function animate() {
    requestAnimationFrame(animate);
    orbitControls.update();
    renderer.render(scene, camera);
}

function onWindowResize() {
    camera.aspect = window.innerWidth / window.innerHeight;
    camera.updateProjectionMatrix();
    renderer.setSize(window.innerWidth, window.innerHeight);
}

// Tap in 3D to select car part
function setupRaycaster() {
    const raycaster = new THREE.Raycaster();
    const mouse = new THREE.Vector2();
    let touchStartTime = 0;

    renderer.domElement.addEventListener('touchstart', (e) => {
        touchStartTime = Date.now();
    });

    renderer.domElement.addEventListener('touchend', (e) => {
        if (Date.now() - touchStartTime > 250) return;
        if (e.changedTouches.length !== 1) return;
        const touch = e.changedTouches[0];
        handlePointerSelect(touch.clientX, touch.clientY);
    });

    renderer.domElement.addEventListener('click', (e) => {
        handlePointerSelect(e.clientX, e.clientY);
    });

    function handlePointerSelect(clientX, clientY) {
        if (transformControls.dragging) return;

        mouse.x = (clientX / window.innerWidth) * 2 - 1;
        mouse.y = -(clientY / window.innerHeight) * 2 + 1;
        raycaster.setFromCamera(mouse, camera);

        if (!currentRootGroup) return;

        const intersects = raycaster.intersectObjects(currentRootGroup.children, true);
        if (intersects.length > 0) {
            let hitObj = intersects[0].object;
            let meshCandidate = (hitObj instanceof THREE.Mesh) ? hitObj : null;

            while (hitObj && hitObj.parent !== currentRootGroup && hitObj.parent !== scene) {
                if (hitObj.userData && hitObj.userData.frameIndex !== undefined) {
                    break;
                }
                hitObj = hitObj.parent;
            }
            if (hitObj && hitObj.userData && hitObj.userData.frameIndex !== undefined) {
                selectNodeByIndex(hitObj.userData.frameIndex, meshCandidate);
            }
        }
    }

    // Hide initial splash loader
    const loader = document.getElementById('app-loading-state');
    if (loader) {
        loader.style.opacity = '0';
        setTimeout(() => loader.remove(), 350);
    }
}

// Procedural Studio / Sky Environment Map for GTA Glossy Reflections
function createStudioEnvMap() {
    const canvas = document.createElement('canvas');
    canvas.width = 1024;
    canvas.height = 512;
    const ctx = canvas.getContext('2d');

    // 1. Sky & Atmosphere gradient (Top half)
    const skyGrad = ctx.createLinearGradient(0, 0, 0, 256);
    skyGrad.addColorStop(0, '#1e3a8a');
    skyGrad.addColorStop(0.35, '#38bdf8');
    skyGrad.addColorStop(0.85, '#bae6fd');
    skyGrad.addColorStop(1, '#ffffff');
    ctx.fillStyle = skyGrad;
    ctx.fillRect(0, 0, 1024, 256);

    // 2. High-intensity Sun / Key light reflection
    const sunGrad = ctx.createRadialGradient(512, 90, 5, 512, 90, 240);
    sunGrad.addColorStop(0, '#ffffff');
    sunGrad.addColorStop(0.25, 'rgba(255, 250, 230, 0.95)');
    sunGrad.addColorStop(0.6, 'rgba(255, 220, 150, 0.4)');
    sunGrad.addColorStop(1, 'rgba(255, 255, 255, 0)');
    ctx.fillStyle = sunGrad;
    ctx.fillRect(0, 0, 1024, 256);

    // 3. Ground & Asphalt gradient (Bottom half)
    const groundGrad = ctx.createLinearGradient(0, 256, 0, 512);
    groundGrad.addColorStop(0, '#0f172a');
    groundGrad.addColorStop(0.2, '#1e293b');
    groundGrad.addColorStop(0.6, '#090d16');
    groundGrad.addColorStop(1, '#020617');
    ctx.fillStyle = groundGrad;
    ctx.fillRect(0, 256, 1024, 256);

    // 4. Softbox highlights for automotive showroom curvature lines
    ctx.fillStyle = 'rgba(255, 255, 255, 0.65)';
    ctx.fillRect(120, 50, 160, 90);
    ctx.fillRect(740, 50, 160, 90);

    const texture = new THREE.CanvasTexture(canvas);
    texture.mapping = THREE.EquirectangularReflectionMapping;
    return texture;
}

function toggleShaderMode() {
    isShaderMode = !isShaderMode;
    const btn = document.getElementById('btn-toggle-shader');
    if (btn) {
        btn.classList.toggle('active', isShaderMode);
    }

    if (!studioEnvMap) {
        studioEnvMap = createStudioEnvMap();
    }

    if (isShaderMode) {
        scene.environment = studioEnvMap;
        renderer.toneMapping = THREE.ACESFilmicToneMapping;
        renderer.toneMappingExposure = 1.25;
        showToast("✨ Shader: Yaltiroq rejim yoqildi (O'yindagi ENB/Glossy)");
    } else {
        scene.environment = null;
        renderer.toneMapping = THREE.NoToneMapping;
        renderer.toneMappingExposure = 1.0;
        showToast("Shader rejimi: Oddiy (Standart)");
    }

    updateAllMaterialsShader();
}

function updateAllMaterialsShader() {
    if (!currentRootGroup) return;

    currentRootGroup.traverse(obj => {
        if (obj instanceof THREE.Mesh && !obj.name.includes("__dummy_")) {
            const mats = Array.isArray(obj.material) ? obj.material : [obj.material];
            mats.forEach(mat => {
                if (mat instanceof THREE.MeshStandardMaterial) {
                    const texName = (mat.userData?.dffMat?.textureName || "").toLowerCase();
                    const partName = (obj.name || "").toLowerCase();
                    const combined = texName + " " + partName;

                    if (isShaderMode) {
                        if (combined.includes("glass") || combined.includes("window") || combined.includes("windscreen")) {
                            mat.transparent = true;
                            mat.opacity = 0.55;
                            mat.roughness = 0.05;
                            mat.metalness = 0.9;
                            mat.envMapIntensity = 2.5;
                        } else if (combined.includes("wheel") || combined.includes("rim") || combined.includes("chrom") || combined.includes("exhaust")) {
                            mat.roughness = 0.08;
                            mat.metalness = 0.95;
                            mat.envMapIntensity = 2.4;
                        } else if (combined.includes("light") || combined.includes("lamp")) {
                            mat.roughness = 0.15;
                            mat.metalness = 0.3;
                            mat.envMapIntensity = 1.6;
                        } else {
                            // Glossy car paint body (Kuzov)
                            mat.roughness = 0.12;
                            mat.metalness = 0.65;
                            mat.envMapIntensity = 1.9;
                        }
                    } else {
                        // Standard edit mode
                        if (combined.includes("glass") || combined.includes("window")) {
                            mat.transparent = true;
                            mat.opacity = 0.65;
                        }
                        mat.roughness = 0.4;
                        mat.metalness = 0.2;
                        mat.envMapIntensity = 0.5;
                    }
                    mat.needsUpdate = true;
                }
            });
        }
    });
}

function toggleUVFlip() {
    isUVFlipped = !isUVFlipped;
    const btn = document.getElementById('btn-toggle-uv');
    if (btn) {
        btn.classList.toggle('active', isUVFlipped);
    }

    if (!currentRootGroup) return;

    currentRootGroup.traverse(obj => {
        if (obj instanceof THREE.Mesh && obj.geometry && obj.geometry.attributes.uv) {
            const uvAttr = obj.geometry.attributes.uv;
            const array = uvAttr.array;
            for (let i = 1; i < array.length; i += 2) {
                array[i] = 1.0 - array[i];
            }
            uvAttr.needsUpdate = true;
        }
    });

    showToast(isUVFlipped ? "🔄 UV: Teskari qilindi (180°)" : "🔄 UV: Asl holatga keltirildi (Normal)");
}

// Build Three.js 3D Scene from DFFModel
function buildThreeSceneFromDFF(dff) {
    if (currentRootGroup) {
        scene.remove(currentRootGroup);
    }
    transformControls.detach();
    selectedNode = null;
    selectedMesh = null;

    currentDFF = dff;
    currentRootGroup = new THREE.Group();
    currentRootGroup.name = "DFF_Root";
    frameGroups = [];
    initialWheelPositions = {};

    // 1. Create a THREE.Group for each frame
    for (let i = 0; i < dff.frames.length; i++) {
        const frame = dff.frames[i];
        const group = new THREE.Group();
        group.name = frame.name;
        group.userData = { frameIndex: i, frameData: frame };

        // Position
        group.position.set(frame.pos[0], frame.pos[1], frame.pos[2]);

        // Rotation matrix (3x3)
        const m = new THREE.Matrix4();
        m.set(
            frame.rot[0], frame.rot[3], frame.rot[6], 0,
            frame.rot[1], frame.rot[4], frame.rot[7], 0,
            frame.rot[2], frame.rot[5], frame.rot[8], 0,
            0, 0, 0, 1
        );
        group.quaternion.setFromRotationMatrix(m);

        frameGroups.push(group);

        // Store initial wheel heights for Posadka slider
        if (frame.name.includes("wheel_") && frame.name.includes("_dummy")) {
            initialWheelPositions[frame.name] = frame.pos[2];
        }
    }

    // 2. Assemble Hierarchy (parent-child)
    for (let i = 0; i < dff.frames.length; i++) {
        const frame = dff.frames[i];
        const group = frameGroups[i];

        if (frame.parentIndex >= 0 && frame.parentIndex < frameGroups.length) {
            frameGroups[frame.parentIndex].add(group);
        } else {
            currentRootGroup.add(group);
        }
    }

    // 3. Attach Geometries via Atomics
    for (let i = 0; i < dff.atomics.length; i++) {
        const at = dff.atomics[i];
        if (at.frameIndex >= frameGroups.length || at.geometryIndex >= dff.geometries.length) continue;

        const targetGroup = frameGroups[at.frameIndex];
        const geom = dff.geometries[at.geometryIndex];

        const bufferGeom = new THREE.BufferGeometry();

        // Vertices
        if (geom.vertices && geom.vertices.length > 0) {
            const posArray = new Float32Array(geom.vertices.length * 3);
            for (let v = 0; v < geom.vertices.length; v++) {
                posArray[v * 3] = geom.vertices[v].x;
                posArray[v * 3 + 1] = geom.vertices[v].y;
                posArray[v * 3 + 2] = geom.vertices[v].z;
            }
            bufferGeom.setAttribute('position', new THREE.BufferAttribute(posArray, 3));
        }

        // Normals
        if (geom.normals && geom.normals.length > 0) {
            const normArray = new Float32Array(geom.normals.length * 3);
            for (let n = 0; n < geom.normals.length; n++) {
                normArray[n * 3] = geom.normals[n].x;
                normArray[n * 3 + 1] = geom.normals[n].y;
                normArray[n * 3 + 2] = geom.normals[n].z;
            }
            bufferGeom.setAttribute('normal', new THREE.BufferAttribute(normArray, 3));
        } else {
            bufferGeom.computeVertexNormals();
        }

        // Texture Coordinates (UVs)
        if (geom.texCoordSets && geom.texCoordSets.length > 0 && geom.texCoordSets[0].length > 0) {
            const uvSet = geom.texCoordSets[0];
            const uvArray = new Float32Array(uvSet.length * 2);
            for (let u = 0; u < uvSet.length; u++) {
                uvArray[u * 2] = uvSet[u].u;
                uvArray[u * 2 + 1] = isUVFlipped ? (1.0 - uvSet[u].v) : uvSet[u].v;
            }
            bufferGeom.setAttribute('uv', new THREE.BufferAttribute(uvArray, 2));
        }

        // Colors (Prelit)
        if (geom.colors && geom.colors.length > 0) {
            const colArray = new Float32Array(geom.colors.length * 3);
            for (let c = 0; c < geom.colors.length; c++) {
                colArray[c * 3] = geom.colors[c].r / 255.0;
                colArray[c * 3 + 1] = geom.colors[c].g / 255.0;
                colArray[c * 3 + 2] = geom.colors[c].b / 255.0;
            }
            bufferGeom.setAttribute('color', new THREE.BufferAttribute(colArray, 3));
        }

        // Indices & Groups (using BinMesh or Triangles)
        let threeMaterials = [];

        if (geom.binMesh && geom.binMesh.meshes && geom.binMesh.meshes.length > 0) {
            let allIndices = [];
            for (const mesh of geom.binMesh.meshes) {
                const start = allIndices.length;
                for (const idx of mesh.indices) {
                    allIndices.push(idx);
                }
                bufferGeom.addGroup(start, mesh.indices.length, mesh.matIndex);
            }
            bufferGeom.setIndex(allIndices);
        } else if (geom.triangles && geom.triangles.length > 0) {
            let allIndices = [];
            for (const t of geom.triangles) {
                allIndices.push(t.v1, t.v2, t.v3);
            }
            bufferGeom.setIndex(allIndices);
        }

        // Materials setup
        if (geom.materials && geom.materials.length > 0) {
            for (let m = 0; m < geom.materials.length; m++) {
                const mat = geom.materials[m];
                const col = mat.color ? new THREE.Color(mat.color.r / 255, mat.color.g / 255, mat.color.b / 255) : new THREE.Color(0xcccccc);
                const threeMat = new THREE.MeshStandardMaterial({
                    color: col,
                    roughness: 0.4,
                    metalness: 0.2,
                    side: THREE.DoubleSide,
                    wireframe: isWireframe
                });
                threeMat.userData = { matIndex: m, geomIndex: at.geometryIndex, dffMat: mat };
                threeMaterials.push(threeMat);
            }
        } else {
            const defMat = new THREE.MeshStandardMaterial({
                color: 0x999999,
                roughness: 0.5,
                side: THREE.DoubleSide,
                wireframe: isWireframe
            });
            threeMaterials.push(defMat);
        }

        const mesh = new THREE.Mesh(bufferGeom, threeMaterials.length === 1 ? threeMaterials[0] : threeMaterials);
        mesh.userData = { geometryIndex: at.geometryIndex, frameIndex: at.frameIndex };
        targetGroup.add(mesh);
    }

    // 4. Attach Visual Helpers for Dummies (frames without geometries)
    for (let i = 0; i < frameGroups.length; i++) {
        const grp = frameGroups[i];
        const hasMeshes = grp.children.some(c => c instanceof THREE.Mesh && !c.name.includes("__dummy_"));

        if (!hasMeshes) {
            let dummyColor = 0xa855f7; // default magenta
            if (grp.name.includes("wheel")) dummyColor = 0x38bdf8; // cyan
            else if (grp.name.includes("light")) dummyColor = 0xfacc15; // yellow
            else if (grp.name.includes("exhaust")) dummyColor = 0xef4444; // red
            else if (grp.name.includes("ped") || grp.name.includes("seat")) dummyColor = 0x22c55e; // green

            const dummyGeo = new THREE.SphereGeometry(0.06, 12, 12);
            const dummyMat = new THREE.MeshBasicMaterial({ color: dummyColor, wireframe: false });
            const dummyMesh = new THREE.Mesh(dummyGeo, dummyMat);
            dummyMesh.name = "__dummy_helper__";

            const axes = new THREE.AxesHelper(0.18);
            axes.name = "__dummy_axes__";

            grp.add(dummyMesh);
            grp.add(axes);
        }
    }

    scene.add(currentRootGroup);

    // Compute bounding box and frame camera
    const box = new THREE.Box3().setFromObject(currentRootGroup);
    const center = box.getCenter(new THREE.Vector3());
    const size = box.getSize(new THREE.Vector3());
    const maxDim = Math.max(size.x, size.y, size.z);

    orbitControls.target.copy(center);
    camera.position.set(center.x - maxDim * 1.5, center.y - maxDim * 1.5, center.z + maxDim * 0.8);
    camera.lookAt(center);
    orbitControls.update();

    // Populate Hierarchy UI
    renderHierarchyList();

    // Hide welcome overlay
    document.getElementById('welcome-overlay').classList.add('hidden');
    if (isShaderMode) {
        updateAllMaterialsShader();
    }

    showToast(`DFF yuklandi: ${dff.frames.length} ta qism, ${dff.geometries.length} ta geometriya`);
}

// Merge an external DFF into current model
function mergeExternalDFF(arrayBuffer, fileName) {
    if (!currentDFF) {
        showToast("Avval asosiy modelni oching!");
        return;
    }

    try {
        const otherModel = new DFFModel();
        otherModel.parse(arrayBuffer);

        // Determine parent for merged model (attach to selected node or root chassis)
        let parentIndex = 0;
        if (selectedNode && selectedNode.userData && selectedNode.userData.frameIndex !== undefined) {
            parentIndex = selectedNode.userData.frameIndex;
        }

        currentDFF.mergeModel(otherModel, parentIndex);

        // Sync and rebuild 3D scene
        buildThreeSceneFromDFF(currentDFF);

        const shortName = fileName.replace(/\.[^/.]+$/, "");
        showToast(`Qo'shildi: ${shortName} (${otherModel.frames.length} qism)`);
    } catch (err) {
        alert("DFF qo'shishda xatolik: " + err.message);
    }
}

// Synchronize Three.js Scene back into DFFModel and Export
function exportCurrentDFF() {
    if (!currentDFF || !currentRootGroup) {
        showToast("Eksport qilish uchun avval modelni oching!");
        return;
    }

    // 1. Update frame positions, rotations, names from Three.js scene
    for (let i = 0; i < currentDFF.frames.length; i++) {
        const grp = frameGroups[i];
        if (!grp) continue;

        // Position
        currentDFF.frames[i].pos[0] = grp.position.x;
        currentDFF.frames[i].pos[1] = grp.position.y;
        currentDFF.frames[i].pos[2] = grp.position.z;

        // Rotation matrix from Quaternion
        const m = new THREE.Matrix4().makeRotationFromQuaternion(grp.quaternion);
        const te = m.elements;
        currentDFF.frames[i].rot = [
            te[0], te[1], te[2],
            te[4], te[5], te[6],
            te[8], te[9], te[10]
        ];

        // Name
        currentDFF.frames[i].name = grp.name;
    }

    // 2. Serialize DFF
    showToast("DFF yig'ilmoqda...");
    const dffBytes = currentDFF.serialize();

    // 3. Native iOS Bridge or Web Download
    const fileName = (currentDFF.fileName || "car_mod") + ".dff";

    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.exportDFF) {
        let binary = '';
        const len = dffBytes.byteLength;
        for (let i = 0; i < len; i++) {
            binary += String.fromCharCode(dffBytes[i]);
        }
        const b64 = window.btoa(binary);

        window.webkit.messageHandlers.exportDFF.postMessage({
            fileName: fileName,
            base64Data: b64,
            sizeBytes: len
        });
    } else {
        const blob = new Blob([dffBytes], { type: "application/octet-stream" });
        const url = URL.createObjectURL(blob);
        const a = document.createElement("a");
        a.href = url;
        a.download = fileName;
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        URL.revokeObjectURL(url);
        showToast(`Saqlandi: ${fileName} (${(dffBytes.length / 1024).toFixed(1)} KB)`);
    }
}

// Texture pool mapping textureName.toLowerCase() -> THREE.Texture
let loadedTexturesPool = {};

function applyTextureMapToScene() {
    if (!currentRootGroup) return;
    let appliedCount = 0;

    currentRootGroup.traverse(child => {
        if (child instanceof THREE.Mesh && !child.name.includes("__dummy_")) {
            const mats = Array.isArray(child.material) ? child.material : [child.material];
            mats.forEach(m => {
                const dffMat = m.userData ? m.userData.dffMat : null;
                if (dffMat && dffMat.textureName) {
                    const cleanName = dffMat.textureName.toLowerCase().trim();
                    let matchedTex = loadedTexturesPool[cleanName];

                    if (!matchedTex) {
                        // Partial match (e.g. "huntley" matches "huntley92...")
                        for (let k in loadedTexturesPool) {
                            if (k.includes(cleanName) || cleanName.includes(k)) {
                                matchedTex = loadedTexturesPool[k];
                                break;
                            }
                        }
                    }

                    if (matchedTex) {
                        m.map = matchedTex;
                        m.needsUpdate = true;
                        appliedCount++;
                    }
                }
            });
        }
    });

    if (appliedCount > 0) {
        if (isShaderMode) {
            updateAllMaterialsShader();
        }
        showToast(`${appliedCount} ta qismga teksturalar ulandi!`);
    }
}

function processTXDData(arrayBuffer, fileName) {
    try {
        const parsed = TXDParser.parse(arrayBuffer);
        const count = Object.keys(parsed).length;
        for (let key in parsed) {
            const t = parsed[key];
            const rgba = TXDParser.decodeToRGBA(t);
            const dataTex = new THREE.DataTexture(rgba, t.width, t.height, THREE.RGBAFormat);
            dataTex.flipY = false;
            dataTex.wrapS = THREE.RepeatWrapping;
            dataTex.wrapT = THREE.RepeatWrapping;
            dataTex.needsUpdate = true;
            loadedTexturesPool[key.toLowerCase()] = dataTex;
        }
        applyTextureMapToScene();
        showToast(`TXD yuklandi: ${fileName} (${count} ta tekstura)`);
    } catch (err) {
        alert("TXD o'qishda xatolik: " + err.message);
    }
}

function processImageFile(file) {
    const reader = new FileReader();
    reader.onload = (e) => {
        const texLoader = new THREE.TextureLoader();
        texLoader.load(e.target.result, (texture) => {
            texture.flipY = false;
            texture.wrapS = THREE.RepeatWrapping;
            texture.wrapT = THREE.RepeatWrapping;
            const nameKey = file.name.replace(/\.[^/.]+$/, "").toLowerCase();
            loadedTexturesPool[nameKey] = texture;
            applyTextureMapToScene();
        });
    };
    reader.readAsDataURL(file);
}

// UI Setup & Event Handlers
function setupUIEvents() {
    // 1. Open primary DFF or multiple files (.dff, .txd, images)
    const fileInput = document.getElementById('dff-file-input');
    fileInput.addEventListener('change', (e) => {
        const fileList = Array.from(e.target.files);
        if (fileList.length === 0) return;

        // Separate DFF and TXD/images
        const dffFiles = fileList.filter(f => f.name.toLowerCase().endsWith('.dff'));
        const txdFiles = fileList.filter(f => f.name.toLowerCase().endsWith('.txd'));
        const imgFiles = fileList.filter(f => /\.(png|jpe?g)$/i.test(f.name));

        if (dffFiles.length > 0) {
            const dffFile = dffFiles[0];
            const reader = new FileReader();
            reader.onload = (event) => {
                try {
                    const model = new DFFModel();
                    model.fileName = dffFile.name.replace(/\.[^/.]+$/, "");
                    model.parse(event.target.result);
                    buildThreeSceneFromDFF(model);

                    // Load TXDs after DFF is loaded
                    txdFiles.forEach(tf => {
                        const tr = new FileReader();
                        tr.onload = (ev) => processTXDData(ev.target.result, tf.name);
                        tr.readAsArrayBuffer(tf);
                    });

                    // Load image files
                    imgFiles.forEach(im => processImageFile(im));
                } catch (err) {
                    alert("DFF ochishda xatolik: " + err.message);
                }
            };
            reader.readAsArrayBuffer(dffFile);
        } else if (txdFiles.length > 0) {
            txdFiles.forEach(tf => {
                const tr = new FileReader();
                tr.onload = (ev) => processTXDData(ev.target.result, tf.name);
                tr.readAsArrayBuffer(tf);
            });
        }
    });

    document.getElementById('btn-open-file').addEventListener('click', () => {
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.openDocumentPicker) {
            window.webkit.messageHandlers.openDocumentPicker.postMessage({ mode: "open" });
        } else {
            fileInput.click();
        }
    });

    // Dedicated TXD button
    const txdInput = document.getElementById('txd-file-input');
    txdInput.addEventListener('change', (e) => {
        const files = Array.from(e.target.files);
        files.forEach(f => {
            if (f.name.toLowerCase().endsWith('.txd')) {
                const r = new FileReader();
                r.onload = (ev) => processTXDData(ev.target.result, f.name);
                r.readAsArrayBuffer(f);
            } else if (/\.(png|jpe?g)$/i.test(f.name)) {
                processImageFile(f);
            }
        });
    });

    document.getElementById('btn-open-txd').addEventListener('click', () => {
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.openDocumentPicker) {
            window.webkit.messageHandlers.openDocumentPicker.postMessage({ mode: "txd" });
        } else {
            txdInput.click();
        }
    });

    // 2. Merge secondary DFF
    const mergeInput = document.getElementById('dff-merge-input');
    mergeInput.addEventListener('change', (e) => {
        const file = e.target.files[0];
        if (!file) return;
        const reader = new FileReader();
        reader.onload = (event) => {
            mergeExternalDFF(event.target.result, file.name);
        };
        reader.readAsArrayBuffer(file);
    });

    const triggerMerge = () => {
        if (!currentDFF) {
            showToast("Avval asosiy modelni oching!");
            return;
        }
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.openDocumentPicker) {
            window.webkit.messageHandlers.openDocumentPicker.postMessage({ mode: "merge" });
        } else {
            mergeInput.click();
        }
    };
    document.getElementById('btn-merge-file').addEventListener('click', triggerMerge);
    document.getElementById('btn-hier-add-dff').addEventListener('click', triggerMerge);

    // 3. Export DFF
    document.getElementById('btn-export-dff').addEventListener('click', exportCurrentDFF);

    // 4. Toggle Drawers
    const leftDrawer = document.getElementById('drawer-hierarchy');
    const rightDrawer = document.getElementById('drawer-inspector');

    document.getElementById('btn-toggle-hierarchy').addEventListener('click', () => {
        leftDrawer.classList.toggle('collapsed');
    });
    document.getElementById('btn-close-hierarchy').addEventListener('click', () => {
        leftDrawer.classList.add('collapsed');
    });

    document.getElementById('btn-toggle-inspector').addEventListener('click', () => {
        rightDrawer.classList.toggle('collapsed');
    });
    document.getElementById('btn-close-inspector').addEventListener('click', () => {
        rightDrawer.classList.add('collapsed');
    });

    // 5. View Toolbar actions
    document.getElementById('btn-toggle-wireframe').addEventListener('click', (e) => {
        isWireframe = !isWireframe;
        e.currentTarget.classList.toggle('active', isWireframe);
        if (currentRootGroup) {
            currentRootGroup.traverse(child => {
                if (child instanceof THREE.Mesh && !child.name.includes("__dummy_")) {
                    if (Array.isArray(child.material)) {
                        child.material.forEach(m => m.wireframe = isWireframe);
                    } else if (child.material) {
                        child.material.wireframe = isWireframe;
                    }
                }
            });
        }
    });

    document.getElementById('btn-toggle-dummies').addEventListener('click', (e) => {
        showDummies = !showDummies;
        e.currentTarget.classList.toggle('active', showDummies);
        if (currentRootGroup) {
            currentRootGroup.traverse(child => {
                if (child.name.includes("__dummy_")) {
                    child.visible = showDummies;
                }
            });
        }
    });

    document.getElementById('btn-toggle-shader').addEventListener('click', toggleShaderMode);
    document.getElementById('btn-toggle-uv').addEventListener('click', toggleUVFlip);

    document.getElementById('btn-reset-cam').addEventListener('click', () => {
        if (currentRootGroup) {
            const box = new THREE.Box3().setFromObject(currentRootGroup);
            const center = box.getCenter(new THREE.Vector3());
            const size = box.getSize(new THREE.Vector3());
            const maxDim = Math.max(size.x, size.y, size.z);
            orbitControls.target.copy(center);
            camera.position.set(center.x - maxDim * 1.5, center.y - maxDim * 1.5, center.z + maxDim * 0.8);
            camera.lookAt(center);
            orbitControls.update();
        }
    });

    // 6. Gizmo Mode buttons
    const gizmoBtns = document.querySelectorAll('.gizmo-btn');
    gizmoBtns.forEach(btn => {
        btn.addEventListener('click', () => {
            gizmoBtns.forEach(b => b.classList.remove('active'));
            btn.classList.add('active');
            const mode = btn.dataset.mode;
            transformControls.setMode(mode);
        });
    });

    // 7. Inspector Tabs
    const tabBtns = document.querySelectorAll('.tab-btn');
    tabBtns.forEach(btn => {
        btn.addEventListener('click', () => {
            tabBtns.forEach(b => b.classList.remove('active'));
            btn.classList.add('active');
            const tabId = btn.dataset.tab;
            document.querySelectorAll('.tab-content').forEach(c => c.style.display = 'none');
            document.getElementById(`tab-${tabId}`).style.display = 'flex';
        });
    });

    // 8. Rename node
    const renameInput = document.getElementById('input-node-name');
    const applyRenameBtn = document.getElementById('btn-apply-rename');
    const executeRename = () => {
        if (!selectedNode) return;
        const newName = renameInput.value.trim();
        if (!newName) return;

        selectedNode.name = newName;
        const idx = selectedNode.userData.frameIndex;
        if (currentDFF && currentDFF.frames[idx]) {
            currentDFF.frames[idx].name = newName;
        }
        document.getElementById('inspector-title').textContent = newName;
        renderHierarchyList();
        showToast(`Nom o'zgartirildi: ${newName}`);
    };
    applyRenameBtn.addEventListener('click', executeRename);
    renameInput.addEventListener('keydown', (e) => {
        if (e.key === 'Enter') executeRename();
    });

    // 9. Hierarchy Reorder: Move Up / Down
    document.getElementById('btn-move-up').addEventListener('click', () => {
        if (!selectedNode) return;
        moveNodeOrder(selectedNode.userData.frameIndex, -1);
    });

    document.getElementById('btn-move-down').addEventListener('click', () => {
        if (!selectedNode) return;
        moveNodeOrder(selectedNode.userData.frameIndex, 1);
    });

    // 10. Reparent Node
    document.getElementById('btn-reparent').addEventListener('click', reparentSelectedNode);

    // 11. Delete Node
    document.getElementById('btn-delete-node').addEventListener('click', deleteSelectedNode);

    // 12. Quick Tuning: Posadka (Lowering) Slider
    const posadkaSlider = document.getElementById('slider-posadka');
    const posadkaVal = document.getElementById('val-posadka');
    posadkaSlider.addEventListener('input', (e) => {
        const offset = parseFloat(e.target.value) / 100.0;
        posadkaVal.textContent = (offset > 0 ? "+" : "") + e.target.value + " sm";

        frameGroups.forEach(grp => {
            if (grp.name.includes("wheel_") && grp.name.includes("_dummy")) {
                const baseZ = initialWheelPositions[grp.name] || 0;
                grp.position.z = baseZ + offset;
            }
        });
        if (selectedNode) updateInspectorCoordinates(selectedNode);
    });

    // Quick Tuning: Wheel Camber (Razval) Slider
    const camberSlider = document.getElementById('slider-camber');
    const camberVal = document.getElementById('val-camber');
    camberSlider.addEventListener('input', (e) => {
        const deg = parseFloat(e.target.value);
        camberVal.textContent = (deg > 0 ? "+" : "") + deg + "°";
        const rad = deg * (Math.PI / 180.0);

        frameGroups.forEach(grp => {
            if (grp.name.includes("wheel_") && grp.name.includes("_dummy")) {
                const isLeft = grp.name.includes("_lf_") || grp.name.includes("_lb_");
                grp.rotation.y = isLeft ? -rad : rad;
            }
        });
        if (selectedNode) updateInspectorCoordinates(selectedNode);
    });

    // Quick Tuning: Wheel Scale
    const scaleSlider = document.getElementById('slider-scale');
    const scaleVal = document.getElementById('val-scale');
    scaleSlider.addEventListener('input', (e) => {
        const scale = parseFloat(e.target.value);
        scaleVal.textContent = scale.toFixed(2) + "x";

        frameGroups.forEach(grp => {
            if (grp.name.includes("wheel_") && grp.name.includes("_dummy")) {
                grp.scale.set(scale, scale, scale);
            }
        });
        if (selectedNode) updateInspectorCoordinates(selectedNode);
    });

    // Quick Tuning: Track Width (Offset)
    const trackSlider = document.getElementById('slider-track');
    const trackVal = document.getElementById('val-track');
    trackSlider.addEventListener('input', (e) => {
        const offset = parseFloat(e.target.value) / 100.0;
        trackVal.textContent = (offset > 0 ? "+" : "") + e.target.value + " sm";

        frameGroups.forEach(grp => {
            if (grp.name.includes("wheel_") && grp.name.includes("_dummy")) {
                const isLeft = grp.name.includes("_lf_") || grp.name.includes("_lb_");
                const initialX = currentDFF.frames[grp.userData.frameIndex].pos[0];
                grp.position.x = isLeft ? (initialX - offset) : (initialX + offset);
            }
        });
        if (selectedNode) updateInspectorCoordinates(selectedNode);
    });

    // 13. Material Editor Setup
    setupMaterialEditor();

    // 14. Coordinate inputs and Step buttons (+/-)
    setupCoordinateInputs();

    // 15. Hierarchy Search
    document.getElementById('hierarchy-search').addEventListener('input', (e) => {
        const query = e.target.value.toLowerCase();
        document.querySelectorAll('.node-item').forEach(item => {
            const name = item.dataset.name.toLowerCase();
            item.style.display = name.includes(query) ? 'flex' : 'none';
        });
    });

    // 16. Add Dummy Button
    document.getElementById('btn-add-dummy').addEventListener('click', showAddDummyDialog);
}

// Material Editor Logic
function setupMaterialEditor() {
    const matSelect = document.getElementById('mat-select');
    const colorPicker = document.getElementById('mat-color-picker');
    const colorHex = document.getElementById('mat-color-hex');
    const alphaSlider = document.getElementById('slider-mat-alpha');
    const alphaVal = document.getElementById('val-mat-alpha');
    const texNameInput = document.getElementById('input-mat-texname');
    const btnPickTexImg = document.getElementById('btn-pick-tex-img');
    const texFileInput = document.getElementById('tex-file-input');
    const ambientSlider = document.getElementById('slider-mat-ambient');
    const ambientVal = document.getElementById('val-mat-ambient');
    const specularSlider = document.getElementById('slider-mat-specular');
    const specularVal = document.getElementById('val-mat-specular');

    matSelect.addEventListener('change', () => {
        selectedMaterialIndex = parseInt(matSelect.value) || 0;
        updateMaterialControls();
    });

    colorPicker.addEventListener('input', (e) => {
        colorHex.value = e.target.value.toUpperCase();
        applyMaterialColor(e.target.value, parseFloat(alphaSlider.value) / 100.0);
    });

    colorHex.addEventListener('change', (e) => {
        colorPicker.value = e.target.value;
        applyMaterialColor(e.target.value, parseFloat(alphaSlider.value) / 100.0);
    });

    alphaSlider.addEventListener('input', (e) => {
        alphaVal.textContent = e.target.value + "%";
        applyMaterialColor(colorPicker.value, parseFloat(e.target.value) / 100.0);
    });

    texNameInput.addEventListener('input', (e) => {
        applyMaterialTextureName(e.target.value.trim());
    });

    ambientSlider.addEventListener('input', (e) => {
        ambientVal.textContent = parseFloat(e.target.value).toFixed(2);
        applyMaterialLighting('ambient', parseFloat(e.target.value));
    });

    specularSlider.addEventListener('input', (e) => {
        specularVal.textContent = parseFloat(e.target.value).toFixed(2);
        applyMaterialLighting('specular', parseFloat(e.target.value));
    });

    // Texture image file loader
    btnPickTexImg.addEventListener('click', () => {
        texFileInput.click();
    });

    texFileInput.addEventListener('change', (e) => {
        const file = e.target.files[0];
        if (!file) return;

        const reader = new FileReader();
        reader.onload = (event) => {
            const imgUrl = event.target.result;
            const texLoader = new THREE.TextureLoader();
            texLoader.load(imgUrl, (texture) => {
                texture.flipY = false;
                texture.wrapS = THREE.RepeatWrapping;
                texture.wrapT = THREE.RepeatWrapping;

                // Update Three.js Mesh Material map
                if (selectedMesh) {
                    const mats = Array.isArray(selectedMesh.material) ? selectedMesh.material : [selectedMesh.material];
                    if (mats[selectedMaterialIndex]) {
                        mats[selectedMaterialIndex].map = texture;
                        mats[selectedMaterialIndex].needsUpdate = true;
                    }
                }

                // Show preview box
                document.getElementById('tex-preview-box').style.display = 'flex';
                document.getElementById('tex-preview-img').src = imgUrl;
                document.getElementById('tex-preview-name').textContent = file.name;

                // Set texture name from file
                const baseName = file.name.replace(/\.[^/.]+$/, "");
                texNameInput.value = baseName;
                applyMaterialTextureName(baseName);
                showToast(`Tekstura ulandi: ${file.name}`);
            });
        };
        reader.readAsDataURL(file);
    });
}

function updateMaterialControls() {
    if (!selectedMesh) return;
    const mats = Array.isArray(selectedMesh.material) ? selectedMesh.material : [selectedMesh.material];
    const threeMat = mats[selectedMaterialIndex];
    if (!threeMat) return;

    const hex = "#" + threeMat.color.getHexString().toUpperCase();
    document.getElementById('mat-color-picker').value = hex;
    document.getElementById('mat-color-hex').value = hex;

    const alpha = Math.round((threeMat.opacity !== undefined ? threeMat.opacity : 1.0) * 100);
    document.getElementById('slider-mat-alpha').value = alpha;
    document.getElementById('val-mat-alpha').textContent = alpha + "%";

    const dffMat = threeMat.userData ? threeMat.userData.dffMat : null;
    if (dffMat) {
        document.getElementById('input-mat-texname').value = dffMat.textureName || "";
        document.getElementById('slider-mat-ambient').value = dffMat.ambient || 1.0;
        document.getElementById('val-mat-ambient').textContent = (dffMat.ambient || 1.0).toFixed(2);
        document.getElementById('slider-mat-specular').value = dffMat.specular || 1.0;
        document.getElementById('val-mat-specular').textContent = (dffMat.specular || 1.0).toFixed(2);
    }
}

function applyMaterialColor(hexStr, alpha) {
    if (!selectedMesh) return;
    const mats = Array.isArray(selectedMesh.material) ? selectedMesh.material : [selectedMesh.material];
    const threeMat = mats[selectedMaterialIndex];
    if (!threeMat) return;

    const col = new THREE.Color(hexStr);
    threeMat.color.copy(col);
    threeMat.transparent = alpha < 0.99;
    threeMat.opacity = alpha;
    threeMat.needsUpdate = true;

    // Update DFF model material
    if (threeMat.userData && threeMat.userData.dffMat) {
        threeMat.userData.dffMat.color = {
            r: Math.round(col.r * 255),
            g: Math.round(col.g * 255),
            b: Math.round(col.b * 255),
            a: Math.round(alpha * 255)
        };
    }
}

function applyMaterialTextureName(name) {
    if (!selectedMesh) return;
    const mats = Array.isArray(selectedMesh.material) ? selectedMesh.material : [selectedMesh.material];
    const threeMat = mats[selectedMaterialIndex];
    if (threeMat && threeMat.userData && threeMat.userData.dffMat) {
        threeMat.userData.dffMat.textureName = name;
        threeMat.userData.dffMat.hasTexture = name.length > 0 ? 1 : 0;
    }
}

function applyMaterialLighting(type, val) {
    if (!selectedMesh) return;
    const mats = Array.isArray(selectedMesh.material) ? selectedMesh.material : [selectedMesh.material];
    const threeMat = mats[selectedMaterialIndex];
    if (threeMat && threeMat.userData && threeMat.userData.dffMat) {
        threeMat.userData.dffMat[type] = val;
    }
}

// Coordinate Inputs and Step buttons setup
function setupCoordinateInputs() {
    ['pos', 'rot', 'scale'].forEach(type => {
        ['x', 'y', 'z'].forEach(axis => {
            const input = document.getElementById(`${type}-${axis}`);
            const btnPlus = document.getElementById(`btn-${type}-${axis}-plus`);
            const btnMinus = document.getElementById(`btn-${type}-${axis}-minus`);
            const step = type === 'rot' ? 5.0 : 0.05;

            input.addEventListener('change', () => {
                if (!selectedNode) return;
                const val = parseFloat(input.value) || 0;
                applyCoordinateChange(type, axis, val);
            });

            btnPlus.addEventListener('click', () => {
                if (!selectedNode) return;
                let val = parseFloat(input.value) || 0;
                val += step;
                input.value = val.toFixed(type === 'rot' ? 1 : 3);
                applyCoordinateChange(type, axis, val);
            });

            btnMinus.addEventListener('click', () => {
                if (!selectedNode) return;
                let val = parseFloat(input.value) || 0;
                val -= step;
                input.value = val.toFixed(type === 'rot' ? 1 : 3);
                applyCoordinateChange(type, axis, val);
            });
        });
    });
}

function applyCoordinateChange(type, axis, val) {
    if (!selectedNode) return;

    if (type === 'pos') {
        selectedNode.position[axis] = val;
    } else if (type === 'rot') {
        const rad = val * (Math.PI / 180.0);
        selectedNode.rotation[axis] = rad;
    } else if (type === 'scale') {
        selectedNode.scale[axis] = val;
    }
}

// Select a node by frame index
function selectNodeByIndex(index, specificMesh = null) {
    if (index < 0 || index >= frameGroups.length) return;
    const grp = frameGroups[index];
    selectedNode = grp;

    transformControls.attach(grp);

    // Find first mesh if not provided
    if (!specificMesh) {
        specificMesh = grp.children.find(c => c instanceof THREE.Mesh && !c.name.includes("__dummy_"));
    }
    selectedMesh = specificMesh;

    // Update Hierarchy items active state
    document.querySelectorAll('.node-item').forEach(item => {
        item.classList.toggle('selected', parseInt(item.dataset.index) === index);
    });

    // Update Inspector Drawer
    document.getElementById('drawer-inspector').classList.remove('collapsed');
    document.getElementById('inspector-title').textContent = grp.name;
    document.getElementById('input-node-name').value = grp.name;

    updateInspectorCoordinates(grp);

    // Populate Material Selector for this mesh
    populateMaterialSelector(specificMesh);
}

function populateMaterialSelector(mesh) {
    const matSelect = document.getElementById('mat-select');
    matSelect.innerHTML = '';

    if (!mesh || !mesh.material) {
        const opt = document.createElement('option');
        opt.value = "0";
        opt.textContent = "Geometriya / Material yo'q (Dummy)";
        matSelect.appendChild(opt);
        document.getElementById('tex-preview-box').style.display = 'none';
        return;
    }

    const mats = Array.isArray(mesh.material) ? mesh.material : [mesh.material];
    mats.forEach((m, idx) => {
        const opt = document.createElement('option');
        opt.value = idx;
        const dffMat = m.userData ? m.userData.dffMat : null;
        const tex = dffMat && dffMat.textureName ? ` [${dffMat.textureName}]` : '';
        opt.textContent = `Material ${idx + 1}${tex}`;
        matSelect.appendChild(opt);
    });

    selectedMaterialIndex = 0;
    updateMaterialControls();
}

function updateInspectorCoordinates(grp) {
    document.getElementById('pos-x').value = grp.position.x.toFixed(3);
    document.getElementById('pos-y').value = grp.position.y.toFixed(3);
    document.getElementById('pos-z').value = grp.position.z.toFixed(3);

    document.getElementById('rot-x').value = (grp.rotation.x * (180 / Math.PI)).toFixed(1);
    document.getElementById('rot-y').value = (grp.rotation.y * (180 / Math.PI)).toFixed(1);
    document.getElementById('rot-z').value = (grp.rotation.z * (180 / Math.PI)).toFixed(1);

    document.getElementById('scale-x').value = grp.scale.x.toFixed(3);
    document.getElementById('scale-y').value = grp.scale.y.toFixed(3);
    document.getElementById('scale-z').value = grp.scale.z.toFixed(3);
}

// Move node order in hierarchy (Up / Down)
function moveNodeOrder(index, direction) {
    if (!currentDFF) return;
    const targetIdx = index + direction;
    if (targetIdx < 0 || targetIdx >= currentDFF.frames.length) return;

    // Swap frames in currentDFF
    const tempFrame = currentDFF.frames[index];
    currentDFF.frames[index] = currentDFF.frames[targetIdx];
    currentDFF.frames[targetIdx] = tempFrame;

    currentDFF.frames[index].index = index;
    currentDFF.frames[targetIdx].index = targetIdx;

    // Swap groups in frameGroups
    const tempGrp = frameGroups[index];
    frameGroups[index] = frameGroups[targetIdx];
    frameGroups[targetIdx] = tempGrp;

    frameGroups[index].userData.frameIndex = index;
    frameGroups[targetIdx].userData.frameIndex = targetIdx;

    renderHierarchyList();
    selectNodeByIndex(targetIdx);
    showToast(`Tartib o'zgardi (${targetIdx + 1}/${currentDFF.frames.length})`);
}

// Reparent selected node to another frame
function reparentSelectedNode() {
    if (!selectedNode || !currentDFF) return;

    const currentIdx = selectedNode.userData.frameIndex;
    const currentName = selectedNode.name;

    const frameListNames = currentDFF.frames
        .map((f, i) => `${i}: ${f.name}`)
        .filter((_, i) => i !== currentIdx)
        .slice(0, 30)
        .join("\n");

    const input = prompt(`"${currentName}" detalini qaysi detal ichiga biriktirmoqchisiz?\nKatalog raqami yoki nomini kiriting:\n\n${frameListNames}`);
    if (input === null) return;

    let targetIdx = parseInt(input.trim());
    if (isNaN(targetIdx)) {
        targetIdx = currentDFF.frames.findIndex(f => f.name.toLowerCase() === input.trim().toLowerCase());
    }

    if (targetIdx < 0 || targetIdx >= currentDFF.frames.length || targetIdx === currentIdx) {
        alert("Noto'g'ri detal tanlandi!");
        return;
    }

    // Update parent in DFFModel
    currentDFF.frames[currentIdx].parentIndex = targetIdx;

    // Update Three.js hierarchy
    frameGroups[targetIdx].add(selectedNode);

    renderHierarchyList();
    showToast(`"${currentName}" -> "${currentDFF.frames[targetIdx].name}" ga biriktirildi!`);
}

// Delete selected node
function deleteSelectedNode() {
    if (!selectedNode || !currentDFF) return;
    const idx = selectedNode.userData.frameIndex;
    const name = selectedNode.name;

    if (!confirm(`Haqiqatan ham "${name}" detalini o'chirmoqchimisiz?`)) return;

    transformControls.detach();
    selectedNode.parent.remove(selectedNode);

    // Remove from DFF
    currentDFF.frames.splice(idx, 1);
    frameGroups.splice(idx, 1);

    // Re-index remaining frames
    for (let i = 0; i < currentDFF.frames.length; i++) {
        currentDFF.frames[i].index = i;
        if (currentDFF.frames[i].parentIndex > idx) {
            currentDFF.frames[i].parentIndex--;
        } else if (currentDFF.frames[i].parentIndex === idx) {
            currentDFF.frames[i].parentIndex = 0;
        }
        frameGroups[i].userData.frameIndex = i;
    }

    // Filter atomics pointing to this frame
    currentDFF.atomics = currentDFF.atomics.filter(a => a.frameIndex !== idx);
    for (let a of currentDFF.atomics) {
        if (a.frameIndex > idx) a.frameIndex--;
    }

    selectedNode = null;
    selectedMesh = null;
    renderHierarchyList();
    showToast(`O'chirildi: ${name}`);
}

// Render Hierarchy List inside Drawer with Drag & Drop
function renderHierarchyList() {
    const listContainer = document.getElementById('hierarchy-list');
    listContainer.innerHTML = '';

    frameGroups.forEach((grp, idx) => {
        const item = document.createElement('div');
        item.className = 'node-item';
        item.dataset.index = idx;
        item.dataset.name = grp.name;
        item.draggable = true;

        const info = document.createElement('div');
        info.className = 'node-info';

        const icon = document.createElement('span');
        icon.className = 'node-icon';
        const isDummy = !grp.children.some(c => c instanceof THREE.Mesh && !c.name.includes("__dummy_"));
        icon.textContent = isDummy ? "📍" : "🚗";

        const name = document.createElement('span');
        name.className = 'node-name';
        name.textContent = `${idx}: ${grp.name}`;

        info.appendChild(icon);
        info.appendChild(name);

        const actions = document.createElement('div');
        actions.style.display = 'flex';
        actions.style.alignItems = 'center';
        actions.style.gap = '2px';

        // Rename pencil button
        const editBtn = document.createElement('button');
        editBtn.className = 'node-eye';
        editBtn.innerHTML = "✏️";
        editBtn.title = "Nomini o'zgartirish";
        editBtn.addEventListener('click', (e) => {
            e.stopPropagation();
            const newName = prompt("Yangi nom kiriting:", grp.name);
            if (newName && newName.trim() && newName.trim() !== grp.name) {
                grp.name = newName.trim();
                currentDFF.frames[idx].name = newName.trim();
                renderHierarchyList();
                if (selectedNode === grp) {
                    document.getElementById('inspector-title').textContent = grp.name;
                    document.getElementById('input-node-name').value = grp.name;
                }
                showToast(`Nom o'zgartirildi: ${grp.name}`);
            }
        });

        // Visibility eye button
        const eyeBtn = document.createElement('button');
        eyeBtn.className = 'node-eye';
        eyeBtn.innerHTML = "👁️";
        eyeBtn.addEventListener('click', (e) => {
            e.stopPropagation();
            grp.visible = !grp.visible;
            eyeBtn.style.opacity = grp.visible ? "1.0" : "0.3";
        });

        actions.appendChild(editBtn);
        actions.appendChild(eyeBtn);

        item.appendChild(info);
        item.appendChild(actions);

        // Selection
        item.addEventListener('click', () => {
            selectNodeByIndex(idx);
        });

        // Drag & Drop reorder
        item.addEventListener('dragstart', (e) => {
            e.dataTransfer.setData('text/plain', idx);
            item.style.opacity = '0.5';
        });

        item.addEventListener('dragend', () => {
            item.style.opacity = '1.0';
            document.querySelectorAll('.node-item').forEach(i => i.style.borderTop = '');
        });

        item.addEventListener('dragover', (e) => {
            e.preventDefault();
            item.style.borderTop = '2px solid #3b82f6';
        });

        item.addEventListener('dragleave', () => {
            item.style.borderTop = '';
        });

        item.addEventListener('drop', (e) => {
            e.preventDefault();
            item.style.borderTop = '';
            const fromIdx = parseInt(e.dataTransfer.getData('text/plain'));
            const toIdx = idx;
            if (fromIdx !== toIdx) {
                // Reorder frames
                const movedFrame = currentDFF.frames.splice(fromIdx, 1)[0];
                currentDFF.frames.splice(toIdx, 0, movedFrame);

                const movedGrp = frameGroups.splice(fromIdx, 1)[0];
                frameGroups.splice(toIdx, 0, movedGrp);

                // Update indices
                currentDFF.frames.forEach((f, i) => f.index = i);
                frameGroups.forEach((g, i) => g.userData.frameIndex = i);

                renderHierarchyList();
                selectNodeByIndex(toIdx);
                showToast(`Qism yangi joyga ko'chirildi!`);
            }
        });

        listContainer.appendChild(item);
    });
}

function showAddDummyDialog() {
    const dummyName = prompt("Yangi Dummy nomini kiriting (masalan: wheel_rf_dummy, headlight_l, exhaust):");
    if (!dummyName || !dummyName.trim()) return;

    if (!currentDFF) {
        alert("Avval modelni oching!");
        return;
    }

    const newIndex = currentDFF.frames.length;
    let parentIndex = 0;
    if (selectedNode && selectedNode.userData) {
        parentIndex = selectedNode.userData.frameIndex;
    }

    const newFrame = {
        index: newIndex,
        name: dummyName.trim(),
        rot: [1, 0, 0, 0, 1, 0, 0, 0, 1],
        pos: [0, 0, 0],
        parentIndex: parentIndex,
        matrixFlags: 0x00020003,
        extensions: []
    };

    currentDFF.frames.push(newFrame);

    const group = new THREE.Group();
    group.name = newFrame.name;
    group.userData = { frameIndex: newIndex, frameData: newFrame };
    group.position.set(0, 0, 0);

    const dummyGeo = new THREE.SphereGeometry(0.06, 12, 12);
    const dummyMat = new THREE.MeshBasicMaterial({ color: 0xa855f7 });
    const dummyMesh = new THREE.Mesh(dummyGeo, dummyMat);
    dummyMesh.name = "__dummy_helper__";
    group.add(dummyMesh);
    group.add(new THREE.AxesHelper(0.18));

    frameGroups.push(group);
    if (frameGroups[parentIndex]) {
        frameGroups[parentIndex].add(group);
    } else {
        currentRootGroup.add(group);
    }

    renderHierarchyList();
    selectNodeByIndex(newIndex);
    showToast(`Yangi dummy qo'shildi: ${newFrame.name}`);
}

// Toast helper
function showToast(msg) {
    const toast = document.getElementById('toast');
    toast.textContent = msg;
    toast.classList.add('show');
    setTimeout(() => {
        toast.classList.remove('show');
    }, 2500);
}

// Global hooks for Native iOS Bridge
window.onNativeFileOpened = function(base64Data, fileName, mode) {
    try {
        const binary = window.atob(base64Data);
        const bytes = new Uint8Array(binary.length);
        for (let i = 0; i < binary.length; i++) {
            bytes[i] = binary.charCodeAt(i);
        }

        const lowerName = fileName.toLowerCase();

        if (mode === "txd" || lowerName.endsWith(".txd")) {
            processTXDData(bytes.buffer, fileName);
        } else if (/\.(png|jpe?g)$/i.test(lowerName)) {
            const blob = new Blob([bytes], { type: lowerName.endsWith(".png") ? "image/png" : "image/jpeg" });
            const file = new File([blob], fileName);
            processImageFile(file);
        } else if (mode === "merge") {
            mergeExternalDFF(bytes.buffer, fileName);
        } else {
            const model = new DFFModel();
            model.fileName = fileName.replace(/\.[^/.]+$/, "");
            model.parse(bytes.buffer);
            buildThreeSceneFromDFF(model);
        }
    } catch (err) {
        alert("Faylni ochishda xatolik: " + err.message);
    }
};

if (document.readyState === 'loading') {
    window.addEventListener('DOMContentLoaded', init);
} else {
    init();
}
