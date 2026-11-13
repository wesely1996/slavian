extends "res://scripts/screens/game_screen_messages.gd"
## In-world screen: the map from the server, your resources, a threat
## line, and a sheet for what is picked. This last link answers the news
## from the server; the rest is in the scripts it extends
## (game_screen_base.gd and the links after it).

func _on_waves_changed() -> void:
	hex_map.queue_redraw()
	_sound_hordes()
	_rebuild_panel_soon()


func _on_world_changed() -> void:
	_update_music()
	hex_map.refresh()
	_refresh_quest_card()
	_open_run_once()
	_view_button.visible = not _my_village().is_empty()
	if _view == "village" and _my_village().is_empty():
		_set_view("map")
		return
	_rebuild_panel_soon()


func _on_village_changed(_village_id: int) -> void:
	hex_map.queue_redraw()
	_rebuild_panel_soon()


func _on_live_connection(connected: bool) -> void:
	_live_label.text = tr("○ offline")
	_live_label.add_theme_color_override("font_color", Color("#e58a7d"))
	_live_label.visible = not connected and not Local.is_active()
	_fit_bar()
	if connected:
		_refetch_world()


func _refetch_world() -> void:
	var response := await Api.get_json("/v1/worlds/%d" % Game.world_id())
	if response.ok:
		Game.set_world(response.data)
	_refetch_inbox()
	_refetch_chat()


func _on_inbox_changed() -> void:
	_update_messages_badge()
	_fit_bar()
	if _panel_mode == "inbox":
		_rebuild_panel()
	_pop_events()


func _on_chat_changed() -> void:
	_update_messages_badge()
	# The inbox's switch counts new chat messages.
	if _panel_mode == "inbox":
		_rebuild_panel()
	if _panel_mode != "chat":
		return
	# Several changes in a frame (a message, then its read mark) lay the
	# chat out once.
	if _chat_stale:
		return
	_chat_stale = true
	var bar := _scroll.get_v_scroll_bar()
	var from_end := int(bar.max_value - _scroll.size.y) - _scroll.scroll_vertical
	var at_bottom := from_end <= 8 or _chat_sent
	_chat_sent = false
	await get_tree().process_frame
	_chat_stale = false
	if _panel_mode != "chat":
		return
	_rebuild_panel()
	_read_chat()
	# Laid out over the next frame: then back to where the reader was (from
	# the end, so older messages loaded above don't push the page), or to
	# the newest.
	await get_tree().process_frame
	await get_tree().process_frame
	if _panel_mode != "chat":
		return
	var end := int(bar.max_value - _scroll.size.y)
	_scroll.scroll_vertical = end if at_bottom else maxi(0, end - from_end)
