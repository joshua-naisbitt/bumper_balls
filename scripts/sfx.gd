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
	# Closing the window comes through quit_game() too, so sounds get the same
	# chance to wind down as every other way out.
	get_tree().auto_accept_quit = false
	for key in CLIPS:
		var stream := load(CLIPS[key]) as AudioStream
		if stream:
			_streams[key] = stream
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)

## Every way out of the game goes through here. Quitting while a sound is still
## playing -- closing the window mid-beep, Android back in the lobby -- left its
## playback with the AudioServer, which Godot reports at exit as leaked objects
## and a resource still in use. stop() only marks a playback for release: the
## audio thread has to fade it out and hand it back before the main thread can
## free it. That is measured in mix buffers, not frames -- a headless run can
## race through several frames before the audio thread wakes once -- so wait on
## the clock. A tenth of a second is a handful of mix buffers, and nobody
## notices it on the way out.
const QUIT_GRACE := 0.1

func quit_game(exit_code := 0) -> void:
	_silence()
	await get_tree().create_timer(QUIT_GRACE, true, false, true).timeout
	get_tree().quit(exit_code)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit_game()

## Fallback for anything that quits the tree directly.
func _exit_tree() -> void:
	_silence()

func _silence() -> void:
	for p in _pool:
		p.stop()
		p.stream = null

func play(key: String, volume_db := 0.0, pitch := 1.0) -> void:
	if not _streams.has(key):
		return
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = _streams[key]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()
