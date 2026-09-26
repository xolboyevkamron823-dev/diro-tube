import SwiftUI
import UniformTypeIdentifiers

public struct TextureListView: View {
    @ObservedObject var database: PVRDatabase
    let onToast: (String, Bool) -> Void
    
    @State private var searchText: String = ""
    @State private var selectedCategory: String = "Barchasi"
    
    @State private var showOpenDatPicker: Bool = false
    @State private var showAddTextureSheet: Bool = false
    @State private var selectedEntry: PVRTextureEntry? = nil
    
    @State private var isSaving: Bool = false
    @State private var saveProgress: Double = 0.0
    
    let categories = [
        "Barchasi",
        "🚗 Mashinalar",
        "👕 Skins",
        "🏙️ Shahar",
        "✨ Yangi",
        "⭐ O'zgargan"
    ]
    
    var filteredEntries: [PVRTextureEntry] {
        var list = database.entries
        
        let vehKeys = ["wheel", "infernus", "bullet", "cheetah", "cop", "taxi", "lights", "plate",
                       "badge", "glass", "tire", "rim", "headlight", "bumper", "car", "truck", "bike"]
        let pedKeys = ["cj", "player", "head", "face", "skin", "body", "hair", "smoke", "sweet", "ryder",
                       "gang", "ped", "cop", "shoes", "legs", "torso"]
        let cityKeys = ["road", "asphalt", "pave", "wall", "grass", "tree", "roof", "brick", "ground", "wood", "water", "sign"]
        
        if selectedCategory == "✨ Yangi" {
            list = list.filter { $0.isNew }
        } else if selectedCategory == "⭐ O'zgargan" {
            list = list.filter { $0.isModified }
        } else if selectedCategory == "🚗 Mashinalar" {
            list = list.filter { ent in
                let n = ent.name.lowercased()
                return vehKeys.contains { n.contains($0) }
            }
        } else if selectedCategory == "👕 Skins" {
            list = list.filter { ent in
                let n = ent.name.lowercased()
                return pedKeys.contains { n.contains($0) }
            }
        } else if selectedCategory == "🏙️ Shahar" {
            list = list.filter { ent in
                let n = ent.name.lowercased()
                return cityKeys.contains { n.contains($0) }
            }
        }
        
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            list = list.filter { $0.name.lowercased().contains(q) }
        }
        
