-- Toasts.lua
local ADDON, NS = ...

NS.Toast = NS.Toast or {}
local Toast = NS.Toast

Toast.active = {}
Toast.pool   = {}
Toast.byKey  = {}

local ICON_SIZE = 38

-- =========================================================
-- Utility
-- =========================================================

local function Clamp(v, a, b)
  if v < a then return a end
  if v > b then return b end
  return v
end

local function RGBToHex(r, g, b)
  r = math.floor((r or 1) * 255 + 0.5)
  g = math.floor((g or 1) * 255 + 0.5)
  b = math.floor((b or 1) * 255 + 0.5)
  return string.format("|cff%02x%02x%02x", r, g, b)
end

local function CurrencyRightText(gained, total, maxQty, r, g, b)
  gained = tonumber(gained) or 0

  local WHITE = "|cffffffff"
  local NAME_COLOR = RGBToHex(r, g, b)

  local line1 = WHITE .. "x" .. gained .. "|r"

  if total ~= nil then
    total = tonumber(total) or 0
    maxQty = tonumber(maxQty) or 0

    if maxQty > 0 then
      return line1 .. "\n"
          .. NAME_COLOR .. total .. "|r"
          .. WHITE .. "/" .. maxQty .. "|r"
    else
      return line1 .. "\n"
          .. NAME_COLOR .. total .. "|r"
    end
  end

  return line1
end

-- =========================================================
-- Frame Construction
-- =========================================================

local function CreateToastFrame()
  local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  f:SetFrameStrata("HIGH")
  f:SetClampedToScreen(true)
  f:SetAlpha(0)
  f:Hide()

  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetAllPoints(true)
  f.bg:SetColorTexture(0, 0, 0, 0.55)

  f.border = CreateFrame("Frame", nil, f, "BackdropTemplate")
  f.border:SetAllPoints(true)
  f.border:SetBackdrop({
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 12,
  })
  f.border:SetBackdropBorderColor(1, 1, 1, 0.35)

  -- Layout constants
  f._padL = 6
  f._padR = 14
  f._padT = 8
  f._padB = 8
  f._gap  = 12

  -- Icon (TOP ALIGNED)
  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetSize(ICON_SIZE, ICON_SIZE)
  f.icon:SetPoint("TOPLEFT", f, "TOPLEFT", f._padL, -f._padT)

  -- Right column (TOP ALIGNED)
  f.right = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  f.right:SetJustifyH("RIGHT")
  f.right:SetJustifyV("TOP")
  f.right:SetWordWrap(true)
  f.right:SetMaxLines(2)
  f.right:SetPoint("TOPRIGHT", f, "TOPRIGHT", -f._padR, -f._padT)

  -- Left column (TOP ALIGNED)
  f.left = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  f.left:SetJustifyH("LEFT")
  f.left:SetJustifyV("TOP")
  f.left:SetWordWrap(true)
  f.left:SetMaxLines(2)
  f.left:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", f._gap, 0)
  f.left:SetPoint("RIGHT", f.right, "LEFT", -f._gap, 0)

  -- Measurement for right width
  f._measureRight = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  f._measureRight:Hide()

  -- Fade animation
  f.fadeGroup = f:CreateAnimationGroup()

  f.fadeIn = f.fadeGroup:CreateAnimation("Alpha")
  f.fadeIn:SetFromAlpha(0)
  f.fadeIn:SetToAlpha(1)
  f.fadeIn:SetDuration(0.12)
  f.fadeIn:SetOrder(1)

  f.hold = f.fadeGroup:CreateAnimation("Alpha")
  f.hold:SetFromAlpha(1)
  f.hold:SetToAlpha(1)
  f.hold:SetDuration(1)
  f.hold:SetOrder(2)

  f.fadeOut = f.fadeGroup:CreateAnimation("Alpha")
  f.fadeOut:SetFromAlpha(1)
  f.fadeOut:SetToAlpha(0)
  f.fadeOut:SetDuration(0.25)
  f.fadeOut:SetOrder(3)

  f.fadeGroup:SetScript("OnFinished", function()
    f:Hide()
    f:SetAlpha(0)
    f._inUse = false

    for i = #Toast.active, 1, -1 do
      if Toast.active[i] == f then
        table.remove(Toast.active, i)
        break
      end
    end

    if f._key and Toast.byKey[f._key] == f then
      Toast.byKey[f._key] = nil
    end

    f._key = nil
    table.insert(Toast.pool, f)
    Toast:Reflow()
  end)

  return f
end

function Toast:Get()
  local f = table.remove(self.pool)
  if not f then f = CreateToastFrame() end
  f._inUse = true
  return f
end

-- =========================================================
-- Layout
-- =========================================================

