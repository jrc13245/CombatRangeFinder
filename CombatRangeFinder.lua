-- By and for Weird Vibes of Turtle WoW

-- local _G = _G or getfenv()

local has_vanillautils = pcall(UnitXP, "nop", "nop") and true or false
local has_superwow = SetAutoloot and true or false
local has_nampower = (GetSpellIdForName ~= nil)
local has_unitxp_sp3 = has_vanillautils and pcall(UnitXP, "distanceBetween", "player", "player") and true or false

local updates_per_sec = 60

-- Cache global functions and constants for efficiency

-- Math library caching
local math               = math
local cos                = math.cos
local sin                = math.sin
local sqrt               = math.sqrt
local atan2              = math.atan2
local mod                = math.mod
local pi                 = math.pi
local TWO_PI             = pi * 2
local abs                = math.abs
local tan                = math.tan
local floor              = math.floor

-- WoW API functions frequently used in loops or OnUpdate handlers
local UnitXP             = UnitXP
local GetTime            = GetTime
local GetScreenWidth     = GetScreenWidth
local GetScreenHeight    = GetScreenHeight
local UnitName           = UnitName
local UnitExists         = UnitExists
local UnitIsVisible      = UnitIsVisible
local UnitIsDead         = UnitIsDead
local UnitCanAssist      = UnitCanAssist
local UnitClassification = UnitClassification
local UnitIsPlayer       = UnitIsPlayer
local UnitCanAttack      = UnitCanAttack
local UnitRace           = UnitRace

-- Nampower API functions (when available)
local GetSpellIdForName  = GetSpellIdForName
local IsSpellInRange     = IsSpellInRange

-- Fallback API functions (used when Nampower is not available)
local SpellInfo          = SpellInfo
local GetActionText      = GetActionText
local IsActionInRange    = IsActionInRange

-- Table and string library functions
local pairs              = pairs
local ipairs             = ipairs
local getn               = getn            -- For WoW 1.12, using getn is common

local settings

if not (has_vanillautils and has_superwow) then
  StaticPopupDialogs["NO_SWOW_VU"] = {
    text = "|cff77ff00Combat Range Finder|r requires the SuperWoW and VanillaUtils dlls to operate.",
    button1 = TEXT(OKAY),
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    showAlert = 1,
  }

  StaticPopup_Show("NO_SWOW_VU")
  return
end

local function crf_print(msg)
  DEFAULT_CHAT_FRAME:AddMessage(msg)
end

-- Create the main frame that covers the entire screen
local crfFrame = CreateFrame("Frame", "crfFrame", UIParent)
crfFrame:SetAllPoints(UIParent)  -- Covers the entire screen

function RotateTexture(texture, angle)
  local cosHalf = cos(angle) * 0.5
  local sinHalf = sin(angle) * 0.5

  texture:SetTexCoord(
    0.5 - cosHalf + sinHalf, 0.5 - sinHalf - cosHalf,
    0.5 + cosHalf + sinHalf, 0.5 + sinHalf - cosHalf,
    0.5 - cosHalf - sinHalf, 0.5 - sinHalf + cosHalf,
    0.5 + cosHalf - sinHalf, 0.5 + sinHalf + cosHalf
  )
end

local textures = {
  in_range = "Interface\\Addons\\CombatRangeFinder\\line2",
  out_range = "Interface\\Addons\\CombatRangeFinder\\line",
}

local UnitPosition = function (unit)
  return UnitXP("unitPosition",unit)
end

local CameraPosition = function ()
  return UnitXP("cameraPosition")
end

local UnitFacing = function (unit)
  return UnitXP("unitFacing",unit)
end

function calculateDistance(x1,y1,z1,x2,y2,z2)
  local dx, dy, dz = x2 - x1, y2 - y1, z2 - z1
  return sqrt(dx*dx + dy*dy + dz*dz)
end

-- Create a pool for managing dots
local DotPool = {}

