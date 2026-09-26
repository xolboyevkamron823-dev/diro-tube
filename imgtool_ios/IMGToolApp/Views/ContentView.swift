import SwiftUI
import UniformTypeIdentifiers

public enum AppMode: String, CaseIterable, Identifiable {
    case img = "📦 3D Modellar"
    case pvr = "🎨 Teksturalar"
    
    public var id: String { rawValue }
}

public struct ContentView: View {
    @StateObject private var archive = IMGArchive()
    @StateObject private var pvrDatabase = PVRDatabase()
    
    @State private var selectedMode: AppMode = .img
    
    // IMG State
    @State private var searchText: String = ""
    @State private var selectedType: IMGEntryType = .all
    
    // Sheets and Modals
    @State private var showOpenPicker: Bool = false
    @State private var showReplacePicker: Bool = false
    @State private var showAddPicker: Bool = false
    @State private var show3DSheet: Bool = false
    @State private var showRebuildSheet: Bool = false
    @State private var showGuideSheet: Bool = false
    @State private var showShareSheet: Bool = false
    
    @State private var activeEntry: IMGEntry? = nil
    @State private var shareURL: URL? = nil
    
    // Toast Notification
    @State private var toastMessage: String? = nil
    @State private var isToastError: Bool = false
    
    // Filtered entries for IMG
    var filteredEntries: [IMGEntry] {
        var result = archive.entries
        
        // Filter by category
        if selectedType != .all {
            result = result.filter { $0.entryType == selectedType }
        }
        
        // Filter by search query
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            result = result.filter { $0.name.lowercased().contains(query) }
        }
        
