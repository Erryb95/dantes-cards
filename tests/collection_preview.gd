extends Node
## The collection screen on one filter, scrolled to a page, to check card faces of a set at a glance.
##   Godot --path . res://tests/collection_preview.tscn --resolution 1920x1080 -- --filter=ulysses --page=0 --out=<file.png>
## Every card is shown as owned (the save is not touched: Collection is only changed in memory).

func _ready() -> void:
	var out := "user://collection_preview.png"
	var filter := "all"
	var page := 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--filter="):
			filter = a.substr(9)
		elif a.begins_with("--page="):
			page = int(a.substr(7))
	for c in CardDB.all_cards():
		Collection.owned[c.id] = maxi(int(Collection.owned.get(c.id, 0)), 2)
	var scene: Node = load("res://scenes/collection.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame
	scene._set_filter(filter)
	await get_tree().create_timer(1.0).timeout
	while "_faces" in scene and not scene._faces.is_done(): # the faces are built a few per frame
		await get_tree().process_frame
	var scroll := scene.find_children("*", "ScrollContainer", true, false)
	if not scroll.is_empty():
		var sc: ScrollContainer = scroll[0]
		sc.scroll_vertical = int(page * sc.size.y)
	await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
