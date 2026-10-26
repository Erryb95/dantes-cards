## Summary and recommendation

*This section is written by hand from the run below (seed 2026, 1000 players per cell). If you change the model or the economy, rerun and re-read it: the numbers quoted here come from the tables further down. Nothing in the game was changed; these are options for the owner.*

### What the numbers say

1. **Refunds dominate the current economy.** A pack in which every card is a duplicate refunds about **108 Obols for a 100 Obol pack** (see "Pack facts"), mostly because a duplicate legendary pays 400 and legendaries appear about once per 10.5 packs. So 85% of all the Obols a player ever holds come from refunds, and the collection "snowballs": the closer you are to done, the cheaper packs get. The quick estimate of ~700 packs to complete the collection is right, but a casual player pays for only ~110 of them out of their own wins (about 15%).
2. **Result for the current economy (A): a full playset in 38 days (casual), 15 days (regular), 6 days (grinder).** 50% of the unique cards in 5 / 2 / 1 days, 90% in 24 / 10 / 4 days, and a "competitive deck" (see proxy below) in 11 / 5 / 2 days. That is about 40 packs, 6-7 hours of play, whatever the profile. Nothing is left to chase after about five weeks, even for the casual player.
3. **The refund rate is the biggest single lever.** Halving the refunds (A4) moves the full playset to 137 / 54 / 21 days; quartering them (A5) to 186 / 73 / 28. It barely changes the time to the first competitive deck (12 / 5 / 2 days). Cutting the pack price makes things much worse (A2, 60 Obols: 10 / 4 / 2 days to everything), because the refund of a duplicate pack then exceeds its price by 80%.
4. **Crafting (Ash) removes the random tail and the snowball.** With Hearthstone ratios (B1) the full playset takes 83 / 33 / 12 days, with costs scaled to this small pool (B2) 67 / 26 / 10 days. The last legendaries stop being a lottery (all 18 legendaries after ~580 packs without crafting, ~190 with it). A player who focuses on one class and disenchants the other class gets the first good deck about 30-40% earlier (casual 10 -> 6 days for B2).
5. **Duplicate protection** for epics and legendaries has a very large effect on the collection tail (all 18 legendaries: 582 packs -> 157 packs) and almost none on the first deck.
6. **Daily quests** (C) are worth +80% Obols to a casual player but only +14% to a grinder, so they narrow the gap between profiles (full playset for casual 38 -> 21 days, grinder 6 -> 5).

### What I would do (for a single-player-first game that may get multiplayer later)

The pacing I assumed as a goal is: a first good deck within about a week or two of casual play, 90% of the cards in 1-2 months, a full playset in about 2-3 months for a casual player and not under 2 weeks for a grinder. That is my guess for a game with no ladder pressure, not something the data can decide.

1. **Fix the refunds first, whatever else is chosen.** Either halve `REFUND` (one line: 2 / 10 / 50 / 200), or, better, stop refunding Obols and turn duplicates into Ash (B). A pack of duplicates must be worth clearly less than its price (40-60%), otherwise the economy snowballs.
2. **Add crafting with an Ash currency** (B2-like costs: 30 / 80 / 250 / 700, disenchant 5 / 20 / 80 / 300). It gives players agency over the last cards, which is the main complaint of pure-pack economies, and it works unchanged if PvP arrives.
3. **Duplicate protection for legendaries (and epics)**, as in Hearthstone: cheap to implement, large effect on the frustration tail.
4. **Daily quests** if you want casual players to keep pace; the sensitivity table shows the scale (half-size quests 25 / 40 / 50 Obols + 25 for the first win of the day are enough).
5. **Candidate F** in the tables combines these with lower game rewards (win 50 / loss 10): casual 12 / 35 / 61 days to a competitive deck / 90% / full playset, regular 7 / 19 / 32, grinder 3 / 9 / 15, with 262 / 500 / 1101 Obols per day (2.6 / 5 / 11 packs). Use the second sensitivity table to slow it down or speed it up (for example win 50 / loss 10 without quests: 22 / 67 / 114 days for a casual player).
6. **For a later multiplayer mode**, the grinder earns 7x the casual player per day. Before PvP, cap or taper the Obols per day (for example full rewards for the first 10 games each day) and keep PvP rewards out of the pack economy, otherwise high-volume play dominates the collection.

### How sure am I?

Only moderately. The model uses fixed win rates and games per day, players who never quit or skip days, and a perfectly rational spender (all Obols into packs at once, sensible crafting). Real players hoard, quit and mis-craft, so real progress will be slower and more spread out; the comparison between variants should be more reliable than the absolute day counts. The "competitive deck" is a simple proxy (1 good legendary + 4 epic slots + 25 common/rare slots from the top of a class pool ranked by a crude power score), the cards are not balance-tested, and the win rate would in reality depend on the deck. The quest assumptions (play 1 / 3 / 5 games) and the 7 minute game length are guesses. Measure real play (games per day, packs per day, session length) once there are testers, put those numbers into `PROFILES` and rerun.
