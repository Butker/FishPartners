# Changelog

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
