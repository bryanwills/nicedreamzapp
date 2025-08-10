import SwiftUI
import Vision
import AVFoundation
import CoreVideo
import Combine

// Enhanced OCRTextProcessor with improved phrase-first pipeline and polishing
class OCRTextProcessor {
    private var grammarRules: [String: Any] = [:]
    private var baseDictionary: [String: [String: Any]] = [:]
    private var lookupMap: [String: String] = [:]
    private var postprocessRules: [String: Any] = [:]
    var isSpanishDataLoaded = false
    
    func loadSpanishData() {
        let candidates = [
            ("es_final_with_rules_ENRICHED", "json"),  // ← prefer enriched
            ("es_final_with_rules_CLEAN", "json"),
            ("es_final_with_rules", "json")
        ]
        var loaded = false

        for (name, ext) in candidates {
            if let url = Bundle.main.url(forResource: name, withExtension: ext),
               let data = try? Data(contentsOf: url),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

                grammarRules = json["rules"] as? [String: Any] ?? [:]
                baseDictionary = json["dictionary"] as? [String: [String: Any]] ?? [:]
                lookupMap = json["lookup"] as? [String: String] ?? [:]
                postprocessRules = (grammarRules["postprocess_en"] as? [String: Any]) ?? [:]

                isSpanishDataLoaded = true
                loaded = true
                _ = (postprocessRules["regex_replacements"] as? [[String: Any]])?.count ?? 0
                break
            }
        }