-- TODO reusing a dot should reset some of the values
-- Create a method to get a dot from the pool (or create a new one if none available)
function DotPool:GetDot()
  for i = 1, getn(self) do
    if not self[i].inUse then
      self[i].inUse = true
      self[i]:Show()
      return self[i]
    end
  end

  -- If no available dot, create a new one
  local dot = CreateFrame("Frame", nil, UIParent)
  dot:SetFrameStrata("BACKGROUND")
  dot:SetFrameLevel(0)  -- or 1, if 0 is not allowed in your context
  dot:SetWidth(100)
  dot:SetHeight(100)

  dot.inUse = true
  dot.x = 0
  dot.y = 0
  dot.z = 0
  dot.width = 32
  dot.height = 32
  dot.screenX = 0
  dot.screenY = 0

  -- accept positions or a table of positions
  dot.SetPosition = function (self,x,y,z)
    if type(x) == "table" then
      self.x = x.x or self.x
      self.y = x.y or self.y
      self.z = x.z or self.z
    else
      self.x = x or self.x
      self.y = y or self.y
      self.z = z or self.z
    end
  end

  local dotIcon = dot:CreateTexture(nil, "ARTWORK")
  dotIcon:SetWidth(dot.width)
  dotIcon:SetHeight(dot.height)
  dotIcon:SetPoint("CENTER", dot, "CENTER")
  dotIcon:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")

  -- local dotRing = dot:CreateTexture(nil, "ARTWORK")
  -- dotRing.width = 512
  -- dotRing.height = 512
  -- dotRing:SetWidth(dotRing.width)
  -- dotRing:SetHeight(dotRing.height)
  -- dotRing:SetPoint("CENTER", dot, "CENTER")
  -- dotRing:SetTexture("Interface\\AddOns\\Rings\\thin.tga")
  -- -- dotRing:SetScale(1) -- ignore uiscale

  local dotText = dot:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  -- dotRing:SetWidth(512)
  -- dotRing:SetHeight(512)
  dotText:SetPoint("BOTTOM", dotIcon, "TOP", 0, 0) -- Position it above the texture
  dotText:SetText("Dot") -- You can change this dynamically later
  dotText:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")

  dot.text = dotText
  dot.text.font,dot.text.size,dot.text.flags = dotText:GetFont()
  dot.icon = dotIcon
  -- dot.ring = dotRing
  -- store dot world facing and pitch?
  -- dot.yaw

  -- local no-scale = 0.9
  -- dot.SetRadius = function (self,rad,eff)
  --   -- dot.text.size = rad
  --   -- dotText:SetFont(dot.text.font,dot.text.size,dot.text.flags)
  --   -- dot.ring.width = (rad) / (10 * dot:GetEffectiveScale()) * 512 * (fovScale * 0.9)
  --   -- dot.ring.height = (rad) / (10 * dot:GetEffectiveScale()) * 512 * (fovScale * 0.9)
  --   local base = 256
  --   -- local diff = 1 - dot:GetEffectiveScale()
  --   local s = 0.9 - UIParent:GetScale()
  --   -- print(s)
  --   local r = rad / (10) * base / (1 + s*2)
  --   self.ring.width  = 2 * r
  --   self.ring.height = 2 * r
  -- end
  -- dot:SetRadius(10)

  dot.SetFontSize = function (self,size)
    self.text.size = size
    self.text:SetFont(dot.text.font,dot.text.size,dot.text.flags)
  end

  dot:Show()

  -- Add to the pool
  table.insert(self, dot)
  return dot
end

-- Create a method to return a dot back to the pool (hide it and mark as unused)
function DotPool:ReturnDot(dot)
  dot:Hide()
  dot.inUse = false
end


-- Instants to use to check for in-melee range
-- Ordered list of melee abilities to check for range (searched in order, first match wins)
-- Avoid taunts/threat abilities (Taunt, Mocking Blow, Growl) as they may have non-melee range
local instants_ordered = {
  -- Warrior
  "Hamstring",
  "Rend",
  "Sunder Armor",
  "Bloodthirst",
  "Mortal Strike",
  "Shield Slam",
  "Overpower",
  "Revenge",
  "Pummel",
  "Shield Bash",
  "Disarm",
  "Execute",
  "Slam",

  -- Rogue
  "Sinister Strike",
  "Backstab",
  "Kick",
  "Expose Armor",
  "Eviscerate",
  "Rupture",
  "Kidney Shot",
  "Garrote",
  "Ambush",
  "Cheap Shot",
  "Gouge",
  "Feint",
  "Ghostly Strike",
  "Hemorrhage",

  -- Paladin
  "Crusader Strike",
  "Holy Strike",

  -- Shaman
  "Storm Strike",

  -- Druid
  "Savage Bite",
  "Bash",
  "Swipe",
  "Claw",
  "Rip",
  "Ferocious Bite",
  "Shred",
  "Rake",
  "Cower",
  "Ravage",
  "Pounce",

  -- Hunter
  "Wing Clip",
  "Disengage",
  "Carve", -- twow
  "Counterattack", -- hunter, also war on twow
}

