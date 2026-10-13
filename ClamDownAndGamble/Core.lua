local ADDON, ns = ...
local PREFIX = "CDAG1"
local VERSION = "0.2.0"

ClamDownAndGambleDB = ClamDownAndGambleDB or { wins = {}, history = {}, deposits = {} }
local DB = ClamDownAndGambleDB

local state = {
  active = false, phase = "idle", host = nil, participants = {}, ready = {},
  rolls = {}, tied = {}, round = 1, item = nil, quantity = 1,
  countdown = 0, countdownTicker = nil, lastWinner = nil
}

local function PlayerName(full)
  if not full then return nil end
  return Ambiguate(full, "short")
end

local function Say(msg)
  print("|cff66ccffClam Down and Gamble:|r " .. tostring(msg))
end

local function GroupChannel()
  if IsInRaid() then return "RAID" end
  if IsInGroup() then return "PARTY" end
  return nil
end

local function SendGroup(msg)
  local channel = GroupChannel()
  if channel then SendAddonMessage(PREFIX, msg, channel) end
end

local function SendPublic(msg)
  local channel = GroupChannel()
  if channel then SendChatMessage("[Clam Down and Gamble] " .. msg, channel) end
end

local function IsHost()
  return state.host == PlayerName(UnitName("player"))
end

local function ItemName(itemID)
  if not itemID then return nil end
  local name = C_Item.GetItemNameByID(itemID)
  return name
end

local function IsClamItem(itemID)
  local name = ItemName(itemID)
  return name and name:lower():find("clam", 1, true) ~= nil
end

local function ItemSellPrice(itemID)
  -- GetItemInfo's 11th return value is the vendor sell price in copper per item.
  local itemName, _, _, _, _, _, _, _, _, _, sellPrice = GetItemInfo(itemID)
  return tonumber(sellPrice) or 0
end

