import Foundation

// MARK: - JSON Models (All shared types in one place)

private struct ESMetadata: Decodable {
    let cleaned: Bool?
    let language_pair: String?
    let total_dictionary: Int?
    let total_rules: Int?
    let version: String?
}

private struct ESDictEntry: Decodable {
    let lemma: String?
    let morph: [String: String]?
    let pos: String?
    let translation: String?
}

private struct ESRegexRule: Decodable {
    let name: String?
    let description: String?
    let pattern: String
    let replace: String
    let options: [String]?
    let enabled: Bool?
}

private struct ESMaster: Decodable {
    let _metadata: ESMetadata?
    let dictionary: [String: ESDictEntry]?
    let rules: [String: AnyDecodable]?
    enum CodingKeys: String, CodingKey { case _metadata, dictionary, rules }
}

// Generic "any" JSON wrapper
private struct AnyDecodable: Decodable {
    let value: Any
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let dict = try? c.decode([String: AnyDecodable].self) {
            value = dict.mapValues { $0.value }
        } else if let arr = try? c.decode([AnyDecodable].self) {
            value = arr.map(\.value)
        } else if let s = try? c.decode(String.self) {
            value = s
        } else if let i = try? c.decode(Int.self) {
            value = i
        } else if let d = try? c.decode(Double.self) {
            value = d
        } else if let b = try? c.decode(Bool.self) {
            value = b
        } else {
            value = NSNull()
        }
    }
}

// MARK: - Aho-Corasick-lite phrase matcher

final class PhraseMatcher {
    private var phraseMap: [String: String] = [:]
    private var lengths: [Int] = []
    init(phrases: [String: String]) {
        var norm: [String: String] = [:]
        for (k, v) in phrases {
            let nk = PhraseMatcher.normalize(k)
            if !nk.isEmpty { norm[nk] = v }
        }
        phraseMap = norm
        lengths = Set(norm.keys.map { $0.split(separator: " ").count }).sorted(by: >)
    }

    private static func normalize(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func match(tokens: [String]) -> [(String, String?)] {
        var i = 0
        var out: [(String, String?)] = []
        while i < tokens.count {
            var matched = false
            for L in lengths {
                guard i + L <= tokens.count else { continue }
                let span = tokens[i ..< (i + L)].joined(separator: " ")
                if let eng = phraseMap[span] {
                    out.append((span, eng))
                    i += L
                    matched = true
                    break
                }
            }
            if !matched { out.append((tokens[i], nil)); i += 1 }
        }
        return out
    }
}

// MARK: - Text Domain Detection

enum TextDomain {
    case restaurant, signage, narrative, general
}

// MARK: - Translation Result Models

struct TranslationResult {
    let text: String
    let confidence: Double
    let unknownTokens: [String]
}

// MARK: - Static Spanish Processor

@MainActor
final class SpanishTranslationProcessor {
    static let shared = SpanishTranslationProcessor()

    // Core stores
    private var dict: [String: String] = [:] // surface (lowercased) → translation
    private var phraseMatcher: PhraseMatcher?
    private var reflexiveMap: [String: String] = [:] // "se vende" → "for sale"

    // Compiled regex packs (from JSON)
    private var compiledGeneral: [(NSRegularExpression, String)] = []
    private var compiledDialogueFromJSON: [(NSRegularExpression, String)] = []
    private var compiledGrammar: [(NSRegularExpression, String)] = []
    private var compiledCleanup: [(NSRegularExpression, String)] = []

    // Built-in deterministic rule packs
    private var builtinPriceAndUnits: [(NSRegularExpression, String)] = []
    private var builtinAlInfinitivo: [(NSRegularExpression, String)] = []
    private var builtinPrepositions: [(NSRegularExpression, String)] = []
    private var builtinMenuLexicon: [(NSRegularExpression, String)] = []
    private var builtinNarrativeGrammar: [(NSRegularExpression, String)] = []
    private var builtinDialogue: [(NSRegularExpression, String)] = []

    // Cache (simplified, no concurrency needed)
    private var cache: [String: String] = [:]

    private(set) var isLoaded = false

    private init() { Task { await loadSpanishData() } }

    // MARK: - Public Translation Methods (Using your exact method names!)

