# Fish & Partners Wealth Management

A Bloomberg-terminal-style gold analytics addon for World of Warcraft: Forever.

## Install & update (Windows, one click)
1. Download **[Update-FishPartners.bat](https://github.com/Butker/FishPartners/raw/main/tools/Update-FishPartners.bat)** once, and keep it somewhere permanent (for example in Documents).
2. Double-click it. It finds your WoW Forever folder (or asks you once), downloads the newest version from GitHub and installs it. Your settings and data are never touched.
3. The first time, it asks whether to check for updates **automatically at every Windows login**. Say yes and you never have to think about it again.
4. Run it any time to update. If the game is open, type `/reload` afterwards.

If Windows SmartScreen warns about the file, click **More info → Run anyway** (it's a plain script; you can open it in Notepad to read it).

**In game:** when someone in your guild or group has a newer version, you get an *UPDATE AVAILABLE* notice. `/fp update` shows the download link.

## Install manually
1. Unzip so you get the folder `FishPartners` (containing `FishPartners.toc`).
2. Move it to `World of Warcraft/_forever_/Interface/AddOns/`
   (whichever folder your Forever install uses for AddOns).
3. Restart the game or `/reload`. If it shows as "out of date", tick **Load out of date AddOns**.

Auctionator is optional but recommended. Without it everything is valued at vendor price.

## Open it
- `/fp`, or left-click the fish on the minimap.
- Right-click the minimap fish to start or pause a session.
- Type functions in the `FPWM>` command line at the bottom: `PNL`, `AUM`, `GL`, `CMPL`, `START`, `PAUSE`, `STOP`, `MTM`, `HELP`.

## Modules
| Key | Code | Module | What it does |
|---|---|---|---|
| 1 | PNL | **Intraday P&L** | Session tracker. Realized = raw coin looted. Unrealized = looted items marked to market. Gold/hour, holdings, loot tape, cumulative P&L chart, booked-session archive. |
| 2 | AUM | **Net Worth** | Cash + bags + bank + mail + AH listings (marked to market) for every character. Daily-close history chart and allocation per character. |
| 3 | PORT | **Portfolio** | Every item on every character (bags, bank, mailbox, AH listings) with avg cost, market price, cost basis and unrealized P&L. Click a row to set your buy price. |
| 4 | RPT | **Report** | AH proceeds, average profit per sale, sell-through, AH costs, top earners, and per-item auction performance with signals (HOT / CUT PRICE / NO BID). |
| 5 | GL | **General Ledger** | Every change to your gold, categorised: AH purchase / sale / deposit / outbid refund, vendor sale / purchase, repairs, loot, quests, mail, trade, flights, training. Filter by time, category and character. |
| 6 | CMPL | **Risk & Compliance** | Settings. |

## Valuation policy
1. Quest items aren't tracked. Containers (clams, lockboxes) count as 0 until opened. Soulbound / BoP items → vendor price.
2. Thin markets are capped: an AH price can be at most 3× its recent median, or 50× vendor when there's no history yet. AH prices older than 7 days (adjustable) are marked stale.
3. Otherwise read Auctionator's last scan price.
4. Use the AH price only if it beats vendor by:
   - **Weapons & armor:** 10% (adjustable)
   - **Everything else:** 5% (adjustable)
5. Optional: deduct the 5% AH cut before comparing.
6. In a session, disenchanting / prospecting / milling is a swap: the input leaves, the result is added.

## Party view (PNL → PARTY)
- **Party book:** everyone in your group with their item fills, item value, coin share, total, share of the party total, and gold per hour. Click a member to see what they've looted. The party tape shows every fill in the group as it happens.
- **Items** are tracked from the game's loot messages and valued with your pricing rules.
- **Coin (estimated):** the game doesn't show other players' coin, but group coin is split evenly, so each member's share is your share while they were in the group.
- **FP tag:** the member also runs Fish & Partners. Your addons quietly share session totals, quests included, so you can hover them for their exact numbers.
- If a member's loot doesn't show up, type `/fp partydebug`. Every party loot line is then echoed with what the addon did with it (booked, not a loot line, looter not in group). Send me that output.
- **House rules:** when other members also run Fish & Partners (2.1+), every desk in the group uses the same rules (gear +10%, other +5%, no AH cut, quest gold counts) and the newest AH scan in the group for every drop, so your party numbers agree. A small bell announces it. `/fp rules` shows the status; turn it off on the Compliance tab.
- Members who leave stay on the board marked "left", and their coin share stops growing. Booked sessions keep a party summary.

## Mini session window
- When you start a session, a small window opens. It shows how long the market has been open, gold per hour, session P&L, coin vs items, and your last 4 fills.
- Its buttons are **PAUSE/RESUME**, **TERMINAL** (opens the full PNL page) and **BOOK** (stop and archive). **x** hides it while the session keeps running.
- Drag it anywhere. Drag the bottom-right corner to scale the whole window, text included, from 60% to 250%. Right-click the corner to reset it to 100%. Position and scale are remembered. Type `/fp hud` to show or hide it. Its scale and auto-open setting are on the Compliance tab.

## Opening bell
- When you enter a dungeon or raid, a pop-up asks:
  - **No session running:** *OPENING BELL — New market: Deadmines.* Choose **OPEN SESSION** or **STAY FLAT**.
  - **Session running:** *PORTFOLIO REBALANCE — New venture.* It shows your session's time, P&L and gold per hour. Choose **BOOK & OPEN NEW** or **HOLD POSITION**. If the session is paused you also get **RESUME CURRENT**.
- Re-entering the same instance within 15 minutes doesn't ask again (corpse runs, porting out). An instance reset always counts as a new run. `/reload` never triggers it.
- Turn it off on the Compliance tab. `/fp bell` shows it on demand.

## Cost basis (Portfolio)
- **Manual:** click any position and enter your buy price (`2g 50s`, `2.5` or `75s`) and how many units it covers. Example: 20 mats worth 1g each, marked at 2g = **-20g unrealized**.
- **Automatic:** AH buyouts, won bids and vendor purchases update a weighted average.
  Holding 20 @ 2g and buying 10 @ 1g gives 30 @ 1.67g.
- **Sales** book realized P&L against the average. Selling doesn't change the average.
- **Sold out, then rebuy:** once you hold 0, the next buy starts fresh at what you actually paid.
- **Looted or crafted units** stay "uncosted" (shown with `~`), so they don't drag your average down. *BASELINE UNCOSTED @ MKT* gives every uncosted item today's market price as its basis.
- Items mailed or traded to your own alts keep their buy price. Items you sell, trade away, use, equip or destroy reduce the units covered.
- **Unexplained:** if items vanish and the addon doesn't know why, they keep their buy price and go to the **UNEXPLAINED** list. Click an entry for "used up", right-click for "keep". Items that reappear are matched automatically.
- Visit your bank once on each character so the portfolio is complete.

## Portfolio views
- **ALL CHARS:** every item combined across characters.
- **BY CHAR:** one foldable group per character, with that character's market value, cost and P&L on the group row. Click a character to fold it out, or Shift-click to fold all in or out. Your current character starts unfolded.
- **THIS CHAR:** only the character you're logged in on.
- A buy price applies to all characters. In BY CHAR it is split in proportion to the units each character holds, so the groups add up to the ALL CHARS totals.

## Hiding items
- **Ctrl-click** a position to hide it: gear you're wearing or swapping, junk, hearthstones. Hidden items are dropped from the Portfolio, from Net Worth inventory value and from the ticker, on every character.
- Switch the Portfolio view to **HIDDEN** and Ctrl-click an item to restore it.

## Auction house features
- **Quest gold** counts toward session P&L by default (it can be switched off on the Compliance tab).
- **Profit on sale:** collecting an AH sale prints a line like `SOLD 5x [Thorium Bar] for 7.00g · +1.00g realized (+16.7%)`.
- **Expired tracking:** expired-auction mails are counted, which feeds sell-through % and the "doesn't sell" signals.
- **Morning report** in chat on your first login each day. Type `REPORT` in the command line to show it again.
- **Ledger:** right-click an entry to change its category or delete it.

## Troubleshooting
- Type `/fp check` to run the self-checks (gold balance, session, cost basis, inventory). They also run on their own after login and every hour, and say something only when there's a problem.
- Type `/fp diag` and send the output. It shows which AH API your client has, which AH events the addon has seen, whether it can read your sell slot, and any recent errors.
- If a page hits an error, it now shows the error text at the bottom instead of going blank.

## Notes
- Developers: `pip install lupa` then `python tests/run_all.py` runs every scenario against a simulated game.
- Sessions pause automatically on logout. After a `/reload` (under 5 min) they resume automatically.
- AH buys are logged when you click buy (this also works with Auctionator's buy buttons). AH sales are logged when you collect the money from the mailbox.
- Bank value updates each time you open your bank.
- Hover any row for details. Shift-click an item row to link it in chat. Right-click a character in AUM to remove it.
