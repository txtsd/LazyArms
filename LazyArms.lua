local libdebuff = pfUI and pfUI.env and pfUI.env.libdebuff

SetCVar("NP_EnableAutoAttackEvents", "1")

local function get_sunder_stacks()
  if not libdebuff then
    print("No libdebuff")
    return 0
  end

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

local function in_combat()
  local flags = GetUnitField("player", "flags")
  local UNIT_FLAG_IN_COMBAT = 524288
  return bit.band(flags, UNIT_FLAG_IN_COMBAT) ~= 0
end

local function has_buff(buff_name)
  for i = 1, 40 do
    local _, _, buff_id = UnitBuff("player", i)
    if buff_id then
      local spell_name = SpellInfo(buff_id)
      if spell_name == buff_name then
        return true
      end
    end
  end
  return false
end

-- Saved variable for persistence
local rotationState = rotationState
  or {
    stepIndex = 1,
    lastAction = nil,
    nextStepAfter = nil,
    waitingFor = nil,
    queued_attack = nil,
  }

-- Define the rotation as a state machine
local rotation = {
  -- Step 1: Slam
  {
    spell = "Slam",
    next = 2,
    condition = function()
      local slam_cd = GetSpellIdCooldown(45961) -- Slam (Rank 5)
      local distance = UnitXP("distanceBetween", "player", "target")
      if
        GetUnitField("player", "power2") >= 15
        and slam_cd.isOnCooldown == 0
        and rotationState.queued_attack ~= "Mortal Strike"
        and rotationState.queued_attack ~= "Whirlwind"
        and distance <= 5
      then
        return true
      end
    end,
  },
  -- Step 2: Wait for Auto
  {
    waitFor = "auto",
    next = 3,
    condition = function()
      -- Check if auto attack just happened
      return GetTime() - (rotationState.lastAutoTime or 0) > 0.1
    end,
  },
  -- Step 3: Mortal Strike
  {
    spell = "Mortal Strike",
    next = 4,
    condition = function()
      local mortalstrike_cd = GetSpellIdCooldown(27580) -- Mortal Strike (Rank 4)
      local distance = UnitXP("distanceBetween", "player", "target")
      if
        GetUnitField("player", "power2") >= 30
        and mortalstrike_cd.isOnCooldown == 0
        and rotationState.queued_attack ~= "Whirlwind"
        and not IsCurrentAction(62)
        and distance <= 5
      then
        return true
      end
    end,
  },
  -- Step 4: Slam
  {
    spell = "Slam",
    next = 5,
    condition = function()
      local slam_cd = GetSpellIdCooldown(45961) -- Slam (Rank 5)
      local distance = UnitXP("distanceBetween", "player", "target")
      if
        GetUnitField("player", "power2") >= 15
        and slam_cd.isOnCooldown == 0
        and rotationState.queued_attack ~= "Mortal Strike"
        and rotationState.queued_attack ~= "Whirlwind"
        and distance <= 5
      then
        return true
      end
    end,
  },
  -- Step 5: Wait for Auto
  {
    waitFor = "auto",
    next = 6,
    condition = function()
      return GetTime() - (rotationState.lastAutoTime or 0) > 0.1
    end,
  },
  -- Step 6: Whirlwind
  {
    spell = "Whirlwind",
    next = 7,
    condition = function()
      whirlwind_cd = GetSpellIdCooldown(1680) -- Whirlwind
      local distance = UnitXP("distanceBetween", "player", "target")
      if
        GetUnitField("player", "power2") >= 25
        and whirlwind_cd.isOnCooldown == 0
        and rotationState.queued_attack ~= "Mortal Strike"
        and not IsCurrentAction(62)
        and distance <= 8
      then
        return true
      end
    end,
  },
  -- Step 7: Slam
  {
    spell = "Slam",
    next = 8,
    condition = function()
      local slam_cd = GetSpellIdCooldown(45961) -- Slam (Rank 5)
      local distance = UnitXP("distanceBetween", "player", "target")
      if
        GetUnitField("player", "power2") >= 15
        and slam_cd.isOnCooldown == 0
        and rotationState.queued_attack ~= "Mortal Strike"
        and rotationState.queued_attack ~= "Whirlwind"
        and distance <= 5
      then
        return true
      end
    end,
  },
  -- Step 8: Wait for Auto
  {
    waitFor = "auto",
    next = 3, -- Loop back to Mortal Strike
    condition = function()
      return GetTime() - (rotationState.lastAutoTime or 0) > 0.1
    end,
  },
}

