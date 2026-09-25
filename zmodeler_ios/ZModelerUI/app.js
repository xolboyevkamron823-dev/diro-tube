/**
 * Diro 3D Studio - ZModeler 2 iOS Core Engine
 * Clean, uncluttered UI:
 * - Default 1-View full screen 3D
 * - 4-Viewport CAD Grid only when user clicks ⊞ 4-Oyna
 * - Drawers only open on user request with tap-outside backdrop
 * - RenderWare Tristrip + 32-bit indices for high-poly DFF models
 * - ZM2 4 Editing Levels (1: Vert, 2: Edge, 3: Poly with bright red face highlight, 4: Obj)
 * - Full Material Editor dialog (Hotkey E) & 2D UV Mapping Editor
 */

// Coordinate System: GTA SA / RenderWare (Z is UP, X is Right, Y is Forward)
THREE.Object3D.DefaultUp.set(0, 0, 1);

let scene, renderer;
let camera3D, cameraTop, cameraFront, cameraLeft;
let orbitControls, transformControls;
let currentDFF = null;
let currentRootGroup = null;
let frameGroups = [];
let selectedNode = null;
let selectedMesh = null;
let selectedMaterialIndex = 0;
let initialWheelPositions = {};

// Viewport System
let isQuadMode = false;
let activeViewportIndex = 3; // 0: Top, 1: Front, 2: Left, 3: 3D User
let viewports = [];

// Edit Levels: 1: Vertex, 2: Edge, 3: Polygon, 4: Object
let currentEditLevel = 4;
let selectedPolygonIndices = new Set();
let selectedVertexIndices = new Set();
let polygonHighlightMesh = null;
let vertexPointsHelper = null;
let vertexGizmoTarget = null;

// Display Flags
let isWireframe = false;
let showDummies = true;
let isShaderMode = false;
let isUVFlipped = false;
let studioEnvMap = null;
let loadedTexturesPool = {};

// UV Editor State
let uvCanvas, uvCtx;
let uvOriginalCoords = null;

function init() {
    const container = document.getElementById('viewport-container');

    // 1. Scene
    scene = new THREE.Scene();
    scene.background = new THREE.Color(0x0e1117);

    // 2. Multi-Cameras setup
    const aspect = window.innerWidth / window.innerHeight;
    
    // 3D User Perspective Camera
    camera3D = new THREE.PerspectiveCamera(45, aspect, 0.1, 500);
    camera3D.up.set(0, 0, 1);
    camera3D.position.set(-5, -6, 3);

    // Orthographic Top Camera (Looking down along -Z, +Y is Up on screen)
    const frustumSize = 8;
    cameraTop = new THREE.OrthographicCamera(-frustumSize * aspect / 2, frustumSize * aspect / 2, frustumSize / 2, -frustumSize / 2, 0.1, 500);
    cameraTop.up.set(0, 1, 0);
    cameraTop.position.set(0, 0, 20);
    cameraTop.lookAt(0, 0, 0);

    // Orthographic Front Camera (Looking along -Y from front of car, +Z is Up)
    cameraFront = new THREE.OrthographicCamera(-frustumSize * aspect / 2, frustumSize * aspect / 2, frustumSize / 2, -frustumSize / 2, 0.1, 500);
    cameraFront.up.set(0, 0, 1);
    cameraFront.position.set(0, 20, 0);
    cameraFront.lookAt(0, 0, 0);

    // Orthographic Left Camera (Looking along +X from left side of car, +Z is Up)
    cameraLeft = new THREE.OrthographicCamera(-frustumSize * aspect / 2, frustumSize * aspect / 2, frustumSize / 2, -frustumSize / 2, 0.1, 500);
    cameraLeft.up.set(0, 0, 1);
    cameraLeft.position.set(-20, 0, 0);
    cameraLeft.lookAt(0, 0, 0);

    viewports = [
        { name: "Top", camera: cameraTop },
        { name: "Front", camera: cameraFront },
        { name: "Left", camera: cameraLeft },
        { name: "3D User", camera: camera3D }
    ];

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
    orbitControls = new THREE.OrbitControls(camera3D, renderer.domElement);
    orbitControls.enableDamping = true;
    orbitControls.dampingFactor = 0.08;
    orbitControls.target.set(0, 0, 0.5);

    // 7. TransformControls (Gizmo)
    transformControls = new THREE.TransformControls(camera3D, renderer.domElement);
    transformControls.size = 0.85;
    transformControls.setSpace('local');
    transformControls.addEventListener('dragging-changed', function (event) {
        orbitControls.enabled = !event.value;
    });
    transformControls.addEventListener('change', function () {
        if (currentEditLevel === 4 && selectedNode) {
            updateInspectorCoordinates(selectedNode);
        } else if (currentEditLevel === 1 && vertexGizmoTarget) {
            applyVertexGizmoDrag();
        }
    });
    scene.add(transformControls);

    vertexGizmoTarget = new THREE.Object3D();
    scene.add(vertexGizmoTarget);

    // 8. Edit Helpers (Red polygons overlay & Point cloud)
    initEditHelpers();

    // 9. Event Listeners
    window.addEventListener('resize', onWindowResize);
    window.addEventListener('keydown', handleGlobalKeydown);
    setupRaycaster();
    setupUIEvents();
    setupMaterialEditorModal();
    setupUVEditor();

    // 10. Start Animation Loop
    animate();
}

function handleGlobalKeydown(e) {
    if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') return;
    if (e.key === ' ' || e.code === 'Space') {
        e.preventDefault();
        toggleQuadMode();
    } else if (e.key === 'e' || e.key === 'E') {
        openMaterialEditorModal();
    } else if (e.key === '1') setEditLevel(1);
    else if (e.key === '2') setEditLevel(2);
    else if (e.key === '3') setEditLevel(3);
    else if (e.key === '4') setEditLevel(4);
}

// Render Loop: Single Viewport or 4-Quadrant Scissor
function animate() {
    requestAnimationFrame(animate);

    orbitControls.update();

    const w = window.innerWidth;
    const h = window.innerHeight;

    if (!isQuadMode) {
        // Single View Mode: Zero overlay clutter
        renderer.setScissorTest(false);
        renderer.setViewport(0, 0, w, h);
        renderer.render(scene, viewports[activeViewportIndex].camera);
    } else {
        // 4-Viewport CAD Grid Mode
        renderer.setScissorTest(true);

        const halfW = Math.floor(w / 2);
        const halfH = Math.floor(h / 2);

        // Viewport 0: Top (Top-Left)
        renderer.setViewport(0, halfH, halfW, halfH);
        renderer.setScissor(0, halfH, halfW, halfH);
        renderer.render(scene, cameraTop);

        // Viewport 1: Front (Top-Right)
        renderer.setViewport(halfW, halfH, halfW, halfH);
        renderer.setScissor(halfW, halfH, halfW, halfH);
        renderer.render(scene, cameraFront);

        // Viewport 2: Left (Bottom-Left)
        renderer.setViewport(0, 0, halfW, halfH);
        renderer.setScissor(0, 0, halfW, halfH);
        renderer.render(scene, cameraLeft);

        // Viewport 3: 3D User (Bottom-Right)
        renderer.setViewport(halfW, 0, halfW, halfH);
        renderer.setScissor(halfW, 0, halfW, halfH);
        renderer.render(scene, camera3D);
    }
}

function onWindowResize() {
    const w = window.innerWidth;
    const h = window.innerHeight;
    const aspect = w / h;

    camera3D.aspect = aspect;
    camera3D.updateProjectionMatrix();

    if (currentRootGroup) {
        const box = new THREE.Box3().setFromObject(currentRootGroup);
        const size = box.getSize(new THREE.Vector3());
        const maxDim = Math.max(size.x, size.y, size.z, 5);
        updateOrthographicFrustums(maxDim);
    }

    renderer.setSize(w, h);
    updateActiveViewportBorder();
}

function updateOrthographicFrustums(dim) {
    const aspect = (window.innerWidth / 2) / (window.innerHeight / 2);
    const frustumSize = dim * 1.35;

    [cameraTop, cameraFront, cameraLeft].forEach(cam => {
        cam.left = -frustumSize * aspect / 2;
        cam.right = frustumSize * aspect / 2;
        cam.top = frustumSize / 2;
        cam.bottom = -frustumSize / 2;
        cam.updateProjectionMatrix();
    });
}

function toggleQuadMode() {
    isQuadMode = !isQuadMode;
    const quadOverlay = document.getElementById('quad-container');
    const singleBadge = document.getElementById('vp-single-indicator');
    const toggleBtn = document.getElementById('btn-toggle-quad-mode');

    if (isQuadMode) {
        quadOverlay.classList.remove('hidden');
        singleBadge.classList.add('hidden');
        if (toggleBtn) toggleBtn.classList.add('active');
        showToast("⊞ 4-Oynali CAD Ko'rinishi (Top, Front, Left, 3D)");
    } else {
        quadOverlay.classList.add('hidden');
        singleBadge.classList.remove('hidden');
        if (toggleBtn) toggleBtn.classList.remove('active');
        updateSingleViewBadge();
        showToast("▢ 1-Oyna Ko'rinishi (" + viewports[activeViewportIndex].name + ")");
    }
    updateActiveViewportBorder();
}

function maximizeViewport(vpIndex) {
    activeViewportIndex = vpIndex;
    isQuadMode = false;
    document.getElementById('quad-container').classList.add('hidden');
    document.getElementById('vp-single-indicator').classList.remove('hidden');
    const toggleBtn = document.getElementById('btn-toggle-quad-mode');
    if (toggleBtn) toggleBtn.classList.remove('active');
    updateSingleViewBadge();
    showToast(`Oyna: ${viewports[vpIndex].name} to'liq ekranga ochildi`);
}

function updateSingleViewBadge() {
    const lbl = document.getElementById('lbl-active-view-name');
    if (lbl) {
        lbl.textContent = `🚗 ${viewports[activeViewportIndex].name.toUpperCase()}`;
    }
}

function updateActiveViewportBorder() {
    const border = document.getElementById('active-vp-border');
    if (!border || !isQuadMode) {
        if (border) border.style.display = 'none';
        return;
    }
    border.style.display = 'block';
    const halfW = window.innerWidth / 2;
    const halfH = window.innerHeight / 2;

    switch (activeViewportIndex) {
        case 0: border.style.top = '0'; border.style.left = '0'; border.style.width = halfW + 'px'; border.style.height = halfH + 'px'; break;
        case 1: border.style.top = '0'; border.style.left = halfW + 'px'; border.style.width = halfW + 'px'; border.style.height = halfH + 'px'; break;
        case 2: border.style.top = halfH + 'px'; border.style.left = '0'; border.style.width = halfW + 'px'; border.style.height = halfH + 'px'; break;
        case 3: border.style.top = halfH + 'px'; border.style.left = halfW + 'px'; border.style.width = halfW + 'px'; border.style.height = halfH + 'px'; break;
    }
}

