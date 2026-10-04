package authutil

// wordlist is a curated subset of the BIP39 English wordlist: 256 common,
// memorable words a recovery phrase is drawn from. Exactly 256, and all
// distinct, so each word carries 8 bits and a draw is unbiased. TestWordlist
// enforces both; it held 232 while its comments claimed 256 (#2153).
//
// The Quark no longer makes phrases: the app does, from its copy in
// lib/utils/recovery_phrase.dart, which test/utils/recovery_phrase_test.dart
// checks against this one (#2430). This stays the canonical list.
var wordlist = []string{
	"abandon", "ability", "able", "about", "above", "absent", "absorb", "abstract",
	"absurd", "abuse", "access", "accident", "account", "accuse", "achieve", "acid",
	"acoustic", "acquire", "across", "action", "actor", "actual", "adapt", "add",
	"addict", "address", "adjust", "admit", "adult", "advance", "advice", "afford",
	"afraid", "again", "agent", "agree", "ahead", "aim", "airport", "aisle",
	"alarm", "album", "alert", "alien", "alley", "allow", "almost", "alone",
	"alpha", "already", "also", "alter", "always", "amateur", "amazing", "amount",
	"amused", "analyst", "anchor", "ancient", "anger", "angle", "angry", "animal",
	"ankle", "answer", "antenna", "antique", "anxiety", "apart", "appear", "apple",
	"approve", "april", "arch", "arctic", "area", "arena", "argue", "armed",
	"armor", "army", "around", "arrange", "arrest", "arrive", "arrow", "artefact",
	"artist", "artwork", "aspect", "assault", "asset", "assist", "assume", "asthma",
	"athlete", "atom", "attack", "attend", "attitude", "attract", "auction", "audit",
	"august", "aunt", "author", "autumn", "average", "avocado", "avoid", "awake",
	"aware", "away", "awesome", "awful", "awkward", "axis", "baby", "balance",
	"bamboo", "banana", "banner", "barrel", "base", "basic", "basket", "battle",
	"beach", "beauty", "become", "before", "begin", "behave", "believe", "below",
	"bench", "benefit", "best", "betray", "better", "between", "beyond", "bicycle",
	"birth", "bitter", "black", "blade", "blame", "blanket", "blast", "bleak",
	"blend", "bless", "blind", "blood", "blossom", "blouse", "blue", "blur",
	"blush", "board", "boost", "border", "boring", "borrow", "bounce", "brave",
	"breeze", "bridge", "bright", "bring", "bronze", "brown", "brush", "budget",
	"build", "bulb", "bulk", "bullet", "bundle", "burden", "burger", "burst",
	"busy", "butter", "buyer", "buzz", "cabbage", "cabin", "cable", "cactus",
	"camera", "cancel", "candy", "cannon", "canvas", "canyon", "capable", "capital",
	"captain", "carbon", "castle", "catalog", "catch", "category", "cause", "cement",
	"census", "certain", "chair", "change", "chaos", "charge", "chase", "cheap",
	"check", "cheese", "cherry", "chest", "chief", "child", "chimney", "choice",
	"choose", "chronic", "cinema", "circle", "citizen", "city", "civil", "claim",
	"clap", "clarify", "claw", "clay", "clean", "clever", "click", "client",
	"cliff", "climb", "clinic", "clip", "clock", "close", "cloth", "cloud",
	"clown", "club", "coach", "coast", "coconut", "code", "coffee", "coin",
}
