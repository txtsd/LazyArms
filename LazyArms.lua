-- LazyArms for TurtleWoW
-- Requires pfUI (with libdebuff), Nampower, and UnitXP_SP3.

-- ============================================================================
-- 1. Dependency checks (run once at load)
-- ============================================================================

-- Check pfUI and its libdebuff
local libdebuff = pfUI and pfUI.api and pfUI.api.libdebuff
if not libdebuff then
  print("LazyArms: pfUI or its libdebuff not found – addon disabled.")
  return
end

-- Check Nampower by testing for its version
if not GetNampowerVersion or type(GetNampowerVersion) ~= "function" then
  print("LazyArms: Nampower not loaded – addon disabled.")
  return
end

-- Check UnitXP_SP3 by testing for UnitXP function
if not UnitXP or type(UnitXP) ~= "function" then
  print("LazyArms: UnitXP_SP3 not loaded – addon disabled.")
  return
end

-- ============================================================================
-- 2. Nampower configuration (safe because Nampower is present)
-- ============================================================================
SetCVar("NP_EnableAutoAttackEvents", "1")

-- ============================================================================
-- 3. Spell IDs and rage costs (populated after PLAYER_LOGIN when spellbook is ready)
-- ============================================================================
local SPELL_ID_CHARGE, SPELL_ID_INTERCEPT, SPELL_ID_INTERVENE
local SPELL_ID_OVERPOWER, SPELL_ID_REVENGE, SPELL_ID_EXECUTE
local SPELL_ID_SUNDER_ARMOR, SPELL_ID_SLAM, SPELL_ID_MORTALSTRIKE
local SPELL_ID_WHIRLWIND, SPELL_ID_BATTLE_SHOUT, SPELL_ID_HEROIC_STRIKE
local SPELL_ID_CLEAVE, SPELL_ID_SWEEPING_STRIKES

local STANCE_BERSERKER, STANCE_DEFENSIVE, STANCE_BATTLE

local RAGE_COST_INTERCEPT, RAGE_COST_EXECUTE, RAGE_COST_SUNDER_ARMOR
local RAGE_COST_MORTALSTRIKE, RAGE_COST_WHIRLWIND, RAGE_COST_SLAM, RAGE_COST_CLEAVE

local SLAM_BASE_CAST_MS

-- Expose Armor debuff; skip Sunder Armor when present on target
local DEBUFF_EXPOSE_ARMOR = 11198

local skipSunder = false

local function init_spell_data()
  SPELL_ID_CHARGE          = GetSpellIdForName("Charge")
  SPELL_ID_INTERCEPT       = GetSpellIdForName("Intercept")
  SPELL_ID_INTERVENE       = GetSpellIdForName("Intervene")
  SPELL_ID_OVERPOWER       = GetSpellIdForName("Overpower")
  SPELL_ID_REVENGE         = GetSpellIdForName("Revenge")
  SPELL_ID_EXECUTE         = GetSpellIdForName("Execute")
  SPELL_ID_SUNDER_ARMOR    = GetSpellIdForName("Sunder Armor")
  SPELL_ID_SLAM            = GetSpellIdForName("Slam")
  SPELL_ID_MORTALSTRIKE    = GetSpellIdForName("Mortal Strike")
  SPELL_ID_WHIRLWIND       = GetSpellIdForName("Whirlwind")
  SPELL_ID_BATTLE_SHOUT    = GetSpellIdForName("Battle Shout")
  SPELL_ID_HEROIC_STRIKE   = GetSpellIdForName("Heroic Strike")
  SPELL_ID_CLEAVE          = GetSpellIdForName("Cleave")
  SPELL_ID_SWEEPING_STRIKES = GetSpellIdForName("Sweeping Strikes")

  STANCE_BERSERKER = GetSpellIdForName("Berserker Stance")
  STANCE_DEFENSIVE = GetSpellIdForName("Defensive Stance")
  STANCE_BATTLE    = GetSpellIdForName("Battle Stance")

  -- Rage costs (manaCost is stored * 10, so divide by 10)
  if SPELL_ID_INTERCEPT    then RAGE_COST_INTERCEPT    = GetSpellRecField(SPELL_ID_INTERCEPT,    "manaCost") / 10 end
  if SPELL_ID_EXECUTE      then RAGE_COST_EXECUTE      = GetSpellRecField(SPELL_ID_EXECUTE,      "manaCost") / 10 end
  if SPELL_ID_SUNDER_ARMOR then RAGE_COST_SUNDER_ARMOR = GetSpellRecField(SPELL_ID_SUNDER_ARMOR, "manaCost") / 10 end
  if SPELL_ID_MORTALSTRIKE then RAGE_COST_MORTALSTRIKE = GetSpellRecField(SPELL_ID_MORTALSTRIKE, "manaCost") / 10 end
  if SPELL_ID_WHIRLWIND    then RAGE_COST_WHIRLWIND    = GetSpellRecField(SPELL_ID_WHIRLWIND,    "manaCost") / 10 end
  if SPELL_ID_SLAM         then
    RAGE_COST_SLAM     = GetSpellRecField(SPELL_ID_SLAM, "manaCost") / 10
    SLAM_BASE_CAST_MS  = GetSpellRecField(SPELL_ID_SLAM, "castingTimeIndex") * 100
  end
  if SPELL_ID_CLEAVE       then RAGE_COST_CLEAVE       = GetSpellRecField(SPELL_ID_CLEAVE,       "manaCost") / 10 end