        #if DEBUG
        if !loaded {
            print("❌ Failed to load Spanish data")
        }
        #endif
    }
    
    /// New pipeline:
    /// 1) OCR corrections → 2) Extract & lock Spanish phrases (placeholders)
    /// 3) Word-by-word translate remaining tokens → 4) Reinsert phrase translations
    /// 5) Post-process English (JSON rules) → 6) Local English polish (hard-coded edge fixes)
    func interpretSpanishWithContext(_ text: String) -> String {
        #if DEBUG
        print("🔍 Starting translation of: \(text)")
        #endif
        
        // 1) Apply OCR corrections first (before any splitting)
        let cleaned = applyOcrCorrections(text)
        #if DEBUG
        print("📝 After OCR corrections: \(cleaned)")
        #endif
        
        // 2) Extract & lock phrases to placeholders so we don't break idioms/expressions
        let (phraseStripped, phraseMap) = extractAndReplacePhrases(cleaned)
        
        // 3) Word-by-word translation of remaining content (placeholders are preserved)
        let translatedBody = translateLooseTextWordByWord(phraseStripped)
        
        // 4) Reinsert phrase translations (already EN) — longest placeholder first just in case
        var withPhrases = translatedBody
        for placeholder in phraseMap.keys.sorted(by: { $0.count > $1.count }) {
            if let en = phraseMap[placeholder], !en.isEmpty {
                withPhrases = withPhrases.replacingOccurrences(of: placeholder, with: en)
            }
        }
        
        // 5) JSON-driven postprocess (detokenize, regex, contractions, spacing, etc.)
        let postProcessed = postProcessEnglish(withPhrases)
        
        // 6) Local English polish for common offline OCR/MT literalisms
        let finalTranslation = applyLocalEnglishPolish(postProcessed)
        
        #if DEBUG
        print("✅ Final translation: \(finalTranslation)")
        #endif
        
        return finalTranslation
    }
    
    // MARK: - Stage 3: word-by-word translation with punctuation handling (preserves placeholders)
    private func translateLooseTextWordByWord(_ text: String) -> String {
        // Treat placeholders as atomic tokens
        let tokens = text.components(separatedBy: .whitespacesAndNewlines)
        var out: [String] = []
        
        for tok in tokens {
            guard !tok.isEmpty else { continue }
            if tok.hasPrefix("¶PHRASE"), tok.hasSuffix("¶") {
                // Locked phrase placeholder — keep as-is for now
                out.append(tok)
                continue
            }
            
            // Extract punctuation
            var prefix = ""
            var suffix = ""
            var core = tok
            
            while let first = core.first, first.isPunctuation || first == "¡" || first == "¿" || first == "«" || first == "»" {
                prefix.append(first)
                core.removeFirst()
            }
            while let last = core.last, last.isPunctuation || last == "!" || last == "?" || last == "”" || last == "“" || last == "’" || last == "”" {
                suffix = String(last) + suffix
                core.removeLast()
            }
            
            if core.isEmpty {
                out.append(tok) // punctuation-only
                continue
            }
            
            if let en = findTranslationWithFallback(for: core) {
                // Preserve capitalization if original token started uppercase
                let finalEN: String
                if let ch = core.first, ch.isUppercase {
                    finalEN = en.prefix(1).uppercased() + en.dropFirst()
                } else {
                    finalEN = en
                }
                out.append(prefix + finalEN + suffix)
            } else {
                out.append(tok) // unknown: pass-through
            }
        }
        
        return out.joined(separator: " ")
    }
    
    // MARK: - Stage 1: OCR cleanup (tightened)
    private func applyOcrCorrections(_ text: String) -> String {
        var corrected = text
        
        // 1) Apply JSON-driven specific corrections first (longest first)
        if let corrections = grammarRules["ocr_corrections"] as? [String: String] {
            let sorted = corrections.sorted { $0.key.count > $1.key.count }
            for (wrong, right) in sorted {
                let pattern = "\\b\(NSRegularExpression.escapedPattern(for: wrong))\\b"
                if let rx = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                    corrected = rx.stringByReplacingMatches(
                        in: corrected,
                        options: [],
                        range: NSRange(location: 0, length: corrected.utf16.count),
                        withTemplate: right
                    )
                }
            }
        }
        
        // 2) Hand-tuned OCR normalizations common in scene text
        corrected = corrected
            // Normalize weird spacing around punctuation
            .replacingOccurrences(of: " :", with: ":")
            .replacingOccurrences(of: " ,", with: ",")
            .replacingOccurrences(of: " ;", with: ";")
            .replacingOccurrences(of: " .", with: ".")
            .replacingOccurrences(of: " ¡", with: "¡")
            .replacingOccurrences(of: " ¿", with: "¿")
        
        // 3) Targeted fixes observed in your sample
        // “He Mercado…” → “El Mercado…”
        if let rx = try? NSRegularExpression(pattern: #"(^|\.\s+)(He)\s+(Mercado\b)"#, options: []) {
            corrected = rx.stringByReplacingMatches(in: corrected, options: [], range: NSRange(location: 0, length: corrected.utf16.count), withTemplate: "$1El $3")
        }
        // “He Boquería…” → “El Boquería…/La Boquería…” (market name is feminine with article “La” before Boquería)
        if let rx = try? NSRegularExpression(pattern: #"(^|\.\s+)(He)\s+(Boquería\b)"#, options: []) {
            corrected = rx.stringByReplacingMatches(in: corrected, options: [], range: NSRange(location: 0, length: corrected.utf16.count), withTemplate: "$1La $3")
        }
        // Common mis-OCR for Boquería variants
        corrected = corrected.replacingOccurrences(of: "Boverta", with: "Boquería")
        corrected = corrected.replacingOccurrences(of: "Botería", with: "Boquería")
        
        // Fix double spaces
        while corrected.contains("  ") {
            corrected = corrected.replacingOccurrences(of: "  ", with: " ")
        }
        return corrected
    }
    
    // MARK: - Phrase extraction (Spanish → English map from JSON rules), returns placeholders
    private func extractAndReplacePhrases(_ text: String) -> (String, [String: String]) {
        var processedText = text
        var phraseMap: [String: String] = [:]
        var phraseCounter = 0
        
        // Collect from rules buckets
        let phraseSources: [(String, Any)] = [
            ("phrases", grammarRules["phrases"] ?? [:]),
            ("idioms", grammarRules["idioms"] ?? [:]),
            ("commonPhrases", grammarRules["commonPhrases"] ?? [:]),
            ("menuPhrases", grammarRules["menuPhrases"] ?? [:])
        ]
        
        var all: [(phrase: String, translation: String)] = []
        for (_, source) in phraseSources {
            if let phrases = source as? [String: String] {
                for (sp, en) in phrases { all.append((sp, en)) }
            } else if let complex = source as? [String: Any] {
                for (sp, v) in complex {
                    if let s = v as? String { all.append((sp, s)) }
                    else if let d = v as? [String: Any], let en = d["translation"] as? String { all.append((sp, en)) }
                }
            }
        }
        
        // Longer Spanish first to avoid partial overlap
        all.sort { $0.phrase.count > $1.phrase.count }
        
        for (sp, en) in all {
            guard !sp.isEmpty, !en.isEmpty else { continue }
            let pat = "\\b\(NSRegularExpression.escapedPattern(for: sp))\\b"
            if let rx = try? NSRegularExpression(pattern: pat, options: .caseInsensitive) {
                let matches = rx.matches(in: processedText, options: [], range: NSRange(location: 0, length: processedText.utf16.count))
                for m in matches.reversed() {
                    if let r = Range(m.range, in: processedText) {
                        let ph = "¶PHRASE\(phraseCounter)¶"
                        processedText.replaceSubrange(r, with: ph)
                        phraseMap[ph] = en
                        phraseCounter += 1
                    }
                }
            }
        }
        return (processedText, phraseMap)
    }
    
    // MARK: - Dictionary lookup with morphological fallback
    private func findTranslationWithFallback(for word: String) -> String? {
        guard !word.isEmpty else { return nil }
        _ = normalizeForLookup(word) // doc no-op
        
        // Exact
        if let t = findTranslation(for: word) { return extractBestTranslation(from: t) }
        // Morphological variants
        for v in generateMorphologicalVariations(word) {
            if let t = findTranslation(for: v) { return extractBestTranslation(from: t) }
        }
        return nil
    }
    
    private func extractBestTranslation(from translation: Any) -> String {
        if let s = translation as? String {
            if s.contains("/") { return s.components(separatedBy: "/").first?.trimmingCharacters(in: .whitespaces) ?? s }
            return s
        } else if let arr = translation as? [String], let first = arr.first {
            return first
        } else if let dict = translation as? [String: Any], let trans = dict["translation"] {
            return extractBestTranslation(from: trans)
        }
        return translation as? String ?? ""
    }
    
    private func generateMorphologicalVariations(_ word: String) -> [String] {
        var vars: [String] = []
        let lower = word.lowercased()
        if lower != word { vars.append(lower) }
        
        // Verb endings & common morphs
        // Present/imperative/plural/gender
        let endings = [
            "s","es","os","as","a","o","mente",
            "ando","iendo","yendo", // gerunds
            "ado","ada","ados","adas","ido","ida","idos","idas", // participles
            // Preterite/imperfect/conditional/subjunctive fragments
            "é","aste","ó","amos","aron","aba","abas","ábamos","aban",
            "í","iste","ió","imos","ieron","ía","ías","íamos","ían",
            "aría","arías","aríamos","arían","ería","erías","eríamos","erían",
            "iría","irías","iríamos","irían",
            "que","gué","cé" // orthographic preterites
        ]
        for e in endings {
            if lower.hasSuffix(e), lower.count > e.count + 1 {
                vars.append(String(lower.dropLast(e.count)))
            }
        }
        // Try infinitives too
        vars.append(lower + "r")
        vars.append(lower + "ar")
        vars.append(lower + "er")
        vars.append(lower + "ir")
        return Array(Set(vars))
    }
    
    private func stripDiacriticsKeepingLetters(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))
    }

    private func normalizeForLookup(_ raw: String) -> (exact: String, folded: String) {
        var s = raw.lowercased()
        s = s.replacingOccurrences(of: "¿", with: "").replacingOccurrences(of: "¡", with: "")
        s = s.unicodeScalars.filter { CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "ñáéíóúü'-")).contains($0) }.map(String.init).joined()
        let folded = stripDiacriticsKeepingLetters(s)
        return (s, folded)
    }
    
    private func findTranslation(for word: String) -> Any? {
        guard !word.isEmpty else { return nil }
        let keys = normalizeForLookup(word)
        
        // Lookup map → base dict
        if let mapped = lookupMap[keys.exact], let e = baseDictionary[mapped] { return e["translation"] }
        if let mapped = lookupMap[keys.folded], let e = baseDictionary[mapped] { return e["translation"] }
        
        // Direct dict hits
        if let e = baseDictionary[keys.exact] { return e["translation"] }
        if let e = baseDictionary[keys.folded] { return e["translation"] }
        
        // Articles
        if let arts = grammarRules["articles"] as? [String: [String: Any]],
           let info = arts[keys.exact] ?? arts[keys.folded],
           let meaning = info["meaning"] { return meaning }
        // Contractions
        if let contr = grammarRules["contractions"] as? [String: [String: String]],
           let info = contr[keys.exact] ?? contr[keys.folded],
           let meaning = info["meaning"] { return meaning }
        // False friends
        if let ff = grammarRules["falseFriends"] as? [String: Any],
           let t = ff[keys.exact] ?? ff[keys.folded] { return t }
        // Abbreviations
        if let abbr = grammarRules["abbreviations"] as? [String: String],
           let m = abbr[keys.exact] ?? abbr[keys.folded] { return m }
        // Regional variants
        if let reg = grammarRules["regionalVariants"] as? [String: [String: String]],
           let v = reg[keys.exact] ?? reg[keys.folded],
           let m = v["meaning"] ?? v["english"] { return m }
        
        return nil
    }
    
    // MARK: - JSON-driven postprocessor (unchanged flow, safer UTF16 ranges)
    private func postProcessEnglish(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        let ppe = postprocessRules

        let defaultOrder = ["detokenize","regex_replacements","phrase_map_es_to_en","article_fixes","order_fixes","contractions","spacing_and_caps"]
        let applyOrder = (ppe["apply_order"] as? [String]) ?? defaultOrder

        var s = text

        for step in applyOrder {
            switch step {
            case "detokenize":
                if let det = (ppe["detokenize"] as? [String: Any])?["fixes"] as? [[String: String]] {
                    s = applyDetokenizeFixes(s, fixes: det)
                }
            case "regex_replacements":
                if let regs = ppe["regex_replacements"] as? [[String: Any]] {
                    s = applyRegexReplacements(s, specs: regs)
                }
            case "phrase_map_es_to_en":
                if let map = ppe["phrase_map_es_to_en"] as? [String: String] {
                    s = applyPhraseMap(s, map: map)
                }
            case "article_fixes":
                if let regs = ppe["article_fixes"] as? [[String: Any]] {
                    s = applyRegexReplacements(s, specs: regs)
                }
            case "order_fixes":
                if let regs = ppe["order_fixes"] as? [[String: Any]] {
                    s = applyRegexReplacements(s, specs: regs)
                }
            case "contractions":
                if let ctr = ppe["contractions"] as? [String: String] {
                    s = applyContractions(s, map: ctr)
                }
            case "spacing_and_caps":
                if let flags = ppe["spacing_and_caps"] as? [String: Any] {
                    s = applySpacingAndCaps(s,
                                             collapseDoubleSpaces: (flags["collapse_double_spaces"] as? Bool) ?? true,
                                             capitalizeStarts: (flags["capitalize_sentence_starts"] as? Bool) ?? true,
                                             trimEdges: (flags["trim_edges"] as? Bool) ?? true)
                }
            default:
                break
            }
        }
        return s
    }

    private func applyDetokenizeFixes(_ text: String, fixes: [[String: String]]) -> String {
        var s = text
        for fix in fixes {
            if let from = fix["from"], let to = fix["to"] {
                s = s.replacingOccurrences(of: from, with: to)
            }
        }
        return s
    }

    private func applyRegexReplacements(_ text: String, specs: [[String: Any]]) -> String {
        var s = text
        for spec in specs {
            guard let pattern = spec["pattern"] as? String,
                  let template = spec["template"] as? String else { continue }
            let flags = (spec["flags"] as? String) ?? ""
            var opts: NSRegularExpression.Options = []
            if flags.lowercased().contains("i") { opts.insert(.caseInsensitive) }

            if let rx = try? NSRegularExpression(pattern: pattern, options: opts) {
                s = rx.stringByReplacingMatches(in: s, options: [], range: NSRange(location: 0, length: s.utf16.count), withTemplate: template)
            }
        }
        return s
    }

    private func applyPhraseMap(_ text: String, map: [String: String]) -> String {
        // Longest Spanish phrase first so longer wins
        let sorted = map.keys.sorted { $0.count > $1.count }
        var s = text
        for sp in sorted {
            let en = map[sp] ?? ""
            guard !en.isEmpty else { continue }
            let pat = "\\b\(NSRegularExpression.escapedPattern(for: sp))\\b"
            if let rx = try? NSRegularExpression(pattern: pat, options: .caseInsensitive) {
                s = rx.stringByReplacingMatches(in: s, options: [], range: NSRange(location: 0, length: s.utf16.count), withTemplate: en)
            }
        }
        return s
    }

    private func applyContractions(_ text: String, map: [String: String]) -> String {
        var s = text
        for (full, short) in map.sorted(by: { $0.key.count > $1.key.count }) {
            s = s.replacingOccurrences(of: full, with: short, options: .caseInsensitive, range: nil)
        }
        return s
    }

    private func applySpacingAndCaps(_ text: String,
                                     collapseDoubleSpaces: Bool,
                                     capitalizeStarts: Bool,
                                     trimEdges: Bool) -> String {
        var s = text
        s = s.replacingOccurrences(of: " ,", with: ",")
        s = s.replacingOccurrences(of: " .", with: ".")
        s = s.replacingOccurrences(of: " !", with: "!")
        s = s.replacingOccurrences(of: " ?", with: "?")
        if collapseDoubleSpaces {
            while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
        }
        if capitalizeStarts {
            s = capitalizeSentenceStarts(s)
        }
        if trimEdges {
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return s
    }

    private func capitalizeSentenceStarts(_ text: String) -> String {
        let delimiters = CharacterSet(charactersIn: ".!?")
        var out: [String] = []
        var buffer = ""

        func push() {
            let t = buffer.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty {
                let cap = t.prefix(1).uppercased() + t.dropFirst()
                out.append(cap)
            }
            buffer.removeAll(keepingCapacity: true)
        }

        for ch in text {
            buffer.append(ch)
            if String(ch).rangeOfCharacter(from: delimiters) != nil {
                push()
            }
        }
        push()

        var s = out.joined(separator: " ")
        s = s.replacingOccurrences(of: " ,", with: ",")
        s = s.replacingOccurrences(of: " .", with: ".")
        s = s.replacingOccurrences(of: " !", with: "!")
        s = s.replacingOccurrences(of: " ?", with: "?")
        while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
        return s
    }
    
    // MARK: - Local English polish (hard-coded edge fixes for naturalness)
    private func applyLocalEnglishPolish(_ text: String) -> String {
        var s = text
        
        // “Yesterday in the morning” → “Yesterday morning”
        if let rx = try? NSRegularExpression(pattern: #"\bYesterday in the morning\b"#, options: .caseInsensitive) {
            s = rx.stringByReplacingMatches(in: s, options: [], range: NSRange(location: 0, length: s.utf16.count), withTemplate: "Yesterday morning")
        }
        // “so much tourists as” / “so many tourists as” → “as many tourists as”
        if let rx = try? NSRegularExpression(pattern: #"\bso (much|many)\s+([A-Za-z]+?)\s+as\b"#, options: .caseInsensitive) {
            s = rx.stringByReplacingMatches(in: s, options: [], range: NSRange(location: 0, length: s.utf16.count), withTemplate: "as many $2 as")
        }
        // “more forward,” literal for “Más adelante,” → “Further along,”
        if let rx = try? NSRegularExpression(pattern: #"\bMore forward\b"#, options: .caseInsensitive) {
            s = rx.stringByReplacingMatches(in: s, options: [], range: NSRange(location: 0, length: s.utf16.count), withTemplate: "Further along")
        }
        // Normalize quote spacing: “me dijo :” → “me dijo:”
        s = s.replacingOccurrences(of: " :", with: ":")
        
        // Collapse stray spaces
        while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// Renamed from CameraManager to avoid conflict with global CameraManager
class ZoomCameraManager: NSObject, ObservableObject {
    @Published var currentZoomLevel: CGFloat = 1.0
    
    private var captureDevice: AVCaptureDevice?
    private var initialZoomFactor: CGFloat = 1.0
    
    func setup(device: AVCaptureDevice) {
        self.captureDevice = device
    }
    
    func handlePinchGesture(_ scale: CGFloat) {
        guard let device = captureDevice else { return }
        
        let newZoomFactor = initialZoomFactor * scale
        let clampedZoom = max(1.0, min(newZoomFactor, min(device.maxAvailableVideoZoomFactor, 5.0)))
        
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = clampedZoom
            device.unlockForConfiguration()
            
            DispatchQueue.main.async {
                self.currentZoomLevel = clampedZoom
            }
        } catch {
            #if DEBUG
            print("Failed to set zoom: \(error)")
            #endif
        }
    }
    
    func setPinchGestureStartZoom() {
        initialZoomFactor = captureDevice?.videoZoomFactor ?? 1.0
    }
}

// LiveOCRViewModel
final class LiveOCRViewModel: NSObject, ObservableObject {
    weak var cameraPreviewRef: CameraPreviewView?
    weak var cameraPreviewView: CameraPreviewView?

    @Published var recognizedText: String = ""
    @Published var translatedText: String = ""
    @Published var isProcessing: Bool = false
    @Published var isUltraWide: Bool = false
    @Published var cameraPosition: AVCaptureDevice.Position = .back
    @Published var isPinching: Bool = false

    let cameraManager = ZoomCameraManager()
    
    private let speechSynthesizer = AVSpeechSynthesizer()
    private let textProcessor = OCRTextProcessor()
    private var textRecognitionRequest: VNRecognizeTextRequest?
    private var lastProcessedTime = Date()
    
    private var processInterval: TimeInterval {
        if textProcessor.isSpanishDataLoaded {
            switch DevicePerf.shared.tier {
            case .low:  return 1.5
            case .mid:  return 1.0
            case .high: return 0.75
            }
        } else {
            switch DevicePerf.shared.tier {
            case .low:  return 0.75
            case .mid:  return 0.50
            case .high: return 0.30
            }
        }
    }
    
    private var speechCompletionHandler: (() -> Void)?
    
    override init() {
        super.init()
        setupTextRecognition()
        textProcessor.loadSpanishData()
        speechSynthesizer.delegate = self
    }
    
    deinit {
        stopSession()
        stopSpeaking()
    }
    
    private func setupTextRecognition() {
        textRecognitionRequest = VNRecognizeTextRequest { [weak self] request, error in
            guard let self = self else { return }
            
            if let error = error {
                #if DEBUG
                print("Text recognition error: \(error)")
                #endif
                return
            }
            
            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                return
            }
            
            let recognizedStrings = observations.compactMap { observation in
                observation.topCandidates(1).first?.string
            }
            
            let fullText = recognizedStrings.joined(separator: " ")
            
            if let request = self.textRecognitionRequest,
               request.recognitionLanguages.contains("es") || request.recognitionLanguages.contains("es-ES") {
                // Spanish mode → show raw and translate on background
                DispatchQueue.main.async {
                    self.recognizedText = fullText
                }
                if !fullText.isEmpty {
                    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                        guard let self = self else { return }
                        let translated = self.textProcessor.interpretSpanishWithContext(fullText)
                        #if DEBUG
                        print("Spanish detected: \(fullText)")
                        print("English translation: \(translated)")
                        #endif
                        DispatchQueue.main.async {
                            self.translatedText = translated
                            self.isProcessing = false
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        self.isProcessing = false
                    }
                }
            } else {
                // English mode → passthrough
                DispatchQueue.main.async {
                    self.recognizedText = fullText
                    self.translatedText = ""
                    self.isProcessing = false
                }
            }
        }
        
        // === Tier tuning ===
        let tier = DevicePerf.shared.tier
        switch tier {
        case .low:
            textRecognitionRequest?.recognitionLevel = .fast
            textRecognitionRequest?.usesLanguageCorrection = false
            textRecognitionRequest?.minimumTextHeight = 0.03
        case .mid:
            textRecognitionRequest?.recognitionLevel = .accurate
            textRecognitionRequest?.usesLanguageCorrection = true
            textRecognitionRequest?.minimumTextHeight = 0.02
        case .high:
            textRecognitionRequest?.recognitionLevel = .accurate
            textRecognitionRequest?.usesLanguageCorrection = true
            textRecognitionRequest?.minimumTextHeight = 0.015
        }
    }
    
    func processFrame(_ pixelBuffer: CVPixelBuffer, mode: OCRMode) {
        guard !isPinching else { return }

        let now = Date()
        guard now.timeIntervalSince(lastProcessedTime) >= processInterval else { return }
        lastProcessedTime = now
        guard !isProcessing else { return }
        
        let isSpanishMode: Bool = (mode == .spanishToEnglish)
        
        DispatchQueue.main.async {
            self.isProcessing = true
        }
        
        if isSpanishMode {
            textRecognitionRequest?.recognitionLanguages = ["es-ES", "es"]
            #if DEBUG
            print("📱 Set recognition language to Spanish")
            #endif
        } else {
            textRecognitionRequest?.recognitionLanguages = ["en-US", "en"]
            #if DEBUG
            print("📱 Set recognition language to English")
            #endif
        }
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, let request = self.textRecognitionRequest else { return }
            do {
                try handler.perform([request])
            } catch {
                #if DEBUG
                print("Failed to perform text recognition: \(error)")
                #endif
                DispatchQueue.main.async {
                    self.isProcessing = false
                }
            }
        }
    }
    
    func speak(text: String, voiceIdentifier: String, completion: @escaping () -> Void) {
        guard !text.isEmpty else {
            completion()
            return
        }
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        self.speechCompletionHandler = completion
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let utterance = AVSpeechUtterance(string: text)
            if let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
                utterance.voice = voice
            }
            utterance.rate = 0.5
            utterance.volume = 0.9
            self.speechSynthesizer.speak(utterance)
        }
    }
    
    func copyText(_ text: String) {
        guard !text.isEmpty else { return }
        UIPasteboard.general.string = text
        SettingsOverlayView.addToCopyHistory(text)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
    
    func clearText() {
        recognizedText = ""
        translatedText = ""
    }
    
    func stopSpeaking() {
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
    }
    
    func startSession() {
        #if DEBUG
        print("🎬 OCR session started")
        #endif
    }
    
    func stopSession() {
        stopSpeaking()
        #if DEBUG
        print("🛑 OCR session stopped")
        #endif
    }
    
    func toggleCameraZoom() {
        isUltraWide.toggle()
        #if DEBUG
        print("📷 Toggled camera zoom: ultraWide = \(isUltraWide)")
        #endif
    }

    func flipCamera() {
        cameraPosition = cameraPosition == .back ? .front : .back
        if cameraPosition == .front {
            isUltraWide = false
        }
        #if DEBUG
        print("📷 Flipped camera: position = \(cameraPosition)")
        #endif
    }
    
    func setCameraPreview(_ preview: CameraPreviewView) {
        self.cameraPreviewView = preview
    }
}

// MARK: - AVSpeechSynthesizerDelegate
extension LiveOCRViewModel: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.speechCompletionHandler?()
            self.speechCompletionHandler = nil
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.speechCompletionHandler?()
            self.speechCompletionHandler = nil
        }
    }
}

extension LiveOCRViewModel {
    func shutdown() {
        print("🧹 LiveOCRViewModel shutdown starting")
        cameraPreviewView?.stopSession()
        stopSession()
        DispatchQueue.main.async { [weak self] in
            self?.recognizedText = ""
            self?.translatedText = ""
        }
        print("🧹 LiveOCRViewModel shutdown complete")
    }
}
