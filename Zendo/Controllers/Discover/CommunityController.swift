//
//  GameController.swift
//  Zendo
//
//  Created by Douglas Purdy on 5/8/20.
//  Copyright © 2020 zenbf. All rights reserved.
//

import UIKit
import Hero
import SpriteKit
import HealthKit
import AVKit
import Mixpanel
import Cache
import AuthenticationServices
import Parse
import SwiftGRPC

class CommunityController: UIViewController, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding
{
    var currentPlayers = [SKSpriteNode]()
    var notifyTimer : Timer?
    
    //#todo(debt): If we moved to SwiftUI can we get rid of some of this?
    var idHero = "" //not too sure what this does but it is store for the one of the dependencies that we have
    

    private let diskConfig = DiskConfig(name: "DiskCache")
    private let memoryConfig = MemoryConfig(expiry: .never, countLimit: 10, totalCostLimit: 10)
    private lazy var storage: Cache.Storage<String, Data>? = {
        return try? Cache.Storage(diskConfig: diskConfig, memoryConfig: memoryConfig, transformer: TransformerFactory.forData())
    }()
    
    var story: Story!
        
    
    @IBOutlet weak var sceneView: SKView!
    {
        didSet {
            
            sceneView.hero.id = idHero
            sceneView.frame = UIScreen.main.bounds
            sceneView.contentMode = .scaleAspectFill
            sceneView.backgroundColor = .clear
            sceneView.allowsTransparency = true
            
            let panGR = UIPanGestureRecognizer(target: self, action: #selector(pan))
            
            sceneView.addGestureRecognizer(panGR)
            
        }
    }
    
    
    
    @IBOutlet weak var connectButton: UIButton!
    {
        didSet
        {
            self.connectButton.addTarget(self, action: #selector(signIn), for: .primaryActionTriggered)
            
            self.connectButton.layer.borderColor = UIColor.white.cgColor
            self.connectButton.layer.borderWidth = 1.0
            self.connectButton.layer.cornerRadius = 10.0
            self.connectButton.backgroundColor = UIColor(red:0.06, green:0.15, blue:0.13, alpha:0.3)
            self.connectButton.layer.shadowOffset = CGSize(width: 0, height: 2)
            self.connectButton.layer.shadowColor = UIColor(red:0, green:0, blue:0, alpha:0.5).cgColor
            self.connectButton.layer.shadowOpacity = 1
            self.connectButton.layer.shadowRadius = 20
            
        }
    }
    
    override func viewDidLayoutSubviews() {
        
        super.viewDidLayoutSubviews()
        
        self.sceneView.frame = self.view.frame
        
        self.sceneView.alpha = CGFloat(Float(self.story.backgroundOpacity ?? "1.0") ?? 1.0)
        
        self.sceneView.layer.zPosition = 0

        
    }
    
    static func loadFromStoryboard() -> CommunityController
    {
        let controller = UIStoryboard(name: "CommunityController", bundle: nil).instantiateViewController(withIdentifier: "CommunityController") as! CommunityController
        
        return controller
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        
        super.viewWillDisappear(animated)
        
        Mixpanel.mainInstance().track(event: "phone_lab", properties: ["name": story.title])
        
        NotificationCenter.default.removeObserver(self)
        
        UIApplication.shared.isIdleTimerDisabled = false
        
    }
    
    override func viewDidLoad() {
        
        super.viewDidLoad()
        
        Mixpanel.mainInstance().time(event: "phone_lab")

        setBackground()
        
        UIApplication.shared.isIdleTimerDisabled = true
        
        self.sceneView.presentScene(self.getIntroScene())
        
    }
    
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        return self.view.window!
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization){
        
        switch authorization.credential
        {
            case let appleIDCredential as ASAuthorizationAppleIDCredential:
            
                let userIdentifier = appleIDCredential.user
            
            if let user = PFUser.current() {
                
            } else {
            
                PFUser.logInWithUsername(inBackground: userIdentifier, password: String(userIdentifier.prefix(9)))
                    { user, error in
                    
                        if let user = user
                        {
                            print("login successful")
                        }
                    
                        if let error = error {
                            //create a new user for this AppleID
                            print(error)
                
                        }
                    }
                
            }
            
            
                break
        
        default:
            
            print("if you are seeing this it is too late")
            
        }
        
        self.start()
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        
    }

    

    
    func setupPhoneAV() {
        
        UIApplication.shared.isIdleTimerDisabled = true
        
        modalPresentationCapturesStatusBarAppearance = true
        
        do {
            
            try? AVAudioSession.sharedInstance().setCategory(AVAudioSessionCategoryPlayAndRecord, with: .mixWithOthers)
            
            try? AVAudioSession.sharedInstance().setActive(true)
        }
    }
    
    
    @objc func pan(_ gestureRecognizer : UIPanGestureRecognizer)
    {
        let translation = gestureRecognizer.translation(in: nil)
        let progress = translation.y / view.bounds.height
        switch gestureRecognizer.state {
        case .began:
            hero.dismissViewController()
        case .changed:
            Hero.shared.update(progress)
            let currentPos = CGPoint(x: translation.x + view.center.x, y: translation.y + view.center.y)
            Hero.shared.apply(modifiers: [.position(currentPos)], to: view)
        default:
            Hero.shared.finish()
        }
        
    }
    
    @objc func signIn() {
        
        let appleIDProvider = ASAuthorizationAppleIDProvider()
        let request = appleIDProvider.createRequest()
        request.requestedScopes = [.fullName, .email]
        
        let authorizationController = ASAuthorizationController(authorizationRequests: [request])
        authorizationController.delegate = self
        authorizationController.presentationContextProvider = self
        authorizationController.performRequests()
    }
    
    func start() {
        
        let main = self.getMainScene()
                
        self.sceneView.presentScene(nil) //don't ask, just invoke
                
        self.sceneView.presentScene(main)
                
        self.connectButton.isHidden = true
        
        self.loadPlayers()
     
    }
    
    @objc func updatePlayers()
    {
        DispatchQueue.main.async {
            
        let scene = self.sceneView.scene!
        
        let oneMinuteAgo = Date().addingTimeInterval(-60)
        
        let playerQuery = PFQuery(className: "Meditation")
        playerQuery.whereKeyExists("game_progress")
        playerQuery.whereKey("updatedAt", greaterThanOrEqualTo: oneMinuteAgo)
        
        playerQuery.findObjectsInBackground {
            
            objects, error in
            
            if let error = error {
                print (error)
            }
            
            if let objects = objects {
                
                if (objects.count > 0) {
                
                    DispatchQueue.main.async {
                    
                        for object in objects {
                            
                            let id = object["player"] as! String
                            let game_progress = object["game_progress"] as! String
                            let typed_progress = game_progress.components(separatedBy: "/")
                            
                            let isMeditating = typed_progress.first!
                            let level = typed_progress.last!
                            let typed_level = Int(level)!
                            let typed_meditating = isMeditating.boolValue
                            
                            if let player = scene.childNode(withName: id)
                            {
                                player.removeAllChildren()
                                
                                if (typed_level >= 0) {
                                    let emitter = SKEmitterNode(fileNamed: "Level0Emitter")
                                    emitter?.particleZPosition = 4.0
                                    emitter?.targetNode = player
                                    player.addChild(emitter!)
                                }
                                
                                if(typed_level >= 1) {
                                    let level1Emitter = SKEmitterNode(fileNamed: "Level1Emitter")
                                    level1Emitter?.particleZPosition = 5.0
                                    level1Emitter?.targetNode = player
                                    player.addChild(level1Emitter!)
                                }
                                
                                if(typed_level >= 2) {
                                    let level2Emitter = SKEmitterNode(fileNamed: "Level2Emitter")
                                    level2Emitter?.particleZPosition = 5.0
                                    level2Emitter?.targetNode = player
                                    
                                    player.addChild(level2Emitter!)
                                }
                            }
                            else {
                            
                                let player = SKSpriteNode(imageNamed: "player1")
                                player.zPosition = 3.0
                                player.position = CGPoint(x: self.randomRange(scene.frame.minX, scene.frame.maxX) , y: self.randomRange(scene.frame.minY, scene.frame.maxY))
                                player.name = id
                                
                                scene.addChild(player)
                                
                                
                                if (typed_level >= 0) {
                                    let emitter = SKEmitterNode(fileNamed: "Level0Emitter")
                                    emitter?.particleZPosition = 4.0
                                    emitter?.targetNode = player
                                    player.addChild(emitter!)
                                }
                                
                                if(typed_level >= 1) {
                                    let level1Emitter = SKEmitterNode(fileNamed: "Level1Emitter")
                                    level1Emitter?.particleZPosition = 5.0
                                    level1Emitter?.targetNode = player
                                    player.addChild(level1Emitter!)
                                }
                                
                                if(typed_level >= 2) {
                                    let level2Emitter = SKEmitterNode(fileNamed: "Level2Emitter")
                                    level2Emitter?.particleZPosition = 5.0
                                    level2Emitter?.targetNode = player
                                    
                                    player.addChild(level2Emitter!)
                                }
                                
                                
                            }
                            
                        }
                    }
                }
            }
        }
        }
    }
    
    func loadPlayers()
    {
        let scene = self.sceneView.scene!
        
        let oneMinuteAgo = Date().addingTimeInterval(-60)
        
        let playerQuery = PFQuery(className: "Meditation")
        playerQuery.whereKeyExists("game_progress")
        playerQuery.whereKey("updatedAt", greaterThanOrEqualTo: oneMinuteAgo)
        
        playerQuery.findObjectsInBackground {
            
            objects, error in
            
            if let error = error {
                print (error)
            }
            
            if let objects = objects {
                
                if (objects.count > 0) {
                
                    DispatchQueue.main.async {
                    
                        for object in objects {
                            
                            let id = object["player"] as? String
                            let game_progress = object["game_progress"] as? String
                            let typed_progress = game_progress?.components(separatedBy: "/")
                            
                            let isMeditating = typed_progress!.first!
                            let level = typed_progress!.last!
                            let typed_level = Int(level)!
                            let typed_meditating = isMeditating.boolValue
                            
                            let player = SKSpriteNode(imageNamed: "player1")
                            player.zPosition = 3.0
                            player.position = CGPoint(x: self.randomRange(scene.frame.minX, scene.frame.maxX) , y: self.randomRange(scene.frame.minY, scene.frame.maxY))
                            player.name = id
                            scene.addChild(player)
                            
                            self.currentPlayers.append(player)
                            
                            if (typed_level >= 0) {
                                let emitter = SKEmitterNode(fileNamed: "Level0Emitter")
                                emitter?.particleZPosition = 4.0
                                emitter?.targetNode = player
                                player.addChild(emitter!)
                            }
                            
                            if(typed_level >= 1) {
                                let level1Emitter = SKEmitterNode(fileNamed: "Level1Emitter")
                                level1Emitter?.particleZPosition = 5.0
                                level1Emitter?.targetNode = player
                                player.addChild(level1Emitter!)
                            }
                            
                            if(typed_level >= 2) {
                                let level2Emitter = SKEmitterNode(fileNamed: "Level2Emitter")
                                level2Emitter?.particleZPosition = 5.0
                                level2Emitter?.targetNode = player
                                player.addChild(level2Emitter!)
                            }
                            
                        }
                    }
                } else
                {
                    DispatchQueue.main.async {
                        
                        let noPlayers = SKLabelNode(text: "No one is meditating.")
                        noPlayers.horizontalAlignmentMode = .center
                        noPlayers.numberOfLines = 3
                        let fontLabel = UIFont.zendo(font: .antennaRegular, size: 14)
                        noPlayers.color = .white
                        noPlayers.fontName = fontLabel.fontName
                        noPlayers.fontSize = 18
                        noPlayers.zPosition = 3.0
                        noPlayers.position = CGPoint(x: scene.frame.midX , y: scene.frame.midY)
                        
                        let startSession = SKLabelNode(text: "Maybe start a session on your watch?")
                        startSession.horizontalAlignmentMode = .center
                        startSession.numberOfLines = 3
                        //let fontLabel = UIFont.zendo(font: .antennaRegular, size: 14)
                        startSession.color = .white
                        startSession.fontName = fontLabel.fontName
                        startSession.fontSize = 18
                        startSession.zPosition = 3.0
                        startSession.position = CGPoint(x: scene.frame.midX , y: scene.frame.midY - 50)
                        
                        scene.addChild(noPlayers)
                        scene.addChild(startSession)
                        
                    }
                }
            }
        }
        
        self.notifyTimer = Timer.scheduledTimer(timeInterval: 10, target:self, selector: #selector(updatePlayers), userInfo: nil, repeats: true)
    }
    
    func randomRange(_ min: CGFloat, _ max: CGFloat) -> CGFloat {
        assert(min < max)
        return CGFloat(arc4random()) / 0xFFFFFFFF * (max - min) + min
    }
    
    func getContent(contentURL: URL, completion: @escaping (AVPlayerItem) -> Void)
    {
        var playerItem: AVPlayerItem?
        
        storage?.async.entry(forKey: contentURL.absoluteString, completion:
                                {
                                    result in
                                    
                                    switch result
                                    {
                                    case .value(let entry):
                                        
                                        if var path = entry.filePath
                                        {
                                            if path.first == "/"
                                            {
                                                path.removeFirst()
                                            }
                                            
                                            let url = URL(fileURLWithPath: path)
                                            
                                            playerItem = AVPlayerItem(url: url)
                                        }
                                        
                                    default:
                                        
                                        playerItem = AVPlayerItem(url: contentURL)
                                        
                                    }
                                    
                                    completion(playerItem!)
                                    
                                })
        
    }
    
    func startBackgroundContent(story : Story, completion: @escaping (AVPlayerItem) -> Void)
    {
        var playerItem: AVPlayerItem?
        
        let streamString = story.content[0].stream
        let downloadString = story.content[0].download
        
        var downloadUrl : URL?
        var streamUrl : URL?
        
        if let urlString = downloadString, let url = URL(string: urlString)
        {
            downloadUrl = url
        }
        
        if let urlString = streamString, let url = URL(string: urlString)
        {
            streamUrl = url
        }
        
        storage?.async.entry(forKey: downloadUrl?.absoluteString ?? "", completion:
                                {
                                    result in
                                    
                                    switch result
                                    {
                                    case .value(let entry):
                                        
                                        if var path = entry.filePath
                                        {
                                            if path.first == "/"
                                            {
                                                path.removeFirst()
                                            }
                                            
                                            let url = URL(fileURLWithPath: path)
                                            
                                            playerItem = AVPlayerItem(url: url)
                                        } else
                                        {
                                            if let url = streamUrl
                                            {
                                                playerItem = AVPlayerItem(url: url)
                                            }
                                            else
                                            {
                                                playerItem = AVPlayerItem(url: downloadUrl!)
                                            }
                                        }
                                    //todo: add invalid to handle a crash
                                    case .error(let error):
                                        
                                        if let url = streamUrl
                                        {
                                            playerItem = AVPlayerItem(url: url)
                                        }
                                        else
                                        {
                                            playerItem = AVPlayerItem(url: downloadUrl!)
                                        }
                                    }
                                    
                                    completion(playerItem!)
                                    
                                })
    }
    
    
    func getIntroScene() -> SKScene
    {
        let scene = SKScene(size: (sceneView.frame.size))
        scene.scaleMode = .resizeFill
        
        self.getContent(contentURL: URL(string: story.introURL!)!)
        {
            item in
            
            DispatchQueue.main.async
            {
                let videoPlayer = AVPlayer(playerItem: item)
                
                let video = SKVideoNode(avPlayer: videoPlayer)
                
                video.zPosition = 1.0
                video.size = scene.frame.size
                video.position = scene.position
                video.anchorPoint = scene.anchorPoint
                video.play()
                scene.addChild(video)
                
                self.removeBackground()
                
                NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                                       object: videoPlayer.currentItem, queue: nil)
                {
                    notification in
                    
                    DispatchQueue.main.async
                    {
                        videoPlayer.seek(to: kCMTimeZero)
                        videoPlayer.play()
                    }
                    
                }
            }
        }
        
        return scene
    }
    
    func getMainScene() -> SKScene
    {
        let scene = SKScene(size: (sceneView.frame.size))
        scene.scaleMode = .resizeFill
        
        sceneView.allowsTransparency = true
        
        self.startBackgroundContent(story: story, completion:
                                        {
                                            item in
                                            
                                            DispatchQueue.main.async
                                            {
                                                let videoPlayer = AVPlayer(playerItem: item)
                                                
                                                let video = SKVideoNode(avPlayer: videoPlayer)
                                                
                                                video.zPosition = 1.0
                                                video.size = scene.frame.size
                                                video.position = scene.position
                                                video.anchorPoint = scene.anchorPoint
                                                video.play()
                                                scene.addChild(video)
                                                
                                                self.removeBackground()
                                                
                                                NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                                                                       object: videoPlayer.currentItem, queue: nil)
                                                {
                                                    notification in
                                                    
                                                    DispatchQueue.main.async
                                                    {
                                                        videoPlayer.seek(to: kCMTimeZero)
                                                        videoPlayer.play()
                                                    }
                                                    
                                                }
                                            }
                                            
                                        })
        
        return scene
        
    }
    

    
    func setBackground() {
        if let story = story, let thumbnailUrl = story.thumbnailUrl, let url = URL(string: thumbnailUrl) {
            UIImage.setImage(from: url) { image in
                DispatchQueue.main.async {
                    self.sceneView.addBackground(image: image, isLayer: false, isReplase: false)
                }
            }
        }
    }
    
    func removeBackground()
    {
        if let viewWithTag = self.view.viewWithTag(100) {
            viewWithTag.removeFromSuperview()
        }
    }
    
}

class PlayerNode : SKSpriteNode {
    
    override var isUserInteractionEnabled: Bool {
        set {
            // ignore
        }
        get {
            return true
        }
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = touches.first {
//            let location = touch.location(in: self)
//
//            let touchedNodes = self.nodes(at: location)
//            for node in touchedNodes.reversed() {
//                if node.name == "draggable" {
//                    self.currentNode = node
//                }
//            }
        }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = touches.first {
            let touchLocation = touch.location(in: self)
            self.position = touchLocation
        }
    }
    
    
}
