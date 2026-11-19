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
		"3. Type /xnah (or click the gold coin at the minimap) and look at the Deals and Strategies pages: they list " ..
		"what you can buy cheap and sell for more. Most of them need a few days of prices, so scan once a day.",
		"4. Star the items you care about: right-click an item in any list, then Add to watch list. Starred items " ..
		"can be searched any time (no 15-minute wait), and the sniper can watch them for you.",
		"5. Use the Sell page to post your items at a good price, and the Buy page to buy from shopping lists.",
		"",
		h("Moving around"),
		"- The tabs at the top of the XNAH window are the pages. This guide has one part for each.",
		"- Click an item to open its Item page. Right-click it for a menu (watch list, search it now).",
		"- Hold the mouse over an item to see its tooltip with XNAH's prices.",
		"- Click a column title to sort by it; click it again to sort the other way. The mouse wheel scrolls.",
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

	{key = "scanning", title = "Scanning", tab = "scan", text = lines(
		"XNAH learns prices in three ways. All of them need the auction house window to be open.",
		"",
		h("1. Full scan"),
		"- Reads every auction on the auction house at once, then works out the prices of every item.",
		"- The server allows it about every 15 minutes. Until then the button shows " .. g("Ready in 12:34") ..
		" counting down.",
		"- Start it with Full scan on the bar above the auction house window, on the Scan page, or with /xnah scan.",
		"- XNAH reads it in small parts so the game never freezes. It can take a little while on a big auction house.",
		"- Items that were listed before but are gone now count as sold out (" .. g("none listed") .. ").",
		"- Tip: on the Scan page you can tick \"Start a full scan by itself when the auction house opens\".",
		"",
		h("2. Using the auction house normally"),
		"- Everything the auction house shows you is recorded too: the lowest price and how many are listed from " ..
		"a list of search results, and the full list of one item when you open it.",
		"- So prices of what you look at are always fresh, even between full scans.",
		"",
		h("3. Watch list scan"),
		"- Searches your starred items one by one. Any time - no 15-minute wait.",
		"- Start it with Watch list on the bar, Scan watch list on the Scan page, or /xnah watch.",
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
		"this on the Scan page.")},

	{key = "market", title = "Market and Item pages", tab = "market", text = lines(
		h("The Market page"),
		"Every item ever seen on this auction house, in one list. Type in Search (a name or an item number) and " ..
		"use the buttons next to it: All, Watch list (only starred items), Listed now, Can be crafted, Quality.",
		"At most 2,000 rows are shown at once - search to narrow it down. Sorting goes through all of them.",
		"",
		h("The columns"),
		"- Item: a " .. GOLD .. "*|r in front means it is on your watch list.",
		"- Lowest: the cheapest one listed at the last scan (" .. g("none") .. " = none listed).",
		"- Market: the market value - the average of the cheapest part of the listings, so one silly price " ..
		"hardly moves it. This is the best guess of what the item is worth now.",
		"- 7-day avg: the average of the last 7 days.",
		"- Trend: how fast the price moved over the last two weeks, in % per week. An arrow up = rising.",
		"- Listed: how many were on the auction house at the last scan.",
		"- Vendor pays: what any vendor gives you for one.",
		"- Sold/day: about how many sell in a day (an estimate - see Good to know).",
		"- Seen: when the item was last seen; " .. g("grey") .. " = old.",
		"",
		h("The Item page"),
		"Everything about one item. Type a name in Find item, or click any item anywhere. Back goes to the item " ..
		"before. Buttons on top:",
		"- Search on the auction house (auction house open): looks the item up now.",
		"- Add to watch list: stars it.",
		"- Max price: the most you would pay for one. The sniper (Buy page) tells you when one is listed at or under it.",
		"- Shopping list: puts it on your shopping list with how many and a max price.",
		"",
		h("The number grid (left)"),
		"- Lowest now, Market value, Listed (with the number of auctions and sellers).",
		"- 3-day, 7-day and 30-day average: one value per day, averaged.",
		"- 30-day low / high: the cheapest and dearest day of the month.",
		"- Trend: % per week. Day-to-day spread: how much the price jumps from day to day. A big spread means a " ..
		"risky item - or a good one to buy on a low day.",
		"- Supply vs 7 days: how many are listed now against the usual number. Fewer than usual is good for sellers.",
		"- Sells per day (an estimate), Vendor pays, Vendor sells at (" .. g("limited") .. " = the vendor has " ..
		"only a few), Disenchant value, After the 5% cut (what a sale brings you).",
		"- Your trades: what you sold and bought (from the Ledger). Market shape: sellers and walls (see Trends).",
		"",
		h("The graph (right)"),
		"Pick 1 day, 7 days, 30 days, 90 days or All. Yellow line = market value, green line = lowest price, blue " ..
		"bars = how many were listed. Move the mouse over it to read the values of that moment.",
		"",
		h("Ways to make gold with this item"),
		"The best (up to four) ways XNAH finds, with the profit for each one: buy the cheapest and sell it again, " ..
		"buy from a vendor and sell here, buy what is listed under the vendor price, craft it, disenchant it, or " ..
		"buy all the cheap ones and relist them. " .. g("(old prices)") .. " means: scan again before you trust it.",
		"",
		h("Crafting (bottom right)"),
		"The recipe that makes the item (the cheapest one), which of your characters know it, each reagent with " ..
		"its price and where to get it cheapest (Vendor, Auction, Craft), and the cost to make one. Click a reagent " ..
		"to open its page. XNAH knows every recipe of the game, also ones none of your characters has.",
		"",
		h("Used in"),
		"Every recipe that needs this item (scroll for more). Hover one to see the whole recipe: profession and " ..
		"skill, who knows it, each reagent with its price, the cost, what it sells for and the profit. Click it to " ..
		"open what it makes.")},

	{key = "tooltips", title = "Tooltips", text = lines(
		"Every item tooltip in the game (bags, bank, chat links, the auction house) gets a few XNAH lines:",
		"",
		"- The first line: how many are listed and when that was seen. " .. "|cffff8040(old)|r" .. " = the price " ..
		"is more than 3 days old.",
		"- Lowest price and Market value (see the Market page).",
		"- 7-day average with the trend per week, and the 30-day average.",
		"- Sells per day: about how many sell in a day (an estimate).",
		"- You: what you sold and bought of it, and at what price (from the Ledger).",
		"- Vendor pays, and Vendor sells at (when a vendor you visited sells it).",
		"- Crafting cost, with the profit in green (or the loss in red).",
		"- Disenchant value: what its disenchanting materials bring on average.",
		"- Items a strategy found (Strategies page) are marked too.",
		"",
		h("A stack in your bags"),
		"For a stack, the prices are for the whole stack, with " .. g("(... each)") .. " for one. The XNAH line shows " ..
		"the stack size, e.g. " .. GOLD .. "XNAH|r " .. g("x20") .. ".",
		"",
		h("Too much?"),
		"On the Scan page, under Item tooltips, you can turn the XNAH lines off, or only some of them (vendor prices, " ..
		"crafting, averages, the stack size).")},

	{key = "deals", title = "Deals", tab = "deals", text = lines(
		"Five lists of chances in what is listed right now. Pick one with the buttons on top. Every list needs a " ..
		"fresh full scan - and what is listed can be bought by someone else at any moment.",
		"",
		h("Under usual price"),
		"Listed far under the usual price (the 30-day average). Buy it now, sell it again at the usual price.",
		"- Listed at, Usual price, % of usual, Profit after cut (what you keep when you sell it at the usual price, " ..
		"minus what you paid), Listed, Sells/day, Days of data.",
		"- The line on top sets the limits: listed at or under 60% of usual, profit at least 10s (type e.g. 50g, " ..
		"then Enter). \"Hide items that sell under 1 a day\" leaves out slow sellers.",
		"- Only items with at least 3 days of prices and a price from the last 3 days.",
		"- Before you buy: open the Item page and look at the graph. Was the usual price real, or one high day? Is " ..
		"the price falling for good? Does it sell (Sells/day)?",
		"",
		h("Under vendor price"),
		"Listed for less than a vendor pays for it. Buy it and sell it to any vendor. No risk at all.",
		"",
		h("Vendor to auction house"),
		"Things a vendor sells that go for more here: buy them from the vendor, list them. XNAH learns what " ..
		"vendors sell when you open their window, so talk to many vendors. " .. g("Limited stock") .. " = the vendor " ..
		"only has a few at a time.",
		"",
		h("Under disenchant value"),
		"Gear listed for less than its disenchanting materials bring. Worth it if you or a friend can disenchant. " ..
		"An orange " .. "|cffff9933?|r" .. " = a material has no price yet (counted as 0). The chances are estimates.",
		"",
		h("Reset chances"),
		"Buy every unit listed under 80% of the usual price, then list them again at the usual price. Only items " ..
		"that sell again within about 5 days. A chance, not a sure thing: others may list cheap again.",
		"",
		h("Buying a deal"),
		"- Search these on the AH (auction house open) searches the first 50 of the list for their live price - a " ..
		"list can be out of date.",
		"- Then buy it in the game's auction house window, or put it on a shopping list or give it a max price " ..
		"(Item page) and buy it on the Buy page. Each purchase is a click of yours.")},

	{key = "strategies", title = "Strategies", tab = "strategies", text = lines(
		"Ready-made ways to make gold. Each strategy is one idea; XNAH goes through all your prices and lists the " ..
		"items where that idea works right now.",
		"",
		h("How to use it"),
		"1. Pick a strategy in the list on the left (grouped Buy, Sell and Make; the number is how many items it " ..
		"found right now).",
		"2. Adjust its numbers if you like (for example how cheap is cheap, or the smallest profit). " ..
		"\"Reset numbers\" puts them back.",
		"3. Read the list: for each item what to do (the action), the price to buy or sell at (the target), the " ..
		"profit, and the risk.",
		"4. Search them on the auction house for live prices, then put the ones you want on a shopping list or " ..
		"give them to the sniper (Buy page).",
		"Tick \"Mark on tooltips\" and the items that strategy finds are marked on their tooltips and item pages, so " ..
		"you notice them while you browse (a * in the list shows which ones are on).",
		"Sell strategies look at what you own (bags, bank, mail, auctions, your other characters).",
		"",
		h("The strategies"),
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

	{key = "trends", title = "Trends", tab = "trends", text = lines(
		"Three views, picked with the buttons on top.",
		"",
		h("Price and supply"),
		"Four lists of items that are moving (each needs at least 3 days of prices and a fresh price):",
		"- Rising prices: up over the last two weeks (% per week). A good time to sell what you hold.",
		"- Falling prices: down over the last two weeks. Sell soon, or wait and buy cheap later.",
		"- Supply dropped: far fewer listed than usual while the price holds. List yours now.",
		"- Flooded: far more listed than usual. Prices are under pressure - wait a few days before selling.",
		"",
		h("Best time to post"),
		"Bars for each hour of the day (your clock): the share of all sales seen in that hour. The three best hours " ..
		"are green; " .. g("grey") .. " bars are hours never watched. Post an hour or two before the best hours, so " ..
		"your auctions are fresh and cheap when buyers come.",
		"This is an estimate. It needs two full scans in one session, an hour or more apart (up to 4 hours) - " ..
		"better many, on different days and at different hours.",
		"",
		h("Few sellers / walls"),
		"- Sellers and Top seller share: one seller holding most of an item can set its price.",
		"- Wall at / Wall units: many units at one price. That is the price you must undercut; above it you wait " ..
		"until the wall is bought.",
		"- The full scan has no seller names on Forever: sellers are counted when you open an item on the auction " ..
		"house, or with a watch list scan. The share is a guess when several sell at one price.")},

	{key = "sell", title = "Sell", tab = "sell", text = lines(
		h("Sell from your bags"),
		"Lists what in your bags can go on the auction house, with the lowest price now, the market value, a " ..
		"suggested price, the deposit and what a sale brings after the cut.",
		"Click an item (auction house open): XNAH searches it for the live lowest price that is not yours. On the " ..
		"right you see the suggestion and why (" .. g("undercut 12g 3s by 1c") .. ", " .. g("floor: 80% of market") ..
		" ...).",
		"",
		h("Posting"),
		"- Price each is filled with the suggestion; type your own if you like (Suggested puts it back).",
		"- Quantity, and Duration 2h / 8h / 24h. The deposit and what you get after the cut update as you type.",
		"- Post: one click = one auction. Stackable items go up as one auction (you type the price of one); other " ..
		"items one auction per click.",
		"- If the game warns you (for example a price far under the market), Confirm: post it or Don't post - a " ..
		"second click.",
		"",
		h("Price rules"),
		"- Floor %: never under this % of the usual price (80%), or under the crafting cost when known. When the " ..
		"cheapest is under the floor, XNAH uses the normal price instead - it does not chase the price down.",
		"- Ceiling %: never over this % of the usual price (200%).",
		"- Undercut by: how much under the cheapest other seller (empty = the smallest step).",
		"- Normal: the price when nobody else sells it (empty = the usual price).",
		"Changing a rule here gives that item its own rules; Back to the general rules undoes it.",
		"",
		h("Undercut auctions"),
		"Press Cancel scan: XNAH asks for your auctions and searches each item (one a second). The list shows the " ..
		"ones where someone sells for less than you, with the time left and what cancelling costs (the deposit is " ..
		"not paid back). Pick one, then Cancel this auction - one click each. The items come back by mail; post " ..
		"them again at a better price.")},

	{key = "buy", title = "Buy", tab = "buy", text = lines(
		h("Shopping lists (left)"),
		"- New list makes a list; the List button switches lists, renames, empties or deletes them.",
		"- Add item: type a name or shift-click an item. Under the list set Buy in all (how many) and Max each " ..
		"(the most to pay for one), then Enter.",
		"- Columns: Need (still to buy), Bought, Max, Lowest now (" .. g("grey") .. " = from the last scan), Cost " ..
		"to buy rest (a red number = only that many are listed under your max).",
		"- Search list searches every item you still need, one a second, for live prices.",
		"",
		h("Buying (right, top)"),
		"Click an item of the list (auction house open): it is searched and the panel shows what one click buys, " ..
		"never over your max price.",
		"- Stackable items (cloth, herbs...): two clicks. The first asks the server for the exact price, the " ..
		"second buys. If the price went up, XNAH tells you instead of buying.",
		"- Other items (gear): one click buys one auction.",
		"- Cancel stops a purchase, Search again looks once more, Clear empties the panel.",
		"",
		h("The sniper (right, below)"),
		"- Sniper: ON searches every watched item that has a max price, one by one, again and again (with a wait " ..
		"between rounds that you set, 10 seconds at first).",
		"- When one is listed at or under your max: a sound, the game's icon flashes, a chat line, and it shows " ..
		"under Hits. Click the hit, then Buy.",
		"- Set a max price: pick a watched item in the list and type it, or use Max price on the Item page.",
		"- It pauses while a scan runs, while you search yourself and while you buy. It never buys by itself.",
		"",
		"Every purchase step is a click of yours: the game does not let an addon buy alone.")},

	{key = "ledger", title = "Ledger", tab = "ledger", text = lines(
		"Your own trades, read from the auction house mails when you open your mailbox: what you sold, bought, and " ..
		"what came back expired or cancelled. Each mail is counted once, even if you leave it there.",
		"",
		h("Totals"),
		"For the last 7 days, 30 days and all time:",
		"- Income: what your sales brought, after the auction house cut.",
		"- Spent: what you paid for auctions you bought.",
		"- Auction house cut: what the auction house kept of your sales.",
		"- Profit: income minus spent. Sales and Purchases: how many mails.",
		"The graph shows income (green) and spending (red) per day for the last 30 days.",
		"",
		h("By item"),
		"Sold, average sale price, Bought, average buy price, Profit, Expired (and cancelled), and Sell-through: " ..
		"the share of what you posted that really sold (" .. "|cff4ade80" .. "60% or more|r" .. " is good, " ..
		"|cfff87171" .. "under 30%|r" .. " means it often comes back). Drop or reprice items with a low sell-through: " ..
		"every expired auction costs its deposit.",
		"",
		h("Recent"),
		"Every sale, purchase, expiry and cancel with the time, the money and the character. " ..
		g("(money on the way)") .. " = sold, the money mail is still coming.")},

	{key = "wealth", title = "Wealth", tab = "wealth", text = lines(
		"What all your characters on this realm and faction are worth.",
		"",
		h("Characters"),
		"- Gold, and the value of their Bags, Bank, Mail and Auctions, the Total, and when it was Updated.",
		"- Items count at their auction house price after the cut; soulbound items at what a vendor pays.",
		"- Log in with each character once, and open the bank and the mailbox, so XNAH can count them. The " ..
		"account bank has its own row.",
		"- Delete a character: forget one you deleted or moved.",
		"",
		h("Net worth graph"),
		"The total of all characters over time (30 days, 90 days, All). It is saved once a day when you log in.",
		"",
		h("Your bags: sell or keep?"),
		"For each thing in this character's bags: its auction house value, what a vendor pays, and the Best place " ..
		"to sell it. Items that sell under 0.2 a day go to a vendor unless the auction house pays 3 times as much. " ..
		"Soulbound items say Keep (bound). The total on top is what selling everything the best way would bring.")},

	{key = "settings", title = "Scan page and settings", tab = "scan", text = lines(
		h("Scanning"),
		"The box on the left: whether the auction house is open, Full scan (or the countdown), Scan watch list, " ..
		"Stop, a progress bar, and the last full scan. Below: the last 10 scans on this realm.",
		"",
		h("Guild price sharing"),
		"- On: XNAH users in your guild (same realm and faction) hand each other the prices of their newest full " ..
		"scan, so one scan helps everyone. Only prices are sent, nothing else.",
		"- It shows who in your guild has XNAH, and when prices were last sent and received.",
		"- During boss fights the game blocks addon messages; XNAH holds them and sends them later.",
		"",
		h("Export prices"),
		"Text to copy (Ctrl+C) into a spreadsheet: item number, name, lowest price, market value, listed, the 7-day " ..
		"and 30-day average and when it was seen, for every item seen in the last 3 days. Prices are in copper.",
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
		"- Minimap button: left-click opens XNAH, right-click opens the Scan page, drag it to move it.",
		"- You can give \"Open / close XNAH\" a key in the game's key bindings.")},

	{key = "good", title = "Good to know", text = lines(
		h("What is only an estimate"),
		"- Sales speed (Sold/day, Sells per day, Best time to post): worked out by comparing two full scans. An " ..
		"auction that disappeared long before its time ran out counts as sold - but a cancelled one looks the same, " ..
		"so items people relist often look faster than they are. It gets better with many scans.",
		"- Disenchant values: they use the classic disenchanting chances. Forever may differ.",
		"- Profits: they assume you sell at the usual price. The market may move before you do.",
		"- The share of the top seller is a guess when several sell at one price.",
		"",
		h("Prices are per realm and faction"),
		"Alliance and Horde have their own auction house, so XNAH keeps their prices apart. All your characters on " ..
		"the same realm and faction share one set of prices.",
		"",
		h("Neutral auction houses"),
		"The neutral auction houses (in the goblin towns) keep a bigger cut, about 15%, and ask a higher deposit. " ..
		"XNAH saves what you scan there with your own faction's prices, so it is best to scan your faction's " ..
		"auction house. If you trade at a neutral one, set the cut to 15 on the Scan page.",
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
