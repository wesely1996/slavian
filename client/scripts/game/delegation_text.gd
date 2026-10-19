class_name DelegationText
extends RefCounted
## Hand-overs between teammates (server commands/delegation.ts).


## The running hand-over of `owner`'s villages, or {}.
static func of_owner(delegations: Array, owner: int, now: float) -> Dictionary:
	for d in delegations:
		if int(d.ownerAccountId) == owner and TimeUtil.parse_iso(d.until) > now:
			return d
	return {}


## Whether `actor` may command a village `owner` owns right now.
static func commands(delegations: Array, owner: int, actor: int, now: float) -> bool:
	if owner == actor:
		return true
	var d := of_owner(delegations, owner, now)
	return not d.is_empty() and int(d.delegateAccountId) == actor


## Owners whose villages `actor` commands for them.
static func owners_for(delegations: Array, actor: int, now: float) -> Array:
	var out := []
	for d in delegations:
		if int(d.delegateAccountId) == actor and TimeUtil.parse_iso(d.until) > now:
			out.append(int(d.ownerAccountId))
	return out


## "Goran (for Mila) queued a build in Mila's village".
static func entry(e: Dictionary, names: Dictionary, village_names: Dictionary) -> String:
	var line := UI.t("%s (for %s) %s") % [names.get(int(e.delegateAccountId), "?"), names.get(int(e.ownerAccountId), "?"), e.action]
	if e.get("villageId") != null and village_names.has(int(e.villageId)):
		line += UI.t(" in %s") % village_names[int(e.villageId)]
	return line
