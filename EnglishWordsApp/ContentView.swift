import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import UIKit

// MARK: - データモデル
struct Word: Identifiable, Codable {
    var id = UUID()
    var english: String
    var meaning: String
    var example: String
    var isReTest: Bool = false
}

// MARK: - メイン画面
struct ContentView: View {
    @State private var words: [Word] = []
    
    // ドキュメントピッカー用の状態変数
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var alertMessage = ""
    @State private var showAlert = false

    init() {
        // 起動時にUserDefaultsから読み込み
        if let savedData = UserDefaults.standard.data(forKey: "SavedWords"),
           let decoded = try? JSONDecoder().decode([Word].self, from: savedData) {
            _words = State(initialValue: decoded)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 上部のJSON管理バー
            HStack {
                Button(action: { isExporting = true }) {
                    Label("JSON書き出し", systemImage: "square.and.arrow.up")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button(action: { isImporting = true }) {
                    Label("JSON読み込み", systemImage: "square.and.arrow.down")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .background(Color.gray.opacity(0.1))

            // メインのタブ画面
            TabView {
                WordListView(words: $words, onSave: saveToUserDefaults)
                    .tabItem { Label("単語一覧", systemImage: "list.bullet") }
                
                TestView(words: $words, isReTestMode: false, onSave: saveToUserDefaults)
                    .tabItem { Label("テスト", systemImage: "checkmark.circle") }
                
                TestView(words: $words, isReTestMode: true, onSave: saveToUserDefaults)
                    .tabItem { Label("再テスト", systemImage: "arrow.clockwise.circle") }
            }
        }
        // JSONファイルの出力処理
        .fileExporter(
            isPresented: $isExporting,
            document: JSONDocument(words: words),
            contentType: .json,
            defaultFilename: "words_backup.json"
        ) { result in
            switch result {
            case .success:
                alertMessage = "JSONファイルへの書き出しが完了しました。"
                showAlert = true
            case .failure(let error):
                alertMessage = "書き出しに失敗しました: \(error.localizedDescription)"
                showAlert = true
            }
        }
        // JSONファイルの読み込み処理
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.json]
        ) { result in
            switch result {
            case .success(let url):
                let gotAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if gotAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                do {
                    let data = try Data(contentsOf: url)
                    let decodedWords = try JSONDecoder().decode([Word].self, from: data)
                    self.words = decodedWords
                    saveToUserDefaults() // 読み込み後即時保存
                    alertMessage = "\(decodedWords.count)件の単語をJSONから読み込みました。"
                    showAlert = true
                } catch {
                    alertMessage = "JSONの読み込みに失敗しました。"
                    showAlert = true
                }
            case .failure(let error):
                alertMessage = "ファイル選択エラー: \(error.localizedDescription)"
                showAlert = true
            }
        }
        .alert("ファイル通知", isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }
    
    // 明示的な保存関数（即座にiPhone本体へ書き込み）
    private func saveToUserDefaults() {
        if let encoded = try? JSONEncoder().encode(words) {
            UserDefaults.standard.set(encoded, forKey: "SavedWords")
            UserDefaults.standard.synchronize() // 即時反映
        }
    }
}

// MARK: - JSON出力用ドキュメント構造体
struct JSONDocument: FileDocument {
    static var readableContentTypes: [UTType] = [.json]
    var words: [Word]

    init(words: [Word]) {
        self.words = words
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.words = try JSONDecoder().decode([Word].self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(words)
        return FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - 単語一覧・管理画面
struct WordListView: View {
    @Binding var words: [Word]
    var onSave: () -> Void
    
    @State private var showingAddSheet = false
    @State private var wordToEdit: Word? = nil

    var body: some View {
        NavigationStack {
            List {
                if words.isEmpty {
                    Text("単語が登録されていません。\n右上の「＋」から追加してください。")
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding()
                } else {
                    ForEach(words) { word in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(word.english)
                                        .font(.headline)
                                    if word.isReTest {
                                        Image(systemName: "arrow.clockwise.circle.fill")
                                            .foregroundColor(.orange)
                                            .font(.caption)
                                    }
                                }
                                Text(word.meaning)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            wordToEdit = word
                        }
                    }
                    .onDelete(perform: deleteWords)
                }
            }
            .navigationTitle("単語一覧 (\(words.count))")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingAddSheet = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                EditWordView(wordToSave: nil) { newWord in
                    words.append(newWord)
                    onSave() // 追加時に強制保存
                }
            }
            .sheet(item: $wordToEdit) { word in
                EditWordView(wordToSave: word) { updatedWord in
                    if let index = words.firstIndex(where: { $0.id == updatedWord.id }) {
                        words[index] = updatedWord
                        onSave() // 編集時に強制保存
                    }
                }
            }
        }
    }

    private func deleteWords(at offsets: IndexSet) {
        words.remove(atOffsets: offsets)
        onSave() // 削除時に強制保存
    }
}

// MARK: - 単語の新規登録 / 編集兼用シート
struct EditWordView: View {
    @Environment(\.dismiss) private var dismiss
    
    let wordToSave: Word?
    var onSave: (Word) -> Void
    
    @State private var english: String = ""
    @State private var meaning: String = ""
    @State private var example: String = ""
    
    var isEditing: Bool {
        wordToSave != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("単語情報")) {
                    TextField("英単語 (例: apple)", text: $english)
                    TextField("意味 (例: りんご)", text: $meaning)
                    TextField("例文 (例: I eat an apple.)", text: $example)
                }
            }
            .navigationTitle(isEditing ? "単語を編集" : "新しい単語")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let updatedWord = Word(
                            id: wordToSave?.id ?? UUID(),
                            english: english,
                            meaning: meaning,
                            example: example,
                            isReTest: wordToSave?.isReTest ?? false
                        )
                        onSave(updatedWord)
                        dismiss()
                    }
                    .disabled(english.isEmpty || meaning.isEmpty)
                }
            }
            .onAppear {
                if let word = wordToSave {
                    english = word.english
                    meaning = word.meaning
                    example = word.example
                }
            }
        }
    }
}

