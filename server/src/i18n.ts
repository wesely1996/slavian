// Server-side text localization for notices (docs/localization.md).
//
// The game data and the client UI live in the gettext catalogs; notices are
// built on the server at event time, so they carry their English template and
// the values to fill in, and are rendered in the recipient's language here.
//
// English is the source text. A translation map holds the Serbian versions of
// the notice templates; the same rendered text is stored in the inbox and sent
// by push, so a player sees one language everywhere. Everything else a notice
// carries from the game data (stories, quests, techs, names, threat levels) is
// already translated in the client's gettext catalog, which serves as the
// fallback, both for templates and for the values filled into them.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

export type Language = string;

const CATALOGS: Record<string, string> = {
	sr: fileURLToPath(new URL('../../client/i18n/sr_Latn.po', import.meta.url)),
};

const SERBIAN: Record<string, string> = {
	// Wave warnings
	'A horde is coming to {village}': 'Horda dolazi u {village}',
	'The {threat} {front} horde arrives in about {hours} hours. Check the garrison and its stance.':
		'Dolazi {threat} horda sa {front}, za oko {hours} h. Proveri posadu i njen stav.',
	'The {threat} {front} horde arrives in about an hour. Check the garrison and its stance.':
		'Dolazi {threat} horda sa {front}, za oko sat vremena. Proveri posadu i njen stav.',
	'The {threat} {front} horde arrives within the hour. Check the garrison and its stance.':
		'Dolazi {threat} horda sa {front}, za manje od sat vremena. Proveri posadu i njen stav.',
	'Today in {world}': 'Danas u svetu {world}',
	// Battles
	'{village} is under attack': '{village} je napadnuto',
	'A horde of {enemy} is fighting your garrison of {defenders}.': 'Horda od {enemy} se bori protiv tvoje posade od {defenders}.',
	'{village} was raided': '{village} je opljačkano',
	'The horde carried off {loot} resources after {rounds} rounds.': 'Horda je odnela {loot} resursa posle {rounds} rundi.',
	'{village} is being razed': '{village} se razara',
	'The horde broke the defenders after {rounds} rounds and is burning the village.': 'Horda je slomila branioce posle {rounds} rundi i pali selo.',
	'{village} held': '{village} se održalo',
	'The horde was beaten after {rounds} rounds.': 'Horda je pobeđena posle {rounds} rundi.',
	'The horde was beaten after {rounds} rounds; the hospital and shamans saved {healed} of the fallen.': 'Horda je pobeđena posle {rounds} rundi; bolnica i šamani su spasli {healed} palih.',
	// Field battles
	'A horde ran into your army at ({q}, {r})': 'Horda je naletela na tvoju vojsku na ({q}, {r})',
	'{enemy} against {defenders}.': '{enemy} protiv {defenders}.',
	'{enemy} against {defenders}, with {ground}.': '{enemy} protiv {defenders}, uz {ground}.',
	'The Holy City held': 'Sveti grad se održao',
	'The Holy City was struck': 'Sveti grad je udaren',
	'The horde was beaten at its walls after {rounds} rounds.': 'Horda je pobeđena kod njegovih zidina posle {rounds} rundi.',
	'Its Sanctity fell to {sanctity}.': 'Njegova svetost je pala na {sanctity}.',
	'Your army held ({q}, {r})': 'Tvoja vojska se održala na ({q}, {r})',
	'Your army fell back from ({q}, {r})': 'Tvoja vojska se povukla sa ({q}, {r})',
	'The horde marches on, {rounds} rounds late.': 'Horda nastavlja dalje, {rounds} rundi zakašnjela.',
	// Camps and lairs
	'Your army cleared the {where}': 'Tvoja vojska je očistila {where}',
	'Your army was driven off from the {where}': 'Tvoja vojska je odbijena od {where}',
	'A caravan from {village} was ambushed': 'Karavan iz {village} je upao u zasedu',
	'A caravan from {village} beat off an ambush': 'Karavan iz {village} je odbio zasedu',
	'Bandits took the fort at ({q}, {r})': 'Razbojnici su zauzeli utvrdu na ({q}, {r})',
	'No army held it, and now it is their camp. Send an army to clear it.': 'Nijedna vojska je nije držala, i sada je njihov logor. Pošalji vojsku da ga očisti.',
	'Monsters made a lair at ({q}, {r})': 'Čudovišta su napravila jazbinu na ({q}, {r})',
	'Raiders made camp at ({q}, {r})': 'Pljačkaši su se utaborili na ({q}, {r})',
	'{count} survivors of wave {wave} settled there.': '{count} preživelih iz talasa {wave} se tu nastanilo.',
	'{village} was razed': '{village} je razoreno',
	'Only ruins are left. Rebuild them, or start over from what remains.': 'Ostale su samo ruševine. Obnovi ih, ili počni iznova od onoga što je ostalo.',
	'A refuge by the Holy City': 'Utočište kod Svetog grada',
	'{camp} takes in your people at ({q}, {r}).': '{camp} prima tvoje ljude na ({q}, {r}).',
	'A horde is at the Holy City': 'Horda je kod Svetog grada',
	'{enemy} of them against its guard of {defenders}.': '{enemy} njih protiv njegove straže od {defenders}.',
	'{village} stands again': '{village} ponovo stoji',
	'Its fields and buildings are rebuilt as they were.': 'Njegove njive i građevine su obnovljene kao što su bile.',
	// Outposts, caravans, settlers, research, heroes, leaders
	'A horde burned an outpost of {village}': 'Horda je spalila ispostavu sela {village}',
	'A caravan from {sender} reached {village}': 'Karavan od {sender} je stigao u {village}',
	'It brought {amount} resources.': 'Doneo je {amount} resursa.',
	'Settlers turned back from ({q}, {r})': 'Doseljenici su se vratili sa ({q}, {r})',
	'They are walking home to {home}.': 'Vraćaju se peške kući u {home}.',
	'{name} founded': '{name} je osnovano',
	'Your settlers built a new village.': 'Tvoji doseljenici su sagradili novo selo.',
	'{tech} researched': '{tech} je istraženo',
	'{name} is wounded': '{name} je ranjen',
	'Back on their feet in a few hours.': 'Na nogama za nekoliko sati.',
	'{name} reached level {level}': '{name} je stigao do nivoa {level}',
	// Field armies
	'An army from {village} starved': 'Vojska iz sela {village} je umrla od gladi',
	'With no food left it scattered; none of them will come back.': 'Bez hrane se razbežala; niko od njih se neće vratiti.',
	'Another horde joins the battle at ({q}, {r})': 'Još jedna horda se pridružuje bici na ({q}, {r})',
	'{enemy} more from the {front} fight alongside the horde already there.': 'Još {enemy} sa {front} bori se uz hordu koja je već tamo.',
	// Generals
	'{name} answers your call': '{name} se odaziva tvom pozivu',
	'A new general stands ready.': 'Novi general je spreman.',
	'{name} fell in battle': '{name} je pao u bici',
	"Recruit another at a Hero's Hall.": 'Unajmi drugog u Dvorani junaka.',
	'The troops they lead fight a little harder.': 'Trupe koje predvodi bore se malo žešće.',
	// Hero quests
	'{name} is back from: {quest}': '{name} se vratio sa zadatka: {quest}',
	'{name} came back wounded from: {quest}': '{name} se vratio ranjen sa zadatka: {quest}',
	'Kept vigil under the oak, and came back wiser.': 'Bdeo je pod hrastom i vratio se mudriji.',
	'{name} has done: {quest}': '{name} je izvršio zadatak: {quest}',
	'The army quest is done: {xp} XP for {name}.': 'Pohod je završen: {xp} iskustva za {name}.',
	'{name} failed: {quest}': '{name} nije uspeo: {quest}',
	'The army did not get there in time, and the chance is gone.': 'Vojska nije stigla na vreme, i prilika je propala.',
	'The road lay empty: that horde had already set out.': 'Put je bio prazan: ta horda je već krenula.',
	'The next horde from the {front} sets out {minutes} minutes later, hating you the more: +{hatred}% attack and defense.':
		'Sledeća horda sa {front} kreće {minutes} minuta kasnije, i mrzi vas još više: +{hatred}% napada i odbrane.',
	"That horde had already set out; the hero saw only its dust.": 'Ta horda je već krenula; junak je video samo njenu prašinu.',
	'A full report on the next horde from the {front} is in the threats panel.': 'Potpun izveštaj o sledećoj hordi sa {front} je u panelu pretnji.',
	'Brought back {wood} wood, {stone} stone, {grain} grain and {iron} iron.': 'Doneo je {wood} drveta, {stone} kamena, {grain} žita i {iron} gvožđa.',
	'The hoard had been dug up already.': 'Blago je već bilo iskopano.',
	'Found the {item}.': 'Pronašao je: {item}.',
	'Someone had been there first.': 'Neko je već bio tamo.',
	'Searched the {site}.': 'Pretražio je: {site}.',
	'A new skill point to spend.': 'Novi poen veštine za trošenje.',
	'{leader} has fallen': '{leader} je pao',
	'{leader} was slain': '{leader} je ubijen',
	"Assassins from {village} killed {leader} in the horde's camp. Another will rise to take their place.":
		'Ubice iz {village} ubile su {leader} u logoru horde. Drugi će se podići na njegovo mesto.',
	'{leader} died with the last of the horde after {battles} battles. Another will rise to take their place.':
		'{leader} je umro sa poslednjim delom horde posle {battles} bitaka. Drugi će ustati na njegovo mesto.',
	'{leader} grows stronger': '{leader} jača',
	'{leader} is now level {level}.': '{leader} je sada nivo {level}.',
	// Bridge and the run
	'Raising {stage}': 'Podizanje: {stage}',
	'{place} rises': '{place} se uzdiže',
	'{story} It is marked on the map at ({q}, {r}).': '{story} Obeleženo je na mapi na ({q}, {r}).',
	'{place} gather': '{place} se okupljaju',
	'{story}': '{story}',
	'Nav strikes at the builders': 'Nav udara na graditelje',
	'While {stage} is raised, every front sends a band at a different target.': 'Dok se {stage} podiže, svaki front šalje odred na drugu metu.',
	'Everything it needs is in place; the builders are at work.': 'Sve što je potrebno je na mestu; graditelji rade.',
	'{stage}: {quest}': '{stage}: {quest}',
	'{name} stands': '{name} stoji',
	'The Kalinov Bridge is whole. Ritual Night is coming.': 'Kalinov most je ceo. Obredna noć dolazi.',
	'A lair in the woods': 'Jazbina u šumi',
	'A forgotten ruin': 'Zaboravljena ruševina',
	// Buildings, delegation, onboarding
	'{building} level {level} in {village}': '{building} nivo {level} u {village}',
	'Finished. Your build queue may have room for more.': 'Završeno. Tvoj red gradnje možda ima mesta za još.',
	'Finished.': 'Završeno.',
	'{name} handed you their villages': '{name} ti je predao svoja sela',
	'{name} left the world': '{name} je napustio svet',
	'Their villages went to your teammates.': 'Njegova sela su pripala tvojim saigračima.',
	'You now command one of their villages.': 'Sada zapovedaš jednim od njegovih sela.',
	'You now command {count} of their villages.': 'Sada zapovedaš sa {count} njegovih sela.',
	'Command them as your own for {days} days. Everything you do is noted for them.':
		'Upravljaj njima kao svojim {days} dana. Sve što uradiš je zabeleženo za njih.',
	'{name} took their villages back': '{name} je vratio svoja sela',
	'{name} handed your villages back': '{name} ti je vratio sela',
	'The hand-over has ended.': 'Predaja je završena.',
	'Done: {step}': 'Završeno: {step}',
	'Claim its reward from the quest card.': 'Preuzmi nagradu sa kartice zadataka.',
	// Raids that also lost building work, camps, fieldworks and outposts
	'The horde carried off {loot} resources after {rounds} rounds. The work on {buildings} building was lost.':
		'Horda je odnela {loot} resursa posle {rounds} rundi. Radovi na {buildings} građevini su izgubljeni.',
	'The horde carried off {loot} resources after {rounds} rounds. The work on {buildings} buildings was lost.':
		'Horda je odnela {loot} resursa posle {rounds} rundi. Radovi na {buildings} građevinama su izgubljeni.',
	"It carries home {loot} resources and a Svarog's Ember for the group.": 'Kući nosi {loot} resursa i Svarogov žar za družinu.',
	'It carries home {loot} resources.': 'Kući nosi {loot} resursa.',
	'{kills} of them fell; {defenders} still hold it.': '{kills} njih je palo; {defenders} ga još drži.',
	'Its escort drove off the {enemy} at ({q}, {r}).': 'Njegova pratnja je oterala {enemy} na ({q}, {r}).',
	'It lost {lost} of its load near ({q}, {r}).': 'Izgubio je {lost} svog tereta blizu ({q}, {r}).',
	'A bridge stands near {village}': 'Most stoji blizu {village}',
	'Roads now cross the river between ({aq}, {ar}) and ({bq}, {br}), for friend and foe alike.':
		'Putevi sada prelaze reku između ({aq}, {ar}) i ({bq}, {br}), za prijatelja i neprijatelja.',
	'Fort at ({q}, {r}) finished': 'Utvrda na ({q}, {r}) je završena',
	'Armies holding it fight from behind its walls.': 'Vojska koja ga drži bori se iza njegovih zidina.',
	'The outpost at ({q}, {r}) is down to level {level}.': 'Ispostava na ({q}, {r}) je spala na nivo {level}.',
	'The outpost at ({q}, {r}) lies in ruins.': 'Ispostava na ({q}, {r}) leži u ruševinama.',
	'{player} joined the run': '{player} se pridružio pohodu',
	'They founded {village} at ({q}, {r}).': 'Osnovao je {village} na ({q}, {r}).',
	'Scouts from {village} found a forgotten ruin': 'Izviđači iz sela {village} našli su zaboravljenu ruševinu',
	'A {site} lies at ({q}, {r}). Send an army to explore it.': '{site} leži na ({q}, {r}). Pošalji vojsku da je istraži.',
	'Scouts from {village} found no ruins': 'Izviđači iz sela {village} nisu našli ruševine',
	'They searched the land around it and came back empty-handed.': 'Pretražili su zemlju oko njega i vratili se praznih ruku.',
	'Supply point at ({q}, {r}) finished': 'Žitnica na ({q}, {r}) je završena',
	'Armies standing there fill up from its grain; supply routes keep it stocked.': 'Vojske koje tamo stoje uzimaju njeno žito; putevi snabdevanja je drže punom.',
	'A horde burned the supply point at ({q}, {r})': 'Horda je spalila žitnicu na ({q}, {r})',
	'Its {grain} grain burned with it.': 'Njenih {grain} žita izgorelo je s njom.',
	// Bridge, settlers, sites, delegation
	'Next: {stage}.': 'Sledeće: {stage}.',
	'The builders send {wood} wood, {stone} stone, {grain} grain and {iron} iron, and the {blessing} is on every village of the group. Next: {stage}.': 'Graditelji šalju {wood} drveta, {stone} kamena, {grain} žita i {iron} gvožđa, a {blessing} je nad svakim selom grupe. Sledeće: {stage}.',
	'Beasts of the North have made a lair by the road their last horde took. {stage} needs it cleared.':
		'Zveri Severa su napravile jazbinu kraj puta kojim je išla njihova poslednja horda. {stage} zahteva da se očisti.',
	'The builders of {stage} remember a ruin nobody has searched yet. It is marked on the map.':
		'Graditelji faze {stage} pamte ruševinu koju još niko nije pretražio. Označena je na mapi.',
	'{problem}. They are walking home to {home}.': '{problem}. Vraćaju se peške kući u {home}.',
	'Guardians drove your army from the {where}': 'Čuvari su oterali tvoju vojsku od {where}',
	'The horde had already set out': 'Horda je već krenula',
	'Your army found its encampment empty and turns for home.': 'Tvoja vojska je zatekla prazan logor i vraća se kući.',
	'Your army broke the horde in its encampment': 'Tvoja vojska je razbila hordu u njenom logoru',
	"Your army was thrown back from the horde's encampment": 'Tvoja vojska je odbijena od logora horde',
	'{kills} of the horde fell before it set out, {lost} of ours. The next horde hates us the more for it.': 'Palo je {kills} iz horde pre nego što je krenula, a {lost} naših. Sledeća horda nas zbog toga još više mrzi.',
	'Your raid sacked the {name}': 'Tvoj pohod je opljačkao {name}',
	'Your raid won the battle of the {name}': 'Tvoj pohod je dobio bitku kod {name}',
	'Your raid was beaten at the {name}': 'Tvoj pohod je poražen kod {name}',
	'It comes home with {loot} resources{found}.': 'Vraća se kući sa {loot} resursa{found}.',
	'{kills} of the enemy fell; it carries {loot} resources{found} and marches on.': '{kills} neprijatelja je palo; nosi {loot} resursa{found} i ide dalje.',
	'It turns for home with {loot} resources; {lost} of its men fell.': 'Vraća se kući sa {loot} resursa; {lost} njegovih ljudi je palo.',
	'{kills} of them fell; {remaining} still watch it.': '{kills} njih je palo; {remaining} još čuvaju.',
	'The {name} at ({q}, {r}) gave up {find}': '{name} na ({q}, {r}) dao je {find}',
	'Explored and done.': 'Istraženo i završeno.',
	'Command them as your own for {days} day. Everything you do is noted for them.':
		'Upravljaj njima kao svojim {days} dan. Sve što uradiš je zabeleženo za njih.',
	'Ritual Night': 'Obredna noć',
	// Values filled into the templates above.
	north: 'severa',
	east: 'istoka',
	south: 'juga',
	west: 'zapada',
	beasts: 'zveri',
	bandits: 'razbojnike',
	site: 'nalazište',
	'your village': 'tvoje selo',
	'an ambush': 'zasedu',
	'a choke point': 'tesnac',
	'a fort': 'utvrdu',
	'Captives are held at ({q}, {r})': 'Zarobljenici su zatočeni na ({q}, {r})',
	'Clear the camp to free them before they are taken away, for a bounty of at least {bounty} resources. If they are taken, the next horde from the {front} hates you the more.':
		'Očisti logor da ih oslobodiš pre nego što ih odvedu, za nagradu od najmanje {bounty} resursa. Ako ih odvedu, sledeća horda sa {front} mrzi vas još više.',
	'A forbidding ruin rises at ({q}, {r})': 'Zlokobna ruševina izranja na ({q}, {r})',
	'Strong guardians watch it, and rich finds lie within, for a while. Searching it brings a bounty of at least {bounty} resources; left alone, it rouses the next horde from the {front}.':
		'Čuvaju je snažni čuvari, a unutra leže bogati nalazi, još neko vreme. Pretraga donosi nagradu od najmanje {bounty} resursa; ostavljena na miru, razjaruje sledeću hordu sa {front}.',
	'Boatwrights wait at ({q}, {r})': 'Brodograditelji čekaju na ({q}, {r})',
	'Send them resources from your villages, and they build a boat that carries armies and caravans fast along the river, with a bounty of at least {bounty} resources for everyone. If nobody does, the next horde from the {front} hates you the more.':
		'Pošalji im resurse iz svojih sela, i sagradiće čamac koji brzo nosi vojske i karavane niz reku, uz nagradu od najmanje {bounty} resursa za svakoga. Ako niko ne pošalje, sledeća horda sa {front} mrzi vas još više.',
	'The boat at ({q}, {r}) is begun': 'Čamac na ({q}, {r}) je započet',
	'Raiders will come every {every} hours until it is done; armies standing there fight them.': 'Pljačkaši će dolaziti svakih {every} sati dok ne bude gotov; vojske koje stoje tamo bore se s njima.',
	'Raiders burned work at the shipyard at ({q}, {r})': 'Pljačkaši su spalili deo posla u brodogradilištu na ({q}, {r})',
	'The boat is set back {hours} hours. Burned {burns} times of {most}: at {most} the boatwrights give up. Armies standing there fight the next raiders.': 'Čamac kasni {hours} sati. Spaljen {burns} puta od {most}: na {most} brodograditelji odustaju. Vojske koje stoje tamo bore se sa sledećim pljačkašima.',
	'Raiders burned the shipyard at ({q}, {r}) to the ground': 'Pljačkaši su spalili brodogradilište na ({q}, {r}) do temelja',
	'The boat at ({q}, {r}) is ready': 'Čamac na ({q}, {r}) je spreman',
	"Armies, caravans and scouts move fast between hexes along its river. The boatwrights' bounty for {village}: {wood} wood, {stone} stone, {grain} grain and {iron} iron.":
		'Vojske, karavani i izviđači brzo se kreću između polja duž njegove reke. Nagrada brodograditelja za {village}: {wood} drveta, {stone} kamena, {grain} žita i {iron} gvožđa.',
	'Bounty for {village}: {wood} wood, {stone} stone, {grain} grain and {iron} iron.': 'Nagrada za {village}: {wood} drveta, {stone} kamena, {grain} žita i {iron} gvožđa.',
	'Done, with no village left to take the bounty.': 'Urađeno, ali nema sela koje bi primilo nagradu.',
	'You freed the captives at ({q}, {r})': 'Oslobodio si zarobljenike na ({q}, {r})',
	'You searched the forbidding ruin at ({q}, {r})': 'Pretražio si zlokobnu ruševinu na ({q}, {r})',
	'The captives at ({q}, {r}) were taken away': 'Zarobljenici sa ({q}, {r}) su odvedeni',
	'The forbidding ruin at ({q}, {r}) sank back into the earth': 'Zlokobna ruševina na ({q}, {r}) potonula je nazad u zemlju',
	'The boatwrights at ({q}, {r}) gave up and left': 'Brodograditelji sa ({q}, {r}) su odustali i otišli',
	'The next horde from the {front} hates you the more for it: +{hatred}% attack and defense.': 'Sledeća horda sa {front} zbog toga vas mrzi još više: +{hatred}% napada i odbrane.',
	'Nothing more came of it.': 'Ništa više od toga nije proizašlo.',
	'Armies, caravans and scouts move fast between hexes along its river.': 'Vojske, karavani i izviđači brzo se kreću između polja duž njegove reke.',
	'Your army drove the raiders off the shipyard at ({q}, {r})': 'Tvoja vojska je oterala pljačkaše iz brodogradilišta na ({q}, {r})',
	'Raiders broke your army at the shipyard at ({q}, {r})': 'Pljačkaši su slomili tvoju vojsku u brodogradilištu na ({q}, {r})',
	'{kills} of them fell, for {lost} of yours.': 'Palo ih je {kills}, a tvojih {lost}.',
	'a wagon fort': 'kolski tabor',
	'a river crossing': 'rečni prelaz',
	'That hex is not on the map': 'To polje nije na mapi',
	'Too close to the Holy City': 'Preblizu Svetom gradu',
	'An outpost stands there': 'Tamo stoji ispostava',
};

