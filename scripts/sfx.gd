extends Node
## Tiny pooled sound player. Sounds are generated at build time into res://audio.

const CLIPS := {
	"bump": "res://audio/bump.wav",
	"dash": "res://audio/dash.wav",
	"fall": "res://audio/fall.wav",
	"beep": "res://audio/beep.wav",
	"go": "res://audio/go.wav",
	"round_win": "res://audio/round_win.wav",
	"match_win": "res://audio/match_win.wav",
	"warn": "res://audio/warn.wav",
}

const POOL_SIZE := 12

var _streams := {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0

func _ready() -> void:
	for key in CLIPS:
		var stream := load(CLIPS[key]) as AudioStream
		if stream:
			_streams[key] = stream
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)

func play(key: String, volume_db := 0.0, pitch := 1.0) -> void:
	if not _streams.has(key):
		return
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = _streams[key]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()