// MARK: - テスト / 再テスト画面
struct TestView: View {
    @Binding var words: [Word]
    let isReTestMode: Bool
    var onSave: () -> Void
    
    @State private var testQueue: [Word] = []
    @State private var currentIndex = 0
    @State private var showMeaning = false
    
    private let synthesizer = AVSpeechSynthesizer()

    var targetWords: [Word] {
        if isReTestMode {
            return words.filter { $0.isReTest }
        } else {
            return words
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 25) {
                if testQueue.isEmpty || currentIndex >= testQueue.count {
                    VStack(spacing: 15) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.green)
                        Text(isReTestMode ? "再テスト完了！" : "テスト終了！")
                            .font(.title2)
                            .bold()
                        Button("もう一度スタート") {
                            startTest()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    let currentWord = testQueue[currentIndex]
                    
                    Spacer()
                    
                    VStack(spacing: 15) {
                        Text(currentWord.english)
                            .font(.system(size: 36, weight: .bold))
                        
                        if !currentWord.example.isEmpty {
                            Text(currentWord.example)
                                .font(.body)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                    }
                    
                    Button(action: {
                        speak(text: currentWord.english)
                    }) {
                        Label("Pronounce", systemImage: "speaker.wave.2.fill")
                    }
                    .buttonStyle(.bordered)

                    if showMeaning {
                        Text(currentWord.meaning)
                            .font(.title2)
                            .foregroundColor(.blue)
                            .padding()
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(10)
                        
                        HStack(spacing: 40) {
                            Button(action: { markAnswer(isCorrect: false) }) {
                                Image(systemName: "xmark")
                                    .font(.title)
                                    .frame(width: 70, height: 70)
                                    .background(Color.red)
                                    .foregroundColor(.white)
                                    .clipShape(Circle())
                            }
                            
                            Button(action: { markAnswer(isCorrect: true) }) {
                                Image(systemName: "circle")
                                    .font(.title)
                                    .frame(width: 70, height: 70)
                                    .background(Color.green)
                                    .foregroundColor(.white)
                                    .clipShape(Circle())
                            }
                        }
                    } else {
                        Button("Show the meaning") {
                            showMeaning = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    
                    Spacer()
                }
            }
            .padding()
            .navigationTitle(isReTestMode ? "再テスト" : "テスト")
            .onAppear {
                startTest()
            }
        }
    }

    private func startTest() {
        testQueue = targetWords.shuffled()
        currentIndex = 0
        showMeaning = false
    }

    private func markAnswer(isCorrect: Bool) {
        let currentWord = testQueue[currentIndex]
        
        if let index = words.firstIndex(where: { $0.id == currentWord.id }) {
            if isCorrect {
                words[index].isReTest = false
            } else {
                words[index].isReTest = true
            }
            onSave() // ○×の結果（再テストフラグ）も即座に保存
        }
        
        showMeaning = false
        currentIndex += 1
    }

    private func speak(text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.5
        synthesizer.speak(utterance)
    }
}
