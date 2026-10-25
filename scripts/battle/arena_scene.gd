class_name ArenaScene
extends Node2D
## An arena laid out in the editor: its Sockets children (Marker2D) mark where the heroes, decks, mana, end-turn
## button, rows and props go, in 1920x1080 layout units matching the painted board (docs/ARENA_BRIEF.md).
## The battle maps them to the screen with the same scale as the board.


func has_socket(n: String) -> bool:
	return has_node("Sockets/" + n)


func socket(n: String) -> Vector2:
	return (get_node("Sockets/" + n) as Node2D).position
