-- Options.lua (Retail - custom scroll panel; avoids Blizzard Settings proxy errors)
local ADDON, NS = ...

local function CopyDefaults(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" then
      dst[k] = dst[k] or {}
      CopyDefaults(dst[k], v)
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
end

-- Keep your latest defaults/features
NS.DEFAULTS = NS.DEFAULTS or {}
do
  local D = NS.DEFAULTS

  D.width = D.width or 520
  D.scale = D.scale or 1.0
  D.animStyle = D.animStyle or "SLIDE_FADE"

  D.anchor = D.anchor or { point="TOPRIGHT", x=-40, y=-220, grow="DOWN" }

  D.show = D.show or { reputation=true, honor=true }

  -- fixed durations
  D.durations = D.durations or {
    poor=5, common=10, uncommon=15, rare=20, epic=25, legendary=40,
    currency=15, quest=15, gold=3, reputation=10, honor=10,
  }

  D.price = D.price or {
    showAH=true, showStack=true, replaceSingleWithStack=true, source="AUCTIONATOR",
  }

  D.hl = D.hl or { enabled=true, unit="GOLD", t1g=1, t1s=0, t1c=0, t2g=5, t2s=0, t2c=0, t3g=100, t3s=0, t3c=0 }

  D.blacklist = D.blacklist or { enabled=true, items={} }

  D.ui = D.ui or { demo=false, unlocked=false }
end

function NS:InitDB()
  LazLootFrameDB = LazLootFrameDB or {}
  CopyDefaults(LazLootFrameDB, NS.DEFAULTS)
  NS.DB = LazLootFrameDB
end

-- -------- UI helpers --------
local function MakeTitle(parent, text, y)
  local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  fs:SetPoint("TOPLEFT", 16, y)
  fs:SetText(text)
  return fs
end

local function MakeLabel(parent, text, x, y)
  local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  fs:SetPoint("TOPLEFT", x, y)
  fs:SetText(text)
  return fs
end

local function MakeCheckbox(parent, text, x, y, get, set)
  local cb = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
  cb:SetPoint("TOPLEFT", x, y)
  cb.Text:SetText(text)

  cb:SetScript("OnShow", function() cb:SetChecked(get() and true or false) end)
  cb:SetScript("OnClick", function() set(cb:GetChecked() and true or false) end)
  return cb
end

local function MakeSlider(parent, text, x, y, minV, maxV, step, get, set, fmt)
  local s = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
  s:SetPoint("TOPLEFT", x, y)
  s:SetMinMaxValues(minV, maxV)
  s:SetValueStep(step or 1)
  s:SetObeyStepOnDrag(true)
  s:SetWidth(260)

  s.Text:SetText(text)
  s.Low:SetText(tostring(minV))
  s.High:SetText(tostring(maxV))

  local function UpdateText(v)
    if fmt then
      s.Text:SetText(string.format("%s: %s", text, string.format(fmt, v)))
    else
      s.Text:SetText(string.format("%s: %s", text, tostring(v)))
    end
  end

  s:SetScript("OnShow", function()
    local v = get()
    s:SetValue(v)
    UpdateText(v)
  end)

  s:SetScript("OnValueChanged", function(_, v)
    if step and step > 0 then v = math.floor((v / step) + 0.5) * step end
    set(v)
    UpdateText(v)
  end)

  return s
end

local function MakeDropdown(parent, text, x, y, width, items, get, set)
  MakeLabel(parent, text, x, y)

  local dd = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
  dd:SetPoint("TOPLEFT", x - 16, y - 22)
  UIDropDownMenu_SetWidth(dd, width or 200)

  local function Initialize()
    local current = get()
    for _, it in ipairs(items) do
      local info = UIDropDownMenu_CreateInfo()
      info.text = it.text
      info.value = it.value
      info.func = function()
        set(it.value)
        UIDropDownMenu_SetSelectedValue(dd, it.value)
        UIDropDownMenu_SetText(dd, it.text)
      end
      info.checked = (it.value == current)
      UIDropDownMenu_AddButton(info)
    end
  end

  dd:SetScript("OnShow", function()
    UIDropDownMenu_Initialize(dd, Initialize)
    UIDropDownMenu_SetSelectedValue(dd, get())
    for _, it in ipairs(items) do
      if it.value == get() then UIDropDownMenu_SetText(dd, it.text) break end
    end
  end)

  return dd
end

-- Anchor mover + slash commands
local function BuildMover()
  local db = NS.DB
  if _G.LazLootFrameMover then return _G.LazLootFrameMover end

  local mover = CreateFrame("Frame", "LazLootFrameMover", UIParent, "BackdropTemplate")
  mover:SetSize(220, 46)
  mover:SetFrameStrata("DIALOG")
  mover:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile="Interface/Tooltips/UI-Tooltip-Border", edgeSize=12 })
  mover:SetBackdropColor(0,0,0,0.7)
  mover:SetBackdropBorderColor(1,1,1,0.6)
  mover:Hide()
  mover:SetClampedToScreen(true)
  mover:SetMovable(true)
  mover:EnableMouse(true)
  mover:RegisterForDrag("LeftButton")
  mover:SetScript("OnDragStart", mover.StartMoving)
  mover:SetScript("OnDragStop", function()
    mover:StopMovingOrSizing()
    local point, _, _, x, y = mover:GetPoint(1)
    db.anchor.point = point
    db.anchor.x = x
    db.anchor.y = y
    if NS.Toast then NS.Toast:Reflow() end
  end)

  local t = mover:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  t:SetPoint("CENTER")
  t:SetText("LazLootFrame Anchor\n(Drag me)")

  return mover
