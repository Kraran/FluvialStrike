extends RefCounted

const DEFAULT := "stratowing"
const IDS := [DEFAULT, "rafale", "f22", "su57", "j20"]
const AIRCRAFT := {
	DEFAULT: {"name": "B1 StratoWing Assault Jet", "short": "B1 StratoWing", "country": "World",
		"flag": "res://flag_world.jpg", "nose": -2.12, "tip": Vector2(2.32, 0.98)},
	"rafale": {"name": "Dassault Rafale", "short": "Dassault Rafale", "country": "France",
		"flag": "res://flag_france.png", "nose": -2.50, "tip": Vector2(2.29, 1.10)},
	"f22": {"name": "Lockheed Martin F-22 Raptor", "short": "F-22 Raptor", "country": "USA",
		"flag": "res://flag_usa.png", "nose": -2.63, "tip": Vector2(2.32, 0.48)},
	"su57": {"name": "Soukhoï Su-57", "short": "Soukhoï Su-57", "country": "Russie",
		"flag": "res://flag_russia.png", "nose": -2.68, "tip": Vector2(2.40, 0.75)},
	"j20": {"name": "Chengdu J-20", "short": "Chengdu J-20", "country": "Chine",
		"flag": "res://flag_china.png", "nose": -2.89, "tip": Vector2(2.30, 0.97)},
}


static func validated(id: String) -> String:
	return id if AIRCRAFT.has(id) else DEFAULT