-- Hash lookup for the action bar fallback path
local instants = {}
for _, name in ipairs(instants_ordered) do
  instants[name] = 1
end

-- store a melee spell id to check for melee range
local melee_spell_id = nil
local range_check_slot = nil  -- fallback for non-Nampower

local function FindMeleeSpell()
  if has_nampower then
    -- Use Nampower: look up spells directly from spellbook (ordered search)
    for _, name in ipairs(instants_ordered) do
      local id = GetSpellIdForName(name)
      if id and id > 0 then
        melee_spell_id = id
        return
      end
    end
    melee_spell_id = nil
  else
    -- Fallback: scan action bar slots (original method)
    for i=1,120 do
      local name,actionType,identifier = GetActionText(i);
      if actionType and identifier and actionType == "SPELL" then
        local name,rank,texture = SpellInfo(identifier)
        if instants[name] then
          range_check_slot = i
          return
        end
      end
    end
    range_check_slot = nil
  end
end

crfFrame:SetScript("OnEvent", function ()
  -- Handle permanent shutdown to prevent SuperWoW API crashes during logout
  if event == "PLAYER_LOGOUT" then
    crf_isShuttingDown = true
    this:UnregisterAllEvents()
    this:SetScript("OnUpdate", nil)
    this:SetScript("OnEvent", nil)
    for i = 1, getn(DotPool) do
      if DotPool[i] then
        DotPool[i]:Hide()
      end
    end
    return
  end
  -- Pause during zone transitions (OnUpdate skips via crf_isShuttingDown flag)
  if event == "PLAYER_LEAVING_WORLD" then
    crf_isShuttingDown = true
    for i = 1, getn(DotPool) do
      if DotPool[i] then
        DotPool[i]:Hide()
      end
    end
    return
  end
  crfFrame[event](this,arg1,arg2,arg3,arg4,arg5,arg6,arg7,arg8,arg9,arg0)
end)

-- Shutdown flag to prevent SuperWoW API calls during logout (crash prevention)
local crf_isShuttingDown = false

crfFrame:RegisterEvent("ADDON_LOADED")
crfFrame:RegisterEvent("PLAYER_LOGOUT")
crfFrame:RegisterEvent("PLAYER_LEAVING_WORLD")

local commands = {
  { name = "enable",      default = true,  desc = "Enable or disable addon" },
  { name = "arrow",       default = true,  desc = "Show indicator arrow for (attackable) target" },
  { name = "any",         default = false, desc = "When arrow is enabled, show for non-attackable targets too" },
  { name = "markers",     default = true,  desc = "Show raid markers at enemy feet" },
  { name = "markerssize", default = 48,    desc = "Size of markers (default 48)" },
  { name = "largearrow",  default = true,  desc = "Use a larger arrow for enemies who are in range" },
  { name = "los",         default = true,  desc = "Show line of sight color on arrow" },
}

local function OffOn(on)
  return on and "|cff00ff00On|r" or "|cffff0000Off|r"
end

--Display commands
local function ShowCommands()
  crf_print("|cff77ff00Combat Range Finder:|r")
  for _,data in ipairs(commands) do
    if type(data.default) == "boolean" then
      crf_print(data.name .. " - " .. OffOn(settings[data.name]) .. " - " .. data.desc)
    else
      crf_print(data.name .. " - |cff00cccc" .. settings[data.name] .. "|r - " .. data.desc)
    end
  end
end

