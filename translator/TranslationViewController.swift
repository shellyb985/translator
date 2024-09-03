//
//  VoiceToVoiceVC.swift
//  translator
//
//  Created by Shelly Pritchard on 23/08/24.
//

import UIKit
import Speech
import AVFoundation
import Translation
import MLKit

struct Language {
    let translateLanguage: TranslateLanguage
    let code: String
    let name: String
}


class TranslationViewController: UIViewController {
    
    @IBOutlet weak var txtVwFrom: UITextView!
    @IBOutlet weak var txtVwTo: UITextView!
    @IBOutlet weak var btnSelectLanguageFrom: UIButton!
    @IBOutlet weak var btnSelectLanguageTo: UIButton!
    @IBOutlet weak var btnSpeak: UIButton!
    
    @IBOutlet weak var vw1: UIView!
    @IBOutlet weak var vw2: UIView!
    @IBOutlet weak var vwBtnContainer: UIView!
        
    private var speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private let audioEngine = AVAudioEngine()
    
    
    var speechPermissionStatus = SFSpeechRecognizerAuthorizationStatus.notDetermined
    var micPermissionStatus = false
        
    var translator: Translator? = nil
    
    var arrSupportedLanguage: [Language] = []
    var fromLanguage = TranslateLanguage.english
    var toLanguage = TranslateLanguage.tamil
    var synthesizer = AVSpeechSynthesizer()

    override func viewDidLoad() {
        super.viewDidLoad()
        
        addShadow(vwBtnContainer)
        addShadow(vw1)
        addShadow(vw2)
        
        self.title = "Language Translation"
        
        self.txtVwFrom.delegate = self
        self.txtVwTo.delegate = self
        
        setupLanguageList()
        
        let longPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPressRecognizer.minimumPressDuration = 0.5 // Duration in seconds for a long press
        btnSpeak.addGestureRecognizer(longPressRecognizer)
        
        
        let supportedLocale = SFSpeechRecognizer.supportedLocales()

    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.speechAndMicPermission()
    }
    
    //MARK: - Setup
    func setupLanguageList() {
        
        let actionClosure1 = { (action: UIAction) in
            if let language = self.filterCountryByName(action.title) {
                self.fromLanguage = language.translateLanguage
                self.txtVwFrom.text = ""
                self.txtVwTo.text = ""
            }
        }

        let actionClosure2 = { (action: UIAction) in
            if let language = self.filterCountryByName(action.title) {
                self.toLanguage = language.translateLanguage
                self.txtVwTo.text = ""
                self.translateText(text: self.txtVwFrom.text)
            }
        }
        
        self.arrSupportedLanguage = TranslateLanguage.getLanguageList()
        
        var menuFrom: [UIMenuElement] = []
        var menuTo: [UIMenuElement] = []
        for language in self.arrSupportedLanguage {
            
            let from = UIAction(title: language.name, handler: actionClosure1)
            let to = UIAction(title: language.name, handler: actionClosure2)
            
            from.state = (language.code == fromLanguage.rawValue) ? .on : .off
            to.state = (language.code == toLanguage.rawValue) ? .on : .off
            
            menuFrom.append(from)
            menuTo.append(to)
        }
        btnSelectLanguageFrom.menu = UIMenu(options: .displayInline, children: menuFrom)
        btnSelectLanguageFrom.showsMenuAsPrimaryAction = true
        btnSelectLanguageFrom.changesSelectionAsPrimaryAction = true
        
        btnSelectLanguageTo.menu = UIMenu(options: .displayInline, children: menuTo)
        btnSelectLanguageTo.showsMenuAsPrimaryAction = true
        btnSelectLanguageTo.changesSelectionAsPrimaryAction = true   
        
    }
    