const TABLES: Record<string, Record<string, string>> = {
	sr: SERBIAN,
};

/** The notice tables by language, bundled into the app for the local engine. */
export const NOTICE_TABLES: Readonly<Record<string, Readonly<Record<string, string>>>> = TABLES;

const merged = new Map<string, Record<string, string>>();

/** The notice table over the client's catalog, for `language`; null for English. */
function table(language: Language): Record<string, string> | null {
	const tag = String(language).toLowerCase().startsWith('sr') ? 'sr' : String(language).toLowerCase();
	const own = TABLES[tag];
	if (!own) return null;
	let all = merged.get(tag);
	if (!all) {
		all = { ...readCatalog(CATALOGS[tag]), ...own };
		merged.set(tag, all);
	}
	return all;
}

/** A gettext catalog's translations (msgid → msgstr, plural forms left out); {} without the file. */
export function parsePo(text: string): Record<string, string> {
	const out: Record<string, string> = {};
	const unquote = (line: string) => JSON.parse(line.trim()) as string;
	let id: string | null = null;
	let str: string | null = null;
	let field: 'id' | 'str' | null = null;
	const flush = () => {
		if (id && str) out[id] = str;
		id = str = null;
		field = null;
	};
	for (const line of text.split(/\r?\n/)) {
		if (line.startsWith('msgid ')) {
			flush();
			id = unquote(line.slice(6));
			field = 'id';
		} else if (line.startsWith('msgstr ')) {
			str = unquote(line.slice(7));
			field = 'str';
		} else if (line.startsWith('"') && field) {
			if (field === 'id') id += unquote(line);
			else str += unquote(line);
		} else if (line.startsWith('msgid_plural') || line.startsWith('msgstr[')) {
			// Plural entries are the client's own.
			id = null;
			field = null;
		}
	}
	flush();
	return out;
}

