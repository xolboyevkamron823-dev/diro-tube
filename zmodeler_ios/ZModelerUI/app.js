/**
 * Diro 3D Studio (ZModeler iOS) - Core Application Logic
 */

// Configure Three.js for GTA SA coordinate system (Z is UP)
THREE.Object3D.DefaultUp.set(0, 0, 1);

let scene, camera, renderer, orbitControls, transformControls;
let currentDFF = null;
let currentRootGroup = null;
let frameGroups = [];
let selectedNode = null;
let initialWheelPositions = {};
let isWireframe = false;
let showDummies = true;

// Predefined GTA SA Vehicle Dummies for quick creation
const GTA_DUMMIES = [
    { name: "wheel_rf_dummy", desc: "O'ng old g'ildirak" },
    { name: "wheel_lf_dummy", desc: "Chap old g'ildirak" },
    { name: "wheel_rb_dummy", desc: "O'ng orqa g'ildirak" },
    { name: "wheel_lb_dummy", desc: "Chap orqa g'ildirak" },
    { name: "headlight_l", desc: "Chap old fara (yorug'lik)" },
    { name: "headlight_r", desc: "O'ng old fara (yorug'lik)" },
    { name: "taillight_l", desc: "Chap orqa fara" },
    { name: "taillight_r", desc: "O'ng orqa fara" },
    { name: "exhaust", desc: "Glushitel (tutun/olov)" },
    { name: "bonnet_dummy", desc: "Kapot nuqtasi" },
    { name: "boot_dummy", desc: "Bagaj nuqtasi" },
    { name: "door_rf_dummy", desc: "O'ng old eshik" },
    { name: "door_lf_dummy", desc: "Chap old eshik" },
    { name: "ped_frontseat", desc: "Haydovchi o'rindig'i (CJ)" }
];

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

    const dirLight1 = new THREE.DirectionalLight(0xffffff, 0.8);
    dirLight1.position.set(10, 10, 20);
    scene.add(dirLight1);

    const dirLight2 = new THREE.DirectionalLight(0xffffff, 0.4);
    dirLight2.position.set(-10, -10, -5);
    scene.add(dirLight2);

    // 5. Grid Helper (XY Plane for Z-up)
    const grid = new THREE.GridHelper(20, 20, 0x3b82f6, 0x1e293b);
    grid.rotation.x = Math.PI / 2; // Lay flat on XY plane
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
        // Only trigger if it was a tap (not a drag)
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
            // Climb up to find frame group
            while (hitObj && hitObj.parent !== currentRootGroup && hitObj.parent !== scene) {
                if (hitObj.userData && hitObj.userData.frameIndex !== undefined) {
                    break;
                }
                hitObj = hitObj.parent;
            }
            if (hitObj && hitObj.userData && hitObj.userData.frameIndex !== undefined) {
                selectNodeByIndex(hitObj.userData.frameIndex);
            }
        }
    }
}

