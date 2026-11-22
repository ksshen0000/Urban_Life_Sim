class_name UiSound
extends Node
## Small interface sounds (T019), synthesized at startup: the project ships no audio files, so
## there is nothing to license. Plays on the "SFX" bus, so the SFX / master volume settings apply.
## `UiSound.attach_buttons(root)` makes every Button below `root` click when pressed.

const MIX_RATE := 22050

static var _cache: Dictionary = {}

var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameSettings.ensure_buses()
	for i in 4:
		var p := AudioStreamPlayer.new()
		p.bus = GameSettings.SFX_BUS
		add_child(p)
		_players.append(p)


static func clear_cache() -> void:
	_cache.clear()


## Quitting while a click is still playing must not leave the playback behind.
func _exit_tree() -> void:
	for p in _players:
		p.stop()
		p.stream = null


func play(sound: String) -> void:
	# Buttons that change scene (New game, Title screen, Load) run their action before the click
	# handler; by then the old scene, and this node with it, has already left the tree.
	if _players.is_empty() or not is_inside_tree():
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = stream(sound)
	p.play()


func click() -> void:
	play("click")


## Connects `pressed` of every Button under `root` (now) to the click sound.
func attach_buttons(root: Node) -> void:
	for c in root.find_children("*", "Button", true, false):
		var b := c as Button
		if not b.pressed.is_connected(click):
			b.pressed.connect(click)


## "click" (short tick), "coin" (two rising notes), "chime" (soft bell for story / day start).
static func stream(sound: String) -> AudioStreamWAV:
	if not _cache.has(sound):
		match sound:
			"coin":
				_cache[sound] = _tones([[988.0, 0.06], [1319.0, 0.12]], 0.35)
			"chime":
				_cache[sound] = _tones([[660.0, 0.35]], 0.25)
			_:
				_cache[sound] = _tones([[1500.0, 0.025]], 0.25)
	return _cache[sound]


## Sine notes in sequence, each with a fast attack and exponential decay. 16-bit mono PCM.
static func _tones(notes: Array, gain: float) -> AudioStreamWAV:
	var data := PackedByteArray()
	for n: Array in notes:
		var freq: float = n[0]
		var count := int(MIX_RATE * float(n[1]))
		for i in count:
			var t := float(i) / MIX_RATE
			var env := minf(1.0, t / 0.004) * exp(-t * 6.0 / float(n[1]))
			var sample := int(clampf(sin(TAU * freq * t) * env * gain, -1.0, 1.0) * 32767.0)
			data.append(sample & 0xFF)
			data.append((sample >> 8) & 0xFF)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	return wav