end

local function SetUnlocked(on)
  local db = NS.DB
  db.ui.unlocked = on and true or false
  local mover = BuildMover()
  if db.ui.unlocked then
    mover:ClearAllPoints()
    mover:SetPoint(db.anchor.point, UIParent, db.anchor.point, db.anchor.x, db.anchor.y)
    mover:Show()
  else
    mover:Hide()
  end
end

-- Demo toggle uses existing demo functions in Options.lua from earlier builds if present.
local function SetDemo(on)
  local db = NS.DB
  db.ui.demo = on and true or false
  if db.ui.demo then
    NS:StartDemo()
  else
    NS:StopDemo()
  end
end

-- =========================================================
-- Open Options (Retail Settings + Classic Interface Options)
-- =========================================================

function NS:OpenOptions()
  -- Retail Settings UI
  if Settings and Settings.OpenToCategory then
    -- Prefer the registered Settings category.
    -- Some clients expect a numeric category ID, not the category table.
    if self.settingsCategory then
      local cat = self.settingsCategory
      local id = (type(cat) == "table" and cat.ID) or cat
      if type(id) == "number" then
        Settings.OpenToCategory(id)
      end
      return
    end
    -- If options weren't built yet, build them now and retry once
    if self.BuildOptions and not self._buildingOptions then
      self._buildingOptions = true
      pcall(function() self:BuildOptions() end)
      self._buildingOptions = false
      if self.settingsCategory then
        local cat = self.settingsCategory
        local id = (type(cat) == "table" and cat.ID) or cat
        if type(id) == "number" then
          Settings.OpenToCategory(id)
        end
        return
      end
    end
  end

  -- Classic / legacy Interface Options
  if InterfaceOptionsFrame_OpenToCategory and self.optionsPanel then
    InterfaceOptionsFrame_OpenToCategory(self.optionsPanel)
    InterfaceOptionsFrame_OpenToCategory(self.optionsPanel) -- Blizzard bug
  end
end

local function EnsureSlash()
  if NS._slashInit then return end
  NS._slashInit = true

  SLASH_LAZLOOTFRAME1 = "/llf"
  SlashCmdList.LAZLOOTFRAME = function()
    -- /llf ONLY opens settings
    if NS and NS.OpenOptions then
      NS:OpenOptions()
    end
  end
end

-- -------- Demo Mode (persistent until toggled off) --------
NS._demoFrames = NS._demoFrames or {}

function NS:StopDemo()
  if not NS.Toast then return end
  for i = #self._demoFrames, 1, -1 do
    local f = self._demoFrames[i]
    if f and self.Toast.ForceRemove then
      self.Toast:ForceRemove(f)
    elseif f then
      f:Hide()
    end
    table.remove(self._demoFrames, i)
  end
end