// -------------------------------------------------------------
// EDITING LEVELS (1: VERTEX, 2: EDGE, 3: POLYGON, 4: OBJECT)
// -------------------------------------------------------------
function initEditHelpers() {
    // Polygon Highlight Mesh: classic bright red overlay (ZModeler 2)
    const polyGeo = new THREE.BufferGeometry();
    const polyMat = new THREE.MeshBasicMaterial({
        color: 0xff1e1e,
        side: THREE.DoubleSide,
        depthTest: true,
        polygonOffset: true,
        polygonOffsetFactor: -2,
        polygonOffsetUnits: -2
    });
    polygonHighlightMesh = new THREE.Mesh(polyGeo, polyMat);
    polygonHighlightMesh.visible = false;
    scene.add(polygonHighlightMesh);

    // Vertex Points Helper (Cyan point cloud)
    const vertGeo = new THREE.BufferGeometry();
    const vertMat = new THREE.PointsMaterial({
        size: 7,
        vertexColors: true,
        sizeAttenuation: false,
        depthTest: false
    });
    vertexPointsHelper = new THREE.Points(vertGeo, vertMat);
    vertexPointsHelper.visible = false;
    scene.add(vertexPointsHelper);
}

function setEditLevel(level) {
    currentEditLevel = level;

    document.querySelectorAll('.level-btn').forEach(b => {
        b.classList.toggle('active', parseInt(b.dataset.level) === level);
    });

    selectedPolygonIndices.clear();
    selectedVertexIndices.clear();
    updatePolygonHighlight();
    updateVertexPointsHelper();

    const actBar = document.getElementById('action-floating-bar');

    if (level === 4) {
        if (selectedNode) transformControls.attach(selectedNode);
        polygonHighlightMesh.visible = false;
        vertexPointsHelper.visible = false;
        if (actBar) actBar.classList.add('hidden');
        showToast("Daraja 4: Obyekt Rejimi (Butun detalni surish/burish)");
    } else if (level === 3) {
        transformControls.detach();
        polygonHighlightMesh.visible = true;
        vertexPointsHelper.visible = false;
        updatePolygonHighlight();
        if (actBar) {
            actBar.classList.remove('hidden');
            document.getElementById('btn-act-detach').style.display = 'inline-flex';
            document.getElementById('btn-act-flip').style.display = 'inline-flex';
            document.getElementById('btn-act-assign-mat').style.display = 'inline-flex';
            document.getElementById('btn-act-weld').style.display = 'none';
        }
        showToast("Daraja 3: Poligon Rejimi (Yuzalarni tanlash - Qizil rang)");
    } else if (level === 1) {
        transformControls.detach();
        polygonHighlightMesh.visible = false;
        vertexPointsHelper.visible = true;
        updateVertexPointsHelper();
        if (actBar) {
            actBar.classList.remove('hidden');
            document.getElementById('btn-act-detach').style.display = 'none';
            document.getElementById('btn-act-flip').style.display = 'none';
            document.getElementById('btn-act-assign-mat').style.display = 'none';
            document.getElementById('btn-act-weld').style.display = 'inline-flex';
        }
        showToast("Daraja 1: Nuqta Rejimi (Vertex nuqtalarini tahrirlash)");
    } else if (level === 2) {
        transformControls.detach();
        polygonHighlightMesh.visible = false;
        vertexPointsHelper.visible = false;
        if (actBar) actBar.classList.add('hidden');
        showToast("Daraja 2: Qirra Rejimi");
    }
}

function updatePolygonHighlight() {
    if (!selectedMesh || currentEditLevel !== 3 || selectedPolygonIndices.size === 0) {
        polygonHighlightMesh.visible = false;
        updateActionBarLabel(0);
        return;
    }

    const geom = selectedMesh.geometry;
    const posAttr = geom.attributes.position;
    const indexAttr = geom.index;
    const triPositions = [];

    selectedPolygonIndices.forEach(faceIdx => {
        const i0 = indexAttr ? indexAttr.getX(faceIdx * 3) : faceIdx * 3;
        const i1 = indexAttr ? indexAttr.getX(faceIdx * 3 + 1) : faceIdx * 3 + 1;
        const i2 = indexAttr ? indexAttr.getX(faceIdx * 3 + 2) : faceIdx * 3 + 2;

        triPositions.push(posAttr.getX(i0), posAttr.getY(i0), posAttr.getZ(i0));
        triPositions.push(posAttr.getX(i1), posAttr.getY(i1), posAttr.getZ(i1));
        triPositions.push(posAttr.getX(i2), posAttr.getY(i2), posAttr.getZ(i2));
    });

    polygonHighlightMesh.geometry.dispose();
    const newGeo = new THREE.BufferGeometry();
    newGeo.setAttribute('position', new THREE.Float32BufferAttribute(triPositions, 3));
    newGeo.computeVertexNormals();
    polygonHighlightMesh.geometry = newGeo;

    polygonHighlightMesh.matrixAutoUpdate = false;
    polygonHighlightMesh.matrix.copy(selectedMesh.matrixWorld);
    polygonHighlightMesh.visible = true;

    updateActionBarLabel(selectedPolygonIndices.size);
    if (document.getElementById('lbl-uv-poly-count')) {
        document.getElementById('lbl-uv-poly-count').textContent = selectedPolygonIndices.size;
    }
}

function updateVertexPointsHelper() {
    if (!selectedMesh || currentEditLevel !== 1) {
        vertexPointsHelper.visible = false;
        updateActionBarLabel(0);
        return;
    }

    const geom = selectedMesh.geometry;
    const posAttr = geom.attributes.position;
    const numVerts = posAttr.count;

    const positions = new Float32Array(numVerts * 3);
    const colors = new Float32Array(numVerts * 3);

    for (let i = 0; i < numVerts; i++) {
        positions[i * 3] = posAttr.getX(i);
        positions[i * 3 + 1] = posAttr.getY(i);
        positions[i * 3 + 2] = posAttr.getZ(i);

        if (selectedVertexIndices.has(i)) {
            colors[i * 3] = 1.0; colors[i * 3 + 1] = 0.1; colors[i * 3 + 2] = 0.1; // Red
        } else {
            colors[i * 3] = 0.2; colors[i * 3 + 1] = 0.7; colors[i * 3 + 2] = 1.0; // Cyan
        }
    }

    vertexPointsHelper.geometry.dispose();
    const newGeo = new THREE.BufferGeometry();
    newGeo.setAttribute('position', new THREE.BufferAttribute(positions, 3));
    newGeo.setAttribute('color', new THREE.BufferAttribute(colors, 3));
    vertexPointsHelper.geometry = newGeo;

    vertexPointsHelper.matrixAutoUpdate = false;
    vertexPointsHelper.matrix.copy(selectedMesh.matrixWorld);
    vertexPointsHelper.visible = true;

    if (selectedVertexIndices.size > 0) attachGizmoToVertexCentroid();
    else transformControls.detach();

    updateActionBarLabel(selectedVertexIndices.size);
}

function attachGizmoToVertexCentroid() {
    if (!selectedMesh || selectedVertexIndices.size === 0) return;
    const posAttr = selectedMesh.geometry.attributes.position;

    let cx = 0, cy = 0, cz = 0;
    selectedVertexIndices.forEach(idx => {
        cx += posAttr.getX(idx); cy += posAttr.getY(idx); cz += posAttr.getZ(idx);
    });
    const count = selectedVertexIndices.size;
    const localCentroid = new THREE.Vector3(cx / count, cy / count, cz / count);
    const worldCentroid = localCentroid.clone().applyMatrix4(selectedMesh.matrixWorld);

    vertexGizmoTarget.position.copy(worldCentroid);
    vertexGizmoTarget.userData.lastWorldPos = worldCentroid.clone();
    transformControls.attach(vertexGizmoTarget);
}

function applyVertexGizmoDrag() {
    if (!selectedMesh || selectedVertexIndices.size === 0 || !vertexGizmoTarget.userData.lastWorldPos) return;

    const currentPos = vertexGizmoTarget.position;
    const deltaWorld = currentPos.clone().sub(vertexGizmoTarget.userData.lastWorldPos);

    const invMat = new THREE.Matrix4().copy(selectedMesh.matrixWorld).invert();
    const deltaLocal = deltaWorld.clone().transformDirection(invMat);

    const posAttr = selectedMesh.geometry.attributes.position;
    selectedVertexIndices.forEach(idx => {
        posAttr.setXYZ(idx, posAttr.getX(idx) + deltaLocal.x, posAttr.getY(idx) + deltaLocal.y, posAttr.getZ(idx) + deltaLocal.z);
    });

    posAttr.needsUpdate = true;
    selectedMesh.geometry.computeVertexNormals();

    vertexGizmoTarget.userData.lastWorldPos = currentPos.clone();
    updateVertexPointsHelper();
}

function updateActionBarLabel(count) {
    const lbl = document.getElementById('act-bar-label');
    if (lbl) lbl.textContent = `${count} ta tanlangan`;
}