function MakeSlash()
  SlashCmdList["CRFCOMMAND"] = function(msg)
    local args = {}
    for word in string.gfind(msg, "[^%s]+") do
      table.insert(args, word)
    end
    local cmd = string.lower(args[1] or "")
    local num = tonumber(args[2])
    
    for _,data in ipairs(commands) do
      if cmd == data.name then
        if type(data.default) == "boolean" then
          settings[data.name] = not settings[data.name]
          crf_print("|cff77ff00CRF:|r " .. data.name .. " - " .. OffOn(settings[data.name]))
        elseif num then
          settings[data.name] = num
          crf_print("|cff77ff00CRF:|r " .. data.name .. " - |cff00cccc" .. num .. "|r")
        end
        return
      end
    end
    ShowCommands()
  end
  SLASH_CRFCOMMAND1 = "/crf"
end

function crfFrame:ADDON_LOADED(addon)
  if addon ~= "CombatRangeFinder" then return end

  CRFDB = CRFDB or {}
  CRFDB.settings = CRFDB.settings or {}
  settings = CRFDB.settings
  for _,data in ipairs(commands) do
    if settings[data.name] == nil then
      settings[data.name] = data.default
    end
  end
  CRFDB.units = CRFDB.units or {}

  MakeSlash()
  crf_print("|cff77ff00Combat Range Finder|r loaded: |cffffff00/crf|r")

  -- RingsDB = RingsDB or {}
  -- RingsDB.heal_mark_waypoints = heal_mark_waypoints
  -- RingsDB.heal_mark_waypoints = RingsDB.heal_mark_waypoints or {}

  -- self:PlaceHealWaypoints()
  -- stopPoints,totalDistance = crfFrame:initializeStopPointsAndDistance(RingsDB.heal_mark_waypoints)

  -- self:RegisterEvent("CHAT_MSG_COMBAT_FRIENDLY_DEATH")
  -- self:RegisterEvent("UNIT_CASTEVENT")
  self:RegisterEvent("PLAYER_ENTERING_WORLD")
  self:RegisterEvent("UNIT_MODEL_CHANGED")
  self:RegisterEvent("UNIT_DIED")
  if not has_nampower then
    self:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
  end

  FindMeleeSpell()

  playerdot1 = DotPool:GetDot()
  -- playerdot1.ring:Hide()
  playerdot1.text:Hide()
  playerdot1.icon:Hide()
  playerdot1:Hide()
  -- playerdot1.icon:SetTexture("Interface/Minimap/MinimapArrow")

  targetdot1 = DotPool:GetDot()
  -- targetdot1.ring:Hide()
  targetdot1.text:Hide()
  targetdot1.icon:Hide()
  targetdot1.icon:SetTexture("Interface/Minimap/MinimapArrow")
  
  -- targetmarkerdot1 = DotPool:GetDot()
  -- targetmarkerdot1.text:Hide()

  targetdot1:Hide()

  self:CreateRaidMarkers()

  -- if rings_debug then MakeHealMarkers() end
end

-- Set texture coordinates for a specific raid marker
-- MarkerIndex is the position in the 4x4 grid, starting from 1 for the top-left icon
function SetRaidMarkerTexture(texture, markerIndex)
  texture:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
  local rows, cols = 4, 4  -- 4x4 grid
  local row = floor((markerIndex - 1) / cols)
  local col = mod(markerIndex - 1, cols)
  local left = col / cols
  local right = (col + 1) / cols
  local top = row / rows
  local bottom = (row + 1) / rows
  texture:SetTexCoord(left, right, top, bottom)
end

function CreateRaidMarker(markerIndex)
  local marker = DotPool:GetDot()
  SetRaidMarkerTexture(marker.icon, markerIndex)
  marker.icon.original_width = 48
  marker.icon.original_height = 48
  marker.icon:SetWidth(marker.icon.original_width)
  marker.icon:SetHeight(marker.icon.original_height)
  marker.text:SetText("")
  -- marker:SetFrameStrata(marker:GetFrameStrata() - 1)
  return marker
end

function GetUnitData(unit)
  local _,guid = UnitExists(unit)
  local type = UnitIsPlayer(unit) and "player" or UnitClassification(unit)
  return { guid = guid, name = UnitName(unit), type = type }
end

-- Pre-allocated mark table (created once)
local _mark_table = { "mark1", "mark2", "mark3", "mark4", "mark5", "mark6", "mark7", "mark8" }

-- Marker scaling constants (pre-computed)
local MARKER_MAX_DIST = 40
local MARKER_MIN_DIST = 5
local MARKER_MIN_SCALE = 0.5
local MARKER_SCALE_RANGE = 1 / (MARKER_MAX_DIST - MARKER_MIN_DIST)  -- 1/35
local MARKER_SCALE_FACTOR = 1 - MARKER_MIN_SCALE  -- 0.5

