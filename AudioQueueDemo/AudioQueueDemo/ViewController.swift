
import UIKit

class ViewController: UIViewController {
    var playing = false
    var player: AudioPlayer?

    @IBOutlet weak var playButton: UIButton!
    override func viewDidLoad() {
        super.viewDidLoad()
        
        player = AudioPlayer(url: URL(string: "https://rawgit.com/futomtom/audioqueue-swift3/master/sample.mp3")!)
    
    }

    @IBAction func playDidTapped(_ sender: UIButton) {
        let _ = playing ?  player?.pause() : player?.play()
        playing = !playing
        let title = playing ? "pause": "play"
        
        playButton.setTitle(title, for: .normal)
    }
}

