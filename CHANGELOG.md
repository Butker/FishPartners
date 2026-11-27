# Changelog

## [2.1.3] — Fix: same prices for loot from before house rules
- **Fix:** items looted before house rules started (or before a friend's desk joined) kept each person's own price. Now every item already on your board and the party board is shared too, so the whole session ends up on the newest scan.
- `/fp sync` now shows the full chain for each member: what was heard (session, hello, prices…), whether their session totals arrived and are fresh enough for the FP badge, your session state, and whether house rules are on and why not.
- More forgiving name matching between desks; the party board refreshes as soon as another desk is heard.

## [2.1.2] — Fix: party sync between desks
Party sync, the FP badge and group loot rules all depend on hidden messages between your desks. 2.1.2 makes those messages much more reliable and tells you when they can't get through.

- **New `/fp sync`** shows which group members your desk hears, what was sent, and the exact reason if the game refused a message. It also pings the group, so you can see that the link works both ways. If sync doesn't work, both of you type `/fp sync`.
- **Trial and veteran accounts:** since WoW Forever 1.60.1 these can't send addon messages. The addon now detects this and tells you, instead of silently failing.
- Messages are paced under the game's limit. A loot burst used to send one message per drop and could get everything dropped, including session totals. Prices are now bundled into one message and session totals replace older queued ones.
- Group Finder groups now use instance chat, which the game requires there.
- Senders are matched to your party board reliably, including realm names with spaces.
- The FP badge also shows (in grey) for members who run the addon but have no session running.

## [2.1.1] — Hotfix: market prices
- **Fix:** Portfolio (and session) market prices could be lower than Auctionator's price. The thin-market cap from 2.0 capped items at 50× their vendor price until the addon had its own price history, and at 3× the recent median after that. Items with a small vendor price were undervalued, e.g. a 60g item shown as 49g. The cap is gone: values are Auctionator's price again.
- Unusual prices (more than 3× the item's 14-day median) are now only flagged in tooltips, never changed.
- Portfolio tooltips have a new *Market price* section: Auctionator price, vendor price, what it's valued at and why.

## [2.1.0] — House rules for groups
When you're in a group with friends who also run Fish & Partners, your party numbers now agree.

- **Same prices:** when an item drops, each desk shares its Auctionator price for it if its scan is newer than what the group already has. Everyone then values that item with the newest scan in the group. Two scans from the same day: the lower price wins. Tooltips say whose scan a price came from.
- **Same rules:** sessions switch to the house rules for the rest of the session: gear must beat vendor by 10%, everything else by 5%, no AH cut deducted, quest gold counts. Your own settings still apply to your Portfolio and Net Worth.
- **Bell:** a small *GROUP LOOT RULES IN EFFECT* notice rings when house rules start, and again when you enter a dungeon or raid with them on. The ticker shows *HOUSE RULES* while they apply.
- Loot that dropped before house rules started is re-marked, so the whole session uses the same rules.
- Type `/fp rules` to see who in your group runs the addon and how many prices have been shared. Turn it off on the Compliance tab.
- Your friends need 2.1 too. Members on older versions are valued with your own prices.
- Fix: party loot is now matched to the right member even when the game leaves out the looter's name.

## [2.0.0] — Bulletproof books
Your numbers should now be right in the tricky cases, and the addon checks its own math.

**Self-checks**
- The addon audits itself 45 seconds after login and once an hour. It checks that the ledger adds up to your real gold change, that sessions have no negative positions, and that the cost basis never covers more units than you hold. If something's off you get one chat line. Type `/fp check` to see every check.
- Saved data now has a version number, so future data cleanups run once, in order, at login.

**Pricing rules**
- Containers (clams, lockboxes, bags of loot) count as 0 until you open them. The contents count when they drop, so nothing is counted twice.
- Thin markets are capped: a single silly AH listing can't inflate your numbers. An AH price is capped at 3× its recent median, or 50× the vendor price if there's no history yet. Capped values are marked in tooltips.
- AH prices older than 7 days are marked as stale (adjustable on the Compliance tab).
- Random-suffix gear ("of the Bear", "of the Eagle") is valued and tracked per variant.

**Ledger**
- Selling several items at once (or a bag of junk) books one line per item, even when the game merges the gold into one change.
- Damaged gear sold to a vendor is matched correctly.
- AH bids, commodity buys, deposits, COD, postage, repairs, buybacks and guild bank deposits/withdrawals are matched by their exact amount.
- New categories: Guild bank in / out.
- Right-click a ledger entry to change its category (or delete it).

**Portfolio**
- Items that disappear with no known reason no longer lose their buy price. They go to a new **UNEXPLAINED** list (button next to BASELINE). Click an entry to mark it as used up, right-click to keep it. If the items turn up again (another bag, the bank), they're matched automatically.
- Trades to your own alts keep the buy price, just like mail.
- Bags aren't scanned while you hold an item on the cursor, so moving items around can't cause false changes.

**Session**
- Disenchanting, prospecting and milling are swaps: the item you used leaves the session and the result is added. No double counting.
- Opening a clam or box during a session counts its contents, not the box.
- If the game crashes, the session clock stops at the moment it last saw you instead of counting the hours you were away.
- The session pauses while you're AFK and takes the idle minutes off the clock (can be switched off on the Compliance tab).

**Tests**
- The addon ships with its test suite (`tests/`): 17 scenario files that simulate the game, including a new one covering every case above.

## [1.9.4]
- The slash command is now just **/fp** (for example `/fp`, `/fp start`, `/fp hud`, `/fp update`). The old /fpwm, /fish and /fishpartners commands are gone.

## [1.9.3]
- Quest items are no longer tracked anywhere (session loot, party view, Portfolio, net worth). They can't be sold and have no value. Quest items saved by older versions are cleaned up automatically.

## [1.9.2]
- Fix: items you post on the AH that expire or get cancelled keep their cost basis. They're counted as on their way to your mailbox until you collect them, instead of looking like they'd been used up.
- Portfolio tooltips show the item's purchase history from the ledger (date, AH or vendor, quantity, price).
- New **FROM LEDGER** button in the buy-price editor: rebuilds the average buy price from your recorded purchases. Use it to repair items that lost their cost basis before this fix.

## [1.9.1]
- Session: quest reward items (including the reward you pick) are now valued and counted, marked REWARD in the loot feed and the mini window. Only items received right at a quest turn-in count, so vendor purchases and crafted items are never mistaken for rewards.

## [1.9.0]
- New one-click updater for Windows (`tools/Update-FishPartners.bat`): finds WoW Forever, downloads the latest version from GitHub and installs it. It can also run automatically at Windows login.
- In-game update notice: copies of the addon in your guild or group compare versions, and you get a chat message (plus a ticker line) when a newer version is out. `/fpwm update` shows the download link.
- The addon version now comes from the .toc file, so it's set in one place only.

## [1.8.4]
- Party view: the selected member is highlighted, the haul panel says whose items it shows, and you can click yourself to see your own haul.

## [1.8.3]
- Party view: other players' loot is now read reliably (name links, realm suffixes, character ID matching). Skinning, mining and corpse loot are counted.
- `/fpwm partydebug` echoes every party loot line with what the addon did with it.

## [1.8.2]
- Mini session window: dragging the corner scales the whole window, text included (60–250%). Right-click the corner to reset.

## [1.8.0]
- Quest gold counts toward session P&L by default.
- New **PARTY** view on the PNL page: what everyone in your group loots, estimated coin shares, and exact totals from party members who also run Fish & Partners.

## [1.7.0]
- Opening bell: entering a dungeon or raid asks whether to open a session, or to book the current one and open a new one.

## [1.6.0]
- New mini session window: clock, gold per hour, P&L and latest fills while you play.
- Market and auction-house overlay features removed for now.

## [1.3.0]
- Portfolio: BY CHAR view with foldable characters.

## [1.2.0]
- Portfolio: Ctrl-click to hide items.

## [1.1.0]
- Portfolio tab with buy prices (cost basis), average-cost tracking and realized/unrealized P&L.

## [1.0.0]
- First release: Intraday P&L, Net Worth, General Ledger and settings.
