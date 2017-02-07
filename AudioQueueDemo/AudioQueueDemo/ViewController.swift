//
//  ViewController.swift
//  AudioQueueDemo
//
//  Created by zhongzhendong on 7/9/16.
//  Copyright © 2016 zerdzhong. All rights reserved.
//

import UIKit

class ViewController: UIViewController {
    
    var player: AudioPlayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        
        player = AudioPlayer(url: URL(string: "http://hao.1015600.com/upload/ring/000/959/3d7847b54addea141736fefa91bb66b6.mp3")!)
        player?.start()
    }

    @IBAction func buttonClicked(_ sender: AnyObject) {
        player?.play()
    }

}