// -------------------------------------------------------------
// RAYCASTER & POINTER INTERACTION
// -------------------------------------------------------------
function setupRaycaster() {
    const raycaster = new THREE.Raycaster();
    const mouse = new THREE.Vector2();
    let touchStartTime = 0;

    renderer.domElement.addEventListener('touchstart', () => { touchStartTime = Date.now(); });

    renderer.domElement.addEventListener('touchend', (e) => {
        if (Date.now() - touchStartTime > 300) return;
        if (e.changedTouches.length !== 1) return;
        handlePointerSelect(e.changedTouches[0].clientX, e.changedTouches[0].clientY);
    });

    renderer.domElement.addEventListener('click', (e) => {
        handlePointerSelect(e.clientX, e.clientY);
    });

    function handlePointerSelect(clientX, clientY) {
        if (transformControls.dragging) return;

        let activeCam = camera3D;

        if (isQuadMode) {
            const halfW = window.innerWidth / 2;
            const halfH = window.innerHeight / 2;

            if (clientX < halfW && clientY < halfH) {
                activeViewportIndex = 0; activeCam = cameraTop;
                mouse.x = (clientX / halfW) * 2 - 1; mouse.y = -(clientY / halfH) * 2 + 1;
            } else if (clientX >= halfW && clientY < halfH) {
                activeViewportIndex = 1; activeCam = cameraFront;
                mouse.x = ((clientX - halfW) / halfW) * 2 - 1; mouse.y = -(clientY / halfH) * 2 + 1;
            } else if (clientX < halfW && clientY >= halfH) {
                activeViewportIndex = 2; activeCam = cameraLeft;
                mouse.x = (clientX / halfW) * 2 - 1; mouse.y = -((clientY - halfH) / halfH) * 2 + 1;
            } else {
                activeViewportIndex = 3; activeCam = camera3D;
                mouse.x = ((clientX - halfW) / halfW) * 2 - 1; mouse.y = -((clientY - halfH) / halfH) * 2 + 1;
            }
            updateActiveViewportBorder();
        } else {
            activeCam = viewports[activeViewportIndex].camera;
            mouse.x = (clientX / window.innerWidth) * 2 - 1;
            mouse.y = -(clientY / window.innerHeight) * 2 + 1;
        }

        raycaster.setFromCamera(mouse, activeCam);
        if (!currentRootGroup) return;

        if (currentEditLevel === 4) {
            // Object Selection
            const intersects = raycaster.intersectObjects(currentRootGroup.children, true);
            if (intersects.length > 0) {
                let hitObj = intersects[0].object;
                let meshCandidate = (hitObj instanceof THREE.Mesh) ? hitObj : null;

                while (hitObj && hitObj.parent !== currentRootGroup && hitObj.parent !== scene) {
                    if (hitObj.userData && hitObj.userData.frameIndex !== undefined) break;
                    hitObj = hitObj.parent;
                }
                if (hitObj && hitObj.userData && hitObj.userData.frameIndex !== undefined) {
                    // Select node WITHOUT auto-opening the inspector drawer!
                    selectNodeByIndex(hitObj.userData.frameIndex, meshCandidate, false);
                }
            }
        } else if (currentEditLevel === 3) {
            // Polygon Selection
            if (!selectedMesh) return;
            const intersects = raycaster.intersectObject(selectedMesh, false);
            if (intersects.length > 0) {
                const faceIndex = intersects[0].faceIndex;
                if (selectedPolygonIndices.has(faceIndex)) selectedPolygonIndices.delete(faceIndex);
                else selectedPolygonIndices.add(faceIndex);
                updatePolygonHighlight();
            }
        } else if (currentEditLevel === 1) {
            // Vertex Selection
            if (!selectedMesh) return;
            const posAttr = selectedMesh.geometry.attributes.position;
            const intersects = raycaster.intersectObject(selectedMesh, false);
            if (intersects.length > 0) {
                const face = intersects[0].face;
                const hitPointLocal = intersects[0].point.clone().applyMatrix4(new THREE.Matrix4().copy(selectedMesh.matrixWorld).invert());
                const vA = new THREE.Vector3(posAttr.getX(face.a), posAttr.getY(face.a), posAttr.getZ(face.a));
                const vB = new THREE.Vector3(posAttr.getX(face.b), posAttr.getY(face.b), posAttr.getZ(face.b));
                const vC = new THREE.Vector3(posAttr.getX(face.c), posAttr.getY(face.c), posAttr.getZ(face.c));

                let closest = face.a;
                let minDist = hitPointLocal.distanceTo(vA);
                if (hitPointLocal.distanceTo(vB) < minDist) { closest = face.b; minDist = hitPointLocal.distanceTo(vB); }
                if (hitPointLocal.distanceTo(vC) < minDist) closest = face.c;

                if (selectedVertexIndices.has(closest)) selectedVertexIndices.delete(closest);
                else selectedVertexIndices.add(closest);
                updateVertexPointsHelper();
            }
        }
    }

    const loader = document.getElementById('app-loading-state');
    if (loader) {
        loader.style.opacity = '0';
        setTimeout(() => loader.remove(), 300);
    }
}

// -------------------------------------------------------------
// POLYGON & VERTEX OPERATIONS
// -------------------------------------------------------------
function detachSelectedPolygons() {
    if (!selectedMesh || selectedPolygonIndices.size === 0 || !currentDFF) {
        showToast("Ajratish uchun avval poligonlarni tanlang!");
        return;
    }

    const partName = prompt("Yangi detal nomi:", `${selectedNode.name}_part`);
    if (!partName) return;

    const oldGeom = selectedMesh.geometry;
    const oldIndex = oldGeom.index;
    const oldPos = oldGeom.attributes.position;
    const oldNorm = oldGeom.attributes.normal;
    const oldUv = oldGeom.attributes.uv;

    const keepIndices = [];
    const detachedIndices = [];
    const detachedVertexMap = new Map();
    const newPositions = [];
    const newNormals = [];
    const newUvs = [];

    const numFaces = oldIndex.count / 3;

    for (let f = 0; f < numFaces; f++) {
        const i0 = oldIndex.getX(f * 3);
        const i1 = oldIndex.getX(f * 3 + 1);
        const i2 = oldIndex.getX(f * 3 + 2);

        if (selectedPolygonIndices.has(f)) {
            [i0, i1, i2].forEach(oldIdx => {
                if (!detachedVertexMap.has(oldIdx)) {
                    const newIdx = detachedVertexMap.size;
                    detachedVertexMap.set(oldIdx, newIdx);
                    newPositions.push(oldPos.getX(oldIdx), oldPos.getY(oldIdx), oldPos.getZ(oldIdx));
                    if (oldNorm) newNormals.push(oldNorm.getX(oldIdx), oldNorm.getY(oldIdx), oldNorm.getZ(oldIdx));
                    if (oldUv) newUvs.push(oldUv.getX(oldIdx), oldUv.getY(oldIdx));
                }
                detachedIndices.push(detachedVertexMap.get(oldIdx));
            });
        } else {
            keepIndices.push(i0, i1, i2);
        }
    }

    oldGeom.setIndex(keepIndices);
    oldGeom.groups = [{ start: 0, count: keepIndices.length, materialIndex: 0 }];

    const newFrameIndex = currentDFF.frames.length;
    const parentIndex = selectedNode.userData.frameIndex;

    const newFrame = {
        index: newFrameIndex,
        name: partName.trim(),
        rot: [1, 0, 0, 0, 1, 0, 0, 0, 1],
        pos: [0, 0, 0],
        parentIndex: parentIndex,
        matrixFlags: 0x00020003,
        extensions: []
    };
    currentDFF.frames.push(newFrame);

    const newBufferGeom = new THREE.BufferGeometry();
    newBufferGeom.setAttribute('position', new THREE.Float32BufferAttribute(newPositions, 3));
    if (newNormals.length > 0) newBufferGeom.setAttribute('normal', new THREE.Float32BufferAttribute(newNormals, 3));
    if (newUvs.length > 0) newBufferGeom.setAttribute('uv', new THREE.Float32BufferAttribute(newUvs, 2));
    newBufferGeom.setIndex(detachedIndices);
    newBufferGeom.computeVertexNormals();

    const newMesh = new THREE.Mesh(newBufferGeom, selectedMesh.material);
    newMesh.userData = { frameIndex: newFrameIndex };

    const newGroup = new THREE.Group();
    newGroup.name = newFrame.name;
    newGroup.userData = { frameIndex: newFrameIndex, frameData: newFrame };
    newGroup.add(newMesh);

    frameGroups.push(newGroup);
    selectedNode.add(newGroup);

    selectedPolygonIndices.clear();
    updatePolygonHighlight();
    renderHierarchyList();
    selectNodeByIndex(newFrameIndex, newMesh, false);
    showToast(`⚡ Ajratildi: "${partName}" yangi detalga aylandi!`);
}

function deleteSelectedElements() {
    if (currentEditLevel === 3) {
        if (!selectedMesh || selectedPolygonIndices.size === 0) return;
        const geom = selectedMesh.geometry;
        const oldIndex = geom.index;
        const keepIndices = [];
        const numFaces = oldIndex.count / 3;

        for (let f = 0; f < numFaces; f++) {
            if (!selectedPolygonIndices.has(f)) {
                keepIndices.push(oldIndex.getX(f * 3), oldIndex.getX(f * 3 + 1), oldIndex.getX(f * 3 + 2));
            }
        }

        geom.setIndex(keepIndices);
        geom.groups = [{ start: 0, count: keepIndices.length, materialIndex: 0 }];
        selectedPolygonIndices.clear();
        updatePolygonHighlight();
        showToast("Tanlangan poligonlar o'chirildi!");
    } else if (currentEditLevel === 1) {
        if (!selectedMesh || selectedVertexIndices.size === 0) return;
        const geom = selectedMesh.geometry;
        const oldIndex = geom.index;
        const keepIndices = [];
        const numFaces = oldIndex.count / 3;

        for (let f = 0; f < numFaces; f++) {
            const i0 = oldIndex.getX(f * 3);
            const i1 = oldIndex.getX(f * 3 + 1);
            const i2 = oldIndex.getX(f * 3 + 2);
            if (!selectedVertexIndices.has(i0) && !selectedVertexIndices.has(i1) && !selectedVertexIndices.has(i2)) {
                keepIndices.push(i0, i1, i2);
            }
        }

        geom.setIndex(keepIndices);
        geom.groups = [{ start: 0, count: keepIndices.length, materialIndex: 0 }];
        selectedVertexIndices.clear();
        updateVertexPointsHelper();
        showToast("Tanlangan nuqtalar o'chirildi!");
    }
}

function flipSelectedPolygons() {
    if (!selectedMesh || selectedPolygonIndices.size === 0) return;
    const geom = selectedMesh.geometry;
    const indexAttr = geom.index;

    selectedPolygonIndices.forEach(faceIdx => {
        const i1 = indexAttr.getX(faceIdx * 3 + 1);
        const i2 = indexAttr.getX(faceIdx * 3 + 2);
        indexAttr.setX(faceIdx * 3 + 1, i2);
        indexAttr.setX(faceIdx * 3 + 2, i1);
    });

    indexAttr.needsUpdate = true;
    geom.computeVertexNormals();
    updatePolygonHighlight();
    showToast("🔄 Poligonlar o'girildi (Normallar teskarilandi)");
}

function weldVertices(threshold = 0.005) {
    if (!selectedMesh) return;
    const geom = selectedMesh.geometry;
    const posAttr = geom.attributes.position;
    const indexAttr = geom.index;
    const numVerts = posAttr.count;

    const targetVerts = selectedVertexIndices.size > 0 ? Array.from(selectedVertexIndices) : Array.from({ length: numVerts }, (_, i) => i);
    const weldMap = new Map();

    let weldedCount = 0;
    for (let i = 0; i < targetVerts.length; i++) {
        const idxA = targetVerts[i];
        if (weldMap.has(idxA)) continue;

        const vA = new THREE.Vector3(posAttr.getX(idxA), posAttr.getY(idxA), posAttr.getZ(idxA));

        for (let j = i + 1; j < targetVerts.length; j++) {
            const idxB = targetVerts[j];
            if (weldMap.has(idxB)) continue;

            const vB = new THREE.Vector3(posAttr.getX(idxB), posAttr.getY(idxB), posAttr.getZ(idxB));
            if (vA.distanceTo(vB) <= threshold) {
                weldMap.set(idxB, idxA);
                weldedCount++;
            }
        }
    }

    if (weldedCount === 0) {
        showToast(`Weld: Ushbu oraliqda (${(threshold * 1000).toFixed(1)}mm) birlashtiriladigan nuqtalar topilmadi`);
        return;
    }

    for (let k = 0; k < indexAttr.count; k++) {
        const idx = indexAttr.getX(k);
        if (weldMap.has(idx)) indexAttr.setX(k, weldMap.get(idx));
    }

    indexAttr.needsUpdate = true;
    geom.computeVertexNormals();
    updateVertexPointsHelper();
    showToast(`🔗 Weld yakunlandi: ${weldedCount} ta nuqta birlashtirildi!`);
}