local function FormatMoney(copper)
  copper = math.max(0, math.floor(tonumber(copper) or 0))
  local gold = math.floor(copper / 10000)
  local silver = math.floor((copper % 10000) / 100)
  local copperPart = copper % 100
  local parts = {}
  if gold > 0 then parts[#parts + 1] = gold .. "g" end
  if silver > 0 then parts[#parts + 1] = silver .. "s" end
  if copperPart > 0 or #parts == 0 then parts[#parts + 1] = copperPart .. "c" end
  return table.concat(parts, " ")
end

local function ScanClams()
  local found, totalValue = {}, 0
  for bag = 0, NUM_BAG_SLOTS do
    local slots = C_Container.GetContainerNumSlots(bag)
    for slot = 1, slots do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.itemID and IsClamItem(info.itemID) then
        local name = ItemName(info.itemID) or ("Item " .. info.itemID)
        local count = info.stackCount or 1
        local sellPrice = ItemSellPrice(info.itemID)
        local stackValue = sellPrice * count
        totalValue = totalValue + stackValue
        found[#found + 1] = {
          itemID = info.itemID, name = name, count = count, bag = bag, slot = slot,
          sellPrice = sellPrice, stackValue = stackValue
        }
      end
    end
  end
  return found, totalValue
end

local function EnsurePlayer(name)
  name = PlayerName(name)
  if name and not state.participants[name] then state.participants[name] = true end
end

local function ResetGame()
  state.active = false
  state.phase = "idle"
  state.host = nil
  state.participants = {}
  state.ready = {}
  state.rolls = {}
  state.tied = {}
  state.round = 1
  state.item = nil
  state.quantity = 1
  state.countdown = 0
end

local function PrintLeaderboard()
  Say("Leaderboard (wins):")
  local rows = {}
  for name, wins in pairs(DB.wins or {}) do
    rows[#rows + 1] = { name = name, wins = wins }
  end
  table.sort(rows, function(a, b)
    if a.wins == b.wins then return a.name < b.name end
    return a.wins > b.wins
  end)
  if #rows == 0 then Say("No winners recorded yet.") return end
  for i, row in ipairs(rows) do
    Say(string.format("%d. %s — %d win(s)", i, row.name, row.wins))
  end
end

local function FinishRound()
  local high, winners = -1, {}
  for name, roll in pairs(state.rolls) do
    if roll > high then high, winners = roll, { name }
    elseif roll == high then winners[#winners + 1] = name end
  end
  table.sort(winners)
  if #winners == 0 then Say("No valid rolls were recorded.") return end
  if #winners > 1 then
    state.phase = "tiebreak"
    state.tied = {}
    for _, name in ipairs(winners) do state.tied[name] = true end
    state.rolls = {}
    state.round = state.round + 1
    local list = table.concat(winners, ", ")
    SendPublic("Tie at " .. high .. " between " .. list .. "! Tied players only: /roll 100. (Round " .. state.round .. ")")
    Say("Tie-break started for: " .. list)
    return
  end
  local winner = winners[1]
  state.lastWinner = winner
  DB.wins[winner] = (DB.wins[winner] or 0) + 1
  DB.history[#DB.history + 1] = {
    winner = winner, roll = high, item = state.item, quantity = state.quantity,
    date = date("%Y-%m-%d %H:%M:%S"), host = state.host
  }
  state.phase = "finished"
  SendPublic(winner .. " wins with " .. high .. "!")
  Say(winner .. " wins with " .. high .. ". Host: record the clam transfer after the game.")
  PrintLeaderboard()
end

local function StartCountdown()
  if not IsHost() then Say("Only the game host can start the countdown.") return end
  if state.phase ~= "ready" then Say("Game must be in the ready phase.") return end
  for name in pairs(state.participants) do
    if not state.ready[name] then Say(name .. " is not ready yet.") return end
  end
  state.phase = "countdown"
  SendGroup("COUNTDOWN")
  state.countdown = 3
  SendPublic("All players ready! Rolling in 3...")
  if state.countdownTicker then state.countdownTicker:Cancel() end
  state.countdownTicker = C_Timer.NewTicker(1, function(ticker)
    state.countdown = state.countdown - 1
    if state.countdown > 0 then
      SendPublic(tostring(state.countdown) .. "...")
    else
      ticker:Cancel()
      state.countdownTicker = nil
      state.phase = "rolling"
      state.rolls = {}
      state.round = 1
      SendPublic("ROLL NOW! Use /roll 100.")
    end
  end)
end

local function BeginGame(itemName, quantity)
  if not GroupChannel() then Say("Join a party or raid first.") return end
  if state.active then Say("A game is already active. Use /clam cancel to stop it.") return end
  state.active = true
  state.phase = "ready"
  state.host = PlayerName(UnitName("player"))
  state.item = "All eligible Clam items; values based on vendor sell price"
  state.quantity = tonumber(quantity) or 1
  state.participants[state.host] = true
  state.ready[state.host] = true
  for i = 1, GetNumGroupMembers() do
    local unit = IsInRaid() and ("raid" .. i) or ("party" .. i)
    local name = UnitName(unit)
    if name then state.participants[PlayerName(name)] = true end
  end
  local clams, totalValue = ScanClams()
  local inventoryText = #clams > 0 and (" Your bag scan found " .. #clams .. " stack(s) with Clam in the item name, worth " .. FormatMoney(totalValue) .. " total at vendor sell prices.") or " Your bags show no recognized Clam items."
  SendGroup("START " .. state.host .. "|" .. state.item .. "|" .. tostring(state.quantity))
  SendPublic("A Clam Down and Gamble game is forming! Host: " .. state.host .. ". Players: /clam ready. Host starts with /clam go." .. inventoryText)
  Say("Game created. Use /clam bag to list your eligible items. Addon scans are local and cannot prove what another player owns.")
end

local function HandleMessage(sender, msg)
  local cmd, rest = msg:match("^(%S+)%s*(.*)$")
  sender = PlayerName(sender)
  if cmd == "JOIN" and state.active then
    EnsurePlayer(sender)
    state.ready[sender] = false
  elseif cmd == "READY" and state.active and state.phase == "ready" then
    EnsurePlayer(sender)
    state.ready[sender] = true
    Say(sender .. " is ready.")
  elseif cmd == "UNREADY" and state.active and state.phase == "ready" then
    state.ready[sender] = false
  elseif cmd == "CANCEL" and state.active and sender == state.host then
    ResetGame()
    Say("Game cancelled by host.")
  elseif cmd == "ROLL" and state.active and (state.phase == "rolling" or state.phase == "tiebreak") then
    local value = tonumber(rest)
    if value and value >= 1 and value <= 100 and value == math.floor(value) then
      if state.phase == "tiebreak" and not state.tied[sender] then return end
      EnsurePlayer(sender)
      if not state.rolls[sender] then
        state.rolls[sender] = value
        Say(sender .. " rolled " .. value .. ".")
      end
    end
  elseif cmd == "RESULT" and state.active and sender == state.host then
    FinishRound()
  end
end

local function OnChatSystem(msg)
  local player, roll = msg:match("^(.+) rolls (%d+) %(1%-100%)%.$")
  if not player then player, roll = msg:match("^(.+) rolls (%d+) %(1%-100%)$") end
  if not player or not roll or not state.active then return end
  local name = PlayerName(player)
  local value = tonumber(roll)
  if state.phase == "tiebreak" and not state.tied[name] then return end
  if state.phase == "rolling" or state.phase == "tiebreak" then
    if not state.rolls[name] then
      -- Each client sees the system roll message; only the host records it to avoid
      -- rebroadcasting another player's roll under the wrong sender identity.
      if IsHost() then
        state.rolls[name] = value
        Say(name .. " rolled " .. value .. ".")
      end
    end
  end
end

local function OnAddonMessage(prefix, msg, channel, sender)
  if prefix ~= PREFIX then return end
  local cmd, rest = msg:match("^(%S+)%s*(.*)$")
  if cmd == "START" then
    local host, item, quantity = rest:match("^([^|]+)|([^|]*)|(%d+)$")
    if host then
      state.active = true
      state.phase = "ready"
      state.host = PlayerName(host)
      state.item = item
      state.quantity = tonumber(quantity) or 1
      state.participants = {}
      state.ready = {}
      state.rolls = {}
      state.participants[state.host] = true
      state.ready[state.host] = true
      for i = 1, GetNumGroupMembers() do
        local unit = IsInRaid() and ("raid" .. i) or ("party" .. i)
        local name = UnitName(unit)
        if name then state.participants[PlayerName(name)] = true end
      end
    end
  elseif cmd == "COUNTDOWN" then
    state.phase = "countdown"
  elseif cmd == "ROLL" then
    local value = tonumber(rest)
    sender = PlayerName(sender)
    if value and state.active and (state.phase == "rolling" or state.phase == "tiebreak") then
      if state.phase ~= "tiebreak" or state.tied[sender] then
        if not state.rolls[sender] then state.rolls[sender] = value end
      end
    end
  else
    HandleMessage(sender, msg)
  end
end

local function Command(input)
  local args = {}
  for word in (input or ""):gmatch("%S+") do args[#args + 1] = word end
  local cmd = (args[1] or "help"):lower()
  if cmd == "help" then
    Say("/clam start — create a game using any eligible Clam items")
    Say("/clam bag — list eligible Clam items and vendor sell values")
    Say("/clam ready — mark yourself ready; /clam unready — undo")
    Say("/clam go — host starts countdown when everyone is ready")
    Say("/clam result — host resolves current rolls/tie-break")
    Say("/clam deposit PLAYER ITEM_NAME COUNT — manually log a non-addon player's escrow item")
    Say("/clam ledger — show recorded deposits; /clam leaderboard — wins")
    Say("/clam cancel — host cancels the game")
  elseif cmd == "bag" then
    local clams, totalValue = ScanClams()
    if #clams == 0 then Say("No bag items with 'Clam' in the item name found.") end
    for _, item in ipairs(clams) do
      Say(item.name .. " x" .. item.count .. " — " .. FormatMoney(item.sellPrice) .. " each; stack value " .. FormatMoney(item.stackValue) .. " (bag " .. item.bag .. ", slot " .. item.slot .. ")")
    end
    if #clams > 0 then Say("Total vendor sell value of all eligible Clam items: " .. FormatMoney(totalValue)) end
  elseif cmd == "start" then
    BeginGame("All eligible Clam items", 1)
  elseif cmd == "ready" then
    if not state.active or state.phase ~= "ready" then Say("There is no game accepting ready checks.") return end
    state.ready[PlayerName(UnitName("player"))] = true
    SendGroup("READY")
    Say("You are marked ready.")
  elseif cmd == "unready" then
    state.ready[PlayerName(UnitName("player"))] = false
    SendGroup("UNREADY")
    Say("You are marked not ready.")
  elseif cmd == "go" then
    StartCountdown()
  elseif cmd == "result" then
    if not IsHost() then Say("Only the host can resolve the round.") return end
    FinishRound()
  elseif cmd == "cancel" then
    if not IsHost() then Say("Only the host can cancel the game.") return end
    SendGroup("CANCEL")
    ResetGame()
    Say("Game cancelled.")
  elseif cmd == "leaderboard" then
    PrintLeaderboard()
  elseif cmd == "deposit" then
    if not IsHost() then Say("Only the host can maintain the escrow ledger.") return end
    if #args < 4 then Say("Usage: /clam deposit PLAYER ITEM_NAME COUNT") return end
    local count = tonumber(args[#args])
    local item = args[#args - 1]
    local playerParts = {}
    for i = 2, #args - 2 do playerParts[#playerParts + 1] = args[i] end
    local player = table.concat(playerParts, " ")
    if not count or count < 1 then Say("Count must be a positive number.") return end
    local itemID = tonumber(item:match("item:(%d+)"))
    local sellPrice = itemID and ItemSellPrice(itemID) or 0
    DB.deposits[#DB.deposits + 1] = { player = player, item = item, count = count, sellPrice = sellPrice, totalValue = sellPrice * count, status = "held", date = date("%Y-%m-%d %H:%M:%S") }
    Say("Ledger recorded: " .. player .. " deposited " .. count .. " x " .. item .. ". Value recorded as " .. FormatMoney(sellPrice * count) .. " where item price data is available. Verify the trade manually.")
  elseif cmd == "ledger" then
    if #DB.deposits == 0 then Say("No deposits recorded.") return end
    for i, d in ipairs(DB.deposits) do
      Say(i .. ". " .. d.player .. " — " .. d.count .. " x " .. d.item .. " [" .. d.status .. "] value: " .. FormatMoney(d.totalValue or 0))
    end
  elseif cmd == "paid" then
    if not IsHost() then Say("Only the host can update escrow records.") return end
    local index = tonumber(args[2])
    local status = (args[3] or ""):lower()
    if not index or not DB.deposits[index] or (status ~= "returned" and status ~= "awarded") then
      Say("Usage: /clam paid DEPOSIT_NUMBER returned|awarded") return
    end
    DB.deposits[index].status = status
    Say("Deposit " .. index .. " marked " .. status .. ".")
  else
    Say("Unknown command. Type /clam help.")
  end
end

SLASH_CLAMDOWNANDGAMBLE1 = "/clam"
SLASH_CLAMDOWNANDGAMBLE2 = "/cdg"
SlashCmdList.CLAMDOWNANDGAMBLE = Command

local frame = CreateFrame("Frame")
frame:RegisterEvent("CHAT_MSG_SYSTEM")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event, ...)
  if event == "CHAT_MSG_SYSTEM" then
    OnChatSystem(...)
  elseif event == "CHAT_MSG_ADDON" then
    OnAddonMessage(...)
  elseif event == "PLAYER_LOGIN" then
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    Say("Loaded v" .. VERSION .. ". Type /clam help.")
  end
end)
