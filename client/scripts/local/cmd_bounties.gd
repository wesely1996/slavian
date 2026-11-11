class_name LocalBounties
extends RefCounted
## The Market's bounty board for the local engine (server/src/sim/bounties.ts,
## commands/bounties.ts): a poster pays what they offer plus a fee at once;
## whoever takes it pays what is asked and gets what is offered, and the
## poster gets what was asked less the fee. In a solo world every bounty is
## the player's own: it can be posted and called off, never taken.

const KINDS := ["wood", "stone", "grain", "iron"]


static func fee(data: Dictionary, offer: Dictionary) -> Dictionary:
	var share := float(data.buildings.village.market.bounties.feeShare)
	return LocalVillage.resources(func(k: String) -> int: return ceili(float(offer[k]) * share - 1e-9))


static func returned(data: Dictionary, want: Dictionary) -> Dictionary:
	var share := float(data.buildings.village.market.bounties.feeShare)
	return LocalVillage.resources(func(k: String) -> int: return floori(float(want[k]) * (1.0 - share) + 1e-9))


static func slots(data: Dictionary, market_level: int) -> int:
	return 1 + floori(float(market_level - 1) / int(data.buildings.village.market.bounties.levelsPerBounty)) if market_level > 0 else 0


static func most(data: Dictionary, market_level: int) -> int:
	return int(data.buildings.village.market.bounties.amountPerLevel) * market_level


static func _side(value: Variant) -> Dictionary:
	var side := {}
	for k in KINDS:
		side[k] = value.get(k, 0) if value is Dictionary else 0
	return side


static func _total(side: Dictionary) -> float:
	var sum := 0.0
	for k in KINDS:
		sum += float(side[k])
	return sum


## A rule refusal for the bounty, or {}.
static func check(data: Dictionary, market_level: int, open: int, offer: Dictionary, want: Dictionary) -> Dictionary:
	if market_level <= 0:
		return LocalVillage.rule("Build a Market to post bounties")
	for side in [offer, want]:
		for k in KINDS:
			var n := float(side[k])
			if n != floorf(n) or n < 0:
				return LocalVillage.rule("Amounts are whole, non-negative numbers")
	if _total(offer) <= 0:
		return LocalVillage.rule("Offer something")
	if _total(want) <= 0:
		return LocalVillage.rule("Ask for something")
	for k in KINDS:
		if float(offer[k]) > 0 and float(want[k]) > 0:
			return LocalVillage.rule("Offer and ask for different resources")
	var top := most(data, market_level)
	if _total(offer) > top or _total(want) > top:
		return LocalVillage.rule("The Market takes bounties of at most %d on each side" % top)
	var n := slots(data, market_level)
	if open >= n:
		return LocalVillage.rule("The Market keeps %d open %s" % [n, "bounty" if n == 1 else "bounties"])
	return {}


## Posts a bounty from `village`: {state, bounty}, or {"error"}/{"missing"}.
static func post(server: LocalServer, world: Dictionary, village: Dictionary, body: Dictionary, now: int) -> Dictionary:
	var data := server.data
	if not body.get("offer") is Dictionary or not body.get("want") is Dictionary:
		return {"error": "Say what you offer and what you ask", "kind": "invalid"}
	var offer := _side(body.offer)
	var want := _side(body.want)
	var open: int = world.bounties.filter(func(b: Dictionary) -> bool: return int(b.villageId) == int(village.id) and b.status == "open").size()
	var refused := check(data, int(village.state.levels.get(LocalVillage.MARKET, 0)), open, offer, want)
	if not refused.is_empty():
		return refused
	var paid_fee := fee(data, offer)
	var ledger := LocalLedger.spend(village.state.ledger, now, LocalVillage.resources(func(k: String) -> float: return float(offer[k]) + float(paid_fee[k])))
	if ledger.has("missing"):
		return ledger
	var bounty := {"id": world.next.bounty, "villageId": village.id, "ownerAccountId": village.ownerAccountId, "offer": offer, "want": want,
		"fee": paid_fee, "status": "open", "createdAt": now, "closedAt": null, "takenByVillageId": null}
	world.next.bounty += 1
	world.bounties.append(bounty)
	var state: Dictionary = village.state.duplicate()
	state.ledger = ledger
	return {"state": state, "bounty": bounty}


static func find(world: Dictionary, id: int) -> Dictionary:
	for b in world.bounties:
		if int(b.id) == id:
			return b
	return {}


## Calls a bounty off: what it offered comes back to its village (the fee does not).
static func cancel(world: Dictionary, bounty: Dictionary, village: Dictionary, now: int) -> Dictionary:
	if bounty.status != "open":
		return LocalVillage.rule("That bounty is closed")
	bounty.status = "cancelled"
	bounty.closedAt = now
	village.state.ledger = LocalLogistics.receive(village.state.ledger, now, bounty.offer).ledger
	return {"ok": true}


## Takes a bounty from `village` (refused for one's own: in a solo world, every one).
static func take(server: LocalServer, world: Dictionary, bounty: Dictionary, village: Dictionary, now: int) -> Dictionary:
	if bounty.status != "open":
		return LocalVillage.rule("That bounty is closed")
	if bounty.ownerAccountId != null and village.ownerAccountId != null and int(bounty.ownerAccountId) == int(village.ownerAccountId):
		return LocalVillage.rule("That bounty is your own")
	var paid := LocalLedger.spend(village.state.ledger, now, bounty.want)
	if paid.has("missing"):
		return paid
	village.state.ledger = LocalLogistics.receive(paid, now, bounty.offer).ledger
	var poster := server.find_village(world, int(bounty.villageId))
	poster.state.ledger = LocalLogistics.receive(poster.state.ledger, now, returned(server.data, bounty.want)).ledger
	bounty.status = "taken"
	bounty.closedAt = now
	bounty.takenByVillageId = village.id
	return {"ok": true}


## The open bounties, oldest first (as the server lists them).
static func bounties_view(world: Dictionary) -> Array:
	var open: Array = world.get("bounties", []).filter(func(b: Dictionary) -> bool: return b.status == "open")
	open.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.id) < int(b.id))
	return open.map(bounty_view)


static func bounty_view(b: Dictionary) -> Dictionary:
	return {"id": b.id, "villageId": b.villageId, "ownerAccountId": b.ownerAccountId, "offer": b.offer, "want": b.want, "fee": b.fee,
		"status": b.status, "createdAt": LocalTime.iso(b.createdAt)}
