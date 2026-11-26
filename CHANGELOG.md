# Changelog

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
