-- OctoTravel - travel atlas for OctoWoW (vanilla 1.12, Lua 5.0)
-- World map + minimap pins for boats, zeppelins, the tram, flight masters,
-- rentable mounts and portals. Data lives in data.lua; user-added nodes in
-- OctoTravel_Custom (SavedVariables). Minimap math follows pfQuest's model
-- (zoom yardage table + inside-zoom detection).

OctoTravel = OctoTravel or {}
local OT = OctoTravel

-- category definitions: icon, tooltip label, title color
OT.cats = {
  boat     = { icon = "Interface\\Icons\\INV_Generic_Anchor",        label = "Boat",          r = 0.4, g = 0.8, b = 1.0 },
  zeppelin = { icon = "Interface\\Icons\\Ability_Mount_Gyrocoptor",  label = "Zeppelin",      r = 1.0, g = 0.7, b = 0.3 },
  tram     = { icon = "Interface\\Icons\\INV_Misc_Gear_01",          label = "Deeprun Tram",  r = 0.8, g = 0.8, b = 0.8 },
  flight   = { icon = "Interface\\TaxiFrame\\UI-Taxi-Icon-Green",    label = "Flight Master", r = 0.5, g = 1.0, b = 0.5, nocrop = true },
  rental   = { icon = "Interface\\Icons\\Ability_Mount_RidingHorse", label = "Mount Rental",  r = 1.0, g = 0.9, b = 0.4 },
  portal   = { icon = "Interface\\Icons\\INV_Misc_Rune_01",          label = "Teleport",      r = 0.8, g = 0.5, b = 1.0 },
  dungeon  = { icon = "Interface\\Icons\\INV_Misc_Key_03",           label = "Dungeon",       r = 0.9, g = 0.8, b = 0.5 },
  raid     = { icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01",   label = "Raid",          r = 1.0, g = 0.5, b = 0.2 },
  worldboss = { icon = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01", label = "World Boss",  r = 1.0, g = 0.3, b = 0.3 },
}

local CATORDER = { "boat", "zeppelin", "tram", "flight", "rental", "portal", "dungeon", "raid", "worldboss" }

-- minimap yardage per zoom level, outdoor [0] / indoor-cvar profile [1]
local minimap_zoom = {
  [0] = { [0] = 300, [1] = 240, [2] = 180, [3] = 120, [4] = 80, [5] = 50 },
  [1] = { [0] = 466 + 2/3, [1] = 400, [2] = 333 + 1/3, [3] = 266 + 2/6, [4] = 200, [5] = 133 + 1/3 },
}

local function minimap_indoor()
  local tempzoom = 0
  local state = 1
  if GetCVar("minimapZoom") == GetCVar("minimapInsideZoom") then
    if GetCVar("minimapInsideZoom") + 0 >= 3 then
      Minimap:SetZoom(Minimap:GetZoom() - 1)
      tempzoom = 1
    else
      Minimap:SetZoom(Minimap:GetZoom() + 1)
      tempzoom = -1
    end
  end
  if GetCVar("minimapInsideZoom") + 0 == Minimap:GetZoom() then state = 0 end
  Minimap:SetZoom(Minimap:GetZoom() + tempzoom)
  return state
end

-- ---------------------------------------------------------------- config --

local defaults = {
  enabled = 1, minimap = 1, enemy = 0,
  boat = 1, zeppelin = 1, tram = 1, flight = 1, rental = 1, portal = 1,
  dungeon = 1, raid = 1, worldboss = 1,
}

local function InitConfig()
  OctoTravel_Config = OctoTravel_Config or {}
  OctoTravel_Custom = OctoTravel_Custom or {}
  for k, v in pairs(defaults) do
    if OctoTravel_Config[k] == nil then OctoTravel_Config[k] = v end
  end
end

local playerFaction -- "Alliance" | "Horde", set on login

local function NodeVisible(node)
  local cfg = OctoTravel_Config
  if cfg.enabled ~= 1 then return nil end
  if cfg[node.t] ~= 1 then return nil end
  if node.faction and cfg.enemy ~= 1 then
    if node.faction == "A" and playerFaction ~= "Alliance" then return nil end
    if node.faction == "H" and playerFaction ~= "Horde" then return nil end
  end
  return true
end

-- iterate static + custom nodes for a map file name
local function EachNode(map, callback)
  for i = 1, table.getn(OctoTravel_Nodes) do
    local n = OctoTravel_Nodes[i]
    if n.map == map and NodeVisible(n) then callback(n) end
  end
  for i = 1, table.getn(OctoTravel_Custom) do
    local n = OctoTravel_Custom[i]
    if n.map == map and n.t and OT.cats[n.t] and NodeVisible(n) then
      n.custom = i
      callback(n)
    end
  end
end

-- --------------------------------------------------------------- tooltip --

local function ShowNodeTooltip(pin, tooltip)
  local node = pin.node
  if not node then return end
  local cat = OT.cats[node.t]

  -- minimap sits at the screen edge (top right in the default UI); anchoring
  -- the tooltip to the pin's right would push it offscreen
  tooltip:SetOwner(pin, pin.minimap and "ANCHOR_LEFT" or "ANCHOR_RIGHT")
  tooltip:SetText(node.name or cat.label, cat.r, cat.g, cat.b)

  local sub = cat.label
  if node.faction == "A" then sub = sub .. " |cff5599ff(Alliance)|r"
  elseif node.faction == "H" then sub = sub .. " |cffff5555(Horde)|r" end
  tooltip:AddLine(sub, 0.9, 0.9, 0.9)

  if node.info  then tooltip:AddLine(node.info, 1, 1, 1) end
  if node.dest  then tooltip:AddLine("To: " .. node.dest, 1, 1, 1) end
  if node.time  then tooltip:AddLine(node.time, 0.7, 0.9, 0.7) end
  if node.freq  then tooltip:AddLine(node.freq, 0.7, 0.9, 0.7) end
  -- multi-destination stops (zeppelin towers, shared piers)
  if node.routes then
    for r = 1, table.getn(node.routes) do
      local route = node.routes[r]
      tooltip:AddLine("To: " .. (route.dest or "?"), 1, 1, 1)
      if route.time then tooltip:AddLine("  " .. route.time, 0.7, 0.9, 0.7) end
      if route.freq then tooltip:AddLine("  " .. route.freq, 0.7, 0.9, 0.7) end
    end
  end
  if node.price then tooltip:AddLine(node.price, 1, 0.85, 0.4) end
  if node.note  then tooltip:AddLine(node.note, 0.8, 0.8, 0.8, 1) end
  if node.custom then
    tooltip:AddLine("Added by you - Shift-Click to remove", 0.5, 0.5, 0.5)
  end
  if node.destmap and not pin.minimap then
    tooltip:AddLine("Click to view destination map", 0.5, 0.5, 0.5)
  end
  if node.lft and LFT_Toggle and not pin.minimap then
    tooltip:AddLine("Click to open the group finder", 0.5, 0.5, 0.5)
  end
  tooltip:Show()
end

-- ------------------------------------------------------------------ pins --

-- name of the currently viewed map zone ("Durotar"), nil on continent view
local function CurrentMapName()
  local c = GetCurrentMapContinent()
  local z = GetCurrentMapZone()
  if not c or not z or z == 0 then return nil end
  local zones = { GetMapZones(c) }
  return zones[z]
end
OT.CurrentMapName = CurrentMapName

-- open the world map zone with the given name
local function OpenMapByName(name)
  for c = 1, 2 do
    local zones = { GetMapZones(c) }
    for z = 1, table.getn(zones) do
      if zones[z] == name then
        SetMapZoom(c, z)
        return true
      end
    end
  end
  return nil
end

local function PinEnter()
  local tooltip = this.minimap and GameTooltip or WorldMapTooltip
  ShowNodeTooltip(this, tooltip)
end

-- remove a custom node by table identity - the index cached on the node can
-- go stale after any other removal
local function RemoveCustomNode(node)
  for i = 1, table.getn(OctoTravel_Custom) do
    if OctoTravel_Custom[i] == node then
      table.remove(OctoTravel_Custom, i)
      return true
    end
  end
  return nil
end

local function PinLeave()
  local tooltip = this.minimap and GameTooltip or WorldMapTooltip
  tooltip:Hide()
end

local function PinClick()
  local node = this.node
  if not node then return end
  if IsShiftKeyDown() and node.custom then
    RemoveCustomNode(node)
    DEFAULT_CHAT_FRAME:AddMessage("|cff88ccffOctoTravel:|r removed custom pin '" .. (node.name or "?") .. "'")
    OT:UpdateWorldMap()
    OT.mforce = true
    return
  end
  if node.lft and LFT_Toggle and not this.minimap then
    LFT_Toggle()
    return
  end
  if node.destmap and not this.minimap then
    OpenMapByName(node.destmap)
  end
end

local function BuildPin(name, parent, size)
  local f = CreateFrame("Button", name, parent)
  f:SetWidth(size)
  f:SetHeight(size)
  f.rim = f:CreateTexture(nil, "BACKGROUND")
  f.rim:SetTexture(0, 0, 0)
  f.rim:SetAllPoints(f)
  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
  f.icon:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
  f:SetScript("OnEnter", PinEnter)
  f:SetScript("OnLeave", PinLeave)
  f:SetScript("OnClick", PinClick)
  return f
end

local function SetPinNode(pin, node)
  pin.node = node
  local cat = OT.cats[node.t]
  local icon = node.icon or cat.icon
  pin.icon:SetTexture(icon)
  if cat.nocrop and not node.icon then
    pin.icon:SetTexCoord(0, 1, 0, 1)
    pin.rim:Hide()
  else
    -- crop the stock icon border for a crisp look
    pin.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    pin.rim:Show()
  end
end

-- ------------------------------------------------------------- world map --

OT.pins = {}

function OT:UpdateWorldMap()
  if not OctoTravel_Config or not OctoTravel_Nodes then return end
  -- world map pins need only a name match; OctoTravel_Zones (yard sizes)
  -- is required for minimap math alone
  local map = CurrentMapName()
  local i = 1
  if map then
    local w = WorldMapButton:GetWidth()
    local h = WorldMapButton:GetHeight()
    EachNode(map, function(node)
      local pin = OT.pins[i]
      if not pin then
        pin = BuildPin("OctoTravelPin" .. i, WorldMapButton, 16)
        pin:SetFrameLevel(WorldMapButton:GetFrameLevel() + 3)
        OT.pins[i] = pin
      end
      SetPinNode(pin, node)
      pin:ClearAllPoints()
      pin:SetPoint("CENTER", WorldMapButton, "TOPLEFT", node.x / 100 * w, -node.y / 100 * h)
      pin:Show()
      i = i + 1
    end)
  end
  for j = i, table.getn(OT.pins) do
    OT.pins[j]:Hide()
    OT.pins[j].node = nil
  end
end

-- --------------------------------------------------------------- minimap --

OT.mpins = {}
OT.playerMap = nil

local function UpdatePlayerMap()
  if not WorldMapFrame:IsShown() then
    SetMapToCurrentZone()
    OT.playerMap = CurrentMapName()
  end
end

local mup = CreateFrame("Frame")
local lastx, lasty, lastzoom

function OT:UpdateMinimap()
  local hideall = nil
  local map = OT.playerMap
  local zinfo = map and OctoTravel_Zones[map]

  -- while the (fullscreen) world map is open, GetPlayerMapPosition is
  -- relative to the BROWSED map, not the player's zone - the math below
  -- would mix coordinate frames. The minimap is hidden behind the map
  -- anyway, so just blank the pins until it closes.
  if WorldMapFrame:IsShown() then
    hideall = true
  end

  if OctoTravel_Config.minimap ~= 1 or OctoTravel_Config.enabled ~= 1 or not zinfo then
    hideall = true
  end

  local px, py = 0, 0
  if not hideall then
    px, py = GetPlayerMapPosition("player")
    if px == 0 and py == 0 then hideall = true end -- instance / unknown
  end

  if hideall then
    for j = 1, table.getn(OT.mpins) do OT.mpins[j]:Hide() end
    lastx = nil
    return
  end

  px, py = px * 100, py * 100
  local zoom = Minimap:GetZoom()

  -- skip work while nothing moved (forced once per second and on config change)
  if lastx == px and lasty == py and lastzoom == zoom and not OT.mforce then
    if (OT.mtick or 0) > GetTime() then return end
  end
  OT.mtick = GetTime() + 1
  OT.mforce = nil
  lastx, lasty, lastzoom = px, py, zoom

  local yards = minimap_zoom[minimap_indoor()][zoom]
  local xscale = yards / zinfo[1]
  local yscale = yards / zinfo[2]
  local mw = Minimap:GetWidth()
  local mh = Minimap:GetHeight()
  local xdraw = mw / xscale / 100
  local ydraw = mh / yscale / 100

  -- square minimap (pfUI) vs round default
  local square = pfUI and pfUI.minimap and true or nil

  local i = 1
  EachNode(map, function(node)
    local xpos = (node.x - px) * xdraw
    local ypos = (node.y - py) * ydraw
    local dist = math.sqrt(xpos * xpos + ypos * ypos)
    local show
    if square then
      show = (math.abs(xpos) + 6 < mw / 2 and math.abs(ypos) + 6 < mh / 2)
    else
      show = (dist + 6 < mw / 2)
    end
    if show then
      local pin = OT.mpins[i]
      if not pin then
        pin = BuildPin("OctoTravelMiniPin" .. i, Minimap, 12)
        pin.minimap = true
        pin:SetFrameLevel(Minimap:GetFrameLevel() + 3)
        OT.mpins[i] = pin
      end
      SetPinNode(pin, node)
      pin:ClearAllPoints()
      pin:SetPoint("CENTER", Minimap, "CENTER", xpos, -ypos)
      pin:Show()
      i = i + 1
    end
  end)
  for j = i, table.getn(OT.mpins) do
    OT.mpins[j]:Hide()
    OT.mpins[j].node = nil
  end
end

-- ---------------------------------------------------- world map button ---

local function ButtonText()
  return OctoTravel_Config.enabled == 1 and "Travel" or "|cff888888Travel|r"
end

local mapbtn -- created on first map show (templates are safe in the world VM,
             -- but the map frame layout is only final once shown)
local dropdown

local function InitDropdown()
  local cfg = OctoTravel_Config
  local info

  info = {}
  info.text = "OctoTravel"
  info.isTitle = 1
  UIDropDownMenu_AddButton(info)

  for i = 1, table.getn(CATORDER) do
    local key = CATORDER[i]
    info = {}
    info.text = OT.cats[key].label
    info.checked = (cfg[key] == 1)
    info.keepShownOnClick = 1
    info.func = function()
      cfg[key] = cfg[key] == 1 and 0 or 1
      OT:UpdateWorldMap()
      OT.mforce = true
    end
    UIDropDownMenu_AddButton(info)
  end

  info = {}
  info.text = "Other faction"
  info.checked = (cfg.enemy == 1)
  info.keepShownOnClick = 1
  info.func = function()
    cfg.enemy = cfg.enemy == 1 and 0 or 1
    OT:UpdateWorldMap()
    OT.mforce = true
  end
  UIDropDownMenu_AddButton(info)

  info = {}
  info.text = "Minimap pins"
  info.checked = (cfg.minimap == 1)
  info.keepShownOnClick = 1
  info.func = function()
    cfg.minimap = cfg.minimap == 1 and 0 or 1
    OT.mforce = true
  end
  UIDropDownMenu_AddButton(info)
end

local function CreateMapButton()
  if mapbtn then return end
  mapbtn = CreateFrame("Button", "OctoTravelMapButton", WorldMapFrame, "UIPanelButtonTemplate")
  mapbtn:SetWidth(70)
  mapbtn:SetHeight(20)
  mapbtn:SetText(ButtonText())
  mapbtn:SetPoint("TOPRIGHT", WorldMapButton, "TOPRIGHT", -4, -4)
  mapbtn:SetFrameLevel(WorldMapButton:GetFrameLevel() + 5)
  mapbtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

  dropdown = CreateFrame("Frame", "OctoTravelDropDown", mapbtn, "UIDropDownMenuTemplate")

  mapbtn:SetScript("OnClick", function()
    if arg1 == "RightButton" then
      UIDropDownMenu_Initialize(dropdown, InitDropdown, "MENU")
      -- 1.12 has no "cursor" anchor; anchorName must be a real frame name
      ToggleDropDownMenu(1, nil, dropdown, "OctoTravelMapButton", 0, 0)
    else
      OctoTravel_Config.enabled = OctoTravel_Config.enabled == 1 and 0 or 1
      mapbtn:SetText(ButtonText())
      OT:UpdateWorldMap()
      OT.mforce = true
    end
  end)
  mapbtn:SetScript("OnEnter", function()
    GameTooltip:SetOwner(mapbtn, "ANCHOR_BOTTOMLEFT")
    GameTooltip:SetText("OctoTravel")
    GameTooltip:AddLine("Click: show/hide travel pins", 0.9, 0.9, 0.9)
    GameTooltip:AddLine("Right-click: filter categories", 0.9, 0.9, 0.9)
    GameTooltip:Show()
  end)
  mapbtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- --------------------------------------------------------------- events --

local ev = CreateFrame("Frame", "OctoTravelEvents")
ev:RegisterEvent("VARIABLES_LOADED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("WORLD_MAP_UPDATE")
ev:RegisterEvent("ZONE_CHANGED")
ev:RegisterEvent("ZONE_CHANGED_NEW_AREA")
ev:RegisterEvent("MINIMAP_ZONE_CHANGED")
ev:SetScript("OnEvent", function()
  if event == "VARIABLES_LOADED" then
    InitConfig()
    -- WORLD_MAP_UPDATE can fire before PLAYER_ENTERING_WORLD; without the
    -- faction set, every faction-tagged pin would be filtered out
    playerFaction = UnitFactionGroup("player")
  elseif event == "PLAYER_ENTERING_WORLD" then
    playerFaction = UnitFactionGroup("player")
    UpdatePlayerMap()
  elseif event == "WORLD_MAP_UPDATE" then
    CreateMapButton()
    OT:UpdateWorldMap()
  else
    UpdatePlayerMap()
  end
end)

-- minimap updater, throttled
local throttle = 0
mup:SetScript("OnUpdate", function()
  if throttle > GetTime() then return end
  throttle = GetTime() + 0.1
  if OctoTravel_Config and OctoTravel_Nodes then OT:UpdateMinimap() end
end)

-- reset browsed map back to the player zone when the map closes
local wasShown
local closer = CreateFrame("Frame")
closer:SetScript("OnUpdate", function()
  if WorldMapFrame:IsShown() then
    wasShown = true
  elseif wasShown then
    wasShown = nil
    SetMapToCurrentZone()
    OT.playerMap = CurrentMapName()
  end
end)

-- ---------------------------------------------------------------- slash --

local function Msg(text)
  DEFAULT_CHAT_FRAME:AddMessage("|cff88ccffOctoTravel:|r " .. text)
end

SLASH_OCTOTRAVEL1 = "/octotravel"
SLASH_OCTOTRAVEL2 = "/otr"
SlashCmdList["OCTOTRAVEL"] = function(msg)
  msg = msg or ""
  local _, _, cmd, rest = string.find(msg, "^(%S*)%s*(.*)$")
  cmd = string.lower(cmd or "")

  if cmd == "" or cmd == "toggle" then
    OctoTravel_Config.enabled = OctoTravel_Config.enabled == 1 and 0 or 1
    Msg("pins " .. (OctoTravel_Config.enabled == 1 and "shown" or "hidden"))
    if mapbtn then mapbtn:SetText(ButtonText()) end
    OT:UpdateWorldMap()
    OT.mforce = true
  elseif OT.cats[cmd] then
    OctoTravel_Config[cmd] = OctoTravel_Config[cmd] == 1 and 0 or 1
    Msg(OT.cats[cmd].label .. " pins " .. (OctoTravel_Config[cmd] == 1 and "on" or "off"))
    OT:UpdateWorldMap()
    OT.mforce = true
  elseif cmd == "enemy" then
    OctoTravel_Config.enemy = OctoTravel_Config.enemy == 1 and 0 or 1
    Msg("other-faction pins " .. (OctoTravel_Config.enemy == 1 and "on" or "off"))
    OT:UpdateWorldMap()
    OT.mforce = true
  elseif cmd == "minimap" then
    OctoTravel_Config.minimap = OctoTravel_Config.minimap == 1 and 0 or 1
    Msg("minimap pins " .. (OctoTravel_Config.minimap == 1 and "on" or "off"))
    OT.mforce = true
  elseif cmd == "add" then
    local _, _, typ, name = string.find(rest, "^(%S+)%s*(.*)$")
    typ = string.lower(typ or "")
    if not OT.cats[typ] then
      Msg("usage: /otr add <boat|zeppelin|tram|flight|rental|portal> <name>")
      return
    end
    -- GetPlayerMapPosition is relative to the currently SET map: with the
    -- world map open that is the browsed zone, otherwise sync to the
    -- player's zone. Either way, name and coords come from the same map.
    local mapname
    if WorldMapFrame:IsShown() then
      mapname = CurrentMapName()
    else
      UpdatePlayerMap()
      mapname = OT.playerMap
    end
    local px, py = GetPlayerMapPosition("player")
    if (px == 0 and py == 0) or not mapname then
      Msg("cannot read your position here (browse to your own zone or close the map)")
      return
    end
    local node = {
      map = mapname,
      x = math.floor(px * 1000 + 0.5) / 10,
      y = math.floor(py * 1000 + 0.5) / 10,
      t = typ,
      name = (name ~= "" and name) or (OT.cats[typ].label),
    }
    table.insert(OctoTravel_Custom, node)
    Msg(string.format("added %s '%s' at %.1f, %.1f in %s", typ, node.name, node.x, node.y, node.map))
    if not OctoTravel_Zones[node.map] then
      Msg("note: no yard-size data for this zone - pin shows on the world map only")
    end
    OT.mforce = true
  elseif cmd == "list" then
    Msg("custom pins:")
    for i = 1, table.getn(OctoTravel_Custom) do
      local n = OctoTravel_Custom[i]
      DEFAULT_CHAT_FRAME:AddMessage(string.format("  %d: [%s] %s (%s %.1f, %.1f)", i, n.t, n.name or "?", n.map, n.x, n.y))
    end
  elseif cmd == "remove" then
    local idx = tonumber(rest)
    if idx and OctoTravel_Custom[idx] then
      local n = OctoTravel_Custom[idx]
      table.remove(OctoTravel_Custom, idx)
      Msg("removed " .. (n.name or "?"))
      OT:UpdateWorldMap()
      OT.mforce = true
    else
      Msg("usage: /otr remove <index from /otr list>")
    end
  else
    Msg("commands: toggle, boat, zeppelin, tram, flight, rental, portal, enemy, minimap, add, list, remove")
  end
end