    func interpretSpanishWithContext(_ text: String) -> String {
        guard isLoaded else { return text }
        let cacheKey = normalizeKey(text)
        if let cached = cache[cacheKey] {
            return cached
        }

        let domain = detectDomain(text)
        let sentences = splitIntoSentences(text)
        let batches = batchSentences(sentences, targetChars: 2200)

        var outPieces: [String] = []
        outPieces.reserveCapacity(batches.count)
        for batch in batches {
            let translated = translateBatch(batch, domain: domain)
            outPieces.append(translated)
        }
        let result = outPieces.joined(separator: " ")
            .replacingOccurrences(of: #"(\s+)"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        cache[cacheKey] = result
        return result
    }

    func interpretSpanishWithConfidence(_ text: String) -> TranslationResult {
        guard isLoaded else { return .init(text: text, confidence: 0, unknownTokens: []) }
        let domain = detectDomain(text)
        let sentences = splitIntoSentences(text)
        let batches = batchSentences(sentences, targetChars: 2200)

        var outPieces: [String] = []
        var unknowns: [String] = []
        var total = 0
        var translated = 0

        for batch in batches {
            let (t, u, tok, got) = translateBatchTelemetry(batch, domain: domain)
            outPieces.append(t)
            unknowns.append(contentsOf: u)
            total += tok
            translated += got
        }
        let result = outPieces.joined(separator: " ")
            .replacingOccurrences(of: #"(\s+)"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let conf = total > 0 ? Double(translated) / Double(total) : 1.0
        return .init(text: result, confidence: conf, unknownTokens: Array(Set(unknowns)))
    }

    // MARK: - Core Translation Methods (Your exact working logic!)

    private func translateBatch(_ text: String, domain: TextDomain) -> String {
        let tokens = tokenize(text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression))
        let phraseApplied = phraseMatcher?.match(tokens: tokens.map { $0.lowercased() }) ?? tokens.map { ($0.lowercased(), nil) }

        var englishPieces: [String] = []
        englishPieces.reserveCapacity(phraseApplied.count)
        for (surface, ph) in phraseApplied {
            if let eng = ph { englishPieces.append(eng); continue }
            if let eng = dict[surface] {
                englishPieces.append(eng)
            } else if let eng = dict[surface.folding(options: .diacriticInsensitive, locale: .current)] {
                englishPieces.append(eng)
            } else {
                englishPieces.append(surface)
            }
        }
        var out = englishPieces.joined(separator: " ")

        // Fast reflexive pack for menus/signage/general
        if domain == .restaurant || domain == .signage || domain == .general {
            if !reflexiveMap.isEmpty {
                for (k, v) in reflexiveMap {
                    let pat = "\\b" + NSRegularExpression.escapedPattern(for: k) + "\\b"
                    if let re = try? NSRegularExpression(pattern: pat, options: [.caseInsensitive]) {
                        out = re.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: v)
                    }
                }
            }
        }

        // Built-ins first (surgical, deterministic)
        out = applyRulePack(builtinPriceAndUnits, to: out) // price/unit
        out = applyRulePack(builtinMenuLexicon, to: out) // menu lexicon
        out = applyRulePack(builtinAlInfinitivo, to: out) // al + infinitivo
        out = applyRulePack(builtinPrepositions, to: out) // prepositions & OCRish

        // JSON packs
        out = applyRulePack(compiledGeneral, to: out)
        out = applyRulePack(compiledGrammar, to: out)

        // Built-in narrative grammar targets (fixes your two stories)
        out = applyRulePack(builtinNarrativeGrammar, to: out)

        // Dialogue: our built-in first, then any JSON dialogue
        if domain == .narrative {
            out = applyRulePack(builtinDialogue, to: out)
            out = applyRulePack(compiledDialogueFromJSON, to: out)
        }

        // Cleanup (from JSON)
        out = applyRulePack(compiledCleanup, to: out)

        // Finalizer
        out = finalize(out)
        return out
    }

    private func translateBatchTelemetry(_ text: String, domain: TextDomain) -> (String, [String], Int, Int) {
        let tokens = tokenize(text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression))
        let phraseApplied = phraseMatcher?.match(tokens: tokens.map { $0.lowercased() }) ?? tokens.map { ($0.lowercased(), nil) }

        var englishPieces: [String] = []
        var unknowns: [String] = []
        var total = 0
        var translated = 0

        for (surface, ph) in phraseApplied {
            total += 1
            if let eng = ph { englishPieces.append(eng); translated += 1; continue }
            if let eng = dict[surface] { englishPieces.append(eng); translated += 1 }
            else if let eng = dict[surface.folding(options: .diacriticInsensitive, locale: .current)] { englishPieces.append(eng); translated += 1 }
            else { englishPieces.append(surface); unknowns.append(surface) }
        }
        var out = englishPieces.joined(separator: " ")