function NS:StartDemo()
  if not NS.Toast then return end
  self:StopDemo()

  local function Add(p)
    p.duration = 86400 -- "infinite" demo
    self.Toast:ShowToast(p)
    local top = self.Toast.active and self.Toast.active[1]
    if top then
      top._demo = true
      table.insert(self._demoFrames, top)
    end
  end

  -- Match the screenshot-style examples
  Add({
    icon = 134145,
    name = "+80 Iskaara Tuskarr Rep (80 / 3000)",
    nameR = 0.2, nameG = 0.8, nameB = 1.0,
    subtext = "",
    priceText = "",
  })

  Add({
    icon = 255132,
    name = "500x Honor (15000 / 15000)",
    nameR = 1.0, nameG = 0.82, nameB = 0.0,
    subtext = "",
    priceText = "",
  })

  Add({
    icon = 236679,
    name = "40x Timewarped Badge (2000)",
    nameR = 1.0, nameG = 0.82, nameB = 0.0,
    subtext = "",
    priceText = "",
  })

  Add({
    icon = 134400,
    name = "Some Epic Sword",
    nameR = 0.64, nameG = 0.21, nameB = 0.93,
    subtext = "ilvl: 400  Leech",
    priceText = [[|cffffffff1|r |cffffd700g|r |cffffffff85|r |cffc7c7cfs|r |cffffffff17|r |cffeda55fc|r
|cffffffff1|r |cffffd700g|r |cffffffff23|r |cffc7c7cfs|r |cffffffff45|r |cffeda55fc|r]],
  })

  Add({
    icon = 135774,
    name = "2x Metal Hat",
    nameR = 0.2, nameG = 0.7, nameB = 1.0,
    subtext = "ilvl: 315  Indestructible",
    priceText = [[|cffffffff11|r |cffffd700g|r |cffffffff11|r |cffc7c7cfs|r |cffffffff4|r |cffeda55fc|r
|cffffffff7|r |cffffd700g|r |cffffffff40|r |cffc7c7cfs|r |cffffffff70|r |cffeda55fc|r]],
  })

  Add({
    icon = 133784,
    name = "Money",
    subtext = "",
    priceText = "|cffffffff200|r |cffffd700g|r |cffffffff0|r |cffc7c7cfs|r |cffffffff0|r |cffeda55fc|r",
  })
end

function NS:BuildOptions()
  EnsureSlash()

  local panel = CreateFrame("Frame", "LazLootFrameOptionsPanel", UIParent)
  panel.name = "LazLootFrame"
  NS.optionsPanel = panel

  local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 0, -8)
  scroll:SetPoint("BOTTOMRIGHT", -30, 8)

  local child = CreateFrame("Frame", nil, scroll)
  child:SetSize(760, 900)
  scroll:SetScrollChild(child)

  MakeTitle(child, "LazLootFrame", -8)
  MakeLabel(child, "Command: /llf (open settings)", 16, -36)

  MakeCheckbox(child, "Unlock Anchor (drag to move)", 16, -70,
    function() return NS.DB.ui.unlocked end,
    function(v) SetUnlocked(v) end
  )

  MakeCheckbox(child, "Demo Mode (sample toasts)", 16, -100,
    function() return NS.DB.ui.demo end,
    function(v) SetDemo(v) end
  )

  MakeSlider(child, "Width", 16, -145, 280, 900, 10,
    function() return NS.DB.width or 520 end,
    function(v) NS.DB.width = v; if NS.Toast then NS.Toast:Reflow() end end
  )

  MakeSlider(child, "Scale", 16, -205, 0.5, 2.0, 0.05,
    function() return NS.DB.scale or 1.0 end,
    function(v) NS.DB.scale = v; if NS.Toast then NS.Toast:Reflow() end end,
    "%.2f"
  )

  MakeDropdown(child, "Animation Style", 16, -325, 200, {
      { value = "SLIDE_FADE", text = "Slide + Fade" },
      { value = "SLIDE",      text = "Slide Only" },
      { value = "FADE",       text = "Fade Only" },
    },
    function() return NS.DB.animStyle end,
    function(v) NS.DB.animStyle = v end
  )

  MakeCheckbox(child, "Show Reputation", 16, -385,
    function() return NS.DB.show.reputation end,
    function(v) NS.DB.show.reputation = v end
  )

  MakeCheckbox(child, "Show Honor", 16, -415,
    function() return NS.DB.show.honor end,
    function(v) NS.DB.show.honor = v end
  )

  MakeCheckbox(child, "Show AH Price (unit)", 16, -455,
    function() return NS.DB.price.showAH end,
    function(v) NS.DB.price.showAH = v end
  )

  MakeCheckbox(child, "Show Stack Price", 16, -485,
    function() return NS.DB.price.showStack end,
    function(v) NS.DB.price.showStack = v end
  )

  MakeCheckbox(child, "Replace Single Price with Stack Price", 16, -515,
    function() return NS.DB.price.replaceSingleWithStack end,
    function(v) NS.DB.price.replaceSingleWithStack = v end
  )

  -- Fixed durations note
  MakeLabel(child, "Display Duration (s) is fixed to your defaults:", 380, -145)
  MakeLabel(child, "Poor 5 | Common 10 | Uncommon 15 | Rare 20 | Epic 25 | Legendary 40", 380, -170)
  MakeLabel(child, "Currency 15 | Quest 15 | Gold 3 | Reputation 10 | Honor 10", 380, -195)

  panel:SetScript("OnShow", function()
    SetUnlocked(NS.DB.ui.unlocked)
    if NS.DB.ui.demo and NS.StartDemo then NS:StartDemo() end
    if (not NS.DB.ui.demo) and NS.StopDemo then NS:StopDemo() end
  end)

  if Settings and Settings.RegisterCanvasLayoutCategory then
    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
    NS.settingsCategory = category
  else
    InterfaceOptions_AddCategory(panel)
  end
end
