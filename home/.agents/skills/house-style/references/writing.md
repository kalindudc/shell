# How a Page Reads

The words on a page are half its design. A page that is not understood on its first read has failed at its one job, however good it looks. This file says how the words go, for every page and every interface. It works with the "Writing for people" rules in the user's AGENTS.md: lead with the answer, complete sentences with one idea each, every acronym and internal term defined on first use, words instead of symbols, no agent bookkeeping.

## Know the Reader

- Name who reads it before writing a word: what they already know, what they have never seen, how long they will give it. Most readers are engineers from a neighbouring team who know the field and were not in the room.
- Bring them in from what they feel. Open with what hurts or what changes for them, in their terms, then why, then the idea. A page that opens with the inside of the machine has lost them by its second sentence.
- Show how the parts connect and what moves what, not a list of features.
- Humans and agents are equal readers. The same facts are on the page for people and in its Markdown twin for agents; words written for an agent (its numbering, its ids) never reach a person.

## Short and Plain, Together

Clear does not mean long. A request for clearer words must not turn titles into sentences without full stops and ledes into paragraphs.

- The title is pithy: three to six words, a finding or a claim. It is Title Case, or a whole sentence with its full stop: "One Cache, Every Build" or "One cache, every build.", never "One cache every build".
- Headings have two parts where they can: a plain lead and an italic turn in the tint that lands the point. "Half of every build *is a download.*", "Small to run, *quick to undo.*" Reading the headings alone gives the argument.
- The lede is one or two short sentences, under about 40 words, saying what hurts and the idea. A reader who stops after the first screen has the whole idea.
- Each part opens with one to three sentences that make its point. More goes in a fold whose summary is the reader's own question ("Why not cache inside each runner").
- One idea a sentence. Colons, semicolons and stacked clauses that pack three facts into a line get split.
- Cut, do not add. A rewrite longer than what it replaced is probably wrong. Figures carry the explanation; words caption them.

## The Walk, by Kind of Page

Each part answers the question the one before it raised. Use these as starting orders and drop any part with nothing true to say.

| Kind | Parts, in order |
| --- | --- |
| Proposal or design | The problem; the idea; how it works; what it costs; the evidence; where it stands; still open |
| Decision | The question; the options; how they compare; the recommendation and why; what it costs; who decides and when |
| Review, concluded work | What it was; what it found; where it went; what stayed behind |
| Incident | What happened; who was affected; why; what fixed it; what changes now |
| Status overview | Where it stands; what moves next; each item and what it waits on; this week |
| Learning guide | The picture in one figure; then one idea a part, each building on the last; a check at the end |

Name parts with a plain label ("02 / The idea") above a heading that says the part's point, never a heading that only names the topic ("Architecture"). The label's words are the part's stop on the route too, so keep them to one or two words.

## The Brief

The memo head ends in a brief: two to five lines that a reader acting on the page needs before anything else, each a mono label and a few plain words. Pick from Status (a state chip and what it means), Asking (what the reader is asked to do, and by when), Owner, Next (the next move and its date), Blocked (what, and on whom) and Updated (one true date). The brief never repeats the lede; it says what the lede leaves out. A page with nothing to ask and no state, such as a guide, says what it covers and how long it takes to read.

## Say What Is True Now

- The present, not the history. The page says where things stand, never how the page or the work got there. Superseded ideas leave the page; a changelog, if any, sits at the end, grouped by day, newest first, each day folded.
- Every number has its meaning first, then the number, then what it is compared with: "a typical build with the cache, down from nine minutes" beside 4:40. A number with no comparison is noise.
- Be honest about what is unmeasured, early or broken. A part called "What it costs" or "Still open" earns more trust than any claim.
- Every part agrees with every other. Take facts from one source so a status changed in one place changes everywhere, and check each date, status and number against its source before publishing.
- One true "updated" date, in the standing line, for when the facts last changed, not when the page was last deployed.

## A Proposal States Its Case

- Say the desired outcome, summarize the recommendation, then build the case.
- Never pose the owner's decisions as questions. Say what was decided and why; leave as open only what is open, and for each open item say what would settle it.
- Data supports the story; it does not lead it. A table of results without a sentence saying what it shows is a fact dump.
- Quote people fairly and short, by name or role, and show a cut with an ellipsis of three full stops.

## Nothing the Reader Cannot Open

- No private references: internal ids, task or thread ids, file paths on someone's disk, scratch branches, or the agents' own codes and metaphors.
- Say what the evidence is, in words: "production metrics, 4 November", "a load test on a full-size copy". Sources go in a quiet `.source` line under the part, never in the sentence.
- Link only where a reader can follow. For deeper detail, publish a clean write-up and link that.
- People by name; agents never. When the page speaks for the user, it says "I".

## Words in an Interface

- Every label, empty state, error and prompt is written as carefully as the prose.
- Buttons are Title Case; headings and navigation are sentence case, like the page; messages are sentences with their full stop.
- One name for each thing everywhere: the same word in the list, the drawer, the keys and the docs.
- An error says what happened and what to do, in words people will paste into a search or a chat.
- Nothing nags: no "don't forget", no badge pleading for attention.

## Checking the Words

Before publishing, give each part to three cold readers who were not there, real people or fresh agents: one who knows the field, one who does not, and one skimming in a hurry. Each says in one sentence what the part means and marks every place they stumbled. Rewrite until all three get it right on the first read. Readers find words; they do not find space, rhythm or craft, so this never replaces looking at the page.
