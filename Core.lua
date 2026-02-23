-- Core.lua
local ADDON, NS = ...

local f = CreateFrame("Frame")

-- Loot tracking
local lootSlots = {}     -- [slot] = { link, quantity, slotType, name, icon }
local looting = false
local moneyStart = 0
local lastLootClosedAt = 0
local LOOT_MONEY_GRACE = 0.75

-- GET_ITEM_INFO_RECEIVED fallback (rare now, but safe)
local pending = {}       -- [key] = { itemLink, quantity }

-- ---------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------

local function HexToRGB(hex)
  if not hex or #hex < 6 then return 1, 1, 1 end
  local r = tonumber(hex:sub(1,2), 16) or 255
  local g = tonumber(hex:sub(3,4), 16) or 255
  local b = tonumber(hex:sub(5,6), 16) or 255
  return r/255, g/255, b/255
end

local function ExtractNameFromLink(link)
  if not link then return "" end
  return link:match("%[(.-)%]") or ""
end

local function GetFastItemIcon(itemID)
  if not itemID then return nil end
  if C_Item and C_Item.GetItemIconByID then
    local ok, icon = pcall(C_Item.GetItemIconByID, itemID)
    if ok and icon then return icon end
  end
  if GetItemInfoInstant then
    local _, _, _, _, icon = GetItemInfoInstant(itemID)
    return icon
  end
  return nil
end

local function GetQualityDuration(quality)
  local db = NS.DB
  if not db or not db.durations then return 3 end
  if quality == 0 then return db.durations.poor end
  if quality == 1 then return db.durations.common end
  if quality == 2 then return db.durations.uncommon end
  if quality == 3 then return db.durations.rare end
  if quality == 4 then return db.durations.epic end
  if quality == 5 then return db.durations.legendary end
  return db.durations.common
end

local function IsBlacklisted(itemID)
  local db = NS.DB
  if not db or not db.blacklist or not db.blacklist.enabled then return false end
  return db.blacklist.items and db.blacklist.items[itemID] == true
end

local function CopperText(copper)
  copper = copper or 0
  local g = math.floor(copper / 10000); copper = copper - g * 10000
  local s = math.floor(copper / 100);  copper = copper - s * 100
  local c = copper
  return string.format("%dg %ds %dc", g, s, c)
end

