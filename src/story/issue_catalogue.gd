class_name IssueCatalogue
extends RefCounted
## What the ship's diagnostics log says: the scripted crash report after the
## failed punch jump, the endless stream of problems the ship fixes on its own,
## the ones it needs the pilot for, and the egress waiver the rift insists on.

## The crash report, played once the ship lands in fractal space. Each line
## waits `delay` seconds after the previous one. Styles: see IssueLog.
const INTRO_SCRIPT := [
	{"delay": 0.4, "style": "fail", "text": "Error: punch jump not completed successfully"},
	{"delay": 1.4, "style": "error", "text": "Error #13432 Mandelbrought recurrence generator has animalifolds instead of manifolds"},
	{"delay": 1.6, "style": "ok", "text": "Resolved successfully, via forced evfoldlution"},
	{"delay": 1.3, "style": "error", "text": "Error #23223 Interdimensional demon deterrents empty"},
	{"delay": 1.6, "style": "ok", "text": "Resolved successfully via same-nanosecond delivery"},
	{"delay": 1.3, "style": "error", "text": "Error #33423 Stuck in fractal space"},
	{"delay": 2.0, "style": "fail", "text": "Unable to automatically resolve, connecting to agent....."},
]

## [problem, how it was fixed]. Drawn at random (without repeats until the
## pool is spent) while the ship is stranded.
const AUTO_ISSUES := [
	["Hull integrity reported as 'vibes'", "rounding vibes up to the nearest integer"],
	["Coffee maker folded into 2.7 dimensions", "decaffeinating the extra 0.7 dimensions"],
	["Starboard nacelle is now also the port nacelle", "agreeing to disagree"],
	["Navigation computer stuck in an infinite loop of self-similarity", "telling it it looks nice today"],
	["Gravity inverted, re-inverted, then inverted again", "taking the parity"],
	["Life support recursion depth exceeded (max 32)", "breathing more efficiently"],
	["Escape-time algorithm has escaped", "recapture with a slightly larger bounding box"],
	["Box fold clamped the snack drawer", "unclamping at plus or minus one snack"],
	["Sphere inversion turned the airlock inside out", "outside-in airlock certification"],
	["Distance estimator estimating distances emotionally", "a firm talking-to"],
	["Ship's cat observed in four superposed states", "opening only one box at a time"],
	["Running derivative fell over", "helping it back up (dz *= |scale|, +1 for morale)"],
	["Warp core reports it is 'fine' in a tone suggesting it is not", "active listening"],
	["Fractal dimension of the toilet exceeds legal limit (2.0)", "a strongly worded sign"],
	["Hyperspace receipt not found", "printing a receipt for the receipt"],
	["Quaternion overflow in the cupholder", "conjugating the cup"],
	["Lipschitz constant has unionised", "a modest pay rise and a dental plan"],
	["Self-similarity in crew roster: all crew members are you", "name tags"],
	["Reality compiled in float32", "squinting"],
	["Scanner returned 'yes'", "asking it a more specific question"],
	["Thruster 3 is thinking about thruster 3 thinking about thruster 3", "a strong cup of tea"],
	["Antimatter containment field slightly matter", "reversing the polarity of the apology"],
	["Hausdorff dimension of the windscreen is non-integer", "wipers set to 'fractional'"],
	["Infinite coastline detected; insurance premium recalculating", "measuring with a longer ruler"],
	["0.0003% of the pilot lost to the box fold", "it was mostly the left eyebrow"],
	["Ship cartographer resigned, citing 'too much detail'", "hiring a cartographer with worse eyesight"],
	["Sub-dimensional pigeons nesting in exhaust port", "polite relocation to a Sierpinski gasket"],
	["Ray march exceeded 128 steps and asked for a lift", "a lift"],
	["Ship clock reports the time as a fraction of itself", "rounding to Tuesday"],
	["Shields at 110%, which is concerning", "donating the extra 10% to charity"],
	["Error message contains itself recursively", "reading only the first one"],
	["Engine room is bigger on the inside", "confirming that is just how fractals work"],
	["Pocket dimension in the pilot's pocket now contains the pilot", "turning out the pockets"],
	["Mandelbox scale set to -2.09 by an unknown party", "blaming the intern"],
	["Universal translator translating everything into Fortran", "compiling it back"],
	["Fold limit reached in the origami department", "one (1) paper crane"],
	["Hyperdrive warranty expired four nanoseconds ago", "backdating it with a stern look"],
	["Space-time continuum mildly creased", "ironing on a low setting"],
	["One (1) unidentified Julia set found in the cargo hold", "returning it to lost property"],
	["Autopilot asked 'are we there yet' 2^31 times", "integer overflow; it has forgotten"],
	["Emergency lighting stuck on 'aesthetic'", "setting it to 'emergency (aesthetic)'"],
	["Ship AI writing poetry about the fractal again", "publishing it to relieve the pressure"],
	["Bounding cube breached by a stray thought", "un-thinking it"],
	["Normal vectors no longer normal", "renormalising them and their attitudes"],
	["Hyperspace punch card has a hanging chad", "a recount"],
]

## Issues the ship cannot resolve without asking the pilot. `question` is what
## the support agent should ask; `default` is what the ship assumes if nobody
## answers in time; `outcome` formats the pilot's answer into the log.
const PILOT_ISSUES := [
	{"problem": "Cupholder has achieved sentience and is requesting a name",
		"question": "What should the cupholder be called?",
		"default": "Cuppy",
		"outcome": "Cupholder now answers to '%s'. It seems happy."},
	{"problem": "Fold limit recalibration requires the pilot's favourite number",
		"question": "What is the pilot's favourite number?",
		"default": "seven",
		"outcome": "Fold limit recalibrated to the essence of '%s'. Do not ask how."},
	{"problem": "Two identical copies of the pilot detected",
		"question": "Which copy is the real pilot: the one on the left or the one on the right?",
		"default": "the left one",
		"outcome": "'%s' confirmed as canonical. The other copy has been politely archived."},
	{"problem": "Safety inspection: pilot may have looked directly at the Hausdorff measure",
		"question": "Has the pilot looked directly at the Hausdorff measure? Yes or no.",
		"default": "no",
		"outcome": "Pilot says '%s'. Optic nerves cleared for further fractals."},
	{"problem": "Ship's music player has collapsed into a single genre",
		"question": "What music would the pilot like playing?",
		"default": "smooth jazz",
		"outcome": "Now playing: '%s', on an infinite loop, which is also a fractal."},
	{"problem": "Escape pod has fractured into 4,096 smaller escape pods",
		"question": "Should we keep all 4,096 escape pods? Yes or no.",
		"default": "yes",
		"outcome": "Pilot chose '%s'. Storage has been reorganised as a fractal."},
	{"problem": "Hyperdrive is requesting a password hint",
		"question": "What is a word that rhymes with 'fractal'?",
		"default": "practical",
		"outcome": "Hyperdrive accepted '%s' as a rhyme. Standards are low in here."},
]

## The rift will not open until this is signed. Raised as the ship nears it.
const EGRESS_WAIVER := {
	"code": 99812,
	"problem": "Egress waiver unsigned: the rift refuses to open",
	"question": "Ask the pilot to state their full name and agree that Sub-Dimensional Support is not liable for any extra dimensions they bring home.",
	"default": "the pilot (auto-signed)",
	"outcome": "Waiver signed by '%s'. Liability for any extra dimensions transferred to the pilot.",
	"gating": true,
}