local function MeasureRightWidth(f, text)
  if not text or text == "" then return 0 end

  local maxW = 0
  for line in text:gmatch("([^\n]+)") do
    f._measureRight:SetText(line)
    local w = f._measureRight:GetStringWidth() or 0
    if w > maxW then maxW = w end
  end

  return Clamp(maxW + 6, 70, 220)
end

local function ApplyLayout(f)
  local db = NS.DB
  if not db then return end

  local width = Clamp(tonumber(db.width) or 520, 280, 900)
  f:SetWidth(width)

  local padL = f._padL
  local padR = f._padR
  local padT = f._padT
  local padB = f._padB
  local gap  = f._gap

  local hasRight = f._hasRight
  local rightW = 0
  if hasRight then
    rightW = MeasureRightWidth(f, f._rightText)
  end

  f.right:SetWidth(rightW)
  f.right:SetShown(hasRight)

  local leftW = width - (padL + ICON_SIZE + gap + gap + rightW + padR)
  if leftW < 80 then leftW = 80 end
  f.left:SetWidth(leftW)

  local leftH  = f.left:GetStringHeight() or 0
  local rightH = hasRight and (f.right:GetStringHeight() or 0) or 0
  local contentH = math.max(ICON_SIZE, leftH, rightH)

  local totalH = math.ceil(contentH + padT + padB)
  if totalH < 44 then totalH = 44 end
  f:SetHeight(totalH)
end

-- =========================================================
-- Reflow
-- =========================================================