// -------------------------------------------------------------
// RENDERWARE DFF PARSING & 32-BIT BUFFERGEOMETRY (34MB+ FIX)
// -------------------------------------------------------------
function buildThreeSceneFromDFF(dff) {
    if (currentRootGroup) scene.remove(currentRootGroup);
    transformControls.detach();
    selectedNode = null;
    selectedMesh = null;
    selectedPolygonIndices.clear();
    selectedVertexIndices.clear();

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

        group.position.set(frame.pos[0], frame.pos[1], frame.pos[2]);

        const m = new THREE.Matrix4();
        m.set(
            frame.rot[0], frame.rot[3], frame.rot[6], 0,
            frame.rot[1], frame.rot[4], frame.rot[7], 0,
            frame.rot[2], frame.rot[5], frame.rot[8], 0,
            0, 0, 0, 1
        );
        group.quaternion.setFromRotationMatrix(m);

        frameGroups.push(group);

        if (frame.name.includes("wheel_") && frame.name.includes("_dummy")) {
            initialWheelPositions[frame.name] = frame.pos[2];
        }
    }

    // 2. Assemble Hierarchy
    for (let i = 0; i < dff.frames.length; i++) {
        const frame = dff.frames[i];
        const group = frameGroups[i];

        if (frame.parentIndex >= 0 && frame.parentIndex < frameGroups.length) {
            frameGroups[frame.parentIndex].add(group);
        } else {
            currentRootGroup.add(group);
        }
    }

    // 3. Attach Geometries using Tristrip Unpacker & 32-bit Indices
    for (let i = 0; i < dff.atomics.length; i++) {
        const at = dff.atomics[i];
        if (at.frameIndex >= frameGroups.length || at.geometryIndex >= dff.geometries.length) continue;

        const targetGroup = frameGroups[at.frameIndex];
        const geom = dff.geometries[at.geometryIndex];
        const bufferGeom = new THREE.BufferGeometry();

        if (geom.vertices && geom.vertices.length > 0) {
            const posArray = new Float32Array(geom.vertices.length * 3);
            for (let v = 0; v < geom.vertices.length; v++) {
                posArray[v * 3] = geom.vertices[v].x;
                posArray[v * 3 + 1] = geom.vertices[v].y;
                posArray[v * 3 + 2] = geom.vertices[v].z;
            }
            bufferGeom.setAttribute('position', new THREE.BufferAttribute(posArray, 3));
        }

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

        if (geom.texCoordSets && geom.texCoordSets.length > 0 && geom.texCoordSets[0].length > 0) {
            const uvSet = geom.texCoordSets[0];
            const uvArray = new Float32Array(uvSet.length * 2);
            for (let u = 0; u < uvSet.length; u++) {
                uvArray[u * 2] = uvSet[u].u;
                uvArray[u * 2 + 1] = isUVFlipped ? (1.0 - uvSet[u].v) : uvSet[u].v;
            }
            bufferGeom.setAttribute('uv', new THREE.BufferAttribute(uvArray, 2));
        }

        if (geom.colors && geom.colors.length > 0) {
            const colArray = new Float32Array(geom.colors.length * 3);
            for (let c = 0; c < geom.colors.length; c++) {
                colArray[c * 3] = geom.colors[c].r / 255.0;
                colArray[c * 3 + 1] = geom.colors[c].g / 255.0;
                colArray[c * 3 + 2] = geom.colors[c].b / 255.0;
            }
            bufferGeom.setAttribute('color', new THREE.BufferAttribute(colArray, 3));
        }

        // Unpack Tristrips & Multi-Materials
        const unpackedMeshes = DFFModel.getGeometryTriangles(geom);
        let allIndices = [];

        if (unpackedMeshes && unpackedMeshes.length > 0) {
            for (const sub of unpackedMeshes) {
                const start = allIndices.length;
                for (let k = 0; k < sub.indices.length; k++) allIndices.push(sub.indices[k]);
                bufferGeom.addGroup(start, sub.indices.length, sub.matIndex);
            }
        }

        const needsUint32 = (geom.numVertices > 65535) || allIndices.some(idx => idx > 65535);
        if (needsUint32) bufferGeom.setIndex(new THREE.Uint32BufferAttribute(new Uint32Array(allIndices), 1));
        else bufferGeom.setIndex(new THREE.Uint16BufferAttribute(new Uint16Array(allIndices), 1));

        let threeMaterials = [];
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

    // 4. Attach Dummy Helpers
    for (let i = 0; i < frameGroups.length; i++) {
        const grp = frameGroups[i];
        const hasMeshes = grp.children.some(c => c instanceof THREE.Mesh && !c.name.includes("__dummy_"));

        if (!hasMeshes) {
            let dummyColor = 0xa855f7;
            if (grp.name.includes("wheel")) dummyColor = 0x38bdf8;
            else if (grp.name.includes("light")) dummyColor = 0xfacc15;
            else if (grp.name.includes("exhaust")) dummyColor = 0xef4444;

            const dummyGeo = new THREE.SphereGeometry(0.06, 12, 12);
            const dummyMesh = new THREE.Mesh(dummyGeo, new THREE.MeshBasicMaterial({ color: dummyColor }));
            dummyMesh.name = "__dummy_helper__";
            grp.add(dummyMesh);
            grp.add(new THREE.AxesHelper(0.18));
        }
    }

    scene.add(currentRootGroup);

    // 5. Precisely frame all 4 cameras to the model bounding box
    const box = new THREE.Box3().setFromObject(currentRootGroup);
    const center = box.getCenter(new THREE.Vector3());
    const size = box.getSize(new THREE.Vector3());
    const maxDim = Math.max(size.x, size.y, size.z, 4);

    // Update Orthographic Frustums
    updateOrthographicFrustums(maxDim);

    // Camera Top: straight down onto the roof
    cameraTop.position.set(center.x, center.y, center.z + maxDim * 2.5);
    cameraTop.lookAt(center);
    cameraTop.updateProjectionMatrix();

    // Camera Front: looking straight at the front bumper (+Y forward)
    cameraFront.position.set(center.x, center.y + maxDim * 2.5, center.z);
    cameraFront.lookAt(center);
    cameraFront.updateProjectionMatrix();

    // Camera Left: looking straight at the driver side profile (-X)
    cameraLeft.position.set(center.x - maxDim * 2.5, center.y, center.z);
    cameraLeft.lookAt(center);
    cameraLeft.updateProjectionMatrix();

    // Camera 3D: 3D perspective angled view
    camera3D.position.set(center.x - maxDim * 1.5, center.y - maxDim * 1.5, center.z + maxDim * 0.8);
    camera3D.lookAt(center);
    orbitControls.target.copy(center);
    orbitControls.update();

    // Clean initial state: Ensure 1-View full screen mode by default (No Quad overlays!)
    isQuadMode = false;
    document.getElementById('quad-container').classList.add('hidden');
    document.getElementById('vp-single-indicator').classList.remove('hidden');
    updateSingleViewBadge();

    // Close drawers if any were open
    closeAllDrawers();

    renderHierarchyList();

    document.getElementById('welcome-overlay').classList.add('hidden');
    if (isShaderMode) updateAllMaterialsShader();

    showToast(`DFF ochildi: ${dff.frames.length} qism, ${dff.geometries.length} geometriya`);
}

// -------------------------------------------------------------
// MATERIAL EDITOR & SHADERS
// -------------------------------------------------------------
function openMaterialEditorModal() {
    if (!currentDFF) { showToast("Avval modelni oching!"); return; }
    document.getElementById('modal-mat-editor').classList.remove('hidden');
    populateModalMaterialList();
}

function closeMaterialEditorModal() {
    document.getElementById('modal-mat-editor').classList.add('hidden');
}

function setupMaterialEditorModal() {
    document.getElementById('btn-close-mat-editor').addEventListener('click', closeMaterialEditorModal);
    document.getElementById('btn-open-mat-editor').addEventListener('click', openMaterialEditorModal);

    const picker = document.getElementById('modal-mat-color-picker');
    const hexInput = document.getElementById('modal-mat-color-hex');
    const alphaSlider = document.getElementById('slider-modal-mat-alpha');
    const alphaVal = document.getElementById('val-modal-mat-alpha');

    picker.addEventListener('input', (e) => {
        hexInput.value = e.target.value.toUpperCase();
        applyModalMatChanges();
    });
    hexInput.addEventListener('change', (e) => {
        picker.value = e.target.value;
        applyModalMatChanges();
    });
    alphaSlider.addEventListener('input', (e) => {
        alphaVal.textContent = e.target.value + "%";
        applyModalMatChanges();
    });

    document.getElementById('slider-modal-ambient').addEventListener('input', (e) => {
        document.getElementById('val-modal-ambient').textContent = parseFloat(e.target.value).toFixed(2);
        applyModalMatChanges();
    });
    document.getElementById('slider-modal-specular').addEventListener('input', (e) => {
        document.getElementById('val-modal-specular').textContent = parseFloat(e.target.value).toFixed(2);
        applyModalMatChanges();
    });

    document.getElementById('modal-mat-shader').addEventListener('change', (e) => {
        applyShaderPreset(e.target.value);
    });

    const texInput = document.getElementById('mat-editor-tex-input');
    document.getElementById('btn-modal-load-tex').addEventListener('click', () => texInput.click());
    texInput.addEventListener('change', (e) => {
        const file = e.target.files[0];
        if (!file) return;
        const reader = new FileReader();
        reader.onload = (ev) => {
            const texLoader = new THREE.TextureLoader();
            texLoader.load(ev.target.result, (texture) => {
                texture.flipY = false;
                texture.wrapS = THREE.RepeatWrapping;
                texture.wrapT = THREE.RepeatWrapping;

                const baseName = file.name.replace(/\.[^/.]+$/, "");
                document.getElementById('modal-mat-texname').value = baseName;
                loadedTexturesPool[baseName.toLowerCase()] = texture;

                document.getElementById('modal-tex-preview-box').style.display = 'flex';
                document.getElementById('modal-tex-preview-img').src = ev.target.result;
                document.getElementById('modal-tex-preview-name').textContent = file.name;

                applyModalMatChanges(texture);
                showToast(`Tekstura ulandi: ${file.name}`);
            });
        };
        reader.readAsDataURL(file);
    });

    document.getElementById('btn-mat-assign-selected-poly').addEventListener('click', () => {
        if (!selectedMesh || selectedPolygonIndices.size === 0) {
            showToast("Avval Poligon rejimida (3) yuzalarni tanlang!");
            return;
        }
        assignMaterialToPolygons(selectedMaterialIndex);
    });

    document.getElementById('btn-mat-assign-object').addEventListener('click', () => {
        if (!selectedMesh) { showToast("Avval detalni tanlang!"); return; }
        const numFaces = selectedMesh.geometry.index.count / 3;
        selectedPolygonIndices = new Set(Array.from({ length: numFaces }, (_, i) => i));
        assignMaterialToPolygons(selectedMaterialIndex);
        showToast("Material butun detalga biriktirildi!");
    });
}

