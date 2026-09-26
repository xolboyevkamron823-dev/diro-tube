import SwiftUI
import UniformTypeIdentifiers

public struct PVRDatabasePickerSheet: View {
    @ObservedObject var database: PVRDatabase
    @Binding var isPresented: Bool
    let onToast: (String, Bool) -> Void
    
    @State private var selectedDatURL: URL? = nil
    @State private var selectedTocURL: URL? = nil
    @State private var selectedTxtURL: URL? = nil
    
    @State private var showFolderPicker: Bool = false
    @State private var showMultiFilePicker: Bool = false
    @State private var showDatPicker: Bool = false
    @State private var showTocPicker: Bool = false
    @State private var showTxtPicker: Bool = false
    
    @State private var localDatabases: [(name: String, datURL: URL, tocURL: URL?, txtURL: URL?)] = []
    
    public init(database: PVRDatabase, isPresented: Binding<Bool>, onToast: @escaping (String, Bool) -> Void) {
        self.database = database
        self._isPresented = isPresented
        self.onToast = onToast
    }
    
    public var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.08, green: 0.09, blue: 0.12).edgesIgnoringSafeArea(.all)
                
                ScrollView {
                    VStack(spacing: 18) {
                        // Header info
                        HStack(spacing: 12) {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.yellow)
                            
                            Text("GTA SA tekstura bazasi 2 ta asosiy fayldan iborat: **.pvr.dat** (teksturalar) va **.pvr.toc** (indekslar). Ikkalasini ham tanlash lozim.")
                                .font(.system(size: 13))
                                .foregroundColor(.white)
                        }
                        .padding(12)
                        .background(Color.yellow.opacity(0.12))
                        .cornerRadius(10)
                        .padding(.horizontal)
                        .padding(.top, 10)
                        
                        // Option 1: Pick Folder (Fastest & Easiest)
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: "folder.fill.badge.gearshape")
                                    .foregroundColor(.cyan)
                                Text("1-USUL: Papkani Tanlash (Eng Oson)")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            
                            Text("Files ilovasida 'gta3' yoki 'texdb' papkasini tanlang. Ilova uning ichidagi barcha fayllarni (.dat, .toc, .txt) o'zi avtomatik ulaydi.")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                            
                            Button(action: { showFolderPicker = true }) {
                                HStack {
                                    Image(systemName: "folder.fill")
                                    Text("Papkani Tanlash (Folder)")
                                }
                                .font(.system(size: 14, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                            }
                        }
                        .padding(14)
                        .background(Color(red: 0.12, green: 0.14, blue: 0.18))
                        .cornerRadius(12)
                        .padding(.horizontal)
                        
                        // Option 2: Pick Multiple Files at Once
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: "doc.on.doc.fill")
                                    .foregroundColor(.green)
                                Text("2-USUL: Bir nechta faylni birga tanlash")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            
                            Text("Fayllar ilovasida yuqoridagi '...' tugmasi -> 'Выбрать' (Select) ni bosib, gta3.pvr.dat va gta3.pvr.toc fayllarini birga belgilab oching.")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                            
                            Button(action: { showMultiFilePicker = true }) {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                    Text("Fayllarni Birga Tanlash (Multi-Select)")
                                }
                                .font(.system(size: 14, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.green)
                                .foregroundColor(.black)
                                .cornerRadius(10)
                            }
                        }
                        .padding(14)
                        .background(Color(red: 0.12, green: 0.14, blue: 0.18))
                        .cornerRadius(12)
                        .padding(.horizontal)
                        
                        // Option 3: Pick Individually
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "slider.horizontal.3")
                                    .foregroundColor(.orange)
                                Text("3-USUL: Alohida-alohida tanlash")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            
                            // DAT picker
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("1. PVR.DAT Fayli (Majburiy):")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.gray)
                                    Text(selectedDatURL?.lastPathComponent ?? "Tanlanmagan")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(selectedDatURL != nil ? .green : .white)
                                }
                                Spacer()
                                Button(action: { showDatPicker = true }) {
                                    Text(selectedDatURL != nil ? "O'zgartirish" : "Tanlash...")
                                        .font(.system(size: 12, weight: .bold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color(red: 0.18, green: 0.22, blue: 0.3))
                                        .foregroundColor(.white)
                                        .cornerRadius(8)
                                }
                            }
                            .padding(10)
                            .background(Color(red: 0.09, green: 0.1, blue: 0.14))
                            .cornerRadius(8)
                            
                            // TOC picker
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("2. TOC Indeks Fayli (Majburiy):")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.gray)
                                    Text(selectedTocURL?.lastPathComponent ?? "Tanlanmagan")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(selectedTocURL != nil ? .green : .white)
                                }
                                Spacer()
                                Button(action: { showTocPicker = true }) {
                                    Text(selectedTocURL != nil ? "O'zgartirish" : "Tanlash...")
                                        .font(.system(size: 12, weight: .bold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color(red: 0.18, green: 0.22, blue: 0.3))
                                        .foregroundColor(.white)
                                        .cornerRadius(8)
                                }
                            }
                            .padding(10)
                            .background(Color(red: 0.09, green: 0.1, blue: 0.14))
                            .cornerRadius(8)
                            
                            // TXT picker
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("3. TXT Nomlar Fayli (Ixtiyoriy):")
                                        .font(.system(size: 11))
                                        .foregroundColor(.gray)
                                    Text(selectedTxtURL?.lastPathComponent ?? "Mavjud emas (Avtomatik nomlanadi)")
                                        .font(.system(size: 12))
                                        .foregroundColor(.gray)
                                }
                                Spacer()
                                Button(action: { showTxtPicker = true }) {
                                    Text(selectedTxtURL != nil ? "O'zgartirish" : "Tanlash...")
                                        .font(.system(size: 12))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color(red: 0.18, green: 0.22, blue: 0.3))
                                        .foregroundColor(.white)
                                        .cornerRadius(8)
                                }
                            }
                            .padding(10)
                            .background(Color(red: 0.09, green: 0.1, blue: 0.14))
                            .cornerRadius(8)
                            
                            // Confirm Button
                            Button(action: openManualSelection) {
                                HStack {
                                    Image(systemName: "arrow.right.circle.fill")
                                    Text("Tanlangan Bazani Ochish")
                                }
                                .font(.system(size: 14, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(canOpenManual ? Color.cyan : Color.gray.opacity(0.3))
                                .foregroundColor(canOpenManual ? .black : .gray)
                                .cornerRadius(10)
                            }
                            .disabled(!canOpenManual)
                        }
                        .padding(14)
                        .background(Color(red: 0.12, green: 0.14, blue: 0.18))
                        .cornerRadius(12)
                        .padding(.horizontal)
                        
                        // Option 4: Local Documents (On My iPhone / IMG Tool)
                        if !localDatabases.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Image(systemName: "bolt.fill")
                                        .foregroundColor(.yellow)
                                    Text("⚡ IMG Tool Papkasidan Aniqlanganlar:")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(.white)
                                }
                                
                                ForEach(localDatabases, id: \.name) { item in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.name)
                                                .font(.system(size: 13, weight: .bold))
                                                .foregroundColor(.white)
                                            Text("TOC: \(item.tocURL != nil ? "Mavjud ✅" : "Yo'q ❌")")
                                                .font(.system(size: 11))
                                                .foregroundColor(item.tocURL != nil ? .green : .red)
                                        }
                                        Spacer()
                                        Button(action: {
                                            openLocalDatabase(item)
                                        }) {
                                            Text("1-Click Ochish")
                                                .font(.system(size: 12, weight: .bold))
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(Color.green)
                                                .foregroundColor(.black)
                                                .cornerRadius(8)
                                        }
                                    }
                                    .padding(8)
                                    .background(Color(red: 0.09, green: 0.1, blue: 0.14))
                                    .cornerRadius(8)
                                }
                            }
                            .padding(14)
                            .background(Color(red: 0.12, green: 0.14, blue: 0.18))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }
                    }
                    .padding(.bottom, 30)
                }
            }
            .navigationBarTitle("PVR Bazani Ochish", displayMode: .inline)
            .navigationBarItems(
                leading: Button("Bekor Qilish") {
                    isPresented = false
                }
                .foregroundColor(.gray)
            )
            .onAppear {
                scanLocalDocuments()
            }
            // 1. Folder Picker
            .sheet(isPresented: $showFolderPicker) {
                DocumentPicker(contentTypes: [.folder], allowsMultipleSelection: false) { folderURL in
                    handleFolderPicked(folderURL)
                }
            }
            // 2. Multi-File Picker
            .sheet(isPresented: $showMultiFilePicker) {
                DocumentPicker(contentTypes: [.item, .data], allowsMultipleSelection: true) { urls in
                    handleMultipleFilesPicked(urls)
                }
            }
            // 3. Individual DAT Picker
            .sheet(isPresented: $showDatPicker) {
                DocumentPicker(contentTypes: [.item, .data], allowsMultipleSelection: false) { url in
                    self.selectedDatURL = url
                    autoFindCompanionFor(datURL: url)
                }
            }
            // 4. Individual TOC Picker
            .sheet(isPresented: $showTocPicker) {
                DocumentPicker(contentTypes: [.item, .data], allowsMultipleSelection: false) { url in
                    self.selectedTocURL = url
                }
            }
            // 5. Individual TXT Picker
            .sheet(isPresented: $showTxtPicker) {
                DocumentPicker(contentTypes: [.item, .data, .plainText], allowsMultipleSelection: false) { url in
                    self.selectedTxtURL = url
                }
            }
        }
    }
    
    private var canOpenManual: Bool {
        selectedDatURL != nil && selectedTocURL != nil
    }
    
    private func openManualSelection() {
        guard let d = selectedDatURL, let t = selectedTocURL else { return }
        isPresented = false
        database.loadDatabase(fromDatURL: d, tocURL: t, txtURL: selectedTxtURL)
    }
    
    private func handleFolderPicked(_ folderURL: URL) {
        isPresented = false
        database.loadFromFolder(folderURL: folderURL)
    }
    
    private func handleMultipleFilesPicked(_ urls: [URL]) {
        isPresented = false
        database.loadFromURLs(urls)
    }
    
    private func autoFindCompanionFor(datURL: URL) {
        let (toc, txt, _) = PVRDatabase.findCompanions(for: datURL)
        if self.selectedTocURL == nil, let t = toc {
            self.selectedTocURL = t
        }
        if self.selectedTxtURL == nil, let x = txt {
            self.selectedTxtURL = x
        }
    }
    
    private func openLocalDatabase(_ item: (name: String, datURL: URL, tocURL: URL?, txtURL: URL?)) {
        guard let t = item.tocURL else {
            self.selectedDatURL = item.datURL
            self.showTocPicker = true
            return
        }
        isPresented = false
        database.loadDatabase(fromDatURL: item.datURL, tocURL: t, txtURL: item.txtURL)
    }
    
    private func scanLocalDocuments() {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        
        var found: [(name: String, datURL: URL, tocURL: URL?, txtURL: URL?)] = []
        let fileManager = FileManager.default
        
        let searchFolders = [docs, docs.appendingPathComponent("texdb/gta3")]
        for f in searchFolders {
            if let files = try? fileManager.contentsOfDirectory(at: f, includingPropertiesForKeys: nil) {
                for file in files {
                    if file.lastPathComponent.hasSuffix(".pvr.dat") || file.lastPathComponent.hasSuffix(".dat") {
                        let base = file.lastPathComponent.replacingOccurrences(of: ".pvr.dat", with: "").replacingOccurrences(of: ".dat", with: "")
                        let tocCand = f.appendingPathComponent("\(base).pvr.toc")
                        let txtCand = f.appendingPathComponent("\(base).txt")
                        
                        let hasToc = fileManager.fileExists(atPath: tocCand.path) ? tocCand : nil
                        let hasTxt = fileManager.fileExists(atPath: txtCand.path) ? txtCand : nil
                        
                        found.append((name: file.lastPathComponent, datURL: file, tocURL: hasToc, txtURL: hasTxt))
                    }
                }
            }
        }
        self.localDatabases = found
    }
}