function Toast:Reflow()
  local db = NS.DB
  if not db then return end

  local anchor = db.anchor
  local x = anchor.x or 0
  local y = anchor.y or 0
  local scale = tonumber(db.scale) or 1
  local gap = 8

  -- Deterministic ordering: Money (1), Currency (2), Items (3), everything else (99)
  local frames = {}
  for _, f in ipairs(self.active) do
    if f and f._inUse then
      frames[#frames+1] = f
    end
  end

  table.sort(frames, function(a, b)
    local pa = a._priority or 99
    local pb = b._priority or 99
    if pa == pb then
      return (a._createdAt or 0) < (b._createdAt or 0)
    end
    return pa < pb
  end)

  local offset = 0
  for _, f in ipairs(frames) do
    ApplyLayout(f)
    f:SetScale(scale)

    f:ClearAllPoints()
    if anchor.grow == "DOWN" then
      f:SetPoint(anchor.point, UIParent, anchor.point, x, y - offset)
    else
      f:SetPoint(anchor.point, UIParent, anchor.point, x, y + offset)
    end

    offset = offset + (f:GetHeight() + gap) * scale
  end
end

-- =========================================================
-- Toast API
-- =========================================================

function Toast:ShowToast(payload)
  if not NS.DB then return end

  local f = self:Get()

  f._key = payload.key
  if f._key then
    self.byKey[f._key] = f
  end

  if payload.icon then
    f.icon:SetTexture(payload.icon)
    f.icon:Show()
  else
    f.icon:Hide()
  end

  f.left:SetTextColor(payload.nameR or 1, payload.nameG or 1, payload.nameB or 1)
  f.left:SetText(payload.name or "")

  local rightText = payload.rightText or ""
  f._rightText = rightText
  f._hasRight = (rightText ~= "")
  f.right:SetText(rightText)

  f._createdAt = GetTime and GetTime() or 0
  f._priority = f._priority or 99

  table.insert(self.active, 1, f)
  self:Reflow()

  f:Show()
  f:SetAlpha(0)
  f.fadeGroup:Stop()
  f.hold:SetDuration(payload.duration or 3)
  f.fadeGroup:Play()

  return f
end

function Toast:UpsertCurrencyToast(currencyID, currencyName, icon, gained, total, maxQty, _, duration)
  if not currencyID then return end

  local key = "currency:" .. tostring(currencyID)
  local existing = self.byKey[key]
  duration = duration or 15

  local nameR, nameG, nameB = 1.0, 0.82, 0.0

  if existing and existing._inUse then
    existing._toastType = "CURRENCY"
    existing._currencyID = currencyID
    existing._priority = 2
    existing._currencyGained = (tonumber(existing._currencyGained) or 0) + (tonumber(gained) or 0)
    if total ~= nil then existing._currencyTotal = tonumber(total) end
    if maxQty ~= nil then existing._currencyMax = tonumber(maxQty) end

    existing.left:SetTextColor(nameR, nameG, nameB)
    existing.left:SetText(currencyName)

    existing._rightText = CurrencyRightText(
        existing._currencyGained,
        existing._currencyTotal,
        existing._currencyMax,
        nameR, nameG, nameB
    )

    existing.right:SetText(existing._rightText)
    existing._hasRight = true

    ApplyLayout(existing)
    Toast:Reflow()
    existing:Show()
    existing:SetAlpha(1)
    return existing
  end

  local f = self:ShowToast({
    key = key,
    icon = icon,
    name = currencyName,
    nameR = nameR,
    nameG = nameG,
    nameB = nameB,
    rightText = CurrencyRightText(gained, total, maxQty, nameR, nameG, nameB),
    duration = duration,
  })
  if f then
    f._toastType = "CURRENCY"
    f._currencyID = currencyID
    f._priority = 2
  end
  return f
end
-- =========================================================
-- Item Toast (Upsert - no duplicates)
-- =========================================================

function Toast:UpsertItemToast(key, icon, baseName, r, g, b, gainedQty, rightText, duration)
  if not key then return end
  gainedQty = tonumber(gainedQty) or 1
  duration = duration or 10

  local existing = self.byKey[key]
  if existing and existing._inUse then
    existing._toastType = "ITEM"
    existing._priority = 3
    existing._itemQty = (tonumber(existing._itemQty) or 0) + gainedQty

    existing.left:SetTextColor(r or 1, g or 1, b or 1)
    existing.left:SetText(baseName .. (existing._itemQty > 1 and (" x" .. existing._itemQty) or ""))

    existing._rightText = rightText or ""
    existing.right:SetText(existing._rightText)
    existing._hasRight = (existing._rightText ~= "")

    ApplyLayout(existing)
    self:Reflow()

    existing:Show()
    existing.fadeGroup:Stop()
    existing.hold:SetDuration(duration)
    existing.fadeGroup:Play()
    return existing
  end

  local f = self:ShowToast({
    key = key,
    icon = icon,
    name = baseName .. (gainedQty > 1 and (" x" .. gainedQty) or ""),
    nameR = r, nameG = g, nameB = b,
    rightText = rightText or "",
    duration = duration,
  })

  if f then
    f._toastType = "ITEM"
    f._priority = 3
    f._itemQty = gainedQty
  end

  return f
end
-- =========================================================
-- Friendly API wrappers
-- =========================================================

-- Currency: prefer calling ShowCurrencyToast; kept UpsertCurrencyToast for backward compatibility.
function Toast:ShowCurrencyToast(currencyID, currencyName, icon, gained, total, maxQty, isHonor, duration)
  return self:UpsertCurrencyToast(currencyID, currencyName, icon, gained, total, maxQty, isHonor, duration)
end

-- Item: thin wrapper around ShowToast that tags it as an item toast + priority ordering.
-- Expected payload is the same structure as ShowToast() uses (icon, name, nameR/G/B, rightText, duration, key optional).
function Toast:ShowItemToast(payload)
  if not payload then return end
  local f = self:ShowToast(payload)
  if f then
    f._toastType = "ITEM"
    f._priority = 3
  end
  return f
end

-- =========================================================
-- Money Toast
-- =========================================================

local function MoneyRightText(copper)
  copper = tonumber(copper) or 0
  if copper <= 0 then return "" end

  if type(GetCoinTextureString) == "function" then
    local ok, s = pcall(GetCoinTextureString, copper)
    if ok and type(s) == "string" then
      return s
    end
  end

  local g = math.floor(copper / 10000)
  local s = math.floor((copper % 10000) / 100)
  local c = copper % 100
  local out = {}
  if g > 0 then out[#out+1] = tostring(g) .. "g" end
  if s > 0 then out[#out+1] = tostring(s) .. "s" end
  if c > 0 or #out == 0 then out[#out+1] = tostring(c) .. "c" end
  return table.concat(out, " ")
end

function Toast:ShowMoneyToast(copper, duration)
  copper = tonumber(copper) or 0
  if copper <= 0 then return end

  duration = duration or (NS.DB and NS.DB.durations and NS.DB.durations.gold) or 3

  local key = "money"
  local existing = self.byKey and self.byKey[key]

  -- If a money toast is already active, accumulate and refresh it.
  if existing and existing._inUse then
    existing._moneyCopper = (tonumber(existing._moneyCopper) or 0) + copper
    existing._toastType = "MONEY"
    existing._priority = 1

    existing.left:SetTextColor(1.0, 0.82, 0.0)
    existing.left:SetText("Money")

    existing._rightText = MoneyRightText(existing._moneyCopper)
    existing.right:SetText(existing._rightText)
    existing._hasRight = true

    if type(ApplyLayout) == "function" then ApplyLayout(existing) end
    if type(self.Reflow) == "function" then self:Reflow() end

    existing:Show()
    if existing.fadeGroup then
      existing.fadeGroup:Stop()
      if existing.hold and existing.hold.SetDuration then
        existing.hold:SetDuration(duration)
      end
      existing.fadeGroup:Play()
    end
    return existing
  end

  local f = self:ShowToast({
    key = key,
    icon = 133784, -- coin icon fileID
    name = "Money",
    nameR = 1.0, nameG = 0.82, nameB = 0.0,
    rightText = MoneyRightText(copper),
    duration = duration,
  })

  if f then
    f._moneyCopper = copper
    f._toastType = "MONEY"
    f._priority = 1
  end
  return f
end