// Build Three.js 3D Scene from DFFModel
function buildThreeSceneFromDFF(dff) {
    if (currentRootGroup) {
        scene.remove(currentRootGroup);
    }
    transformControls.detach();
    selectedNode = null;

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
                uvArray[u * 2 + 1] = 1.0 - uvSet[u].v; // Flip V for Three.js
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
                threeMaterials.push(threeMat);
            }
        } else {
            threeMaterials.push(new THREE.MeshStandardMaterial({
                color: 0x999999,
                roughness: 0.5,
                side: THREE.DoubleSide,
                wireframe: isWireframe
            }));
        }

        const mesh = new THREE.Mesh(bufferGeom, threeMaterials.length === 1 ? threeMaterials[0] : threeMaterials);
        mesh.userData = { geometryIndex: at.geometryIndex, frameIndex: at.frameIndex };
        targetGroup.add(mesh);
    }

    // 4. Attach Visual Helpers for Dummies (frames without geometries)
    for (let i = 0; i < frameGroups.length; i++) {
        const grp = frameGroups[i];
        const hasMeshes = grp.children.some(c => c instanceof THREE.Mesh);

        if (!hasMeshes) {
            // It's a dummy! Add visual sphere & axes
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
    showToast(`DFF yuklandi: ${dff.frames.length} ta qism`);
}

// Synchronize Three.js Scene back into DFFModel and Export
function exportCurrentDFF() {
    if (!currentDFF || !currentRootGroup) {
        showToast("Eksport qilish uchun avval modelni oching!");
        return;
    }

    // 1. Update frame positions and rotations from Three.js scene
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
    const fileName = (currentDFF.fileName || "model") + ".dff";

    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.exportDFF) {
        // Convert Uint8Array to base64
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
        // Standard Web browser download
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

// UI Setup & Event Handlers
function setupUIEvents() {
    // File inputs
    const fileInput = document.getElementById('dff-file-input');
    fileInput.addEventListener('change', (e) => {
        const file = e.target.files[0];
        if (!file) return;
        const reader = new FileReader();
        reader.onload = (event) => {
            try {
                const model = new DFFModel();
                model.fileName = file.name.replace(/\.[^/.]+$/, "");
                model.parse(event.target.result);
                buildThreeSceneFromDFF(model);
            } catch (err) {
                alert("DFF ochishda xatolik: " + err.message);
            }
        };
        reader.readAsArrayBuffer(file);
    });

    document.getElementById('btn-open-file').addEventListener('click', () => {
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.openDocumentPicker) {
            window.webkit.messageHandlers.openDocumentPicker.postMessage({});
        } else {
            fileInput.click();
        }
    });

    document.getElementById('btn-export-dff').addEventListener('click', exportCurrentDFF);

    // Toggle Drawers
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

    // View Toolbar actions
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

    // Gizmo Mode buttons
    const gizmoBtns = document.querySelectorAll('.gizmo-btn');
    gizmoBtns.forEach(btn => {
        btn.addEventListener('click', () => {
            gizmoBtns.forEach(b => b.classList.remove('active'));
            btn.classList.add('active');
            const mode = btn.dataset.mode;
            transformControls.setMode(mode);
        });
    });

    // Inspector Tabs
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

    // Quick Tuning: Posadka (Lowering) Slider
    const posadkaSlider = document.getElementById('slider-posadka');
    const posadkaVal = document.getElementById('val-posadka');
    posadkaSlider.addEventListener('input', (e) => {
        const offset = parseFloat(e.target.value) / 100.0; // cm to meters
        posadkaVal.textContent = (offset > 0 ? "+" : "") + e.target.value + " sm";

        // Move all wheel dummies
        frameGroups.forEach(grp => {
            if (grp.name.includes("wheel_") && grp.name.includes("_dummy")) {
                const baseZ = initialWheelPositions[grp.name] || 0;
                // In GTA SA, increasing wheel Z lowers the car chassis!
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

    // Coordinate inputs and Step buttons (+/-)
    setupCoordinateInputs();

    // Hierarchy Search
    document.getElementById('hierarchy-search').addEventListener('input', (e) => {
        const query = e.target.value.toLowerCase();
        document.querySelectorAll('.node-item').forEach(item => {
            const name = item.dataset.name.toLowerCase();
            item.style.display = name.includes(query) ? 'flex' : 'none';
        });
    });

    // Add Dummy Button
    document.getElementById('btn-add-dummy').addEventListener('click', showAddDummyDialog);
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
function selectNodeByIndex(index) {
    if (index < 0 || index >= frameGroups.length) return;
    const grp = frameGroups[index];
    selectedNode = grp;

    transformControls.attach(grp);

    // Update Hierarchy items active state
    document.querySelectorAll('.node-item').forEach(item => {
        item.classList.toggle('selected', parseInt(item.dataset.index) === index);
    });

    // Update Inspector Drawer
    document.getElementById('drawer-inspector').classList.remove('collapsed');
    document.getElementById('inspector-title').textContent = grp.name;
    document.getElementById('input-node-name').value = grp.name;

    updateInspectorCoordinates(grp);
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

// Render Hierarchy List inside Drawer
function renderHierarchyList() {
    const listContainer = document.getElementById('hierarchy-list');
    listContainer.innerHTML = '';

    frameGroups.forEach((grp, idx) => {
        const item = document.createElement('div');
        item.className = 'node-item';
        item.dataset.index = idx;
        item.dataset.name = grp.name;

        const info = document.createElement('div');
        info.className = 'node-info';

        const icon = document.createElement('span');
        icon.className = 'node-icon';
        const isDummy = !grp.children.some(c => c instanceof THREE.Mesh);
        icon.textContent = isDummy ? "📍" : "🚗";

        const name = document.createElement('span');
        name.className = 'node-name';
        name.textContent = grp.name;

        info.appendChild(icon);
        info.appendChild(name);

        const eyeBtn = document.createElement('button');
        eyeBtn.className = 'node-eye';
        eyeBtn.innerHTML = "👁️";
        eyeBtn.addEventListener('click', (e) => {
            e.stopPropagation();
            grp.visible = !grp.visible;
            eyeBtn.style.opacity = grp.visible ? "1.0" : "0.3";
        });

        item.appendChild(info);
        item.appendChild(eyeBtn);

        item.addEventListener('click', () => {
            selectNodeByIndex(idx);
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
    const newFrame = {
        index: newIndex,
        name: dummyName.trim(),
        rot: [1, 0, 0, 0, 1, 0, 0, 0, 1],
        pos: [0, 0, 0],
        parentIndex: 0,
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
    currentRootGroup.add(group);

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

// Global hook for Native iOS Bridge
window.onNativeFileOpened = function(base64Data, fileName) {
    try {
        const binary = window.atob(base64Data);
        const bytes = new Uint8Array(binary.length);
        for (let i = 0; i < binary.length; i++) {
            bytes[i] = binary.charCodeAt(i);
        }
        const model = new DFFModel();
        model.fileName = fileName.replace(/\.[^/.]+$/, "");
        model.parse(bytes.buffer);
        buildThreeSceneFromDFF(model);
    } catch (err) {
        alert("Faylni ochishda xatolik: " + err.message);
    }
};

window.addEventListener('DOMContentLoaded', init);