end

-- ============================================================================
-- 4. Helper functions (using stored libdebuff and Nampower)
-- ============================================================================
local function get_sunder_stacks()
  if not UnitExists("target") then
    return 0
  end

  for slot = 1, 16 do
    local name, _, _, stacks, _, _, timeleft = libdebuff:UnitDebuff("target", slot)
    if name and name == "Sunder Armor" then
      return stacks, timeleft or 0
    end
  end
  return 0
end

-- Combat flag caching using Nampower's UNIT_FLAGS_GUID event
local UNIT_FLAG_IN_COMBAT = 524288
local inCombat = false
local combatFrame = CreateFrame("Frame", "LazyArmsCombatTracker")
combatFrame:RegisterEvent("UNIT_FLAGS_GUID")
combatFrame:SetScript("OnEvent", function()
  -- arg1: guid, arg2: isPlayer, arg3: isTarget, arg4: isMouseover, arg5: isPet, arg6: partyIndex, arg7: raidIndex
  if arg2 == 1 then -- only care about player
    local flags = GetUnitField("player", "flags", 1)
    inCombat = flags and (bit.band(flags, UNIT_FLAG_IN_COMBAT) ~= 0) or false
  end
end)

-- Initialize combat flag
local flags = GetUnitField("player", "flags", 1)
inCombat = flags and (bit.band(flags, UNIT_FLAG_IN_COMBAT) ~= 0) or false

-- Replace existing in_combat() with cached value
local function in_combat()
  return inCombat
end

local function has_buff(spellId)
  -- Retrieve the aura table for the player; indices 1‑48 correspond to slots 0‑47
  local auras = GetUnitField("player", "aura", 1)
  if not auras then
    return false
  end

  for i = 1, 48 do
    if auras[i] == spellId then
      return true
    end
  end
  return false
end

local function target_has_debuff(spellId)
  local auras = GetUnitField("target", "aura", 1)
  if not auras then return false end
  for i = 1, 48 do
    if auras[i] == spellId then return true end
  end
  return false
end

local function get_rage()
  local raw = GetUnitField("player", "power2", 1)
  return raw and math.floor(raw / 10) or 0
end

local function is_off_cooldown(spell_id)
  local cd_table = GetSpellIdCooldown(spell_id)
  if cd_table then
    local spell_is_off_cooldown = cd_table.isOnCooldown
    return spell_is_off_cooldown == 0
  end
  return false
end

-- ============================================================================
-- 5. Rotation state
-- ============================================================================
local rotationState = rotationState
  or {
    queued_attack_id = nil,
    lastAutoTime = nil,
    lastSlamCast = nil,
  }

