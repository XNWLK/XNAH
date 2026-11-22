-- The guide: a window that explains every page of XNAH in plain words - what the numbers mean, what needs a click and
-- why, what is only an estimate, and how to use each page to make gold.
--   X.ShowGuide(page) opens it (page = number or key, e.g. "deals"; nil = the page shown last).
--   X.GuidePages() returns the pages: {{key, title, tab, text}, ...} (tab = the XNAH tab the page is about, or nil).
-- First time: shown by itself about 4 seconds after logging in; XNAHDB.guideSeen is set (to the version) when it is
-- closed. After that it only comes at login when "Show this guide when I log in" is ticked (setting guideAtLogin).
local ADDON, X = ...
local K = X.K

local W, H = 760, 520
local LIST_W = 180          -- the list of pages on the left
local RX = LIST_W + 20      -- where the page area starts
local GOLD, GREY = "|cffe6b422", "|cff999999"

-- ticked at first (shown until seen); the first time the guide comes by itself it is unticked, so it does not come
-- back at every login unless you tick it
X.Default("guideAtLogin", true)

-- [[ the pages ]]
local function h(t) return GOLD .. t .. "|r" end
local function g(t) return GREY .. t .. "|r" end
local function lines(...) return table.concat({...}, "\n") end

local PAGES = {
	{key = "welcome", title = "Welcome", text = lines(
		"XNAH keeps the price of everything on your auction house, day after day, and shows you where the gold is: " ..
		"what is listed too cheap, what sells for more than it costs, when to sell and when to wait.",
		"",
		h("Quick start"),
		"1. Talk to an auctioneer. A small XNAH bar appears on top of the auction house window.",
		"2. Press Full scan on that bar. XNAH reads every auction at once (a bar shows how far it is). The server " ..
		"allows one full scan about every 15 minutes - do one every time you visit the auction house.",
		"3. Type /xnah (or click the gold coin at the minimap) and look at the Deals page: it lists " ..
		"what you can buy cheap and sell for more. Most of them need a few days of prices, so scan once a day.",
		"4. Star the items you care about: right-click an item in any list, then Add to watch list. Starred items " ..
		"can be searched any time (no 15-minute wait), and the sniper can watch them for you.",
		"5. Use the Sell page to post your items at a good price, and the Buy page to buy from shopping lists.",
		"",
		h("Moving around"),
		"- The tabs at the top of the XNAH window are the pages. This guide has one part for each.",
		"- Click an item to open its Item page. Right-click it for a menu (watch list, search it now).",
		"- Hold the mouse over an item to see its tooltip with XNAH's prices.",
		"- Click a column title to sort by it; click it again to sort the other way. The mouse wheel scrolls. " ..
		"XNAH remembers how you sorted each list, and the Market page's search and filters, for next time.",
		"- Find (top right): type an item or recipe name and pick it. From anywhere in the game: Alt-click an item " ..
		"in your bags, a link in chat or a loot window to open its XNAH page.",
		"- Right-click a column title (or an item, in most lists): Copy this list as text - for a spreadsheet or notes.",
		"- Drag the bottom right corner to make the window bigger or smaller (text too); right-click it for the " ..
		"normal size. Or type /xnah size 120.",
		"- Prices in " .. g("grey") .. " are old (from a scan more than 3 days ago). Gold, silver and copper are " ..
		"shown as 12g 34s 56c.",
		"",
		h("The guide itself"),
		"- Previous and Next walk through the parts; the list on the left jumps to one.",
		"- Open this page closes the guide and opens the XNAH page it talks about.",
		"- /xnah guide brings the guide back any time.",
		"",
		h("One thing to know first"),
		"The game lets an addon post, buy, cancel or craft only when you click a button. XNAH never does these by " ..
		"itself: one click of yours = one step. Everything else (scanning, working out prices, searching) it does alone.")},

	{key = "home", title = "Home", tab = "home", text = lines(
		"Home is the first page: what to do today.",
		"",
		h("The cards on top"),
		"The gold of all your characters (and how it changed today and this week), what your sales brought today " ..
		"and in the last 7 days, your net worth, and your last full scan. Click a card for the page with the details.",
		"",
		h("What to do today"),
		"Your to-do list, most urgent first: expired auctions to collect or post again, undercut auctions, watched " ..
		"items under your max price, deals, what your strategies found, your crafting queue, shopping lists, things " ..
		"in your bags worth selling, and an old scan.",
		"Each job has one button. It opens the right page, or starts a scan when the auction house is open. It never " ..
		"buys, posts or cancels by itself.",
		"",
		h("Good to know"),
		"- Sales come from your auction house mails, so open your mailbox now and then.",
		"- The gold change counts from the first time XNAH sees each character's gold on a day.",
		"- XNAH opens on Home the first time each session; untick the box at the bottom right to stop that.")},

	{key = "scanning", title = "Scanning", tab = "scan", text = lines(
		"XNAH learns prices in three ways. All of them need the auction house window to be open.",
		"",
		h("1. Full scan"),
		"- Reads every auction on the auction house at once, then works out the prices of every item.",
		"- The server allows it about every 15 minutes. Until then the button shows " .. g("Ready in 12:34") ..
		" counting down.",
		"- Start it with Full scan on the bar above the auction house window, on the Settings page, or with /xnah scan.",
		"- XNAH reads it in small parts so the game never freezes. It can take a little while on a big auction house.",
		"- Items that were listed before but are gone now count as sold out (" .. g("none listed") .. ").",
		"- Tip: on the Settings page you can tick \"Start a full scan by itself when the auction house opens\".",
		"",
		h("2. Using the auction house normally"),
		"- Everything the auction house shows you is recorded too: the lowest price and how many are listed from " ..
		"a list of search results, and the full list of one item when you open it.",
		"- So prices of what you look at are always fresh, even between full scans.",
		"",
		h("3. Watch list scan"),
		"- Searches your starred items one by one. Any time - no 15-minute wait.",
		"- Start it with Watch list on the bar, Scan watch list on the Settings page, or /xnah watch.",
		"- Other buttons do the same for a few items: Search on the auction house (Item page), Search these on the " ..
		"AH (Deals page), Search reagents (Crafting page).",
		"",
		h("The price check message"),
		"After your first full scan, open one stackable item on the auction house (cloth, herbs, ore). XNAH compares " ..
		"what the full scan said with what the game shows and tells you in chat:",
		"- " .. g("price check passed") .. ": all is right, nothing to do.",
		"- A yellow " .. GOLD .. "price check:|r message: the full scan gave the price of one item where XNAH expected " ..
		"a whole stack (or the other way round). XNAH has fixed it for the next scans. Run a new full scan. If the " ..
		"prices of the last scan look wrong, /xnah forget deletes this realm's price data (it asks first).",
		"",
		h("Names filling in"),
		"Right after a scan many items are shown as " .. g("item 12345") .. ": the game has not loaded them yet. XNAH " ..
		"takes the names from the item links and loads the rest in the background, a few at a time. Give it a few " ..
		"minutes - nothing to click.",
		"",
		h("How long prices are kept"),
		"Every scan is kept for 7 days, then one price a day; after 60 days one a week, for a year. You can change " ..
		"this on the Settings page.")},

	{key = "ahwindow", title = "In the auction house window", text = lines(
		"XNAH also works inside the game's own auction house window.",
		"",
		h("The panel beside the window"),
		"Click an item in the game's auction house list and a panel beside the window shows XNAH's numbers for it: " ..
		"lowest price, market value, averages, trend, how many sell a day, vendor and crafting prices, how many you " ..
		"own, and a small graph of the last 30 days. Picking an item from your bags to post shows it there too.",
		"Buttons: open the item in XNAH, add it to the watch list, or set the highest price you would pay. " ..
		"Hide tucks the panel away; a small XNAH button beside the window brings it back.",
		"",
		h("Extra columns"),
		"The game's lists get " .. g("% usual") .. " (the price now against the usual price: green = cheaper than " ..
		"usual, red = dearer) and " .. g("a day") .. " (how many sell a day). The check box at the bottom of the panel " ..
		"turns them off.",
		"",
		h("The bar on top"),
		"Full scan, Watch list, XNAH (opens this window) and Next step (the one-key routine, see Sell).",
		"Search on the auction house (item page, or right-click an item) also opens the item in the game's window.")},

	{key = "market", title = "Market and Item pages", tab = "market", text = lines(
		h("The Market page"),
		"Every item ever seen on this auction house, in one list. Type in Search (a name or an item number) and " ..
		"use the buttons next to it: All, Watch list, Listed now, Can be crafted, Quality, Rising and Falling.",
		"- Rising / Falling: only items whose price went up (or down) over the last two weeks, fastest first: sell " ..
		"into a rise, wait out a fall.",
		"- The 7 days column: a small line of each item's price over the last week (green up, red down).",
		"- Sells a day: about how many sell in a day (an estimate from two full scans - see Good to know).",
		"- Lowest: the cheapest one listed at the last scan. Market: the market value - the average of the cheapest " ..
		"part of the listings, so one silly price hardly moves it. Trend: % per week. Seen: " .. g("grey") .. " = old.",
		"At most 2,000 rows are shown at once - search to narrow it down. Sorting goes through all of them.",
		"",
		h("The Item page"),
		"Everything about one item. Type a name in Find item, or click any item anywhere. Back goes to the item before.",
		"- Buy: buys what is listed at or under the fair price to buy (first click checks the price, then buy, then " ..
		"confirm for stackable things).",
		"- Search on the auction house (auction house open): looks it up now.",
		"- Watch list: watch list on / off, the highest price to pay (or the fair price to buy), the shopping list.",
		"",
		h("The numbers (left)"),
		"Ten plain rows: Lowest now (" .. g("a good price") .. " when it is at or under the fair price to buy), Usually " ..
		"sells for (the 30-day average), Fair price to buy, Fair price to sell, Sells a day, Listed now (fewer or more " ..
		"than usual), Price trend, Vendor pays, You own (all your characters here), Seen.",
		"- Fair price to buy: over the last 14 days it was listed this cheap or cheaper about 1 time in 4. Fair price to " ..
		"sell: its usual market value in that time. Both show as thin flat lines on the graph.",
		"- More numbers: averages, 30-day low and high, trend, day-to-day spread, supply, vendor price, disenchant " ..
		"value, your trades, strategies.",
		"",
		h("The graph (right)"),
		"Pick 1 day, 7 days, 30 days, 90 days or All. Yellow line = market value, green line = lowest price, blue " ..
		"bars = how many were listed. Move the mouse over it to read the values of that moment.",
		"- Your own sales (orange) and buys (violet) are dots at the price you got or paid for one.",
		"- Click a name under the graph to hide or show that line, the dots or the fair prices.",
		"- Compare: a second item's market value in cyan (on its own scale when the prices are far apart).",
		"- Best time: the price by weekday and by hour of the day (server time), and when your own sales did best.",
		"",
		h("Ways to make gold with this item"),
		"Up to three real chances, worked out at the fair price to sell after the cut. Ideas that need buying right " ..
		"now only show with fresh prices.",
		"",
		h("Crafting and Used in (bottom)"),
		"The recipe that makes the item (the cheapest), who knows it, each reagent with its price and where to get it " ..
		"cheapest, and the cost to make one. Used in: every recipe that needs this item - hover one to see the whole " ..
		"recipe with prices, click it to open what it makes. XNAH knows every recipe of the game.")},

	{key = "tooltips", title = "Tooltips", text = lines(
		"Every item tooltip in the game (bags, bank, chat links, the auction house) gets a few XNAH lines:",
		"",
		"- The first line: how many are listed and when that was seen. " .. "|cffff8040(old)|r" .. " = the price " ..
		"is more than 3 days old.",
		"- Lowest price and Market value (see the Market page).",
		"- 7-day average with the trend per week, and the 30-day average.",
		"- Sells per day: about how many sell in a day (an estimate).",
		"- You: what you sold and bought of it, and at what price (from the Gold page).",
		"- Vendor pays, and Vendor sells at (when a vendor you visited sells it).",
		"- Crafting cost, with the profit in green (or the loss in red).",
		"- Disenchant value: what its disenchanting materials bring on average.",
		"- Items a strategy found (Deals page, Adjust ideas, Mark on tooltips) are marked too.",
		"",
		h("A stack in your bags"),
		"For a stack, the prices are for the whole stack, with " .. g("(... each)") .. " for one. The XNAH line shows " ..
		"the stack size, e.g. " .. GOLD .. "XNAH|r " .. g("x20") .. ".",
		"",
		h("Too much?"),
		"On the Settings page, under Item tooltips, you can turn the XNAH lines off, or only some of them (vendor prices, " ..
		"crafting, averages, the stack size).")},

	{key = "deals", title = "Deals and ideas", tab = "deals", text = lines(
		"Everything XNAH found to make gold right now, in one place. The buttons on top switch between Buy ideas, " ..
		"Sell ideas and Make ideas; Adjust ideas is on the right.",
		"",
		h("Buy ideas"),
		"Everything worth buying right now in one list, best first (most profit in all). Each row says which idea " ..
		"found it and why, and has a Buy button: click to check the price, again to buy (stackable things ask once " ..
		"more to confirm). " .. g("+2") .. " after the idea = two more ideas found it too.",
		"- Hide items that sell under N a day: leaves out slow sellers (unknown speed is shown).",
		"- Search these on the AH, Add to shopping list, Snipe at this price: for the whole list.",
		"- Right-click a row: Never suggest buying this (it never shows up again; Settings lists them).",
		"",
		h("Sell ideas and Make ideas"),
		"Sell ideas are about what you have (sell now, hold); the best time to post is shown there. Make ideas are " ..
		"crafting, recipes worth learning, cooldown crafts and what to gather.",
		"",
		h("Adjust ideas"),
		"Every idea in Buy, Sell and Make groups: switch one in or out of the lists (Use in the lists), change its " ..
		"numbers, read how it works and what it finds right now. Reset numbers puts them back. Mark on tooltips " ..
		"marks the items an idea finds on their tooltips.",
		"",
		h("The ideas"),
		"- Vendor floor: listed under what a vendor pays. Buy, sell to a vendor. No risk.",
		"- Buy the dip: far under its usual price for now. Buy, sell when it is back.",
		"- Undercut gaps: a few cheap ones, then a big jump in price. Buy the cheap ones, list just under the next.",
		"- Market resets: buy everything listed cheap, list it again at the usual price.",
		"- Momentum: the price is climbing. Buy early, or sell what you hold while it rises.",
		"- Sell into scarcity: far fewer listed than usual. List yours now, buyers have little choice.",
		"- Hold in a flood: far more listed than usual. Wait before you sell.",
		"- Crafting margin: recipes that sell for more than their reagents cost.",
		"- Disenchant: gear that brings more as materials than it costs.",
		"- Vendor flips: buy from a vendor, sell on the auction house.",
		"- Volume flipping: items that sell many a day; small profit each, many times.",
		"- Time-of-day cycles: items cheaper at some hours than at others. Buy low, sell high in the same day.",
		"- Weekday cycles: items dearer on some days (raid days for consumables). Buy on the cheap day, sell on the dear one.",
		"- Steady earners: steady price and steady sales - good to keep posting again and again.",
		"- Falling knife (sell): you own it and its price keeps dropping - sell before it falls further.",
		"- Price spike (sell): you own it and it sells far over its usual price right now - sell into the spike.",
		"- Recipes worth learning: recipes none of your characters has whose item sells well over its cost, by profit a day.",
		"- Cooldown crafts: transmutes, Mooncloth and other crafts with a waiting time. Do them every time the wait is over.",
		"- What to farm: herbs, ore, cloth, leather and other gathered things, by the gold they bring a day.",
		"- Stock up at a low: sells steadily and sits near its lowest price of the month. Buy now, sell when it climbs back.",
		"",
		h("The risk"),
		"Profit is worked out from the prices of the last scan and the usual price of the item. Others can buy " ..
		"first, undercut you or flood the market. Low risk = it worked for a long time; high risk = few days of " ..
		"data, a jumpy price or slow sales. Start small with a new strategy.")},

	{key = "craft", title = "Crafting and the queue", tab = "craft", text = lines(
		h("Recipes"),
		"XNAH knows every recipe of the game. Open your profession windows on each character so it knows which ones " ..
		"your characters have (tick " .. g("Only recipes my characters know") .. " to see just those). The Crafting page lists every recipe with:",
		"- Cost to make: every reagent bought the cheapest way (vendor, auction house, or crafted). A grey " ..
		g("?") .. " = a reagent has no price yet, so the cost is too low.",
		"- Sells for (after cut), Profit, Margin %, how many are listed, and which characters know it.",
		"- A green " .. "|cff4ade80Q|r" .. " = it is in the crafting queue.",
		"- \"Only recipes my characters know\" and the Profession button narrow the list.",
		"",
		"Click a recipe to see its reagents below. Buttons there: Open item, Search reagents (live prices, auction " ..
		"house open) and the queue controls.",
		"How to use it: sort by Profit, check Listed and the Item page (does it sell?), then queue it.",
		"",
		h("The queue"),
		"Pick a mode, type a number, press Add to queue:",
		"- Restock: keep this many. XNAH counts what you have in bags, bank, mail, on the auction house and on " ..
		"your other characters, and only the rest is crafted.",
		"- Craft x times: craft it this many times.",
		"",
		"The Queue view (button at the top) shows each recipe with its target, what you have, what is left to " ..
		"craft and the profit. - and + change the number (Shift: by 10), x takes it out.",
		"- Materials for the queue: what to buy, minus what you own, and from where.",
		"- Send to shopping list: puts every reagent to buy (not the vendor ones) on the shopping list \"Crafting " ..
		"queue\", at most 120% of its current price. Buy them on the Buy page.",
		"- Craft next: open your profession window, then one click starts the next recipe you can make now.",
		"",
		"The game lets an addon craft only on a click: each Craft next is one click of yours.")},

	{key = "sell", title = "Sell", tab = "sell", text = lines(
		h("Worth posting"),
		"Your undercut auctions first, then everything in your bags that can go on the auction house, with XNAH's " ..
		"price. What is worth posting (it brings more than a vendor pays) is ticked; untick what you want to keep - " ..
		"XNAH remembers it.",
		"- Post next (or your key) does one step per press: cancel an undercut auction, then post the ticked items, " ..
		"most valuable first. If the game warns about a price, press again to post anyway, or Skip.",
		"- Set the key in the game's key bindings, under AddOns, XNAH: " .. g("One-key routine: next step") .. ". It " ..
		"works only while the auction house is open. Next step on the bar above the auction house window does the same.",
		"- XNAH checks your auctions by itself when the auction house opens (at most every 5 minutes).",
		"",
		h("Undercut auctions"),
		"Your auctions where someone sells for less, with the time left and what cancelling costs (the deposit is not " ..
		"paid back). Cancel them one by one; the items come back by mail - post them again.",
		"",
		h("Post by hand"),
		"Your own price, amount and duration (2h / 8h / 24h), one auction per click, and each item's price rules, " ..
		"which Post next uses too:",
		"- Floor %: never under this % of the usual price, or under the crafting cost when known.",
		"- Ceiling %: never over this % of the usual price.",
		"- Undercut by: how much under the cheapest other seller (empty = the smallest step).",
		"- Normal: the price when nobody else sells it (empty = the usual price).")},

	{key = "buy", title = "Buy", tab = "buy", text = lines(
		h("Best buys"),
		"What is worth buying right now. Your shopping lists and watched items under your max price come first, then " ..
		"the best ideas and deals.",
		"- Each row has a Buy button: the first click checks the live price (it buys nothing), the next one buys; " ..
		"stackable items ask for the exact price first, so they need one more click to confirm.",
		"- The Next buy key (key bindings, AddOns, XNAH: " .. g("Next buy: next step") .. ") does the same for the best " ..
		"buy, one step per press, then moves on. Skip leaves a buy out for 10 minutes.",
		"- Right-click a row: Never suggest buying this.",
		"",
		h("Shopping lists and sniper"),
		"- New list makes a list; add items with how many to buy in all and the most to pay for one. Buy goes through " ..
		"the list one item at a time.",
		"- The sniper watches your watched items with a max price while you are at the auction house and tells you " ..
		"when one is listed at or under it.")},

	{key = "gold", title = "Gold", tab = "gold", text = lines(
		"What you earn on the auction house (read from its mails when you open your mailbox) and what you own. Four " ..
		"views: Overview, By item, Recent, Characters.",
		"",
		h("Overview"),
		"- Income, spent, the auction house cut and profit for 7 days, 30 days and everything.",
		"- Auction house time: how long its window was open. Gold per hour: the profit divided by those hours.",
		"- Profit per week: one bar a week, green for a profit and red for a loss. Hover a bar for its numbers.",
		"- Your flips: items you bought and later sold. Profit of one = the sale after the cut minus what you paid " ..
		"(oldest purchase first). Best first, worst last.",
		"",
		h("By item and Recent"),
		"Every item you sold or bought with its totals, and the newest sales, purchases and expired auctions one by one.",
		"",
		h("Characters"),
		"Gold, bags, bank, mail and auctions of each of your characters (also your other accounts after Sync " ..
		"accounts), your net worth over time, and what to do with each thing in your bags.")},

	{key = "settings", title = "Settings", tab = "scan", text = lines(
		"Settings opens from the Settings button in the title bar.",
		"",
		h("Scanning"),
		"The box on the left: whether the auction house is open, Full scan (or the countdown), Scan watch list, " ..
		"Stop, a progress bar, and the last full scan. Below: the last 10 scans on this realm.",
		"",
		h("Mailbox"),
		"- At a mailbox, Open all auction mail (above the game's mail window) takes the gold and items of every " ..
		"auction house mail (sold, bought, expired, cancelled, outbid), one after the other, and writes them in the ledger.",
		"- Mails from players, cash on delivery and Game Masters are never touched. It stops when your bags are full " ..
		"(gold is still taken); click it again to stop.",
		"- The Mailbox box here switches the button on or off and shows what it took last time.",
		"",
		h("Settings"),
		"- Price used for costs and values: market value (best for most), lowest price, or an average (steadier, " ..
		"but slow to follow a change).",
		"- Auction house cut: 5% (what the auction house keeps of a sale).",
		"- Prices count as old after 72 hours: old prices are shown dimmed and not used for deals.",
		"- Deals and trends need 3 days of price history per item.",
		"- How long every scan and the daily prices are kept.",
		"- Use vendor prices for crafting reagents (when a vendor is cheaper).",
		"- Start a full scan by itself when the auction house opens.",
		"- The XNAH bar on the auction house window, the minimap button, debug messages.",
		"- Item tooltips: which XNAH lines to show.",
		"",
		h("Other"),
		"- Delete this realm's data: starts this realm's price history over (it asks first, and it cannot be undone).",
		"- Minimap button: left-click opens XNAH, right-click opens Settings, drag it to move it.",
		"- Key bindings (AddOns, XNAH): Open / close XNAH, One-key routine: next step (posting), Next buy: next step.")},

	{key = "good", title = "Good to know", text = lines(
		h("Silly prices"),
		"- Sometimes someone lists an item for a silly price, or a scan sees only a few silly listings. A price more " ..
		"than 4 times above or below the item's typical price is left out of its history, averages and graph, so it " ..
		"never makes a normal price look like a bargain. If three scans in a row show the new price, XNAH takes it as " ..
		"a real change.",
		"- Grey (junk) items are never suggested as buys to sell again - only to sell to a vendor when they are " ..
		"listed under what a vendor pays.",
		"- Right-click any item: Never suggest buying this. It no longer shows up on the Buy page, in deals or " ..
		"strategies. Settings lists them (click one to allow it again).",
		"",
		h("What is only an estimate"),
		"- Sales speed (Sold/day, Sells per day, Best time to post): worked out by comparing two full scans. An " ..
		"auction that disappeared long before its time ran out counts as sold - but a cancelled one looks the same, " ..
		"so items people relist often look faster than they are. It gets better with many scans.",
		"- Disenchant values: they use the classic disenchanting chances. Forever may differ.",
		"- Profits: they assume you sell at the usual price. The market may move before you do.",
		"- The share of the top seller is a guess when several sell at one price.",
		"",
		h("One auction house for both factions"),
		"On Forever, Alliance and Horde share one auction house, so XNAH keeps one set of prices per realm. All your " ..
		"characters on the same realm - both factions - share it, and the Gold page counts them all.",
		"- " .. g("All my characters are on one realm") .. " (Settings, on): the game does not always give the same " ..
		"realm number, so XNAH keeps one set whatever it says. Turn it off only if you have characters on several realms.",
		"",
		h("Clicks"),
		"The game allows posting, buying, cancelling and crafting only on a click of yours. XNAH prepares " ..
		"everything and one click does one step - it never does these by itself. Searches go about one a second, " ..
		"and wait while a scan runs.",
		"",
		h("Chat commands"),
		"- /xnah: open or close the window.",
		"- /xnah scan: full scan (auction house open).",
		"- /xnah watch: scan the watch list.",
		"- /xnah guide: this guide.",
		"- /xnah Linen Cloth (or a shift-clicked link): open that item's page.",
		"- /xnah raw 5: print the first auctions of the last full scan as the game gives them (to check prices).",
		"- /xnah forget: delete this realm's price data (asks first).",
		"- /xnah help: all commands.")},
}
-- page numbers by key
local INDEX = {}
for i, p in ipairs(PAGES) do INDEX[p.key] = i end