        return result
    }
    
    public init() {}
    
    public var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.07, blue: 0.1).edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Top App Header & Mode Switcher
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "wrench.and.screwdriver.fill")
                            .foregroundColor(.yellow)
                            .font(.system(size: 16))
                        
                        Text("DIRO GTA MOD STUDIO")
                            .font(.system(size: 15, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        Button(action: { showGuideSheet = true }) {
                            HStack(spacing: 4) {
                                Image(systemName: "questionmark.circle.fill")
                                Text("Qo'llanma")
                            }
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.1))
                            .foregroundColor(.yellow)
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    
                    // Segmented Mode Switcher
                    HStack(spacing: 4) {
                        ForEach(AppMode.allCases) { mode in
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedMode = mode
                                }
                            }) {
                                HStack(spacing: 6) {
                                    Text(mode.rawValue)
                                        .font(.system(size: 13, weight: .bold))
                                    
                                    if mode == .pvr && pvrDatabase.modifiedCount > 0 {
                                        Text("\(pvrDatabase.modifiedCount)")
                                            .font(.system(size: 10, weight: .black))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(Color.green)
                                            .foregroundColor(.black)
                                            .clipShape(Capsule())
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(selectedMode == mode ? Color(red: 0.18, green: 0.22, blue: 0.3) : Color.clear)
                                .foregroundColor(selectedMode == mode ? .white : .gray)
                                .cornerRadius(8)
                            }
                        }
                    }
                    .padding(3)
                    .background(Color(red: 0.1, green: 0.12, blue: 0.16))
                    .cornerRadius(10)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                }
                .background(Color(red: 0.08, green: 0.09, blue: 0.13))
                
                Divider().background(Color.white.opacity(0.08))
                
                // Content based on Mode
                if selectedMode == .img {
                    imgToolView
                } else {
                    TextureListView(database: pvrDatabase) { msg, isErr in
                        showToast(msg, isError: isErr)
                    }
                }
            }
            
            // Toast Notification Overlay
            if let toast = toastMessage {
                VStack {
                    HStack(spacing: 10) {
                        Image(systemName: isToastError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(isToastError ? .red : .green)
                        
                        Text(toast)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(2)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(red: 0.14, green: 0.16, blue: 0.22))
                    .cornerRadius(25)
                    .overlay(RoundedRectangle(cornerRadius: 25).stroke(isToastError ? Color.red.opacity(0.4) : Color.green.opacity(0.4), lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.4), radius: 10, y: 5)
                    .padding(.top, 60)
                    
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(), value: toastMessage)
            }
        }
        // Document Picker: Open IMG
        .sheet(isPresented: $showOpenPicker) {
            DocumentPicker(contentTypes: [.item, .data]) { url in
                archive.load(from: url)
            }
        }
        // Document Picker: Replace
        .sheet(isPresented: $showReplacePicker) {
            DocumentPicker(contentTypes: [.item, .data]) { url in
                guard let ent = activeEntry else { return }
                do {
                    try archive.replace(entry: ent, withSourceURL: url)
                    showToast("\(ent.name) muvaffaqiyatli almashtirildi!", isError: false)
                } catch {
                    showToast("Almashtirishda xatolik: \(error.localizedDescription)", isError: true)
                }
            }
        }
        // Document Picker: Add File
        .sheet(isPresented: $showAddPicker) {
            DocumentPicker(contentTypes: [.item, .data]) { url in
                do {
                    try archive.addFile(from: url)
                    showToast("\(url.lastPathComponent) arxivga qo'shildi!", isError: false)
                } catch {
                    showToast("Qo'shishda xatolik: \(error.localizedDescription)", isError: true)
                }
            }
        }
        // 3D DFF Viewer Sheet
        .sheet(isPresented: $show3DSheet) {
            if let ent = activeEntry {
                DFFViewerSheet(entry: ent, archive: archive)
            }
        }
        // Rebuild Sheet
        .sheet(isPresented: $showRebuildSheet) {
            RebuildSheet(archive: archive)
        }
        // Modding Guide Sheet
        .sheet(isPresented: $showGuideSheet) {
            ModdingGuideSheet()
        }
        // Share Sheet (Extract)
        .sheet(isPresented: $showShareSheet) {
            if let url = shareURL {
                ActivityView(activityItems: [url])
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenIMGFileNotification"))) { notification in
            if let url = notification.object as? URL {
                selectedMode = .img
                archive.load(from: url)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenPVRFileNotification"))) { notification in
            if let url = notification.object as? URL {
                selectedMode = .pvr
                pvrDatabase.loadDatabase(fromDatURL: url)
            }
        }
    }
    
    // MARK: - IMG Tool Tab View
    private var imgToolView: some View {
        VStack(spacing: 0) {
            // Archive Header
            ArchiveHeaderView(
                archive: archive,
                onOpen: { showOpenPicker = true },
                onRebuild: { showRebuildSheet = true },
                onAdd: { showAddPicker = true },
                onGuide: { showGuideSheet = true }
            )
            
            if archive.isLoaded {
                // Search Bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    
                    TextField("Fayl nomini qidirish (masalan: infernus, cheetah)...", text: $searchText)
                        .foregroundColor(.white)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(red: 0.12, green: 0.14, blue: 0.18))
                .cornerRadius(10)
                .padding(.horizontal)
                .padding(.top, 10)
                
                // Filter Pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(IMGEntryType.allCases) { type in
                            Button(action: {
                                selectedType = type
                            }) {
                                HStack(spacing: 5) {
                                    Image(systemName: type.iconName)
                                        .font(.system(size: 11))
                                    Text(type.rawValue)
                                        .font(.system(size: 12, weight: .bold))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(selectedType == type ? type.color : Color(red: 0.12, green: 0.14, blue: 0.18))
                                .foregroundColor(selectedType == type ? .black : .gray)
                                .cornerRadius(20)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                
                // Entries Count Label
                HStack {
                    Text("\(filteredEntries.count) ta element topildi")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.gray)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, 4)
                
                // Virtualized List
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(filteredEntries) { entry in
                            EntryRowView(
                                entry: entry,
                                onView3D: { ent in
                                    activeEntry = ent
                                    show3DSheet = true
                                },
                                onReplace: { ent in
                                    activeEntry = ent
                                    showReplacePicker = true
                                },
                                onExtract: { ent in
                                    extractFile(entry: ent)
                                },
                                onDelete: { ent in
                                    deleteFile(entry: ent)
                                }
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if entry.isDFF {
                                    activeEntry = entry
                                    show3DSheet = true
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
            } else if archive.isLoading {
                Spacer()
                VStack(spacing: 14) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .yellow))
                        .scaleEffect(1.6)
                    Text("GTA Arxiv o'qilmoqda...")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                    Text("13,000+ fayl indekslanmoqda...")
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                }
                Spacer()
            } else {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.system(size: 64))
                        .foregroundColor(.gray.opacity(0.6))
                    
                    Text("IMG Arxiv Yuklanmagan")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("GTA San Andreas 'gta3.img' faylini tanlash uchun pastdagi tugmani bosing")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    
                    Button(action: { showOpenPicker = true }) {
                        HStack(spacing: 8) {
                            Image(systemName: "folder.fill")
                            Text("IMG Faylni Tanlash")
                        }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.yellow)
                        .cornerRadius(10)
                    }
                }
                Spacer()
            }
        }
    }
    
    private func extractFile(entry: IMGEntry) {
        do {
            let url = try archive.extractToFile(entry: entry)
            self.shareURL = url
            self.showShareSheet = true
        } catch {
            showToast("Eksport qilishda xatolik: \(error.localizedDescription)", isError: true)
        }
    }
    
    private func deleteFile(entry: IMGEntry) {
        do {
            try archive.delete(entry: entry)
            showToast("\(entry.name) arxivdan o'chirildi.", isError: false)
        } catch {
            showToast("O'chirishda xatolik: \(error.localizedDescription)", isError: true)
        }
    }
    
    private func showToast(_ msg: String, isError: Bool) {
        self.toastMessage = msg
        self.isToastError = isError
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            if self.toastMessage == msg {
                self.toastMessage = nil
            }
        }
    }
}