function readCatalog(path: string | undefined): Record<string, string> {
	if (!path) return {};
	try {
		return parsePo(readFileSync(path, 'utf8'));
	} catch {
		return {};
	}
}

/** A value filled into a template, in `t`: as written, or capitalised as the
 * data has it ("severe" → "Severe" → "teška"), or each of a list's items. */
function translateValue(t: Record<string, string>, value: string): string {
	if (t[value]) return t[value];
	const capital = value.charAt(0).toUpperCase() + value.slice(1);
	if (capital !== value && t[capital]) {
		const found = t[capital];
		return found.charAt(0).toLowerCase() + found.slice(1);
	}
	if (value.includes(', ')) return value.split(', ').map((part) => translateValue(t, part)).join(', ');
	return value;
}

/** Fills `{name}` placeholders from `vars` (missing ones are left as-is). */
export function fill(template: string, vars?: Record<string, string | number>): string {
	if (!vars) return template;
	return template.replace(/\{(\w+)\}/g, (whole, key: string) => (key in vars ? String(vars[key]) : whole));
}

/** Renders an English template in `language`, then fills its values. */
export function localize(language: Language, template: string, vars?: Record<string, string | number>): string {
	const t = table(language);
	if (!t) return fill(template, vars);
	const values = vars && Object.fromEntries(Object.entries(vars).map(([k, v]) => [k, typeof v === 'string' ? translateValue(t, v) : v]));
	return fill(t[template] ?? template, values);
}