    func speechAndMicPermission() {
        
        SFSpeechRecognizer.requestAuthorization { authStatus in
            self.speechPermissionStatus = authStatus
        }
        
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { status in
                self.micPermissionStatus = status
            }
        } else {
            // Fallback on earlier versions
        }
    }

    //MARK: - Button Action
    @IBAction func startButtonTapped(_ sender: UIButton) {
        if audioEngine.isRunning {
            stopRecording()
            sender.setTitle("Start Speech", for: .normal)
        } else {
            self.txtVwFrom.text = ""
            self.txtVwTo.text = ""
            startRecording()
            sender.setTitle("Stop Speech", for: .normal)
        }
    }
    
    @IBAction func actionClearFromText(_ sender: Any) {
        txtVwFrom.text = ""
        txtVwTo.text = ""
    }
    
    @IBAction func actionTranslate(_ sender: Any) {
        self.view.endEditing(true)
        if txtVwFrom.text.isEmpty {
            showError(msg: "Please enter the text then prese translate")
        } else {
            txtVwTo.text = ""
            self.translateText(text: self.txtVwFrom.text)
        }
    }
    static let s = Speaker()

    @IBAction func actionTextToSpeech(_ sender: Any) {
        print("actionTextToSpeech")
        self.view.endEditing(true)
        if !txtVwTo.text.isEmpty {
            TranslationViewController.s.speak(msg: txtVwTo.text, locale: toLanguage.rawValue)
        }
    }
    
    @objc func handleLongPress(_ gestureRecognizer: UILongPressGestureRecognizer) {
        self.view.endEditing(true)
        switch gestureRecognizer.state {
        case .began:
            print("Long press began")
            btnSpeak.backgroundColor = .green
            startRecording()
        case .ended, .cancelled:
            print("Long press ended or cancelled")
            btnSpeak.backgroundColor = .clear
            stopRecording()

        default:
            break
        }
    }
    
    //MARK: - Core logic
    func startRecording() {
        // Ensure there isn't a previous recognition task running
        if recognitionTask != nil {
            recognitionTask?.cancel()
            recognitionTask = nil
        }

        // Set up the audio session
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

        guard let recognitionRequest = recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: fromLanguage.rawValue))
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { result, error in
            if let result = result {
                let transcribedText = result.bestTranscription.formattedString
                print("Recognized text: \(transcribedText)")
                // Update your UI with the transcribed text
                self.txtVwFrom.text = transcribedText
            }
    
            if error != nil || result?.isFinal == true {
                self.audioEngine.stop()
                inputNode.removeTap(onBus: 0)
                self.recognitionRequest = nil
                self.recognitionTask = nil
                
                print("Recognized failed")

            }
            
            if result?.isFinal == true {
                if !self.txtVwFrom.text.isEmpty {
                    self.translateText(text: self.txtVwFrom.text)
                }

            }

        }

        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, when in
            recognitionRequest.append(buffer)
        }

        audioEngine.prepare()
        try? audioEngine.start()

        print("Say something, I'm listening!")
    }

    func stopRecording() {
        audioEngine.stop()
        recognitionRequest?.endAudio()
        audioEngine.inputNode.removeTap(onBus: 0)
    }
    
    func translateText(text: String) {
        let options = TranslatorOptions(sourceLanguage: fromLanguage, targetLanguage: toLanguage)
        self.translator = Translator.translator(options: options)
        
        let conditions = ModelDownloadConditions(
            allowsCellularAccess: false,
            allowsBackgroundDownloading: true
        )
        let translatorForDownloading = self.translator!
        translatorForDownloading.downloadModelIfNeeded(with: conditions) { error in
            guard error == nil else { return }

            // Model downloaded successfully. Okay to start translating.
            if translatorForDownloading == self.translator {
                translatorForDownloading.translate(text) { result, error in
                    guard error == nil else {
                      print("Failed with error \(error!)")
                      return
                    }
                    DispatchQueue.main.async {
                      self.txtVwTo.text = result
                    }

                }
            }
        }

    }
    
    //MARK: - Utility
    func showError(msg: String) {
        let alert = UIAlertController(title: "My Alert", message: msg, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Default action"), style: .default, handler: { _ in
        }))
        self.present(alert, animated: true, completion: nil)
    }
    
    func addShadow(_ yourView: UIView) {
        yourView.layer.cornerRadius = 16
        yourView.layer.shadowColor = UIColor.init(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.25).cgColor//UIColor.black.cgColor
        yourView.layer.shadowOpacity = 1
        yourView.layer.shadowOffset = .zero
        yourView.layer.shadowRadius = 3
        
    }
    
    func filterCountryByName(_ name: String) -> Language? {
        return self.arrSupportedLanguage.filter{ $0.name == name }.first ?? nil
    }
}


extension TranslationViewController: UITextViewDelegate {
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        if text == "\n" {
            textView.resignFirstResponder()
            return false
        }
        return true
    }
}


extension TranslateLanguage {
    
    func localizedName() -> String {
        let locale = Locale.current
        return locale.localizedString(forLanguageCode: self.rawValue)!
    }
    
    static func getLanguageList() -> [Language] {
        let allLanguage = TranslateLanguage.allLanguages()
        var arrLanguage: [Language] = []
        for code in allLanguage {
            arrLanguage.append(Language(translateLanguage: code, code: code.rawValue, name: code.localizedName()))
        }
        return arrLanguage.sorted { $0.name < $1.name}
    }
    
}


class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    let synthesizer = AVSpeechSynthesizer()
    let audioSession = AVAudioSession.sharedInstance()

    override init() {
        super.init()
        
       synthesizer.delegate = self
    }

    func speak(msg: String, locale: String) {
        
        do {
            try audioSession.setCategory(.playback, mode: .voicePrompt, options: .duckOthers)
            try audioSession.setActive(false)
        } catch let error {
            print("❓\(error.localizedDescription)")
        }
        
        let utterance = AVSpeechUtterance(string: msg)
        utterance.rate = 0.57
        utterance.pitchMultiplier = 0.8
        utterance.postUtteranceDelay = 0.2
        utterance.volume = 0.8

        let voice = AVSpeechSynthesisVoice(language: locale) //"en-US"
        utterance.voice = voice
        synthesizer.speak(utterance)
    }
    
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        print("Cancelled")
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        print("demo")
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        print("finish")
    }
}