function crfFrame:UpdateRaidMarkers()
  if not self.raidMarkers then return end

  local markersize = settings.markerssize
  local px, py, pz

  for mark, marker in ipairs(self.raidMarkers) do
    local _,unit = UnitExists(_mark_table[mark])
    if unit and settings.markers and UnitIsVisible(unit) and not UnitIsDead(unit) then
      local tx, ty, tz = UnitPosition(unit)
      marker:SetPosition(tx, ty, tz)

      local distance
      if has_unitxp_sp3 then
        distance = UnitXP("distanceBetween", "player", unit)
      else
        if not px then px, py, pz = UnitPosition("player") end
        distance = calculateDistance(px, py, pz, tx, ty, tz)
      end

      if distance > MARKER_MAX_DIST then
        marker.icon:Hide()
      else
        local scale = 1
        if distance > MARKER_MIN_DIST then
          scale = 1 - (distance - MARKER_MIN_DIST) * MARKER_SCALE_RANGE * MARKER_SCALE_FACTOR
        end

        local size = markersize * scale
        marker.icon:SetWidth(size)
        marker.icon:SetHeight(size)
        marker.icon:Show()
      end
    else
      marker.icon:Hide()
    end
  end
end

function crfFrame:CreateRaidMarkers()
  self.raidMarkers = {}
  for i=1,8 do
    self.raidMarkers[i] = CreateRaidMarker(i)
  end
end

function crfFrame:ACTIONBAR_SLOT_CHANGED(slot)
  if not has_nampower then
    FindMeleeSpell()
  end
end

function crfFrame:UNIT_DIED(guid)
  local _, targetGuid = UnitExists("target")
  if guid == targetGuid then
    playerdot1.icon:Hide()
    lastColorState = nil
  end
end

-- Melee range threshold for distanceBetween (edge-to-edge, hitbox-aware)
local MELEE_RANGE = 2.00

local function IsInRange(distance)
  return distance <= MELEE_RANGE
end

function crfFrame:PLAYER_ENTERING_WORLD()
  crf_isShuttingDown = false
  FindMeleeSpell()

  -- Reset cached UI state
  lastColorState = nil
  lastAlpha = nil
  lastTextureInRange = nil

  -- clean seen-units
  for k,entry in pairs(CRFDB.units) do
    if not UnitExists(entry.guid) then
      CRFDB.units[k] = nil
    end
  end
end

function crfFrame:UNIT_MODEL_CHANGED(guid)
  if not CRFDB.units[guid] then CRFDB.units[guid] = GetUnitData(guid) end
end

-- Pre-allocated FOV lookup tables (created once)
local _fov_values = {0.2, 1, 1.57, 2, 3, 3.14}
local _scaled_values = {0.14, 0.69, 1.135, 1.3125, 1.82, 1.885}
local _fov_count = 6

function ScaleFOV(fov)
  if fov <= _fov_values[1] then
    return _scaled_values[1]
  elseif fov >= _fov_values[_fov_count] then
    return _scaled_values[_fov_count]
  end

  for i = 1, _fov_count - 1 do
    local fov1, fov2 = _fov_values[i], _fov_values[i + 1]
    if fov >= fov1 and fov <= fov2 then
      local scale1, scale2 = _scaled_values[i], _scaled_values[i + 1]
      local m = (scale2 - scale1) / (fov2 - fov1)
      return m * fov + (scale1 - m * fov1)
    end
  end
end

-- Projection parameters (pre-computed to avoid per-frame math)
local screenWidth = GetScreenWidth()
local screenHeight = GetScreenHeight()
local aspectRatio = screenWidth / screenHeight

local c_fov = UnitXP("cameraFoV")
FOV = ScaleFOV(c_fov)
fovScale = tan(FOV / 2)
local invFovScale = 1 / fovScale
-- Combined projection multipliers (invFovScale * halfScreen)
local projX = invFovScale * screenWidth * 0.5
local projY = aspectRatio * invFovScale * screenHeight * 0.5

crfFrame.camera_data = { sinPitch = 0, cosPitch = 0, yaw = 0, sinYaw = 0, cosYaw = 0, x = 0, y = 0, z = 0 }