local function BuildPriceText(unitCopper, stackCopper, quantity)
  local db = NS.DB
  if not db or not db.price or (not db.price.showAH and not db.price.showStack) then return "" end

  local unitText = unitCopper and unitCopper > 0 and CopperText(unitCopper) or ""
  local stackText = stackCopper and stackCopper > 0 and CopperText(stackCopper) or ""

  if db.price.replaceSingleWithStack and quantity and quantity > 1 then
    if db.price.showStack and stackText ~= "" then
      if db.price.showAH and unitText ~= "" then
        return stackText .. "\n" .. unitText
      end
      return stackText
    end
  end

  local parts = {}
  if db.price.showAH and unitText ~= "" then parts[#parts+1] = unitText end
  if db.price.showStack and stackText ~= "" then parts[#parts+1] = stackText end

  if #parts == 0 then return "" end
  if #parts == 1 then return parts[1] end
  return parts[2] .. "\n" .. parts[1]
end

local function GetAuctionatorUnitPrice(itemLink, itemID)
  if not Auctionator or not Auctionator.API or not Auctionator.API.v1 then return 0 end

  if itemID then
    local ok, v = pcall(Auctionator.API.v1.GetAuctionPriceByItemID, ADDON, itemID)
    if ok and type(v) == "number" then return v end
  end
  if itemLink then
    local ok, v = pcall(Auctionator.API.v1.GetAuctionPriceByItemLink, ADDON, itemLink)
    if ok and type(v) == "number" then return v end
  end
  return 0
end

-- ---------------------------------------------------------
-- Item Toast (backend-driven) - uses UpsertItemToast (no dupes)
-- ---------------------------------------------------------

local function ShowItemToastFast(itemLink, quantity)
  quantity = tonumber(quantity) or 1
  if not itemLink then return end

  local itemID = tonumber(itemLink:match("item:(%d+)"))
  if itemID and IsBlacklisted(itemID) then return end

  local name = ExtractNameFromLink(itemLink)
  if name == "" then name = itemLink end

  local quality = (C_Item and C_Item.GetItemQualityByID) and C_Item.GetItemQualityByID(itemID) or nil
  local r, g, b
  if quality ~= nil then
    r, g, b = GetItemQualityColor(quality)
  else
    local hex = itemLink:match("|cff(%x%x%x%x%x%x)")
    r, g, b = HexToRGB(hex)
    quality = 1
  end

  local icon = GetFastItemIcon(itemID)
  local dur = GetQualityDuration(quality)

  local unitCopper = GetAuctionatorUnitPrice(itemLink, itemID) or 0
  local stackCopper = unitCopper * quantity
  local priceText = BuildPriceText(unitCopper, stackCopper, quantity)

  local key = itemID and ("item:" .. itemID) or ("itemlink:" .. itemLink)

  if NS.Toast and NS.Toast.UpsertItemToast then
    NS.Toast:UpsertItemToast(key, icon, name, r, g, b, quantity, priceText, dur)
  elseif NS.Toast and NS.Toast.ShowToast then
    NS.Toast:ShowToast({
      key = key,
      icon = icon,
      name = name .. (quantity > 1 and (" x" .. quantity) or ""),
      nameR = r, nameG = g, nameB = b,
      rightText = priceText or "",
      duration = dur,
    })
  end
end

-- ---------------------------------------------------------
-- Loot Slot Snapshot (backend)
-- ---------------------------------------------------------

local function SnapshotLootSlots()
  wipe(lootSlots)
  local numSlots = GetNumLootItems() or 0
  for slot = 1, numSlots do
    local slotType = GetLootSlotType(slot)
    local icon, name, qty = GetLootSlotInfo(slot)
    local link = GetLootSlotLink(slot)

    lootSlots[slot] = {
      link = link,
      quantity = qty or 1,
      slotType = slotType,
      name = name,
      icon = icon,
    }
  end
end

local function OnLootOpened()
  looting = true
  moneyStart = GetMoney() or 0
  SnapshotLootSlots()
end

local function OnLootReady()
  if looting then
    SnapshotLootSlots()
  end
end

local function OnLootSlotCleared(slot)
  local data = lootSlots[slot]
  lootSlots[slot] = nil
  if not data then return end

  -- Retail slotType numeric: 1=item, 2=money, 3=currency
  if data.slotType == 1 then
    if data.link then
      ShowItemToastFast(data.link, data.quantity)
    end
  end
  -- money handled by PLAYER_MONEY
  -- currency handled by CURRENCY_DISPLAY_UPDATE
end

local function OnLootClosed()
  -- capture any delta right away
  local now = GetMoney() or 0
  local delta = now - (moneyStart or 0)
  if delta > 0 and NS.Toast and NS.Toast.ShowMoneyToast then
    NS.Toast:ShowMoneyToast(delta, (NS.DB and NS.DB.durations and NS.DB.durations.gold) or 3)
    moneyStart = now
  end

  looting = false
  lastLootClosedAt = GetTime() or 0
  wipe(lootSlots)
end

-- ---------------------------------------------------------
-- Money (backend): PLAYER_MONEY delta w/ grace window
-- ---------------------------------------------------------

local function OnPlayerMoney()
  local t = GetTime() or 0
  if not looting then
    if (t - (lastLootClosedAt or 0)) > LOOT_MONEY_GRACE then
      return
    end
  end

  local now = GetMoney() or 0
  local delta = now - (moneyStart or 0)
  if delta > 0 and NS.Toast and NS.Toast.ShowMoneyToast then
    moneyStart = now
    NS.Toast:ShowMoneyToast(delta, (NS.DB and NS.DB.durations and NS.DB.durations.gold) or 3)
  end
end

-- ---------------------------------------------------------
-- Currency (backend): CURRENCY_DISPLAY_UPDATE quantityChange
-- ---------------------------------------------------------

local function OnCurrencyDisplayUpdate(...)
  local currencyID, quantity, quantityChange = ...

  if type(currencyID) ~= "number" then return end
  quantityChange = tonumber(quantityChange)
  if not quantityChange or quantityChange <= 0 then return end

  if not (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo) then return end
  local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
  if not info then return end

  if NS.Toast and NS.Toast.UpsertCurrencyToast then
    NS.Toast:UpsertCurrencyToast(
      currencyID,
      info.name or ("Currency " .. currencyID),
      info.iconFileID,
      quantityChange,
      info.quantity,
      info.maxQuantity,
      false,
      (NS.DB and NS.DB.durations and NS.DB.durations.currency) or 15
    )
  end
end

-- ---------------------------------------------------------
-- Event Wiring
-- ---------------------------------------------------------

f:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    local name = ...
    if name ~= ADDON then return end

    NS:InitDB()
    NS:BuildOptions()

    f:RegisterEvent("LOOT_OPENED")
    f:RegisterEvent("LOOT_READY")
    f:RegisterEvent("LOOT_SLOT_CLEARED")
    f:RegisterEvent("LOOT_CLOSED")
    f:RegisterEvent("PLAYER_MONEY")
    f:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
    f:RegisterEvent("LOOT_ITEM_ROLL_WON")
    f:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    return
  end

  if not NS.DB then return end

  if event == "LOOT_OPENED" then
    OnLootOpened()

  elseif event == "LOOT_READY" then
    OnLootReady()

  elseif event == "LOOT_SLOT_CLEARED" then
    local slot = ...
    OnLootSlotCleared(slot)

  elseif event == "LOOT_CLOSED" then
    OnLootClosed()

  elseif event == "PLAYER_MONEY" then
    OnPlayerMoney()

  elseif event == "CURRENCY_DISPLAY_UPDATE" then
    OnCurrencyDisplayUpdate(...)

  elseif event == "LOOT_ITEM_ROLL_WON" then
    local itemLink, rollQuantity, _, _, _, rollerId = ...
    if itemLink and rollerId == UnitGUID("player") then
      ShowItemToastFast(itemLink, rollQuantity or 1)
    end

  elseif event == "GET_ITEM_INFO_RECEIVED" then
    for key, p in pairs(pending) do
      if p.itemLink and GetItemInfo(p.itemLink) then
        pending[key] = nil
        ShowItemToastFast(p.itemLink, p.quantity)
      end
    end
  end
end)

f:RegisterEvent("ADDON_LOADED")