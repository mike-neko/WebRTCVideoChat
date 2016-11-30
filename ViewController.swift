//
//  ViewController.swift
//  WebRTCVideoChat
//
//  Created by M.Ike on 2016/11/30.
//  Copyright © 2016年 M.Ike. All rights reserved.
//

import UIKit
import WebRTC

class ViewController: UIViewController, RTCPeerConnectionDelegate {

    @IBOutlet private weak var localView: UIView!
    @IBOutlet private weak var remoteView: UIView!
    @IBOutlet private weak var connectButton: UIButton!

    private weak var localVideo: RTCEAGLVideoView!
    private weak var remoteVideo: RTCEAGLVideoView!
    
    private static let constraints = RTCMediaConstraints(
        mandatoryConstraints: ["OfferToReceiveVideo": kRTCMediaConstraintsValueTrue,
                               "OfferToReceiveAudio": kRTCMediaConstraintsValueTrue],
        optionalConstraints: nil)
    
    private let factory = RTCPeerConnectionFactory()
    
    private var peer: RTCPeerConnection!
    
    private var localStream: RTCMediaStream!
    private var remoteStream: RTCMediaStream!

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        // ローカルストリーム（Video）の生成
        localStream = factory.mediaStream(withStreamId: "MIKE-VIDEOCHAT")
        
        let video = factory.avFoundationVideoSource(with: nil)
        let track = factory.videoTrack(with: video, trackId: "MIKE-VIDEOCHAT-V0")
        localStream.addVideoTrack(track)

        // ローカルストリーム（Audio）の生成
        localStream.addAudioTrack(factory.audioTrack(withTrackId: "MIKE-VIDEOCHAT-A0"))
        
        // VideoViewの作成
        let local = RTCEAGLVideoView(frame: localView.bounds)
        localView.addSubview(local)
        localVideo = local
        track.add(local)
        let remote = RTCEAGLVideoView(frame: remoteView.bounds)
        remoteView.addSubview(remote)
        remoteVideo = remote
        
        // 接続の生成
        peer = factory.peerConnection(with: RTCConfiguration(),
                                      constraints: ViewController.constraints,
                                      delegate: self)
        peer.add(localStream)
        
        // シグナリング用
        P2PConnectivity.manager.start(
            serviceType: "MIKE-VIDEOCHAT",
            displayName: UIDevice.current.name,
            stateChangeHandler: { [weak self] state in
                // 接続状況の変化
                DispatchQueue.main.async {
                    if case .connected = state {
                        self?.connectButton.isEnabled = true
                    } else {
                        self?.connectButton.isEnabled = false
                    }
                }
            }, recieveHandler: { [weak self] data in
                // データを受信
                let sdp = data.substring(from: data.index(after: data.startIndex))
                switch data.substring(to: data.index(after: data.startIndex)) {
                case "O": self?.recieveOffer(sdp: sdp)
                case "A": self?.recieveAnswer(sdp: sdp)
                case "I": self?.recieveICE(sdp: sdp)
                default: break
                }
            }
        )
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        localVideo.frame = localView.bounds
        remoteVideo.frame = remoteView.bounds
    }
    
    
    @IBAction func tapConnectButton(sender: UIButton) {
        makeOffer()
    }
    
    // MARK: -
    private func makeOffer() {
        print("Make Offer")
        
        peer.offer(for: ViewController.constraints) { [weak self] (description, error) in
            guard let localDescription = description, error == nil else {
                print("makeOffer Error: \(error?.localizedDescription ?? "")")
                return
            }
            
            self?.peer.setLocalDescription(localDescription) { [weak self] error in
                guard error == nil,
                    let state = self?.peer.signalingState, case .haveLocalOffer = state else {
                        print("setLocalDescription Error: \(error?.localizedDescription ?? "")")
                        return
                }
                
                print("Offer Send")
                P2PConnectivity.manager.send(message: "O" + localDescription.sdp)
            }
        }
        
    }
    
    private func recieveOffer(sdp: String) {
        print("Recieve Offer")
        
        let remoteDescription = RTCSessionDescription(type: .offer, sdp: sdp)
        peer.setRemoteDescription(remoteDescription) { [weak self] error in
            guard error == nil,
                let state = self?.peer.signalingState, case .haveRemoteOffer = state else {
                    print("setRemoteDescription Error: \(error?.localizedDescription ?? "")")
                    return
            }
            
            print("Make Answer")
            self?.peer.answer(for: ViewController.constraints) { [weak self] (description, error) in
                guard let localDescription = description, error == nil else {
                    print("makeAnswer Error: \(error?.localizedDescription ?? "")")
                    return
                }
                
                self?.peer.setLocalDescription(localDescription) { error in
                    guard error == nil else {
                        print("setLocalDescription Error: \(error?.localizedDescription ?? "")")
                        return
                    }
                    
                    print("Answer Send")
                    P2PConnectivity.manager.send(message: "A" + localDescription.sdp)
                }
            }
        }
    }
    
    private func recieveAnswer(sdp: String) {
        print("Recieve Answer")
        let remoteDescription = RTCSessionDescription(type: .answer, sdp: sdp)
        peer.setRemoteDescription(remoteDescription) { error in
            guard error == nil else {
                print("setRemoteDescription Error: \(error?.localizedDescription ?? "")")
                return
            }
        }
    }
    
    private func recieveICE(sdp: String) {
        let can = RTCIceCandidate(sdp: sdp, sdpMLineIndex: 0, sdpMid: nil)
        peer.add(can)
    }
    
    // MARK: - RTCPeerConnectionDelegate
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        P2PConnectivity.manager.send(message: "I" + candidate.sdp)
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        remoteStream = stream
        stream.videoTracks.last?.add(remoteVideo)

        P2PConnectivity.manager.stop()
        DispatchQueue.main.async { [weak self] in
            self?.connectButton.isEnabled = false
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
    }
    
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
    }

}