function populateModalMaterialList() {
    const list = document.getElementById('mat-modal-list');
    list.innerHTML = '';
    if (!currentDFF || currentDFF.geometries.length === 0) return;

    const allMats = [];
    currentDFF.geometries.forEach((g, gIdx) => {
        if (g.materials) {
            g.materials.forEach((m, mIdx) => {
                allMats.push({ mat: m, geomIndex: gIdx, matIndex: mIdx });
            });
        }
    });

    allMats.forEach((item, idx) => {
        const div = document.createElement('div');
        div.className = 'mat-item' + (idx === selectedMaterialIndex ? ' selected' : '');

        const swatch = document.createElement('div');
        swatch.className = 'mat-color-swatch';
        const c = item.mat.color || { r: 200, g: 200, b: 200 };
        swatch.style.background = `rgb(${c.r}, ${c.g}, ${c.b})`;

        const nameSpan = document.createElement('span');
        nameSpan.textContent = `[${idx}] ${item.mat.textureName || "Material " + (idx + 1)}`;

        div.appendChild(swatch);
        div.appendChild(nameSpan);

        div.addEventListener('click', () => {
            selectedMaterialIndex = idx;
            document.querySelectorAll('.mat-item').forEach(i => i.classList.remove('selected'));
            div.classList.add('selected');
            loadMaterialPropertiesToModal(item.mat);
        });

        list.appendChild(div);
    });

    if (allMats.length > 0) {
        loadMaterialPropertiesToModal(allMats[Math.min(selectedMaterialIndex, allMats.length - 1)].mat);
    }
}

function loadMaterialPropertiesToModal(dffMat) {
    if (!dffMat) return;
    const c = dffMat.color || { r: 255, g: 255, b: 255, a: 255 };
    const hex = "#" + ((1 << 24) + (c.r << 16) + (c.g << 8) + c.b).toString(16).slice(1).toUpperCase();

    document.getElementById('modal-mat-color-picker').value = hex;
    document.getElementById('modal-mat-color-hex').value = hex;

    const alphaPercent = Math.round((c.a !== undefined ? c.a : 255) / 2.55);
    document.getElementById('slider-modal-mat-alpha').value = alphaPercent;
    document.getElementById('val-modal-mat-alpha').textContent = alphaPercent + "%";

    document.getElementById('modal-mat-name').value = dffMat.textureName || "";
    document.getElementById('modal-mat-texname').value = dffMat.textureName || "";

    document.getElementById('slider-modal-ambient').value = dffMat.ambient || 1.0;
    document.getElementById('val-modal-ambient').textContent = (dffMat.ambient || 1.0).toFixed(2);
    document.getElementById('slider-modal-specular').value = dffMat.specular || 1.0;
    document.getElementById('val-modal-specular').textContent = (dffMat.specular || 1.0).toFixed(2);
}

function applyModalMatChanges(customTexture = null) {
    if (!selectedMesh) return;
    const mats = Array.isArray(selectedMesh.material) ? selectedMesh.material : [selectedMesh.material];
    const targetMat = mats[selectedMaterialIndex] || mats[0];
    if (!targetMat) return;

    const hex = document.getElementById('modal-mat-color-hex').value;
    const alpha = parseFloat(document.getElementById('slider-modal-mat-alpha').value) / 100.0;
    const col = new THREE.Color(hex);

    targetMat.color.copy(col);
    targetMat.transparent = alpha < 0.99;
    targetMat.opacity = alpha;
    if (customTexture) targetMat.map = customTexture;
    targetMat.needsUpdate = true;

    if (targetMat.userData && targetMat.userData.dffMat) {
        targetMat.userData.dffMat.color = {
            r: Math.round(col.r * 255),
            g: Math.round(col.g * 255),
            b: Math.round(col.b * 255),
            a: Math.round(alpha * 255)
        };
        targetMat.userData.dffMat.textureName = document.getElementById('modal-mat-texname').value.trim();
    }
}

function applyShaderPreset(presetName) {
    if (!selectedMesh) return;
    const mats = Array.isArray(selectedMesh.material) ? selectedMesh.material : [selectedMesh.material];
    const mat = mats[selectedMaterialIndex] || mats[0];
    if (!mat) return;

    if (!studioEnvMap) studioEnvMap = createStudioEnvMap();

    switch (presetName) {
        case 'paint_primary':
            mat.roughness = 0.12; mat.metalness = 0.65; mat.envMap = studioEnvMap; mat.envMapIntensity = 2.0; break;
        case 'paint_secondary':
            mat.roughness = 0.15; mat.metalness = 0.55; mat.envMap = studioEnvMap; mat.envMapIntensity = 1.8; break;
        case 'glass':
            mat.transparent = true; mat.opacity = 0.45; mat.roughness = 0.05; mat.metalness = 0.9; mat.envMap = studioEnvMap; mat.envMapIntensity = 2.8; break;
        case 'lights':
            mat.roughness = 0.2; mat.emissive = new THREE.Color(0xfff0aa); mat.emissiveIntensity = 1.2; break;
        case 'chrome':
            mat.roughness = 0.05; mat.metalness = 0.95; mat.envMap = studioEnvMap; mat.envMapIntensity = 3.0; break;
        case 'matte':
            mat.roughness = 0.9; mat.metalness = 0.0; mat.envMap = null; break;
        default:
            mat.roughness = 0.4; mat.metalness = 0.2; mat.envMap = null;
    }
    mat.needsUpdate = true;
    showToast(`Shader: ${presetName}`);
}

function assignMaterialToPolygons(matIdx) {
    if (!selectedMesh || selectedPolygonIndices.size === 0) return;
    const geom = selectedMesh.geometry;
    const numFaces = geom.index.count / 3;

    const groups = {};
    for (let f = 0; f < numFaces; f++) {
        let m = 0;
        for (const g of geom.groups) {
            if (f * 3 >= g.start && f * 3 < g.start + g.count) { m = g.materialIndex; break; }
        }
        if (selectedPolygonIndices.has(f)) m = matIdx;
        if (!groups[m]) groups[m] = [];
        groups[m].push(geom.index.getX(f * 3), geom.index.getX(f * 3 + 1), geom.index.getX(f * 3 + 2));
    }

    const newIndices = [];
    const newGroups = [];
    for (const m in groups) {
        const start = newIndices.length;
        groups[m].forEach(idx => newIndices.push(idx));
        newGroups.push({ start: start, count: groups[m].length, materialIndex: parseInt(m) });
    }

    geom.setIndex(newIndices);
    geom.groups = newGroups;

    showToast(`Material ${matIdx + 1} biriktirildi!`);
    updatePolygonHighlight();
}

// -------------------------------------------------------------
// 2D UV MAPPING EDITOR
// -------------------------------------------------------------
function setupUVEditor() {
    uvCanvas = document.getElementById('uv-canvas');
    if (!uvCanvas) return;
    uvCtx = uvCanvas.getContext('2d');

    document.getElementById('btn-open-uv-mapper').addEventListener('click', openUVEditor);
    document.getElementById('btn-close-uv-mapper').addEventListener('click', () => {
        document.getElementById('modal-uv-mapper').classList.add('hidden');
    });

    document.getElementById('btn-uv-scale-up').addEventListener('click', () => transformUV(1.1, 1.1, 0, 0));
    document.getElementById('btn-uv-scale-down').addEventListener('click', () => transformUV(0.9, 0.9, 0, 0));
    document.getElementById('btn-uv-rot-90').addEventListener('click', rotateUV90);
    document.getElementById('btn-uv-flip-h').addEventListener('click', flipUVHorizontal);
    document.getElementById('btn-uv-flip-v').addEventListener('click', flipUVVertical);
    document.getElementById('btn-uv-fit').addEventListener('click', fitUVToBounds);
    document.getElementById('btn-uv-reset').addEventListener('click', resetUV);
}

function openUVEditor() {
    if (!selectedMesh) { showToast("UV tahrirlash uchun avval detalni tanlang!"); return; }
    document.getElementById('modal-uv-mapper').classList.remove('hidden');

    if (selectedMesh.geometry && selectedMesh.geometry.attributes.uv) {
        uvOriginalCoords = new Float32Array(selectedMesh.geometry.attributes.uv.array);
    }
    drawUVCanvas();
}

function drawUVCanvas() {
    if (!uvCanvas || !uvCtx || !selectedMesh) return;
    const w = uvCanvas.width;
    const h = uvCanvas.height;

    uvCtx.fillStyle = '#080a0e';
    uvCtx.fillRect(0, 0, w, h);

    // 10x10 Grid
    uvCtx.strokeStyle = 'rgba(255, 255, 255, 0.08)';
    uvCtx.lineWidth = 1;
    for (let i = 0; i <= 10; i++) {
        const x = (w * i) / 10; const y = (h * i) / 10;
        uvCtx.beginPath(); uvCtx.moveTo(x, 0); uvCtx.lineTo(x, h); uvCtx.stroke();
        uvCtx.beginPath(); uvCtx.moveTo(0, y); uvCtx.lineTo(w, y); uvCtx.stroke();
    }

    const mats = Array.isArray(selectedMesh.material) ? selectedMesh.material : [selectedMesh.material];
    const activeMat = mats[selectedMaterialIndex] || mats[0];
    if (activeMat && activeMat.map && activeMat.map.image) {
        try {
            uvCtx.globalAlpha = 0.55;
            uvCtx.drawImage(activeMat.map.image, 0, 0, w, h);
            uvCtx.globalAlpha = 1.0;
        } catch (e) {}
    }

    const geom = selectedMesh.geometry;
    if (!geom.attributes.uv || !geom.index) return;

    const uvAttr = geom.attributes.uv;
    const indexAttr = geom.index;
    const numFaces = indexAttr.count / 3;

    for (let f = 0; f < numFaces; f++) {
        const isSel = selectedPolygonIndices.has(f);
        uvCtx.strokeStyle = isSel ? '#ef4444' : '#22c55e';

        const i0 = indexAttr.getX(f * 3);
        const i1 = indexAttr.getX(f * 3 + 1);
        const i2 = indexAttr.getX(f * 3 + 2);

        const u0 = uvAttr.getX(i0) * w; const v0 = (1.0 - uvAttr.getY(i0)) * h;
        const u1 = uvAttr.getX(i1) * w; const v1 = (1.0 - uvAttr.getY(i1)) * h;
        const u2 = uvAttr.getX(i2) * w; const v2 = (1.0 - uvAttr.getY(i2)) * h;

        uvCtx.beginPath();
        uvCtx.moveTo(u0, v0); uvCtx.lineTo(u1, v1); uvCtx.lineTo(u2, v2);
        uvCtx.closePath();
        uvCtx.stroke();
    }
}

function transformUV(scaleU, scaleV, offsetU, offsetV) {
    if (!selectedMesh || !selectedMesh.geometry.attributes.uv) return;
    const uvAttr = selectedMesh.geometry.attributes.uv;
    const arr = uvAttr.array;

    for (let i = 0; i < arr.length; i += 2) {
        arr[i] = (arr[i] - 0.5) * scaleU + 0.5 + offsetU;
        arr[i + 1] = (arr[i + 1] - 0.5) * scaleV + 0.5 + offsetV;
    }
    uvAttr.needsUpdate = true;
    drawUVCanvas();
}