-- ============================================================================
-- 6. Event handling (auto attack, spell queue, etc.)
-- ============================================================================
local frame_autoattack = CreateFrame("Frame", "LazyArmsAutoAttack")
frame_autoattack:RegisterEvent("AUTO_ATTACK_SELF")
frame_autoattack:RegisterEvent("SPELL_DAMAGE_EVENT_SELF")
frame_autoattack:RegisterEvent("SPELL_QUEUE_EVENT")
frame_autoattack:RegisterEvent("PLAYER_LOGIN")
frame_autoattack:RegisterEvent("SPELLS_CHANGED")
frame_autoattack:SetScript("OnEvent", function()
  if event == "PLAYER_LOGIN" or event == "SPELLS_CHANGED" then
    init_spell_data()
  elseif event == "AUTO_ATTACK_SELF" then
    if arg4 then
      rotationState.lastAutoTime = GetTime()
    end
  elseif event == "SPELL_DAMAGE_EVENT_SELF" then
    local spellId = arg3
    local hitInfo = arg6

    if hitInfo then
      -- print("Got hit event: " .. GetSpellRecField(spellId, "name", 1))
    end
  elseif event == "SPELL_QUEUE_EVENT" then
    local eventCode = arg1
    local spellId = arg2

    -- eventCode values: 0=ON_SWING_QUEUED, 1=ON_SWING_QUEUE_POPPED,
    -- 2=NORMAL_QUEUED, 3=NORMAL_QUEUE_POPPED,
    -- 4=NON_GCD_QUEUED, 5=NON_GCD_QUEUE_POPPED
    if eventCode == 0 or eventCode == 2 or eventCode == 4 then
      -- A spell was queued – store its ID
      rotationState.queued_attack_id = spellId
    elseif eventCode == 1 or eventCode == 3 or eventCode == 5 then
      -- A spell was popped from queue – clear the ID
      rotationState.queued_attack_id = nil
    end
  end
end)

-- ============================================================================
-- 7. Pre-rotation (shared between single-target and AoE)
-- ============================================================================
local function pre_rotation(use_sweeping_strikes)
  -- Auto Attack
  local _, _, _, _, _, _, autoattack = GetCurrentCastingInfo()
  if autoattack ~= 1 then
    CastSpellByName("Attack")
    return true
  end

  -- Charge & Intercept (use distance check instead of IsSpellInRange to avoid
  -- nil returns when in the wrong stance)
  if UnitExists("target") and UnitCanAttack("player", "target") == 1 then
    local dist = UnitXP("distanceBetween", "player", "target", "AoE")
    if dist >= 8 and dist <= 25 then
      if is_off_cooldown(SPELL_ID_INTERCEPT) and get_rage() >= RAGE_COST_INTERCEPT
        and (not IsInInstance() or (in_combat() and UnitAffectingCombat("target") == 1)) then
        CastSpellByName("Intercept")
        return true
      end
      if not in_combat() and is_off_cooldown(SPELL_ID_CHARGE) then
        CastSpellByName("Charge")
        return true
      end
    end
  end

  -- Sweeping Strikes (AoE only, before stance check to avoid loop)
  if use_sweeping_strikes then
    if
      in_combat()
      and is_off_cooldown(SPELL_ID_SWEEPING_STRIKES)
      and UnitExists("target")
    then
      CastSpellByName("Sweeping Strikes")
      return true
    end
  end

  -- Berserker Stance
  if not has_buff(STANCE_BERSERKER) then
    CastSpellByName("Berserker Stance")
    return true
  end

  -- Battle Shout
  if not has_buff(SPELL_ID_BATTLE_SHOUT) then
    CastSpellByName("Battle Shout")
    return true
  end

  return false
end