function X.GuidePages()
	return PAGES
end

-- [[ the window ]]
local frame
local current = 1

local function tabExists(tab)
	return tab ~= nil and X.UI ~= nil and X.UI.tabs ~= nil and X.UI.tabs[tab] ~= nil
end

local function showPage(i)
	i = math.max(1, math.min(#PAGES, i or 1))
	current = i
	local page = PAGES[i]
	for n, b in ipairs(frame.pageButtons) do b:SetSelected(n == i) end
	frame.pageTitle:SetText(page.title)
	frame.counter:SetText(GREY .. "Part " .. i .. " of " .. #PAGES .. "|r")
	frame.text:SetText(page.text)
	frame.child:SetHeight(math.max(10, (frame.text:GetStringHeight() or 0) + 16))
	frame.scroll:SetVerticalScroll(0)
	frame.prev:SetEnabled(i > 1)
	frame.next:SetEnabled(i < #PAGES)
	local can = tabExists(page.tab)
	frame.open:SetEnabled(can)
	frame.page = i
end

local function build()
	frame = CreateFrame("Frame", "XNAHGuide", UIParent, "BackdropTemplate")
	frame:Hide() -- hidden before any script is set (hiding it later would count as closing it)
	frame:SetSize(W, H)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetToplevel(true)
	K.Backdrop(frame, K.colors.bg)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	tinsert(UISpecialFrames, "XNAHGuide")
	-- closed (the Close button, the X, Escape, Open this page): the guide counts as seen
	frame:SetScript("OnHide", function()
		if X.db then X.db.guideSeen = X.VERSION end
	end)

	local title = K.Label(frame, GOLD .. "XNAH|r  guide", "GameFontNormal")
	title:SetPoint("TOPLEFT", 12, -10)
	local close = K.Button(frame, "X", 24, 20, function() frame:Hide() end)
	close:SetPoint("TOPRIGHT", -6, -6)

	-- [[ left: the parts ]]
	frame.pageButtons = {}
	for i, page in ipairs(PAGES) do
		local b = K.Flat(frame, LIST_W, 22)
		b:SetPoint("TOPLEFT", 10, -36 - (i - 1) * 24)
		b:SetLabel(GREY .. i .. "|r  " .. page.title)
		b:SetScript("OnClick", function() showPage(i) end)
		frame.pageButtons[i] = b
	end

	-- [[ right: the title and the text ]]
	frame.pageTitle = K.Label(frame, "", "GameFontNormalLarge")
	frame.pageTitle:SetPoint("TOPLEFT", RX + 4, -38)
	frame.pageTitle:SetWidth(W - RX - 140)
	frame.pageTitle:SetWordWrap(false)
	frame.counter = K.Label(frame, "", "GameFontHighlightSmall", "RIGHT")
	frame.counter:SetPoint("TOPRIGHT", -14, -42)
	frame.counter:SetWidth(120)
	local box = K.Panel(frame, nil, nil, {0, 0, 0, 0.25})
	box:SetPoint("TOPLEFT", RX, -62)
	box:SetPoint("BOTTOMRIGHT", -10, 42)
	local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 8, -8)
	scroll:SetPoint("BOTTOMRIGHT", -28, 8)
	frame.scroll = scroll
	local textW = W - RX - 10 - 8 - 28 -- 514
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(textW, 10)
	scroll:SetScrollChild(child)
	frame.child = child
	local text = K.Label(child, "", "GameFontHighlight")
	text:SetPoint("TOPLEFT", 2, -2)
	text:SetWidth(textW - 6)
	text:SetJustifyV("TOP")
	text:SetSpacing(3)
	frame.text = text

	-- [[ bottom ]]
	local check = K.Check(frame, "Show this guide when I log in", function(on) X.S().guideAtLogin = on end)
	check:SetPoint("BOTTOMLEFT", 10, 10)
	K.Tooltip(check, "Show this guide when I log in", "Ticked: the guide opens by itself every time you log in. " ..
		"/xnah guide opens it any time.")
	frame.check = check
	frame.closeButton = K.Button(frame, "Close", 80, 22, function() frame:Hide() end)
	frame.closeButton:SetPoint("BOTTOMRIGHT", -10, 10)
	frame.open = K.Button(frame, "Open this page", 130, 22, function()
		local page = PAGES[current]
		if not tabExists(page.tab) then return end
		frame:Hide()
		X.UI.Open(page.tab)
	end)
	frame.open:SetPoint("RIGHT", frame.closeButton, "LEFT", -8, 0)
	K.Tooltip(frame.open, "Open this page", "Closes the guide and opens the XNAH page this part is about. " ..
		"/xnah guide brings the guide back on the same part.")
	frame.next = K.Button(frame, "Next", 80, 22, function() showPage(current + 1) end)
	frame.next:SetPoint("RIGHT", frame.open, "LEFT", -8, 0)
	frame.prev = K.Button(frame, "Previous", 80, 22, function() showPage(current - 1) end)
	frame.prev:SetPoint("RIGHT", frame.next, "LEFT", -6, 0)

	frame:SetScript("OnShow", function() check:SetChecked(X.S().guideAtLogin and true or false) end)
end

-- opens the guide on a part (a number or a key like "deals"; nil = the part shown last)
function X.ShowGuide(page)
	if not X.db then return end
	if not frame then build() end
	local i = type(page) == "number" and page or (page and INDEX[page]) or current
	showPage(i)
	frame.check:SetChecked(X.S().guideAtLogin and true or false)
	frame:Show()
	frame:Raise()
end

-- [[ at login ]] the first time (XNAHDB.guideSeen not set): shown by itself; false = shown once but not closed yet
-- (a reload before closing it shows it again). After that only when the box is ticked.
X.On("XNAH_LOGIN", function()
	local db = X.db
	if not db then return end
	local show
	if db.guideSeen == nil then
		db.guideSeen = false
		X.S().guideAtLogin = false
		show = true
	elseif db.guideSeen == false then
		show = true
	else
		show = X.S().guideAtLogin == true
	end
	if show then
		X.After(4, function()
			if frame and frame:IsShown() then return end
			X.ShowGuide(1)
		end)
	end
end)