function rotateUV90() {
    if (!selectedMesh || !selectedMesh.geometry.attributes.uv) return;
    const uvAttr = selectedMesh.geometry.attributes.uv;
    const arr = uvAttr.array;

    for (let i = 0; i < arr.length; i += 2) {
        const u = arr[i] - 0.5; const v = arr[i + 1] - 0.5;
        arr[i] = -v + 0.5; arr[i + 1] = u + 0.5;
    }
    uvAttr.needsUpdate = true;
    drawUVCanvas();
    showToast("🔄 UV 90° burildi");
}

function flipUVHorizontal() {
    if (!selectedMesh || !selectedMesh.geometry.attributes.uv) return;
    const uvAttr = selectedMesh.geometry.attributes.uv;
    const arr = uvAttr.array;
    for (let i = 0; i < arr.length; i += 2) arr[i] = 1.0 - arr[i];
    uvAttr.needsUpdate = true;
    drawUVCanvas();
    showToast("↔️ UV Gorizontal o'girildi");
}

function flipUVVertical() {
    if (!selectedMesh || !selectedMesh.geometry.attributes.uv) return;
    const uvAttr = selectedMesh.geometry.attributes.uv;
    const arr = uvAttr.array;
    for (let i = 1; i < arr.length; i += 2) arr[i] = 1.0 - arr[i];
    uvAttr.needsUpdate = true;
    drawUVCanvas();
    showToast("↕️ UV Vertikal o'girildi (180°)");
}

function fitUVToBounds() {
    if (!selectedMesh || !selectedMesh.geometry.attributes.uv) return;
    const uvAttr = selectedMesh.geometry.attributes.uv;
    const arr = uvAttr.array;

    let minU = Infinity, maxU = -Infinity, minV = Infinity, maxV = -Infinity;
    for (let i = 0; i < arr.length; i += 2) {
        minU = Math.min(minU, arr[i]); maxU = Math.max(maxU, arr[i]);
        minV = Math.min(minV, arr[i + 1]); maxV = Math.max(maxV, arr[i + 1]);
    }

    const rangeU = maxU - minU || 1;
    const rangeV = maxV - minV || 1;

    for (let i = 0; i < arr.length; i += 2) {
        arr[i] = (arr[i] - minU) / rangeU;
        arr[i + 1] = (arr[i + 1] - minV) / rangeV;
    }
    uvAttr.needsUpdate = true;
    drawUVCanvas();
    showToast("🔲 UV katakka moslandi");
}

function resetUV() {
    if (!selectedMesh || !uvOriginalCoords || !selectedMesh.geometry.attributes.uv) return;
    selectedMesh.geometry.attributes.uv.array.set(uvOriginalCoords);
    selectedMesh.geometry.attributes.uv.needsUpdate = true;
    drawUVCanvas();
    showToast("↩️ UV boshlang'ich holatga qaytarildi");
}

// -------------------------------------------------------------
// ENVIRONMENT MAP & SHADERS
// -------------------------------------------------------------
function createStudioEnvMap() {
    const canvas = document.createElement('canvas');
    canvas.width = 1024; canvas.height = 512;
    const ctx = canvas.getContext('2d');

    const skyGrad = ctx.createLinearGradient(0, 0, 0, 256);
    skyGrad.addColorStop(0, '#1e3a8a'); skyGrad.addColorStop(0.35, '#38bdf8'); skyGrad.addColorStop(1, '#ffffff');
    ctx.fillStyle = skyGrad; ctx.fillRect(0, 0, 1024, 256);

    const sunGrad = ctx.createRadialGradient(512, 90, 5, 512, 90, 240);
    sunGrad.addColorStop(0, '#ffffff'); sunGrad.addColorStop(1, 'rgba(255, 255, 255, 0)');
    ctx.fillStyle = sunGrad; ctx.fillRect(0, 0, 1024, 256);

    const groundGrad = ctx.createLinearGradient(0, 256, 0, 512);
    groundGrad.addColorStop(0, '#0f172a'); groundGrad.addColorStop(1, '#020617');
    ctx.fillStyle = groundGrad; ctx.fillRect(0, 256, 1024, 256);

    const texture = new THREE.CanvasTexture(canvas);
    texture.mapping = THREE.EquirectangularReflectionMapping;
    return texture;
}

function toggleShaderMode() {
    isShaderMode = !isShaderMode;
    const btn = document.getElementById('btn-toggle-shader');
    if (btn) btn.classList.toggle('active', isShaderMode);

    if (!studioEnvMap) studioEnvMap = createStudioEnvMap();

    if (isShaderMode) {
        scene.environment = studioEnvMap;
        renderer.toneMapping = THREE.ACESFilmicToneMapping;
        renderer.toneMappingExposure = 1.25;
        showToast("✨ Shader: Yaltiroq Carpaint yoqildi!");
    } else {
        scene.environment = null;
        renderer.toneMapping = THREE.NoToneMapping;
        renderer.toneMappingExposure = 1.0;
        showToast("Shader: Standart rejim");
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
                        if (combined.includes("glass") || combined.includes("window")) {
                            mat.transparent = true; mat.opacity = 0.55; mat.roughness = 0.05; mat.metalness = 0.9; mat.envMapIntensity = 2.5;
                        } else if (combined.includes("wheel") || combined.includes("rim") || combined.includes("chrom")) {
                            mat.roughness = 0.08; mat.metalness = 0.95; mat.envMapIntensity = 2.4;
                        } else if (combined.includes("light")) {
                            mat.roughness = 0.15; mat.metalness = 0.3; mat.envMapIntensity = 1.6;
                        } else {
                            mat.roughness = 0.12; mat.metalness = 0.65; mat.envMapIntensity = 1.9;
                        }
                    } else {
                        mat.roughness = 0.4; mat.metalness = 0.2; mat.envMapIntensity = 0.5;
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
    if (btn) btn.classList.toggle('active', isUVFlipped);

    if (!currentRootGroup) return;
    currentRootGroup.traverse(obj => {
        if (obj instanceof THREE.Mesh && obj.geometry && obj.geometry.attributes.uv) {
            const uvAttr = obj.geometry.attributes.uv;
            const array = uvAttr.array;
            for (let i = 1; i < array.length; i += 2) array[i] = 1.0 - array[i];
            uvAttr.needsUpdate = true;
        }
    });
    showToast(isUVFlipped ? "🔄 UV: Teskari qilindi (180°)" : "🔄 UV: Asl holatga keltirildi");
}

// -------------------------------------------------------------
// UI SETUP & GENERAL EVENT HANDLERS
// -------------------------------------------------------------
function setupUIEvents() {
    // Native File Picker Bridge
    const triggerFilePicker = (mode) => {
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.openDocumentPicker) {
            window.webkit.messageHandlers.openDocumentPicker.postMessage({ mode: mode });
        } else {
            if (mode === "txd") document.getElementById('txd-file-input').click();
            else if (mode === "merge") document.getElementById('dff-merge-input').click();
            else document.getElementById('dff-file-input').click();
        }
    };

    // File Menu Toggle
    const btnMenuFile = document.getElementById('btn-menu-file');
    const menuFile = document.getElementById('menu-file');
    btnMenuFile.addEventListener('click', (e) => {
        e.stopPropagation();
        menuFile.classList.toggle('hidden');
    });
    document.addEventListener('click', () => menuFile.classList.add('hidden'));

    document.getElementById('btn-open-file').addEventListener('click', () => triggerFilePicker("open"));
    document.getElementById('btn-open-txd').addEventListener('click', () => triggerFilePicker("txd"));
    document.getElementById('btn-merge-file').addEventListener('click', () => triggerFilePicker("merge"));
    document.getElementById('btn-hier-add-dff').addEventListener('click', () => triggerFilePicker("merge"));
    document.getElementById('btn-export-dff').addEventListener('click', exportCurrentDFF);
    document.getElementById('btn-quick-export').addEventListener('click', exportCurrentDFF);

    // Fallback file input listeners
    document.getElementById('dff-file-input').addEventListener('change', handleFileInput);
    document.getElementById('txd-file-input').addEventListener('change', handleTXDInput);
    document.getElementById('dff-merge-input').addEventListener('change', handleMergeInput);

    // Quad View Toggle
    document.getElementById('btn-toggle-quad-mode').addEventListener('click', toggleQuadMode);
    document.getElementById('btn-quick-switch-quad').addEventListener('click', toggleQuadMode);

    document.querySelectorAll('.vp-btn').forEach(btn => {
        btn.addEventListener('click', (e) => {
            e.stopPropagation();
            maximizeViewport(parseInt(btn.dataset.vp));
        });
    });

    // Edit Level Buttons (1: Nuqta, 2: Qirra, 3: Poligon, 4: Detal)
    document.querySelectorAll('.level-btn').forEach(b => {
        b.addEventListener('click', () => setEditLevel(parseInt(b.dataset.level)));
    });

    // Action Bar buttons
    document.getElementById('btn-act-detach').addEventListener('click', detachSelectedPolygons);
    document.getElementById('btn-act-delete').addEventListener('click', deleteSelectedElements);
    document.getElementById('btn-act-flip').addEventListener('click', flipSelectedPolygons);
    document.getElementById('btn-act-assign-mat').addEventListener('click', openMaterialEditorModal);
    document.getElementById('btn-act-weld').addEventListener('click', () => {
        document.getElementById('modal-weld-threshold').classList.remove('hidden');
    });
    document.getElementById('btn-act-clear').addEventListener('click', () => {
        selectedPolygonIndices.clear();
        selectedVertexIndices.clear();
        updatePolygonHighlight();
        updateVertexPointsHelper();
        document.getElementById('action-floating-bar').classList.add('hidden');
    });

    // Weld threshold modal
    document.getElementById('btn-close-weld-modal').addEventListener('click', () => {
        document.getElementById('modal-weld-threshold').classList.add('hidden');
    });
    document.getElementById('slider-weld-threshold').addEventListener('input', (e) => {
        const m = parseFloat(e.target.value);
        document.getElementById('val-weld-threshold').textContent = `${m.toFixed(3)} m (${(m * 1000).toFixed(0)}mm)`;
    });
    document.getElementById('btn-confirm-weld').addEventListener('click', () => {
        const threshold = parseFloat(document.getElementById('slider-weld-threshold').value);
        weldVertices(threshold);
        document.getElementById('modal-weld-threshold').classList.add('hidden');
    });

    // Gizmo Switcher
    const gizmoBtns = document.querySelectorAll('.gizmo-btn');
    gizmoBtns.forEach(btn => {
        btn.addEventListener('click', () => {
            gizmoBtns.forEach(b => b.classList.remove('active'));
            btn.classList.add('active');
            transformControls.setMode(btn.dataset.mode);
        });
    });

    // Toolbar buttons
    document.getElementById('btn-toggle-wireframe').addEventListener('click', (e) => {
        isWireframe = !isWireframe;
        e.currentTarget.classList.toggle('active', isWireframe);
        if (currentRootGroup) {
            currentRootGroup.traverse(child => {
                if (child instanceof THREE.Mesh && !child.name.includes("__dummy_")) {
                    if (Array.isArray(child.material)) child.material.forEach(m => m.wireframe = isWireframe);
                    else if (child.material) child.material.wireframe = isWireframe;
                }
            });
        }
    });

    document.getElementById('btn-toggle-dummies').addEventListener('click', (e) => {
        showDummies = !showDummies;
        e.currentTarget.classList.toggle('active', showDummies);
        if (currentRootGroup) {
            currentRootGroup.traverse(child => {
                if (child.name.includes("__dummy_")) child.visible = showDummies;
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
            camera3D.position.set(center.x - maxDim * 1.5, center.y - maxDim * 1.5, center.z + maxDim * 0.8);
            camera3D.lookAt(center);
            orbitControls.update();
        }
    });

    // Drawers & Backdrop Management (Easy toggle and dismiss on tap outside!)
    const leftDrawer = document.getElementById('drawer-hierarchy');
    const rightDrawer = document.getElementById('drawer-inspector');
    const backdrop = document.getElementById('drawer-backdrop');

    const toggleDrawer = (drawerToOpen, drawerToClose) => {
        drawerToClose.classList.add('collapsed');
        drawerToOpen.classList.toggle('collapsed');
        const isOpen = !drawerToOpen.classList.contains('collapsed');
        backdrop.classList.toggle('active', isOpen);
    };

    const closeAllDrawers = () => {
        leftDrawer.classList.add('collapsed');
        rightDrawer.classList.add('collapsed');
        backdrop.classList.remove('active');
    };

    document.getElementById('btn-toggle-hierarchy').addEventListener('click', () => toggleDrawer(leftDrawer, rightDrawer));
    document.getElementById('btn-toggle-inspector').addEventListener('click', () => toggleDrawer(rightDrawer, leftDrawer));
    document.getElementById('btn-close-hierarchy').addEventListener('click', closeAllDrawers);
    document.getElementById('btn-close-inspector').addEventListener('click', closeAllDrawers);
    backdrop.addEventListener('click', closeAllDrawers);

    // Inspector Tabs
    const tabBtns = document.querySelectorAll('.tab-btn');
    tabBtns.forEach(btn => {
        btn.addEventListener('click', () => {
            tabBtns.forEach(b => b.classList.remove('active'));
            btn.classList.add('active');
            document.querySelectorAll('.tab-content').forEach(c => c.style.display = 'none');
            document.getElementById(`tab-${btn.dataset.tab}`).style.display = 'flex';
        });
    });

    // Rename Node
    document.getElementById('btn-apply-rename').addEventListener('click', () => {
        if (!selectedNode) return;
        const newName = document.getElementById('input-node-name').value.trim();
        if (!newName) return;
        selectedNode.name = newName;
        const idx = selectedNode.userData.frameIndex;
        if (currentDFF && currentDFF.frames[idx]) currentDFF.frames[idx].name = newName;
        document.getElementById('inspector-title').textContent = newName;
        renderHierarchyList();
        showToast(`Nom o'zgartirildi: ${newName}`);
    });

    // Stance Tuning Sliders & Coordinate inputs
    setupStanceTuning();
    setupCoordinateInputs();

    // Hierarchy Drag & Drop and buttons
    document.getElementById('btn-move-up').addEventListener('click', () => {
        if (selectedNode) moveNodeOrder(selectedNode.userData.frameIndex, -1);
    });
    document.getElementById('btn-move-down').addEventListener('click', () => {
        if (selectedNode) moveNodeOrder(selectedNode.userData.frameIndex, 1);
    });
    document.getElementById('btn-reparent').addEventListener('click', reparentSelectedNode);
    document.getElementById('btn-delete-node').addEventListener('click', deleteSelectedNode);
    document.getElementById('btn-add-dummy').addEventListener('click', showAddDummyDialog);
}

function handleFileInput(e) {
    const fileList = Array.from(e.target.files);
    if (fileList.length === 0) return;
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
                txdFiles.forEach(tf => {
                    const tr = new FileReader();
                    tr.onload = (ev) => processTXDData(ev.target.result, tf.name);
                    tr.readAsArrayBuffer(tf);
                });
                imgFiles.forEach(im => processImageFile(im));
            } catch (err) {
                alert("DFF ochishda xatolik: " + err.message);
            }
        };
        reader.readAsArrayBuffer(dffFile);
    }
}

