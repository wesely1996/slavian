class_name ChatText
extends RefCounted
## Words for the group chat (screens/game_screen.gd).

## The longest message the server takes (api/app.ts CHAT_MAX).
const MAX_LENGTH := 500


## "Ana · 5m ago" above a message ("You" for your own).
static func header(message: Dictionary, mine: bool, now: float) -> String:
	var who := UI.t("You") if mine else String(message.get("name", ""))
	return UI.t("%s · %s") % [who, InboxText.ago(TimeUtil.parse_iso(String(message.at)), now)]
