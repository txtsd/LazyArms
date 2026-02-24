local libdebuff = pfUI and pfUI.env and pfUI.env.libdebuff

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
        print("Charging!")
        CastSpellByName("Charge")
        return
      elseif in_combat() and intercept.isOnCooldown == 0 and GetUnitField("player", "power2") >= 10 then
        print("Intercepting!")
        CastSpellByName("Intercept")
        return
        -- elseif in_combat() and intervene.isOnCooldown == 0 then
        --   print("Intervening!")
        --   CastSpellByName("Intervene")
      end
    end
  end

  -- ==========
  -- Battle Shout
  -- ==========
  if not has_buff("Battle Shout") then
    print("Battle Shouting!")
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
          print("Sundering!")
          CastSpellByName("Sunder Armor")
          return
        end
      end
    end
  end

  -- ==========
  -- Execute
  -- ==========
  if UnitExists("target") and UnitCanAttack("player", "target") == 1 then
    local target_hp = GetUnitField("target", "health")
    local target_maxhp = GetUnitField("target", "maxHealth")
    if (target_hp / target_maxhp * 100) <= 20 and GetUnitField("player", "power2") >= 15 then
      print("Executing!")
      CastSpellByName("Execute")
      return
    end
  end

  -- if GetUnitField("player", "power2") > 15 and UnitExists("target") then
  --   print("Slamming!")
  --   CastSpellByName("Slam")
  --   return
  -- end
  --
  -- if GetUnitField("player", "power2") > 30 and UnitExists("target") then
  --   print("Mortal Striking!")
  --   CastSpellByName("Mortal Strike")
  --   return
  -- end
end

SlashCmdList["LAZYARMS_SLASH"] = run
SLASH_LAZYARMS_SLASH1 = "/lazyarms"