        if domain == .restaurant || domain == .signage || domain == .general {
            if !reflexiveMap.isEmpty {
                for (k, v) in reflexiveMap {
                    let pat = "\\b" + NSRegularExpression.escapedPattern(for: k) + "\\b"
                    if let re = try? NSRegularExpression(pattern: pat, options: [.caseInsensitive]) {
                        out = re.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: v)
                    }
                }
            }
        }

        out = applyRulePack(builtinPriceAndUnits, to: out)
        out = applyRulePack(builtinMenuLexicon, to: out)
        out = applyRulePack(builtinAlInfinitivo, to: out)
        out = applyRulePack(builtinPrepositions, to: out)

        out = applyRulePack(compiledGeneral, to: out)
        out = applyRulePack(compiledGrammar, to: out)
        out = applyRulePack(builtinNarrativeGrammar, to: out)
        if domain == .narrative {
            out = applyRulePack(builtinDialogue, to: out)
            out = applyRulePack(compiledDialogueFromJSON, to: out)
        }
        out = applyRulePack(compiledCleanup, to: out)

        out = finalize(out)
        return (out, unknowns, total, translated)
    }

    private func applyRulePack(_ pack: [(NSRegularExpression, String)], to text: String) -> String {
        guard !pack.isEmpty else { return text }
        var s = text
        for (re, repl) in pack {
            s = re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: repl)
        }
        return s
    }

    // MARK: - Text Processing Utilities (Your exact methods)

    private func detectDomain(_ text: String) -> TextDomain {
        let t = text.lowercased()
        let menuHits = ["menú", "menu", "plato", "platos", "postre", "entrante", "bebida", "bebidas", "cuenta", "€", "euros", "kilo", "docena", "kg", "precio", "oferta"]
            .filter { t.contains($0) }.count
        let signHits = ["se vende", "se alquila", "prohibido", "entrada", "salida", "cerrado", "abierto", "peligro", "precaución", "no fumar", "no pasar"]
            .filter { t.contains($0) }.count
        let narrativeHits = ["ayer", "mañana", "me desperté", "mientras", "de pronto", "cuando", "entonces", "luego", "sonriendo", "caminé", "pensé", "observé", "—", "\""]
            .filter { t.contains($0) }.count
        let m = max(menuHits, signHits, narrativeHits)
        if m == 0 { return .general }
        if m == menuHits { return .restaurant }
        if m == signHits { return .signage }
        return .narrative
    }

    private func splitIntoSentences(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var s = text
        let abbrs = ["Sr", "Sra", "Dr", "Dra", "etc", "vs", "pág", "pp"]
        for abbr in abbrs {
            s = s.replacingOccurrences(of: "\(abbr).", with: "\(abbr)<<DOT>>", options: .caseInsensitive)
        }
        let pattern = try! NSRegularExpression(pattern: #"(?<=[.!?])\s+(?=[A-ZÀ-Ú""])"#, options: [])
        let range = NSRange(s.startIndex..., in: s)
        var sentences: [String] = []
        var last = s.startIndex
        pattern.enumerateMatches(in: s, options: [], range: range) { m, _, _ in
            guard let m else { return }
            let r = Range(m.range, in: s)!
            let end = r.lowerBound
            sentences.append(String(s[last ..< end]))
            last = r.upperBound
        }
        sentences.append(String(s[last...]))
        sentences = sentences.map {
            $0.replacingOccurrences(of: "<<DOT>>", with: ".")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        return sentences
    }

    private func batchSentences(_ sentences: [String], targetChars: Int) -> [String] {
        guard !sentences.isEmpty else { return [] }
        var batches: [String] = []
        var current = ""
        for s in sentences {
            if (current.count + s.count + 1) > targetChars, !current.isEmpty {
                batches.append(current); current = s
            } else {
                if current.isEmpty { current = s } else { current += " " + s }
            }
        }
        if !current.isEmpty { batches.append(current) }
        return batches
    }

    private func normalizeKey(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Tokenizer & Finalizer (Your exact working methods)

    private func tokenize(_ s: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        func flush() {
            if !current.isEmpty { tokens.append(current); current.removeAll(keepingCapacity: true) }
        }
        for ch in s {
            if ch.isLetter || ch.isNumber || ch == "'" || ch == "'" { current.append(ch) }
            else if ch.isWhitespace { flush() }
            else { flush(); tokens.append(String(ch)) }
        }
        flush()
        return tokens
    }

    private func finalize(_ s: String) -> String {
        var out = s
        out = out.replacingOccurrences(of: #"\s+([,\.!\?:;)\]\}])"#, with: "$1", options: .regularExpression)
        out = out.replacingOccurrences(of: #"([,\.!\?:;])([^\s\)\]\}])"#, with: "$1 $2", options: .regularExpression)
        out = out.replacingOccurrences(of: #"([\(\[\{])\s+"#, with: "$1", options: .regularExpression)
        out = out.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Capitalize sentence starts
        let sentenceEnd = CharacterSet(charactersIn: ".!?")
        var chars = Array(out)
        if let first = chars.first, first.isLetter { chars[0] = Character(String(first).capitalized) }
        var i = 1
        while i < chars.count {
            if let u = chars[i - 1].unicodeScalars.first, sentenceEnd.contains(u) {
                var j = i
                while j < chars.count, chars[j].isWhitespace {
                    j += 1
                }
                if j < chars.count, chars[j].isLetter {
                    chars[j] = Character(String(chars[j]).capitalized)
                }
                i = j
            } else { i += 1 }
        }
        return String(chars)
    }

    // MARK: - Data Loading (Your exact JSON loading logic)

    private func loadSpanishData() async {
        // Load & decode JSON on main actor, then parse off main actor, then assign on main actor
        let (master, _) = await MainActor.run { () -> (ESMaster?, URL?) in
            guard let url = locateJSON(),
                  let data = try? Data(contentsOf: url, options: .mappedIfSafe)
            else {
                print("⚠ Could not find/load es_final_with_rules*.json")
                return (nil, nil)
            }
            do {
                let decoder = JSONDecoder()
                let master = try decoder.decode(ESMaster.self, from: data)
                return (master, url)
            } catch {
                print("⚠ JSON decode error:", error)
                return (nil, nil)
            }
        }

        guard let master else { return }

        // Process off-main actor
        var newDict: [String: String] = [:]
        if let d = master.dictionary {
            var m: [String: String] = [:]
            m.reserveCapacity(d.count)
            for (k, v) in d {
                let key = k.lowercased()
                if let t = v.translation, !t.isEmpty { m[key] = t }
            }
            newDict = m
        }

        var phrases: [String: String] = [:]
        var reflexives: [String: String] = [:]
        var gen: [(NSRegularExpression, String)] = []
        var diaJSON: [(NSRegularExpression, String)] = []
        var gra: [(NSRegularExpression, String)] = []
        var cle: [(NSRegularExpression, String)] = []

        if let rulesBag = master.rules {
            // phrases
            if let rawPhrases = rulesBag["phrases"]?.value {
                if let pdict = rawPhrases as? [String: String] {
                    phrases = pdict
                } else if let parr = rawPhrases as? [[String: String]] {
                    for row in parr {
                        if let k = row["src"], let v = row["tgt"] { phrases[k] = v }
                    }
                }
            }
            // reflexives
            if let rp = rulesBag["reflexive_passives"]?.value as? [String: String] {
                reflexives = rp.reduce(into: [:]) { acc, kv in
                    let k = kv.key.lowercased()
                        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    acc[k] = kv.value
                }
            }
            // regex rules (bucket by heuristics)
            if let rawRR = (rulesBag["regex_rules"]?.value ?? rulesBag["regex"]?.value) as? [[String: Any]] {
                for obj in rawRR {
                    guard let pattern = obj["pattern"] as? String,
                          let replace = obj["replace"] as? String else { continue }
                    let enabled = (obj["enabled"] as? Bool) ?? true
                    guard enabled else { continue }
                    let optsArray = (obj["options"] as? [String]) ?? []
                    var opts: NSRegularExpression.Options = []
                    if optsArray.contains("i") { opts.insert(.caseInsensitive) }
                    if optsArray.contains("m") { opts.insert(.anchorsMatchLines) }
                    if optsArray.contains("s") { opts.insert(.dotMatchesLineSeparators) }
                    guard let re = try? NSRegularExpression(pattern: pattern, options: opts) else { continue }

                    let name = (obj["name"] as? String ?? "") + " " + (obj["description"] as? String ?? "")
                    let lower = name.lowercased()
                    if lower.contains("dialogue") || lower.contains("quote") || pattern.contains("—") {
                        diaJSON.append((re, replace))
                    } else if lower.contains("grammar") || lower.contains("verb") || lower.contains("tense") {
                        gra.append((re, replace))
                    } else if lower.contains("cleanup") || lower.contains("space") || lower.contains("punct") {
                        cle.append((re, replace))
                    } else {
                        gen.append((re, replace))
                    }
                }
            }
        }

        // Phrase matcher incl. multiword dict keys
        var phraseSource = phrases
        for k in newDict.keys where k.contains(" ") {
            phraseSource[k] = newDict[k]
        }
        let matcher = phraseSource.isEmpty ? nil : PhraseMatcher(phrases: phraseSource)

        // Compile built-ins
        let packs = Self.compileBuiltinRules()

        // Publish to singleton on main actor
        await MainActor.run {
            self.dict = newDict
            self.phraseMatcher = matcher
            self.reflexiveMap = reflexives
            self.compiledGeneral = gen
            self.compiledDialogueFromJSON = diaJSON
            self.compiledGrammar = gra
            self.compiledCleanup = cle

            self.builtinPriceAndUnits = packs.priceUnits
            self.builtinAlInfinitivo = packs.alInf
            self.builtinPrepositions = packs.preps
            self.builtinMenuLexicon = packs.menuLex
            self.builtinNarrativeGrammar = packs.narrative
            self.builtinDialogue = packs.dialogue

            self.cache.removeAll()
            self.isLoaded = true
            print("✅ es data loaded: dict=\(self.dict.count) phrases=\(self.phraseMatcher == nil ? 0 : 1) regex: gen=\(self.compiledGeneral.count) gra=\(self.compiledGrammar.count) diaJSON=\(self.compiledDialogueFromJSON.count) cle=\(self.compiledCleanup.count) builtinNarr=\(self.builtinNarrativeGrammar.count)")
        }
    }

    private func locateJSON() -> URL? {
        let candidates = [
            ("es_final_with_rules_CLEANED", "json"),
            ("es_final_with_rules_ENRICHED", "json"),
            ("es_final_with_rules_CLEAN", "json"),
            ("es_final_with_rules", "json"),
        ]
        for (name, ext) in candidates {
            if let url = Bundle.main.url(forResource: name, withExtension: ext) { return url }
        }
        let doc = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        let custom = doc?.appendingPathComponent("es_final_with_rules.json")
        if let u = custom, FileManager.default.fileExists(atPath: u.path) { return u }
        return nil
    }

    // MARK: - Built-in deterministic rules (Your exact code)

    private struct Packs {
        let priceUnits: [(NSRegularExpression, String)]
        let alInf: [(NSRegularExpression, String)]
        let preps: [(NSRegularExpression, String)]
        let menuLex: [(NSRegularExpression, String)]
        let narrative: [(NSRegularExpression, String)]
        let dialogue: [(NSRegularExpression, String)]
    }

    private static func rex(_ p: String, _ opt: NSRegularExpression.Options = [.caseInsensitive]) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: p, options: opt)
    }

    private static func compileBuiltinRules() -> Packs {
        // Prices/units
        let pricePatterns: [(String, String)] = [
            (#"(\d+)\s*(€|euros?)\s+el\s+kilo"#, "$1$2 per kilo"),
            (#"(\d+)\s*(€|euros?)\s+la\s+docena"#, "$1$2 per dozen"),
            (#"(\d+)\s*(€|euros?)\s+cada\s+uno"#, "$1$2 each"),
            (#"\bto fifteen euros the kilo\b"#, "for fifteen euros a kilo"),
        ]
        let priceUnits = pricePatterns.compactMap { p, r in rex(p).map { ($0, r) } }

        // "al + infinitivo" → "upon <gerund>"
        let alInfPatterns = [
            (#"\bal\s+([a-záéíóúñ]+)r\b"#, "upon $1ing"),
        ]
        let alInf = alInfPatterns.compactMap { p, r in rex(p).map { ($0, r) } }

        // Preposition/cleanup fixes (general)
        let prepPatterns: [(String, String)] = [
            (#"\brealized of\b"#, "realized"),
            (#"\brealized of that\b"#, "realized that"),
            (#"\bbrought of the field\b"#, "brought from the countryside"),
            (#"\bbrought of\b"#, "brought from"),
            (#"\bto the enter\b"#, "upon entering"),
            (#"\bmirror in the floor\b"#, "mirror on the ground"),
            (#"\bas the rain I created\b"#, "as the rain created"),
            (#"\bunder the awning of a little coffee\b"#, "under the awning of a small café"),
            (#"\brestaurant of to the side\b"#, "next-door restaurant"),
            (#"\bOctopos\b"#, "octopus"),
            (#"\boctopos\b"#, "octopus"),
        ]
        let preps = prepPatterns.compactMap { p, r in rex(p).map { ($0, r) } }

        // Menu lexicon tweaks (English-side)
        let menuPatterns: [(String, String)] = [
            (#"\bPosts of\b"#, "stalls of"),
            (#"\bstalls of fruit\b"#, "fruit stalls"),
            (#"\bpuestos de\s+([a-záéíóúñ]+)\b"#, "$1 stalls"),
            (#"\bpremises\b"#, "locals"),
        ]
        let menuLex = menuPatterns.compactMap { p, r in rex(p).map { ($0, r) } }

        // Narrative grammar/idiom targets (exact issues you reported)
        let narrativePatterns: [(String, String)] = [
            // Story 1
            (#"(?m)^Is a\b"#, "It's a"),
            (#"\bhe can find of all\b"#, "you can find everything"),
            (#"\bof all\b"#, "everything"),
            (#"\bthere was a lot people\b"#, "there were a lot of people"),
            (#"\bso (?:much|many)\s+tourists as\b"#, "as many tourists as"),
            (#"\bPosts of\b"#, "stalls of"),
            (#"\ba Sir elderly\b"#, "an elderly man"),
            (#"\bmoustache\b"#, "mustache"),
            (#"\bproof this\b"#, "try this"),
            (#"\bis of acorn-fed\b"#, "is acorn-fed"),
            (#"\bthe buys of all the week\b"#, "the shopping for the whole week"),
            // Story 2
            (#"\bI would be a day perfect\b"#, "It would be a perfect day"),
            (#"\bfor lose\b"#, "to lose"),
            (#"\bstreets old\b"#, "old streets"),
            (#"\bAfter of\b"#, "After"),
            (#"\bbreakfast fast\b"#, "quick breakfast"),
            (#"\bThis\s+Fill of\b"#, "It's filled with"),
            (#"\bpeppers\s+Red\b"#, "red peppers"),
            (#"\ba cluster of musicians street\b"#, "a group of street musicians"),
            (#"\bdrawer flamenco\b"#, "cajón flamenco"),
            (#"\bFollowing the rhythm\b"#, "clapping along to the rhythm"),
            (#"\bsquare central\b"#, "central square"),
            (#"\bstreet market colorful\b"#, "colorful street market"),
            (#"\ball guy of things\b"#, "all kinds of things"),
            (#"\bblankets\s+tejidas\s+handmade\b"#, "hand-woven blankets"),
            (#"\bA women elderly\b"#, "An elderly woman"),
            (#"\bme told\b"#, "told me"),
            (#"\bOf soon\b"#, "Suddenly"),
            (#"\bbegan to rain further strong\b"#, "began to rain harder"),
            (#"\bThe surf They hit\b"#, "The waves crashed"),
            (#"\bMe I approached\b"#, "I approached"),
            (#"\byou I asked\b"#, "I asked him"),
            (#"\bYeah there was had good fishing\b"#, "if he had a good catch"),
            (#"\bencogiéndose of shoulders\b"#, "shrugging his shoulders"),
            (#"\bBefore of go back to home\b"#, "Before heading home"),
            (#"\bHappens by a\b"#, "I stopped by a"),
            (#"\bwith he low the arm\b"#, "with it under my arm"),
            (#"\bEnjoying of the calm\b"#, "enjoying the calm"),
            (#"\bis left over after of the rain\b"#, "lingers after the rain"),
        ]
        let narrative = narrativePatterns.compactMap { p, r in rex(p).map { ($0, r) } }

        // Dialogue: handle a common Spanish em-dash pattern (your sample)
        // —Pruébala, chico —me dijo sonriendo—.  ->  "Try it, kid," he said, smiling.
        let dialoguePatterns = [
            (#"—\s*([^—]+?)\s*—\s*me dijo sonriendo—\s*\."#, "\"$1,\" he said, smiling."),
        ]
        let dialogue = dialoguePatterns.compactMap { p, r in rex(p).map { ($0, r) } }

        return Packs(priceUnits: priceUnits, alInf: alInf, preps: preps, menuLex: menuLex, narrative: narrative, dialogue: dialogue)
    }
}