-- ============================================================================
-- 8. Single-target rotation runner
-- ============================================================================
local function run()
  if pre_rotation(false) then return end

  -- Reset rotation state if no target or out of combat
  if not UnitExists("target") or not in_combat() then
    rotationState.lastSlamCast = nil
    rotationState.lastAutoTime = nil
  end

  local rage = get_rage()

  -- Execute
  if UnitExists("target") and UnitCanAttack("player", "target") == 1 then
    local target_hp = GetUnitField("target", "health", 1)
    local target_maxhp = GetUnitField("target", "maxHealth", 1)
    if
      target_hp
      and target_maxhp
      and (target_hp / target_maxhp * 100) <= 20
      and rage >= RAGE_COST_EXECUTE
    then
      CastSpellByName("Execute")
      return
    end
  end

  -- Sunder Armor (skip if target has an equivalent armor-reduction debuff, or mode disabled)
  if
    UnitExists("target")
    and UnitCanAttack("player", "target") == 1
    and not skipSunder
    and not target_has_debuff(DEBUFF_EXPOSE_ARMOR)
  then
    if IsSpellInRange("Sunder Armor", "target") == 1 then
      local sunder_stacks, sunder_timeleft = get_sunder_stacks()
      if sunder_stacks < 5 or sunder_timeleft < 5 then
        local resistances = GetUnitField("target", "resistances")
        local armor = resistances and resistances[1] or 0
        if armor > 0 and rage >= RAGE_COST_SUNDER_ARMOR then
          CastSpellByName("Sunder Armor")
          return
        end
      end
    end
  end

  -- Reactions: require stance switch, so only use when rage <= 25 (Tactical Mastery retention
  -- limit) to avoid losing rage on the switch. Also skip if WW is castable at exactly 25 rage.
  local ww_castable = rage >= RAGE_COST_WHIRLWIND and is_off_cooldown(SPELL_ID_WHIRLWIND)
  if
    IsSpellUsable("Overpower") == 1
    and is_off_cooldown(SPELL_ID_OVERPOWER)
    and rage <= 25
    and not ww_castable
  then
    CastSpellByName("Overpower")
    return
  end
  if
    IsSpellUsable("Revenge") == 1
    and is_off_cooldown(SPELL_ID_REVENGE)
    and rage <= 25
    and not ww_castable
  then
    CastSpellByName("Revenge")
    return
  end

  -- Rotation (priority-based: MS > WW > Slam)
  local castId = GetCurrentCastingInfo()
  local isCastingSlam = castId == SPELL_ID_SLAM

  -- Mortal Strike (instant, highest priority)
  if
    not isCastingSlam
    and rage >= RAGE_COST_MORTALSTRIKE
    and is_off_cooldown(SPELL_ID_MORTALSTRIKE)
    and rotationState.queued_attack_id ~= SPELL_ID_WHIRLWIND
    and UnitExists("target")
    and IsSpellInRange("Mortal Strike", "target") == 1
  then
    CastSpellByName("Mortal Strike")
    return
  end

  -- Whirlwind (instant, second priority)
  if
    not isCastingSlam
    and rage >= RAGE_COST_WHIRLWIND
    and is_off_cooldown(SPELL_ID_WHIRLWIND)
    and rotationState.queued_attack_id ~= SPELL_ID_MORTALSTRIKE
    and UnitExists("target")
    and UnitXP("distanceBetween", "player", "target", "AoE") <= 8
  then
    CastSpellByName("Whirlwind")
    return
  end

  -- Slam (filler, gated on auto-attack to avoid delaying swings)
  -- Window = swing_speed - slam_cast_time: casting outside this pushes back the next auto attack
  local now = GetTime()
  local swing_ms = GetUnitField("player", "baseAttackTime") or 2000
  local mod_cast_speed = GetUnitField("player", "modCastSpeed") or 1.0
  local slam_cast_ms = (SLAM_BASE_CAST_MS or 2000) * mod_cast_speed
  local slam_window_s = (swing_ms - slam_cast_ms) / 1000
  local autoSinceSlam = rotationState.lastAutoTime
    and (not rotationState.lastSlamCast or rotationState.lastAutoTime > rotationState.lastSlamCast)
    and slam_window_s > 0
    and (now - rotationState.lastAutoTime) <= slam_window_s
  if
    autoSinceSlam
    and rage >= RAGE_COST_SLAM
    and is_off_cooldown(SPELL_ID_SLAM)
    and rotationState.queued_attack_id ~= SPELL_ID_MORTALSTRIKE
    and rotationState.queued_attack_id ~= SPELL_ID_WHIRLWIND
    and UnitExists("target")
    and IsSpellInRange("Slam", "target") == 1
  then
    CastSpellByName("Slam")
    rotationState.lastSlamCast = GetTime()
    return
  end

  -- Heroic Strike: queue if next swing would rage cap
  -- Rage formula (hit): ((dmg / 230.6) * 7.5 / 1.075) + (base_speed * 3.5 / 2.25)
  local weapon = GetEquippedItem("player", 16)
  if weapon then
    local base_speed_s  = GetItemStatsField(weapon.itemId, "delay") / 1000
    local avg_dmg       = (GetUnitField("player", "minDamage") + GetUnitField("player", "maxDamage")) / 2
    local dmg_rage      = (avg_dmg / 230.6) * 7.5 / 1.075
    local speed_rage    = base_speed_s * 3.5 / 2.25
    local max_rage      = GetUnitField("player", "maxPower2") / 10
    local would_cap     = (rage + dmg_rage + speed_rage) >= max_rage
    if
      not isCastingSlam
      and would_cap
      and rotationState.queued_attack_id ~= SPELL_ID_HEROIC_STRIKE
      and UnitExists("target")
      and IsSpellInRange("Heroic Strike", "target") == 1
    then
      CastSpellByName("Heroic Strike")
      return
    end
  end
