extends Node

# Main logic for the game.tscn scene.
# This script can interact with the GameController autoload globally (e.g., GameController.some_method())
# and manage the child nodes of game.tscn.
const scr_debug : bool = false
var debug 

func _ready():
	debug = scr_debug or GameController.sys_debug
	if debug: print("game.tscn main logic ready.")