        return list
    }
    
    public var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.07, blue: 0.1).edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Header Bar
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(database.isLoaded ? "\(database.databaseName).pvr.dat" : "PVR Tekstura Baza")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text(database.isLoaded ? "\(database.entries.count) ta tekstura mavjud" : "Hech qanday baza yuklanmagan")
                            .font(.system(size: 11))
                            .foregroundColor(database.isLoaded ? .green : .gray)
                    }
                    
                    Spacer()
                    
                    // Open PVR.DAT button
                    Button(action: { showOpenDatPicker = true }) {
                        HStack(spacing: 5) {
                            Image(systemName: "folder")
                            Text("Ochish")
                        }
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    
                    // Save Button
                    if database.isLoaded {
                        Button(action: saveDatabase) {
                            HStack(spacing: 5) {
                                Image(systemName: "square.and.arrow.down")
                                Text("Saqlash")
                                if database.modifiedCount > 0 {
                                    Text("\(database.modifiedCount)")
                                        .font(.system(size: 10, weight: .black))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Color.white)
                                        .foregroundColor(.black)
                                        .clipShape(Capsule())
                                }
                            }
                            .font(.system(size: 12, weight: .bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(database.hasUnsavedChanges ? Color.green : Color.gray.opacity(0.3))
                            .foregroundColor(database.hasUnsavedChanges ? .black : .gray)
                            .cornerRadius(8)
                        }
                        .disabled(!database.hasUnsavedChanges || isSaving)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(Color(red: 0.1, green: 0.12, blue: 0.16))
                
                if database.isLoaded {
                    // Search Bar
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                        
                        TextField("Tekstura qidirish (masalan: wheel, cj, road)...", text: $searchText)
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
                    .padding(.vertical, 9)
                    .background(Color(red: 0.12, green: 0.14, blue: 0.18))
                    .cornerRadius(10)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    
                    // Category Filter Pills
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(categories, id: \.self) { cat in
                                Button(action: { selectedCategory = cat }) {
                                    Text(cat)
                                        .font(.system(size: 12, weight: .bold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(selectedCategory == cat ? Color.cyan : Color(red: 0.12, green: 0.14, blue: 0.18))
                                        .foregroundColor(selectedCategory == cat ? .black : .gray)
                                        .cornerRadius(20)
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                    
                    // Texture List
                    let currentList = filteredEntries
                    if currentList.isEmpty {
                        VStack(spacing: 10) {
                            Spacer()
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 36))
                                .foregroundColor(.gray.opacity(0.4))
                            Text("Tekstura topilmadi")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.gray)
                            Spacer()
                        }
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 6) {
                                ForEach(currentList) { entry in
                                    TextureRowView(entry: entry, database: database) {
                                        self.selectedEntry = entry
                                    }
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 6)
                            .padding(.bottom, 80) // Leave space for Floating Action Button
                        }
                    }
                } else if database.isLoading {
                    VStack(spacing: 16) {
                        Spacer()
                        ProgressView(value: database.loadingProgress)
                            .progressViewStyle(LinearProgressViewStyle(tint: .cyan))
                            .padding(.horizontal, 40)
                        
                        Text(database.loadingStatus)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.gray)
                        Spacer()
                    }
                } else {
                    // Empty State
                    VStack(spacing: 16) {
                        Spacer()
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.12))
                                .frame(width: 80, height: 80)
                            Image(systemName: "photo.stack")
                                .font(.system(size: 36))
                                .foregroundColor(.blue)
                        }
                        
                        Text("GTA PVR Tekstura Bazasi Tanlanmagan")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text("iPhone Files ilovasi yoki GTA SA Documents papkasidagi gta3.pvr.dat (yoki .toc) faylini tanlang.")
                            .font(.system(size: 13))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        
                        Button(action: { showOpenDatPicker = true }) {
                            HStack {
                                Image(systemName: "doc.badge.plus")
                                Text("gta3.pvr.dat Faylini Ochish")
                            }
                            .font(.system(size: 14, weight: .bold))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .padding(.top, 10)
                        
                        Spacer()
                    }
                }
            }
            
            // Floating Action Button (Add New Texture)
            if database.isLoaded {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: { showAddTextureSheet = true }) {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                    .font(.system(size: 16, weight: .bold))
                                Text("Yangi Tekstura")
                                    .font(.system(size: 13, weight: .bold))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color.green)
                            .foregroundColor(.black)
                            .cornerRadius(25)
                            .shadow(color: Color.black.opacity(0.4), radius: 6, x: 0, y: 3)
                        }
                        .padding(.trailing, 16)
                        .padding(.bottom, 16)
                    }
                }
            }
            
            // Saving Progress Modal
            if isSaving {
                ZStack {
                    Color.black.opacity(0.7).edgesIgnoringSafeArea(.all)
                    VStack(spacing: 16) {
                        ProgressView(value: saveProgress)
                            .progressViewStyle(LinearProgressViewStyle(tint: .green))
                            .frame(width: 220)
                        
                        Text("Tekstura bazasi saqlanmoqda...")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text("TOC indekslari va 16-bayt hizalash yangilanmoqda")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                    }
                    .padding(24)
                    .background(Color(red: 0.12, green: 0.14, blue: 0.18))
                    .cornerRadius(16)
                }
            }
        }
        .sheet(isPresented: $showOpenDatPicker) {
            DocumentPicker(contentTypes: [.item, .data]) { url in
                database.loadDatabase(fromDatURL: url)
            }
        }
        .sheet(isPresented: $showAddTextureSheet) {
            AddTextureSheet(database: database, isPresented: $showAddTextureSheet) { newName in
                onToast("'\(newName)' bazaga qo'shildi! Saqlash tugmasini bosing.", false)
            }
        }
        .sheet(item: $selectedEntry) { entry in
            TextureDetailSheet(
                entry: entry,
                database: database,
                isPresented: Binding(
                    get: { selectedEntry != nil },
                    set: { if !$0 { selectedEntry = nil } }
                ),
                onToast: onToast
            )
        }
    }
    
    private func saveDatabase() {
        isSaving = true
        saveProgress = 0.0
        
        database.saveDatabase(progress: { p in
            self.saveProgress = p
        }) { result in
            self.isSaving = false
            switch result {
            case .success:
                onToast("Tekstura bazasi muvaffaqiyatli saqlandi! O'yinda 100% tayyor.", false)
            case .failure(let err):
                onToast("Saqlashda xatolik: \(err.localizedDescription)", true)
            }
        }
    }
}