function handleTXDInput(e) {
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
}

function handleMergeInput(e) {
    const file = e.target.files[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = (event) => mergeExternalDFF(event.target.result, file.name);
    reader.readAsArrayBuffer(file);
}

function closeAllDrawers() {
    const leftDrawer = document.getElementById('drawer-hierarchy');
    const rightDrawer = document.getElementById('drawer-inspector');
    const backdrop = document.getElementById('drawer-backdrop');
    if (leftDrawer) leftDrawer.classList.add('collapsed');
    if (rightDrawer) rightDrawer.classList.add('collapsed');
    if (backdrop) backdrop.classList.remove('active');
}

function handleMenuAction(action) {
    switch (action) {
        case 'mirror-x': mirrorSelectedNode('x'); break;
        case 'mirror-y': mirrorSelectedNode('y'); break;
        case 'mirror-z': mirrorSelectedNode('z'); break;
        case 'reorient-pivot': centerNodePivot(); break;
        case 'calc-normals':
            if (selectedMesh) {
                selectedMesh.geometry.computeVertexNormals();
                showToast("Normallar hisoblandi!");
            }
            break;
        case 'flip-normals':
            if (selectedMesh) {
                const normAttr = selectedMesh.geometry.attributes.normal;
                if (normAttr) {
                    for (let i = 0; i < normAttr.array.length; i++) normAttr.array[i] *= -1;
                    normAttr.needsUpdate = true;
                    showToast("Normallar teskarilandi!");
                }
            }
            break;
    }
}

function mirrorSelectedNode(axis) {
    if (!selectedNode) { showToast("Avval detalni tanlang!"); return; }
    selectedNode.scale[axis] *= -1;
    selectedNode.traverse(c => {
        if (c instanceof THREE.Mesh && c.geometry && c.geometry.index) {
            const idxAttr = c.geometry.index;
            for (let i = 0; i < idxAttr.count; i += 3) {
                const tmp = idxAttr.getX(i + 1);
                idxAttr.setX(i + 1, idxAttr.getX(i + 2));
                idxAttr.setX(i + 2, tmp);
            }
            idxAttr.needsUpdate = true;
            c.geometry.computeVertexNormals();
        }
    });
    showToast(`🪞 Mirror ${axis.toUpperCase()} qo'llandi!`);
}

function centerNodePivot() {
    if (!selectedNode) return;
    const box = new THREE.Box3().setFromObject(selectedNode);
    const center = box.getCenter(new THREE.Vector3());
    const delta = center.clone().sub(selectedNode.position);
    selectedNode.position.copy(center);
    selectedNode.children.forEach(c => c.position.sub(delta));
    showToast("🎯 Pivot detal markaziga to'g'rilandi!");
}

// -------------------------------------------------------------
// STANCE TUNING & COORDINATES
// -------------------------------------------------------------
function setupStanceTuning() {
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

    const scaleSlider = document.getElementById('slider-scale');
    const scaleVal = document.getElementById('val-scale');
    scaleSlider.addEventListener('input', (e) => {
        const scale = parseFloat(e.target.value);
        scaleVal.textContent = scale.toFixed(2) + "x";
        frameGroups.forEach(grp => {
            if (grp.name.includes("wheel_") && grp.name.includes("_dummy")) grp.scale.set(scale, scale, scale);
        });
        if (selectedNode) updateInspectorCoordinates(selectedNode);
    });

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
}

function setupCoordinateInputs() {
    ['pos', 'rot', 'scale'].forEach(type => {
        ['x', 'y', 'z'].forEach(axis => {
            const input = document.getElementById(`${type}-${axis}`);
            const btnPlus = document.getElementById(`btn-${type}-${axis}-plus`);
            const btnMinus = document.getElementById(`btn-${type}-${axis}-minus`);
            const step = type === 'rot' ? 5.0 : 0.05;

            input.addEventListener('change', () => {
                if (!selectedNode) return;
                applyCoordinateChange(type, axis, parseFloat(input.value) || 0);
            });
            btnPlus.addEventListener('click', () => {
                if (!selectedNode) return;
                let val = (parseFloat(input.value) || 0) + step;
                input.value = val.toFixed(type === 'rot' ? 1 : 3);
                applyCoordinateChange(type, axis, val);
            });
            btnMinus.addEventListener('click', () => {
                if (!selectedNode) return;
                let val = (parseFloat(input.value) || 0) - step;
                input.value = val.toFixed(type === 'rot' ? 1 : 3);
                applyCoordinateChange(type, axis, val);
            });
        });
    });
}

function applyCoordinateChange(type, axis, val) {
    if (!selectedNode) return;
    if (type === 'pos') selectedNode.position[axis] = val;
    else if (type === 'rot') selectedNode.rotation[axis] = val * (Math.PI / 180.0);
    else if (type === 'scale') selectedNode.scale[axis] = val;
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

// -------------------------------------------------------------
// NODE SELECTION & HIERARCHY TREE
// -------------------------------------------------------------
// openInspectorDrawer parameter: false by default to prevent unwanted clutter!
function selectNodeByIndex(index, specificMesh = null, openDrawer = false) {
    if (index < 0 || index >= frameGroups.length) return;
    const grp = frameGroups[index];
    selectedNode = grp;

    if (currentEditLevel === 4) {
        transformControls.attach(grp);
    }

    if (!specificMesh) {
        specificMesh = grp.children.find(c => c instanceof THREE.Mesh && !c.name.includes("__dummy_"));
    }
    selectedMesh = specificMesh;

    document.querySelectorAll('.node-item').forEach(item => {
        item.classList.toggle('selected', parseInt(item.dataset.index) === index);
    });

    document.getElementById('inspector-title').textContent = grp.name;
    document.getElementById('input-node-name').value = grp.name;
    updateInspectorCoordinates(grp);

    if (openDrawer) {
        document.getElementById('drawer-inspector').classList.remove('collapsed');
        document.getElementById('drawer-backdrop').classList.add('active');
    }

    selectedPolygonIndices.clear();
    selectedVertexIndices.clear();
    updatePolygonHighlight();
    updateVertexPointsHelper();
}

function renderHierarchyList() {
    const listContainer = document.getElementById('hierarchy-list');
    listContainer.innerHTML = '';

    frameGroups.forEach((grp, idx) => {
        const item = document.createElement('div');
        item.className = 'node-item' + (selectedNode === grp ? ' selected' : '');
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

        const editBtn = document.createElement('button');
        editBtn.className = 'node-eye';
        editBtn.innerHTML = "✏️";
        editBtn.addEventListener('click', (e) => {
            e.stopPropagation();
            const newName = prompt("Yangi nom:", grp.name);
            if (newName && newName.trim()) {
                grp.name = newName.trim();
                currentDFF.frames[idx].name = newName.trim();
                renderHierarchyList();
                showToast(`Nom o'zgardi: ${grp.name}`);
            }
        });

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

        item.addEventListener('click', () => selectNodeByIndex(idx, null, false));

        listContainer.appendChild(item);
    });
}

function moveNodeOrder(index, direction) {
    if (!currentDFF) return;
    const targetIdx = index + direction;
    if (targetIdx < 0 || targetIdx >= currentDFF.frames.length) return;

    const tempFrame = currentDFF.frames[index];
    currentDFF.frames[index] = currentDFF.frames[targetIdx];
    currentDFF.frames[targetIdx] = tempFrame;
    currentDFF.frames[index].index = index;
    currentDFF.frames[targetIdx].index = targetIdx;

    const tempGrp = frameGroups[index];
    frameGroups[index] = frameGroups[targetIdx];
    frameGroups[targetIdx] = tempGrp;
    frameGroups[index].userData.frameIndex = index;
    frameGroups[targetIdx].userData.frameIndex = targetIdx;

    renderHierarchyList();
    selectNodeByIndex(targetIdx, null, false);
}

function reparentSelectedNode() {
    if (!selectedNode || !currentDFF) return;
    const currentIdx = selectedNode.userData.frameIndex;
    const currentName = selectedNode.name;

    const list = currentDFF.frames.map((f, i) => `${i}: ${f.name}`).slice(0, 30).join("\n");
    const input = prompt(`"${currentName}" ni qaysi detal ichiga biriktirasiz?\nRaqamini kiriting:\n\n${list}`);
    if (!input) return;

    const targetIdx = parseInt(input.trim());
    if (isNaN(targetIdx) || targetIdx < 0 || targetIdx >= currentDFF.frames.length || targetIdx === currentIdx) {
        alert("Noto'g'ri raqam kiritildi!");
        return;
    }

    currentDFF.frames[currentIdx].parentIndex = targetIdx;
    frameGroups[targetIdx].add(selectedNode);
    renderHierarchyList();
    showToast(`"${currentName}" -> "${currentDFF.frames[targetIdx].name}" ga biriktirildi!`);
}

function deleteSelectedNode() {
    if (!selectedNode || !currentDFF) return;
    const idx = selectedNode.userData.frameIndex;
    const name = selectedNode.name;
    if (!confirm(`"${name}" detalini o'chirmoqchimisiz?`)) return;

    transformControls.detach();
    selectedNode.parent.remove(selectedNode);

    currentDFF.frames.splice(idx, 1);
    frameGroups.splice(idx, 1);

    for (let i = 0; i < currentDFF.frames.length; i++) {
        currentDFF.frames[i].index = i;
        if (currentDFF.frames[i].parentIndex > idx) currentDFF.frames[i].parentIndex--;
        else if (currentDFF.frames[i].parentIndex === idx) currentDFF.frames[i].parentIndex = 0;
        frameGroups[i].userData.frameIndex = i;
    }

    currentDFF.atomics = currentDFF.atomics.filter(a => a.frameIndex !== idx);
    for (let a of currentDFF.atomics) {
        if (a.frameIndex > idx) a.frameIndex--;
    }

    selectedNode = null;
    selectedMesh = null;
    renderHierarchyList();
    showToast(`O'chirildi: ${name}`);
}

function showAddDummyDialog() {
    const dummyName = prompt("Yangi Dummy nomi (masalan: wheel_rf_dummy, headlight_l, exhaust):");
    if (!dummyName || !dummyName.trim() || !currentDFF) return;

    const newIndex = currentDFF.frames.length;
    let parentIndex = selectedNode ? selectedNode.userData.frameIndex : 0;

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
    const dummyMesh = new THREE.Mesh(dummyGeo, new THREE.MeshBasicMaterial({ color: 0xa855f7 }));
    dummyMesh.name = "__dummy_helper__";
    group.add(dummyMesh);
    group.add(new THREE.AxesHelper(0.18));

    frameGroups.push(group);
    if (frameGroups[parentIndex]) frameGroups[parentIndex].add(group);
    else currentRootGroup.add(group);

    renderHierarchyList();
    selectNodeByIndex(newIndex, null, false);
    showToast(`Yangi dummy qo'shildi: ${newFrame.name}`);
}

// -------------------------------------------------------------
// DFF EXPORT & EXTERNAL MERGE
// -------------------------------------------------------------
function exportCurrentDFF() {
    if (!currentDFF || !currentRootGroup) {
        showToast("Avval modelni oching!");
        return;
    }

    for (let i = 0; i < currentDFF.frames.length; i++) {
        const grp = frameGroups[i];
        if (!grp) continue;

        currentDFF.frames[i].pos[0] = grp.position.x;
        currentDFF.frames[i].pos[1] = grp.position.y;
        currentDFF.frames[i].pos[2] = grp.position.z;

        const m = new THREE.Matrix4().makeRotationFromQuaternion(grp.quaternion);
        const te = m.elements;
        currentDFF.frames[i].rot = [
            te[0], te[1], te[2],
            te[4], te[5], te[6],
            te[8], te[9], te[10]
        ];
        currentDFF.frames[i].name = grp.name;
    }

    frameGroups.forEach(grp => {
        grp.children.forEach(c => {
            if (c instanceof THREE.Mesh && !c.name.includes("__dummy_") && c.userData.geometryIndex !== undefined) {
                const geom = currentDFF.geometries[c.userData.geometryIndex];
                if (geom && c.geometry) {
                    const posAttr = c.geometry.attributes.position;
                    const normAttr = c.geometry.attributes.normal;
                    const uvAttr = c.geometry.attributes.uv;

                    if (posAttr) {
                        geom.numVertices = posAttr.count;
                        geom.vertices = [];
                        for (let v = 0; v < posAttr.count; v++) {
                            geom.vertices.push({ x: posAttr.getX(v), y: posAttr.getY(v), z: posAttr.getZ(v) });
                        }
                    }

                    if (normAttr) {
                        geom.normals = [];
                        for (let n = 0; n < normAttr.count; n++) {
                            geom.normals.push({ x: normAttr.getX(n), y: normAttr.getY(n), z: normAttr.getZ(n) });
                        }
                    }

                    if (uvAttr && geom.texCoordSets && geom.texCoordSets.length > 0) {
                        geom.texCoordSets[0] = [];
                        for (let u = 0; u < uvAttr.count; u++) {
                            geom.texCoordSets[0].push({
                                u: uvAttr.getX(u),
                                v: isUVFlipped ? (1.0 - uvAttr.getY(u)) : uvAttr.getY(u)
                            });
                        }
                    }

                    if (c.geometry.index) {
                        const indexAttr = c.geometry.index;
                        const numTris = indexAttr.count / 3;
                        geom.numTriangles = numTris;
                        geom.triangles = [];

                        const binMeshes = [];
                        if (c.geometry.groups && c.geometry.groups.length > 0) {
                            c.geometry.groups.forEach(g => {
                                const subIndices = [];
                                for (let k = g.start; k < g.start + g.count; k++) {
                                    subIndices.push(indexAttr.getX(k));
                                }
                                binMeshes.push({ matIndex: g.materialIndex || 0, indices: subIndices });
                            });
                        } else {
                            const allIdx = [];
                            for (let k = 0; k < indexAttr.count; k++) allIdx.push(indexAttr.getX(k));
                            binMeshes.push({ matIndex: 0, indices: allIdx });
                        }

                        for (let t = 0; t < numTris; t++) {
                            const v1 = indexAttr.getX(t * 3);
                            const v2 = indexAttr.getX(t * 3 + 1);
                            const v3 = indexAttr.getX(t * 3 + 2);
                            let matIndex = 0;
                            if (c.geometry.groups) {
                                for (const g of c.geometry.groups) {
                                    if (t * 3 >= g.start && t * 3 < g.start + g.count) {
                                        matIndex = g.materialIndex;
                                        break;
                                    }
                                }
                            }
                            geom.triangles.push({ v1, v2, v3, matIndex });
                        }

                        if (!geom.binMesh) geom.binMesh = { flags: 0, numMeshes: binMeshes.length, totalIndices: indexAttr.count, meshes: binMeshes };
                        else {
                            geom.binMesh.flags = 0;
                            geom.binMesh.numMeshes = binMeshes.length;
                            geom.binMesh.totalIndices = indexAttr.count;
                            geom.binMesh.meshes = binMeshes;
                        }
                    }
                }
            }
        });
    });

    showToast("DFF yig'ilmoqda...");
    const dffBytes = currentDFF.serialize();
    const fileName = (currentDFF.fileName || "car_mod") + ".dff";

    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.exportDFF) {
        let binary = '';
        for (let i = 0; i < dffBytes.byteLength; i++) binary += String.fromCharCode(dffBytes[i]);
        window.webkit.messageHandlers.exportDFF.postMessage({
            fileName: fileName,
            base64Data: window.btoa(binary),
            sizeBytes: dffBytes.byteLength
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

function mergeExternalDFF(arrayBuffer, fileName) {
    if (!currentDFF) { showToast("Avval asosiy modelni oching!"); return; }
    try {
        const otherModel = new DFFModel();
        otherModel.parse(arrayBuffer);
        const parentIndex = selectedNode ? selectedNode.userData.frameIndex : 0;
        currentDFF.mergeModel(otherModel, parentIndex);
        buildThreeSceneFromDFF(currentDFF);
        showToast(`Qo'shildi: ${fileName} (${otherModel.frames.length} qism)`);
    } catch (err) {
        alert("DFF qo'shishda xatolik: " + err.message);
    }
}

// -------------------------------------------------------------
// TXD & TEXTURE PARSING
// -------------------------------------------------------------
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

function applyTextureMapToScene() {
    if (!currentRootGroup) return;
    let count = 0;
    currentRootGroup.traverse(child => {
        if (child instanceof THREE.Mesh && !child.name.includes("__dummy_")) {
            const mats = Array.isArray(child.material) ? child.material : [child.material];
            mats.forEach(m => {
                const texName = m.userData?.dffMat?.textureName?.toLowerCase()?.trim();
                if (texName) {
                    let matched = loadedTexturesPool[texName];
                    if (!matched) {
                        for (let k in loadedTexturesPool) {
                            if (k.includes(texName) || texName.includes(k)) {
                                matched = loadedTexturesPool[k];
                                break;
                            }
                        }
                    }
                    if (matched) {
                        m.map = matched;
                        m.needsUpdate = true;
                        count++;
                    }
                }
            });
        }
    });
    if (count > 0 && isShaderMode) updateAllMaterialsShader();
}

function showToast(msg) {
    const toast = document.getElementById('toast');
    if (!toast) return;
    toast.textContent = msg;
    toast.classList.add('show');
    setTimeout(() => toast.classList.remove('show'), 2200);
}

window.onNativeFileOpened = function(base64Data, fileName, mode) {
    try {
        const binary = window.atob(base64Data);
        const bytes = new Uint8Array(binary.length);
        for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);

        const lowerName = fileName.toLowerCase();
        if (mode === "txd" || lowerName.endsWith(".txd")) {
            processTXDData(bytes.buffer, fileName);
        } else if (/\.(png|jpe?g)$/i.test(lowerName)) {
            const blob = new Blob([bytes], { type: lowerName.endsWith(".png") ? "image/png" : "image/jpeg" });
            processImageFile(new File([blob], fileName));
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
