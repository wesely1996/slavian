class_name OrderText
extends RefCounted
## Words for standing orders (see server/src/sim/orders.ts).


static func describe(order: Dictionary, units: Dictionary) -> String:
	match order.kind:
		"train":
			var unit_name: String = UI.t(units.get(order.unit, {"name": order.unit}).name)
			return UI.t("Keep %d %s, %d at a time") % [int(order.target), unit_name, int(order.batch)]
		"rebuild":
			return UI.t("Rebuild raided outposts")
		"surplus":
			return UI.t("Send all above %d%% of storage to the vault") % roundi(float(order.share) * 100.0)
	return String(order.kind)