function crfFrame:UpdateCamera()
  local camera = self.camera_data

  local px, py = UnitPosition("player")
  if not px then return end

  camera.x, camera.y, camera.z = CameraPosition()
  if not camera.x then
    camera.x = 0
    camera.y = 0
    camera.z = 0
  end

  camera.yaw = -atan2(camera.y - py, camera.x - px)

  camera.sinYaw = sin(camera.yaw)
  camera.cosYaw = cos(camera.yaw)

  camera.sinPitch = -UnitXP("cameraPitch")
  camera.cosPitch = sqrt(1 - camera.sinPitch * camera.sinPitch)
end

function crfFrame:ShowArrow()
  return settings.arrow
    and UnitExists("target")
    and UnitIsVisible("target")
    and (settings.any or UnitCanAttack("player","target"))
    and not UnitIsDead("target")
end

local function GetAngleBetweenPoints(x1, y1, x2, y2)
  local angle = atan2(x2 - x1, y2 - y1)
  if angle < 0 then
    return angle + TWO_PI
  end
  return angle
end

local function IsUnitFacingUnit(playerX, playerY, playerFacing, targetX, targetY, maxAngle)
  local angleToTarget = atan2(targetY - playerY, targetX - playerX)
  if angleToTarget < 0 then
    angleToTarget = angleToTarget + TWO_PI
  end

  local angularDifference = mod(angleToTarget - playerFacing, TWO_PI)
  if angularDifference > pi then
    angularDifference = angularDifference - TWO_PI
  elseif angularDifference < -pi then
    angularDifference = angularDifference + TWO_PI
  end

  return abs(angularDifference) <= maxAngle
end

-- Precompute constant values outside the OnUpdate handler
local CONSTANT_FACING_LIMIT = 61 * (pi / 180)  -- constant facing limit in radians
local HALF_PI = pi / 2
local ALPHA_FADE_START = 30
local ALPHA_FADE_END = 50
local ALPHA_FADE_RANGE = 1 / (ALPHA_FADE_END - 25)  -- 1/25

local distance_change = 0
local boss_markers = {}
local elapsed_total = 0
local was_disabled = false
local update_interval = 1 / updates_per_sec

-- Cached color state variables
local lastColorState, lastAlpha = nil, nil
local lastTextureInRange = nil  -- tracks which texture is currently set

