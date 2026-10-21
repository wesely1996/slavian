class_name QuestCard
extends PanelContainer
## The getting-started quest card (PLAN.md M5 step 23): always on screen over
## the map and the village while the chain is open. Folded, it shows the step
## and its reward; open, the elder's reason, what to tap, and Show me. A done
## step's reward waits behind Claim, and the card pulses until it is taken.

signal claim(step_id: String)
signal show_me(target: String)
signal hide_tutorial

var _open := true
var _pulse: Tween


func _init() -> void:
	add_theme_stylebox_override("panel", UiTheme.sheet_style(16))
	mouse_filter = MOUSE_FILTER_STOP


## Shows `member`'s current step; hides the card once the chain is over.
func show_for(data: Dictionary, member: Dictionary) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var step := OnboardingText.current(data, member)
	visible = not step.is_empty()
	if step.is_empty():
		_stop_pulse()
		return
	var ready := OnboardingText.claimable(member, step)
	var body := UI.vbox(8)
	add_child(body)

	var head := UI.hbox(10)
	head.add_child(UI.icon("icon/research", 34))
	var titles := UI.vbox(0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_child(UI.label(OnboardingText.progress(data, member), UI.SMALL_SIZE, UI.MUTED))
	var title := UI.label(UI.t(step.title), 0, UI.ACCENT if ready else Color.WHITE)
	title.add_theme_font_size_override("font_size", UI.scaled(UI.SMALL_SIZE + 6))
	titles.add_child(title)
	head.add_child(titles)
	var fold := UI.button("▾" if _open else "▸", func() -> void:
		_open = not _open
		show_for(data, member))
	fold.custom_minimum_size = Vector2(52, 52)
	fold.tooltip_text = UI.t("Fold the card") if _open else UI.t("Open the card")
	head.add_child(fold)
	body.add_child(head)

	if ready:
		body.add_child(UI.label(UI.t("Done! Its reward is waiting for you."), UI.SMALL_SIZE))
	elif _open:
		body.add_child(UI.label(UI.t(step.story), UI.SMALL_SIZE, UI.MUTED))
		for line in OnboardingText.how(step):
			body.add_child(UI.label(line, UI.SMALL_SIZE))
	var reward := UI.rich(UI.costs(step.reward, 26), UI.SMALL_SIZE, UiTheme.INK)
	body.add_child(reward)

	var buttons := UI.hbox(8)
	if ready:
		var take := UI.primary(UI.t("Claim reward"), func() -> void: claim.emit(String(step.id)))
		take.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		buttons.add_child(take)
	elif _open:
		var point := UI.primary(UI.t("Show me"), func() -> void: show_me.emit(String(step.get("show", ""))))
		point.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		buttons.add_child(point)
		buttons.add_child(UI.button(UI.t("Hide"), func() -> void: hide_tutorial.emit()))
	if buttons.get_child_count() > 0:
		body.add_child(buttons)
	if ready:
		_start_pulse()
	else:
		_stop_pulse()
	reset_size()


## A gentle glow while a reward waits.
func _start_pulse() -> void:
	if _pulse and _pulse.is_valid():
		return
	_pulse = create_tween().set_loops()
	_pulse.tween_property(self, "self_modulate", Color(1.12, 1.06, 0.82), 0.6).set_trans(Tween.TRANS_SINE)
	_pulse.tween_property(self, "self_modulate", Color.WHITE, 0.6).set_trans(Tween.TRANS_SINE)


func _stop_pulse() -> void:
	if _pulse and _pulse.is_valid():
		_pulse.kill()
	self_modulate = Color.WHITE