-- Track when auto attacks happen
local frame_autoattack = CreateFrame("Frame", "LazyArmsAutoAttack")
frame_autoattack:RegisterEvent("AUTO_ATTACK_SELF")
frame_autoattack:RegisterEvent("SPELL_DAMAGE_EVENT_SELF")
frame_autoattack:RegisterEvent("SPELL_QUEUE_EVENT")
frame_autoattack:SetScript("OnEvent", function()
  if event == "AUTO_ATTACK_SELF" then
    local attackerGuid = arg1
    local targetGuid = arg2
    local hitInfo = arg4
    local victimState = arg5

    if hitInfo then
      -- print("Got autoattack event!")
      rotationState.lastAutoTime = GetTime()
    end
  elseif event == "SPELL_DAMAGE_EVENT_SELF" then
    local spellId = arg3
    local hitInfo = arg6

    if hitInfo then
      -- print("Got hit event: " .. SpellInfo(spellId))
    end
  elseif event == "SPELL_QUEUE_EVENT" then
    local eventCode = arg1
    local spellId = arg2

    if eventCode == 0 or eventCode == 2 or eventCode == 4 then
      rotationState.queued_attack = SpellInfo(spellId)
    elseif eventCode == 1 or eventCode == 3 or eventCode == 5 then
      rotationState.queued_attack = nil
    end
  end
end)

local function run()
  -- ==========
  -- Auto Attack
  -- ==========
  local auto_attack = 1
  for i = 1, 172 do
    if IsCurrentAction(i) then
      auto_attack = 0
    end
  end
  if auto_attack == 1 then
    CastSpellByName("Attack")
  end

  -- ==========
  -- Charge & Intercept
  -- ==========
  if UnitExists("target") and UnitCanAttack("player", "target") == 1 then
    local charge = GetSpellIdCooldown(11578) -- Charge (Rank 3)
    local intercept = GetSpellIdCooldown(20617) -- Intercept (Rank 3)
    -- local intervene = GetSpellIdCooldown(45595) -- Intervene (Rank 1)
    local distance = UnitXP("distanceBetween", "player", "target")
    if distance >= 8 and distance <= 25 then
      if not in_combat() and charge.isOnCooldown == 0 then
        -- print("Charging!")
        CastSpellByName("Charge")
        return
      elseif in_combat() and intercept.isOnCooldown == 0 and GetUnitField("player", "power2") >= 10 then
        -- print("Intercepting!")
        CastSpellByName("Intercept")
        return
        -- elseif in_combat() and intervene.isOnCooldown == 0 then
        --   -- print("Intervening!")
        --   CastSpellByName("Intervene")
      end
    end
  end

  -- ==========
  -- Battle Shout
  -- ==========
  if not has_buff("Battle Shout") then
    -- print("Battle Shouting!")
    CastSpellByName("Battle Shout")
    return
  end

  -- ==========
  -- Sunder Armor
  -- ==========
  if UnitExists("target") and UnitCanAttack("player", "target") == 1 then
    local distance = UnitXP("distanceBetween", "player", "target")
    if distance <= 5 then
      local sunder_stacks, sunder_timeleft = get_sunder_stacks()
      if sunder_stacks < 4 or sunder_timeleft < 5 then
        if GetUnitField("player", "power2") >= 10 and UnitExists("target") then
          -- print("Sundering!")
          CastSpellByName("Sunder Armor")
          return
        end
      end
    end
  end

  -- ==========
  -- Reactions
  -- ==========
  local overpower = IsSpellUsable("Overpower")
  local overpower_cd = GetSpellIdCooldown(11585) -- Overpower (Rank 4)
  if overpower == 1 and GetUnitField("player", "power2") <= 50 and overpower_cd.isOnCooldown == 0 then
    CastSpellByName("Overpower")
    return
  end

  local revenge = IsSpellUsable("Revenge")
  local revenge_cd = GetSpellIdCooldown(11601) -- Revenge (Rank 5)
  if revenge == 1 and GetUnitField("player", "power2") <= 50 and revenge_cd.isOnCooldown == 0 then
    CastSpellByName("Revenge")
    return
  end

  -- ==========
  -- Execute
  -- ==========
  if UnitExists("target") and UnitCanAttack("player", "target") == 1 then
    local target_hp = GetUnitField("target", "health")
    local target_maxhp = GetUnitField("target", "maxHealth")
    if (target_hp / target_maxhp * 100) <= 20 and GetUnitField("player", "power2") >= 15 then
      -- print("Executing!")
      CastSpellByName("Execute")
      return
    end
  end

  -- ==========
  -- Rest of the rotation
  -- ==========

  local currentStep = rotation[rotationState.stepIndex]
  if not currentStep then
    rotationState.stepIndex = 1
    return
  end

  -- Check if conditions are met
  if currentStep.condition() then
    -- Cast spell if this step has one
    if currentStep.spell then
      -- print("Casting: " .. currentStep.spell)
      CastSpellByName(currentStep.spell)
      rotationState.lastCast = currentStep.spell
    end

    -- Move to next step
    rotationState.stepIndex = currentStep.next
  end
end

SlashCmdList["LAZYARMS_SLASH"] = run
SLASH_LAZYARMS_SLASH1 = "/lazyarms"
