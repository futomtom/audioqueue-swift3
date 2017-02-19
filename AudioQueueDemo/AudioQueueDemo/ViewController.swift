
import UIKit

class ViewController: UIViewController {
    var playing = false
    var player: AudioPlayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        
        player = AudioPlayer(url: URL(string: "https://drive.google.com/uc?export=download&id=0B8CZdQgUg03peWp5c0pQelNmNFU")!)
    
    }

    @IBAction func playDidTapped(_ sender: UIButton) {
        let _ = playing ?  player?.pause() : player?.play()
        playing = !playing
    }
}

