class_name DayCycle
extends RefCounted
## Time of day for presentation (D-035): the four phases shown in the HUD and the colour the
## outdoor world is tinted with. Pure functions of the game minute; never affects rules.
##   morning 05:00–09:00 · day 09:00–17:00 · dusk 17:00–19:30 · night 19:30–05:00

## minute of day -> tint (multiplied over the outdoor world). Interpolated between keys.
const KEYS := [
	[0, Color(0.36, 0.42, 0.68)],
	[300, Color(0.42, 0.46, 0.70)],
	[390, Color(1.0, 0.86, 0.78)],    # sunrise
	[480, Color(1.0, 0.95, 0.90)],
	[540, Color(1, 1, 1)],
	[1020, Color(1, 1, 1)],
	[1080, Color(1.0, 0.9, 0.76)],    # golden hour
	[1140, Color(0.9, 0.76, 0.74)],   # sunset
	[1200, Color(0.52, 0.48, 0.72)],  # blue hour
	[1290, Color(0.38, 0.42, 0.68)],
	[1440, Color(0.36, 0.42, 0.68)],
]


static func phase(minute_of_day: int) -> String:
	var m := posmod(minute_of_day, 1440)
	if m >= 300 and m < 540:
		return "morning"
	if m >= 540 and m < 1020:
		return "day"
	if m >= 1020 and m < 1170:
		return "dusk"
	return "night"


static func tint(minute_of_day: float) -> Color:
	var m := fposmod(minute_of_day, 1440.0)
	for i in KEYS.size() - 1:
		var a: Array = KEYS[i]
		var b: Array = KEYS[i + 1]
		if m >= float(a[0]) and m <= float(b[0]):
			var k := (m - float(a[0])) / maxf(float(b[0]) - float(a[0]), 1.0)
			return (a[1] as Color).lerp(b[1], k)
	return KEYS[0][1]


## 0 in daylight, 1 deep at night: how strongly lamps and windows glow.
static func darkness(minute_of_day: float) -> float:
	var c := tint(minute_of_day)
	return clampf((1.0 - (c.r + c.g + c.b) / 3.0) / 0.45, 0.0, 1.0)