end

-- ============================================================================
-- 9. AoE rotation runner
-- ============================================================================
local function run_aoe()
  if pre_rotation(true) then return end

  local rage = get_rage()

  -- Keep Cleave queued (on-swing, no GCD conflict)
  if
    rage >= RAGE_COST_CLEAVE
    and rotationState.queued_attack_id ~= SPELL_ID_CLEAVE
    and UnitExists("target")
  then
    CastSpellByName("Cleave")
    return
  end

  -- Whirlwind (top GCD priority)
  if
    rage >= RAGE_COST_WHIRLWIND
    and is_off_cooldown(SPELL_ID_WHIRLWIND)
    and UnitExists("target")
    and UnitXP("distanceBetween", "player", "target", "AoE") <= 8
  then
    CastSpellByName("Whirlwind")
    return
  end

  -- Sunder Armor (once per target, tab after this lands; skip if equivalent debuff present or mode disabled)
  if
    UnitExists("target")
    and UnitCanAttack("player", "target") == 1
    and not skipSunder
    and not target_has_debuff(DEBUFF_EXPOSE_ARMOR)
  then
    if IsSpellInRange("Sunder Armor", "target") == 1 then
      local sunder_stacks = get_sunder_stacks()
      if sunder_stacks < 1 then
        local resistances = GetUnitField("target", "resistances")
        local armor = resistances and resistances[1] or 0
        if armor > 0 and rage >= RAGE_COST_SUNDER_ARMOR then
          CastSpellByName("Sunder Armor")
          return
        end
      end
    end
  end

  -- Mortal Strike (fill GCDs)
  if
    rage >= RAGE_COST_MORTALSTRIKE
    and is_off_cooldown(SPELL_ID_MORTALSTRIKE)
    and UnitExists("target")
    and IsSpellInRange("Mortal Strike", "target") == 1
  then
    CastSpellByName("Mortal Strike")
    return
  end

  -- Execute (low priority, only as last GCD)
  if UnitExists("target") and UnitCanAttack("player", "target") == 1 then
    local target_hp = GetUnitField("target", "health", 1)
    local target_maxhp = GetUnitField("target", "maxHealth", 1)
    if
      target_hp
      and target_maxhp
      and (target_hp / target_maxhp * 100) <= 20
      and rage >= RAGE_COST_EXECUTE
    then
      CastSpellByName("Execute")
      return
    end
  end
end

-- ============================================================================
-- 10. Slash command registration
-- ============================================================================
SlashCmdList["LAZYARMS_SLASH"] = run
SLASH_LAZYARMS_SLASH1 = "/lazyarms"

SlashCmdList["LAZYARMS_AOE_SLASH"] = run_aoe
SLASH_LAZYARMS_AOE_SLASH1 = "/lazyarmsaoe"

SlashCmdList["LAZYARMS_NOSUNDER_SLASH"] = function()
  skipSunder = not skipSunder
  print("LazyArms: Sunder Armor " .. (skipSunder and "disabled" or "enabled"))
end
SLASH_LAZYARMS_NOSUNDER_SLASH1 = "/lazyarmsnosunder"