function crfFrame_OnUpdate()
  -- Prevent SuperWoW API calls during shutdown (crash prevention)
  if crf_isShuttingDown then return end

  elapsed_total = elapsed_total + arg1
  if elapsed_total < update_interval then return end
  elapsed_total = 0

  local dotCount = getn(DotPool)

  if not settings.enable then
    if not was_disabled then
      for i = 1, dotCount do
        local dot = DotPool[i]
        if dot.inUse then
          dot:Hide()
        end
      end
      playerdot1.icon:Hide()
      was_disabled = true
    end
    return
  elseif settings.enable then
    if was_disabled then
      for i = 1, dotCount do
        local dot = DotPool[i]
        if dot.inUse then
          dot:Show()
        end
      end
      playerdot1.icon:Show()
      was_disabled = false
    end
  end

  local crf = this
  local camera = crf.camera_data
  crf:UpdateCamera()

  local px,py,pz = UnitPosition("player")
  playerdot1:SetPosition(px,py,pz)
  
  local tx,ty,tz
  if UnitExists("target") and UnitIsVisible("target") then
    tx,ty,tz = UnitPosition("target")
    targetdot1:SetPosition(tx,ty,tz)
  end

  -- local cx,cy,cz = CameraPosition()

  crf:UpdateRaidMarkers()

  -- Cache camera values into locals
  local camX, camY, camZ = camera.x, camera.y, camera.z
  local cosYaw, sinYaw = camera.cosYaw, camera.sinYaw
  local cosPitch, sinPitch = camera.cosPitch, camera.sinPitch

  for i = 1, dotCount do
    local dot = DotPool[i]
    if dot.inUse then
      local relX = dot.x - camX
      local relY = dot.y - camY
      local relZ = dot.z - camZ

      -- Yaw rotation
      local yAfterYaw = -(cosYaw * relX - sinYaw * relY)
      local xAfterYaw = (sinYaw * relX + cosYaw * relY)
      local zAfterYaw = relZ

      -- Pitch rotation
      local finalY = (cosPitch * yAfterYaw - sinPitch * zAfterYaw)
      local finalZ = (sinPitch * yAfterYaw + cosPitch * zAfterYaw)
      local finalX = xAfterYaw

      if finalY < 0 then
        dot:Hide()
      else
        dot:Show()
        local normX = finalX / finalY
        local normZ = finalZ / finalY

        local screenX = normX * projX
        local screenY = normZ * projY

        dot:SetPoint("CENTER", UIParent, "CENTER", screenX, screenY)
        dot.screenX = screenX
        dot.screenY = screenY
      end
    end
  end

  -- Arrow update block using cached values
  if crf:ShowArrow() and tx then
    local obj_distance
    if has_unitxp_sp3 then
      obj_distance = UnitXP("distanceBetween", "player", "target")
    else
      obj_distance = calculateDistance(px, py, pz, tx, ty, tz)
    end
    local player_facing = UnitFacing("player")

    local is_facing = player_facing and IsUnitFacingUnit(px, py, player_facing, tx, ty, CONSTANT_FACING_LIMIT)
    local is_behind
    if has_unitxp_sp3 then
      is_behind = UnitXP("behind", "player", "target")
    else
      local target_facing = UnitFacing("target")
      is_behind = target_facing and not IsUnitFacingUnit(tx, ty, target_facing, px, py, HALF_PI)
    end
    local has_los = true
    if has_unitxp_sp3 and settings.los then
      has_los = UnitXP("inSight", "player", "target")
    end

    local _, _, _, pxPoint, pyPoint = playerdot1:GetPoint()
    local _, _, _, txPoint, tyPoint = targetdot1:GetPoint()
    local dx = txPoint - pxPoint
    local dy = tyPoint - pyPoint
    local distance = sqrt(dx * dx + dy * dy)
    local midX = (pxPoint + txPoint) / 2
    local midY = (pyPoint + tyPoint) / 2

    playerdot1.icon:SetWidth(distance)
    playerdot1.icon:SetHeight(distance)

    local angle1 = GetAngleBetweenPoints(pxPoint, pyPoint, txPoint, tyPoint) + (pi / 2)
    RotateTexture(playerdot1.icon, angle1)

    local alpha = (obj_distance < ALPHA_FADE_START) and 1 or ((obj_distance > ALPHA_FADE_END) and 0 or (1 - (obj_distance - 25) * ALPHA_FADE_RANGE))

    -- Determine the new color state and desired RGB values.
    local newColorState, r, g, b
    if not has_los then
      newColorState = "no_los"
      r, g, b = 0.5, 0.5, 0.5
      if lastTextureInRange ~= false then
        playerdot1.icon:SetTexture(textures.out_range)
        lastTextureInRange = false
      end
    elseif IsInRange(obj_distance) then
      if settings.largearrow and lastTextureInRange ~= true then
        playerdot1.icon:SetTexture(textures.in_range)
        lastTextureInRange = true
      end

      if not is_facing then
        newColorState = "not_facing"
        r, g, b = 1, 0.5, 0
      elseif is_behind then
        newColorState = "behind"
        r, g, b = 0.25, 0.75, 0.65
      else
        newColorState = "normal"
        r, g, b = 0.1, 0.85, 0.15
      end
    else
      newColorState = "out_range"
      r, g, b = 0.95, 0.1, 0.1
      if lastTextureInRange ~= false then
        playerdot1.icon:SetTexture(textures.out_range)
        lastTextureInRange = false
      end
    end

    -- Only update the vertex color if the new state differs from the cached state.
    if lastColorState ~= newColorState or lastAlpha ~= alpha then
      playerdot1.icon:SetVertexColor(r, g, b, alpha)
      lastColorState = newColorState
      lastAlpha = alpha
    end

    playerdot1.icon:SetPoint("CENTER", UIParent, "CENTER", midX, midY)
    playerdot1:Show()
    if not playerdot1.icon:IsVisible() then playerdot1.icon:Show() end
  else
    targetdot1.icon:Hide()
    playerdot1.icon:Hide()
  end
end

crfFrame:SetScript("OnUpdate",crfFrame_OnUpdate)
