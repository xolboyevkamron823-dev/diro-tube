import SwiftUI

struct ModdingGuideSheet: View {
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.06, green: 0.07, blue: 0.1).edgesIgnoringSafeArea(.all)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        
                        // Header Banner
                        VStack(alignment: .leading, spacing: 6) {
                            Text("iPhone-da GTA Mod Qilish")
                                .font(.system(size: 22, weight: .heavy))
                                .foregroundColor(.white)
                            Text("Oddiy iPhone (Sideloadly / Scarlet / ESign) foydalanuvchilari uchun to'liq yo'riqnoma")
                                .font(.system(size: 13))
                                .foregroundColor(.gray)
                        }
                        .padding(.top, 10)
                        
                        // Step 1
                        GuideStepCard(
                            stepNumber: "1",
                            title: "gta3.img Faylini Topish",
                            description: "iPhone-dagi 'Fayllar' (Files) ilovasini oching -> 'Mening iPhone-imda' (On My iPhone) bo'limiga kiring -> 'GTA: SA' yoki o'yin papkasini oching. U yerda gta3.img fayli turadi.",
                            iconName: "folder.fill",
                            accentColor: .blue
                        )
                        
                        // Step 2
                        GuideStepCard(
                            stepNumber: "2",
                            title: "IMG Tool-da Ochish",
                            description: "IMG Tool dasturiga kiring va 'IMG Ochish' tugmasini bosing. Fayllar ilovasi orqali gta3.img ni tanlang. Bir soniyada 13,500+ ta barcha avtomobil, odam va xaritalar ochiladi.",
                            iconName: "archivebox.fill",
                            accentColor: .orange
                        )
                        
                        // Step 3
                        GuideStepCard(
                            stepNumber: "3",
                            title: "3D Ko'rish va Qidiruv",
                            description: "Qidiruvga almashtirmoqchi bo'lgan mashinangizni yozing (masalan: infernus.dff, elegy.dff, sultan.dff). '3D' tugmasini bosib, o'yindagi mashinaning holatini 360° aylanuvchi kamerada ko'rishingiz mumkin!",
                            iconName: "cube.fill",
                            accentColor: Color(red: 0.0, green: 0.8, blue: 0.95)
                        )
                        
                        // Step 4
                        GuideStepCard(
                            stepNumber: "4",
                            title: "Mashinani Almashtirish (Replace)",
                            description: "Mashina yonidagi to'q sariq 'Almashtirish' tugmasini bosing. Internetdan yoki ZModeler-dan tayyorlagan yangi .dff faylingizni tanlang. Dastur 0.01 soniyada uni o'yin arxiviga yozib beradi.",
                            iconName: "arrow.triangle.2.circlepath",
                            accentColor: .yellow
                        )
                        
                        // Step 5
                        GuideStepCard(
                            stepNumber: "5",
                            title: "O'yinni Oching!",
                            description: "GTA San Andreas ilovasini oching. O'yin to'g'ridan-to'g'ri yangilangan mashinani yuklaydi. Barcha jarayon telefonning o'zida amalga oshadi!",
                            iconName: "gamecontroller.fill",
                            accentColor: .green
                        )
                    }
                    .padding()
                }
            }
            .navigationBarTitle("Qo'llanma", displayMode: .inline)
            .navigationBarItems(trailing: Button("Yopish") {
                presentationMode.wrappedValue.dismiss()
            }.foregroundColor(.blue).fontWeight(.bold))
        }
    }
}

struct GuideStepCard: View {
    let stepNumber: String
    let title: String
    let description: String
    let iconName: String
    let accentColor: Color
    
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.2))
                    .frame(width: 40, height: 40)
                    .overlay(Circle().stroke(accentColor.opacity(0.4), lineWidth: 1))
                
                Image(systemName: iconName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(accentColor)
            }
            
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("\(stepNumber)-QADAM:")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundColor(accentColor)
                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                }
                
                Text(description)
                    .font(.system(size: 13))
                    .foregroundColor(Color(red: 0.7, green: 0.75, blue: 0.85))
                    .lineSpacing(3)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.1, green: 0.12, blue: 0.16))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }
}
