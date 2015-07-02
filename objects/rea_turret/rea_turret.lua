-- Needed Json Params: 
-- <int> turLevel, 
-- <float> turFireTime, 
-- <int> turConsumeEnergy, 
-- <path> turFireSound,
-- <int> turDamPerShot, 
-- <float> turFireSpeed, 
-- <int / 1> turSpread, 
-- <projectileName> projToFire, 
-- <effectName> turDebuff
-- @Kayuko

function init(args)
  --Bunch of parameters
  self.baseOffset = entity.configParameter("baseOffset")
  self.tipOffset = entity.configParameter("tipOffset") --This is offset from BASE position, not object origin

  self.targetRange = entity.configParameter("targetRange")
  self.targetCooldown = entity.configParameter("targetCooldown")
  self.targetAngleRange = entity.configParameter("targetAngleRange")
  self.maxTrackingYVel = entity.configParameter("maxTrackingYVel")
  self.targetOffset = entity.configParameter("targetOffset")
  self.minTargetRange = entity.configParameter("minTargetRange")

  self.rotationRange = entity.configParameter("rotationRange")
  self.rotationTime = entity.configParameter("rotationTime")

  self.letGoCooldown = entity.configParameter("letGoCooldown")

  self.energy = entity.configParameter("energy")
  self.maxEnergy = self.energy.baseEnergy

  self.state = stateMachine.create({
    "deadState",
    "attackState",
    "scanState"
  })
  self.active = true
  self.isActive = nil

  entity.setAnimationState("movement", "idle")
  entity.setInteractive(true)
  --entity.setAllOutboundNodes(false)

  if storage.energy == nil then setEnergy(self.maxEnergy) end
  
  --checkInboundNode()
end

--------------------------------------------------------------------------------
--stateMachine update per deltatime
function update(dt)
  self.state.update(dt)
end

--------------------------------------------------------------------------------
--Enable wiring

function onNodeConnectionChange(args)
  if entity.isInboundNodeConnected(0) then
    onInboundNodeChange({ level = entity.getInboundNodeLevel(0) })
  end
end

function onInboundNodeChange(args)
  if args.level then
    isActive = true
  else
    isActive = false
  end
end
--------------------------------------------------------------------------------

function getBasePosition()
  return entity.toAbsolutePosition(self.baseOffset)
end

--------------------------------------------------------------------------------

function visibleTarget(targetId)
  local targetPosition = targetPos(targetId)
  local basePosition = getBasePosition()
  local angleRange = self.targetAngleRange * math.pi / 180;

  --Check if target angle is in angle range
  local targetVector = world.distance(targetPosition, basePosition)
  local targetAngle = directionTransformAngle(math.atan2(targetVector[2], targetVector[1]))
  if targetAngle < -angleRange or targetAngle > angleRange then
    return false
  end
  
  --Check for blocks in the way
  local blocks = world.collisionBlocksAlongLine(basePosition, targetPosition, "Dynamic", 1)
  if #blocks > 0 then
    return false
  end
  
  return true
end


function validTarget(targetId)
  local selfId = entity.id()
  
  --Does it exist?
  if world.entityExists(targetId) == false then
    return false
  end
  
  --Is it dead yet
  local targetHealth = world.entityHealth(targetId)
  if targetHealth ~= nil and targetHealth[1] <= 0 then
    return false
  end
  
  --Is it in range and visible
  local direction = entity.direction()
  local distance = world.magnitude(targetPos(targetId), getBasePosition())
  
  if distance < self.targetRange and distance > self.minTargetRange and visibleTarget(targetId) then
    return true
  else
    return false
  end
end

--------------------------------------------------------------------------------

function directionTransformAngle(angle)
  local direction = 1
  if entity.direction() < 0 then
    direction = -1
  end
  local angleVec = {direction * math.cos(angle), math.sin(angle)}
  return math.atan2(angleVec[2], angleVec[1])
end

--------------------------------------------------------------------------------

function potentialTargets()  
  --Gets all valid player + monster targets
  local playerIds = world.entityQuery(getBasePosition(), self.targetRange, { includedTypes = {"player"} })
  local monsterIds = world.entityQuery(getBasePosition(), self.targetRange, { includedTypes = {"monster"} })

  for i,playerId in ipairs(playerIds) do
    if entity.isValidTarget(playerId) then
      monsterIds[#monsterIds+1] = playerId
    end
  end
  
  return monsterIds
end


--------------------------------------------------------------------------------
function findTarget()
  local selfId = entity.id()
  
  local minDistance = self.targetRange
  local winnerEntity = 0
  
  local entityIds = potentialTargets()
  
  for i, entityId in ipairs(entityIds) do
    
    local distance = world.magnitude(getBasePosition(), targetPos(entityId))
  
    if validTarget(entityId) then
      winnerEntity = entityId
      minDistance = distance
    end
  end
  
  return winnerEntity
end

--------------------------------------------------------------------------------

function setActive(active)
  self.active = active
end

--function isActive()
--  if entity.isInboundNodeConnected(0) and not entity.getInboundNodeLevel(0) then
--    return false
--  else
--    return self.gunStats ~= false
--  end
--end 

function setEnergy(energy)
  storage.energy = energy

  local level = entity.configParameter("turLevel") or 1
  self.maxEnergy = self.energy.baseEnergy + root.evalFunction("npcLevelEnergyIncrease", level) * self.energy.baseEnergy

  if storage.energy > self.maxEnergy then storage.energy = self.maxEnergy end
  
  local animationState = "full"
  
  if energy / self.maxEnergy <= 0.75 then animationState = "high" end
  if energy / self.maxEnergy <= 0.5 then animationState = "medium" end
  if energy / self.maxEnergy <= 0.25 then animationState = "low" end
  if energy / self.maxEnergy <= 0 then animationState = "none" end

  entity.scaleGroup("energy", {energy / self.maxEnergy * 11, 1})
  entity.scaleGroup("energyv", {1, energy / self.maxEnergy * 11})
  
  entity.setAnimationState("energy", animationState)
end

function consumeEnergy(amount)
  if storage.energy - amount < 0 then
    return false 
  end

  setEnergy(storage.energy - amount)
  return true
end

function regenEnergy()
  local energyRegenFactor = self.energy.energyRegen / self.energy.baseEnergy
  local energy = storage.energy + energyRegenFactor * self.maxEnergy * script.updateDt()
  setEnergy(energy)
end

--------------------------------------------------------------------------------

function targetPos(entityId)
  local position = world.entityPosition(entityId)
  --Until I can get the center of a target collision poly
  position[1] = position[1] + self.targetOffset[1]
  position[2] = position[2] + self.targetOffset[2]
  return position
end

function dotProduct(firstVector, secondVector)
  return firstVector[1] * secondVector[1] + firstVector[2] * secondVector[2]
end

function predictedPosition(targetPosition, basePosition, targetVel, bulletSpeed)
  local targetVector = world.distance(targetPosition, basePosition)
  local bs = bulletSpeed
  local dotVectorVel = dotProduct(targetVector, targetVel)
  local vector2 = dotProduct(targetVector, targetVector)
  local vel2 = dotProduct(targetVel, targetVel)
  
  --If the answer is a complex number, for the love of god don't continue
  if ((2*dotVectorVel) * (2*dotVectorVel)) - (4 * (vel2 - bs * bs) * vector2) < 0 then
    return targetPosition
  end
  
  local timesToHit = {} --Gets two values from solving quadratic equation
  --Quadratic formula up in dis
  timesToHit[1] = (-2 * dotVectorVel + math.sqrt((2*dotVectorVel) * (2*dotVectorVel) - 4*(vel2 - bs * bs) * vector2)) / (2 * (vel2 - bs * bs))
  timesToHit[2] = (-2 * dotVectorVel - math.sqrt((2*dotVectorVel) * (2*dotVectorVel) - 4*(vel2 - bs * bs) * vector2)) / (2 * (vel2 - bs * bs))
  
  --Find the nearest lowest positive solution
  local timeToHit = 0
  if timesToHit[1] > 0 and (timesToHit[1] <= timesToHit[2] or timesToHit[2] < 0) then timeToHit = timesToHit[1] end
  if timesToHit[2] > 0 and (timesToHit[2] <= timesToHit[1] or timesToHit[1] < 0) then timeToHit = timesToHit[2] end
  
  local predictedPos = vec2.add(targetPosition, vec2.mul(targetVel, timeToHit))
  return predictedPos
end

--------------------------------------------------------------------------------

deadState = {}

function deadState.enter()
  if not isActive then
    return {}
  end
end

function deadState.enteringState(stateData)
  entity.setAnimationState("movement", "dead")
  local rotationRange = self.rotationRange * math.pi / 180;
  entity.rotateGroup("gun", -rotationRange)
  entity.setAllOutboundNodes(false)

  setEnergy(0)
end

function deadState.update(dt, stateData)
  local rotationRange = self.rotationRange * math.pi / 180;
  entity.rotateGroup("gun", -rotationRange)

  if isActive then
    return true
  end

  return false
end

function deadState.leavingState(stateData)
  entity.playSound("powerUp")
  self.state.pickState()
end

--------------------------------------------------------------------------------
scanState = {}

function scanState.enter()
  if isActive then
    return {
      timer = 0,
      targetCooldown = self.targetCooldown,
      targetId = nil
    }
  end
end

function scanState.enteringState(stateData)
  entity.setAnimationState("movement", "idle")
  entity.setAllOutboundNodes(false)
end

function scanState.update(dt, stateData)
  if not isActive then
    return true
  end
  
  regenEnergy()

  scanState.rotateGun(stateData)
  
  local targetEntity = scanState.scanForTargets(stateData)
  if targetEntity then
      stateData.targetId = targetEntity
      return true
  end

  return false
end

function scanState.rotateGun(stateData)
  local rotationRange = self.rotationRange * math.pi / 180;
  local angle = rotationRange * math.sin(stateData.timer / self.rotationTime * math.pi * 2)
  entity.rotateGroup("gun", angle)

  stateData.timer = stateData.timer + script.updateDt()
  if stateData.timer > self.rotationTime then
    stateData.timer = 0
  end
end

function scanState.scanForTargets(stateData)
  --Look for targets
  if stateData.targetCooldown <= 0 then
    local targetEntity = findTarget()
    if targetEntity ~= 0 then
        return targetEntity
    end
    stateData.targetCooldown = self.targetCooldown
  end

  stateData.targetCooldown = stateData.targetCooldown - script.updateDt()
  if stateData.targetCooldown < 0 then
    stateData.targetCooldown = 0
  end
  return false
end

function scanState.leavingState(stateData)
  if storage.energy <= 0 or isActive == false then
    entity.playSound("powerDown")
  end
  self.state.pickState(stateData.targetId)
end

--------------------------------------------------------------------------------
attackState = {}

function attackState.enterWith(targetId)
  if targetId ~= nil and world.entityPosition(targetId) ~= nil then
    return {
      fireTimer = 0,
      targetId = targetId,
      lastPosition = targetPos(targetId),
      letGoTimer = 0
    }
  end
end

function attackState.enteringState(stateData)
  entity.playSound("foundTarget")
  
  entity.setAnimationState("movement", "attack")
  entity.setAllOutboundNodes(true)
end

function attackState.update(dt, stateData)
  if not isActive then
    return true
  end

  regenEnergy()
  
  local haveTarget = attackState.haveValidTarget(stateData)
  
  if haveTarget then

    attackState.followTarget(stateData)
    
    if stateData.fireTimer >= entity.configParameter("turFireTime") and consumeEnergy(entity.configParameter("turConsumeEnergy")) then

      attackState.fire(stateData)

      stateData.fireTimer = stateData.fireTimer - entity.configParameter("turFireTime")
    end
    
    stateData.fireTimer = stateData.fireTimer + dt
  elseif stateData.letGoTimer > self.letGoCooldown or world.entityPosition == nil then
      return true
  end

  return false
end

function attackState.fire(stateData)
  local direction = entity.direction()
  
  local aimAngle = entity.currentRotationAngle("gun")

  local tipPosition = attackState.tipPosition(stateData, aimAngle)
  local aimVector = {direction * math.cos(aimAngle), math.sin(aimAngle)}
  
  if entity.configParameter("turSpread") == 1 then
    world.spawnProjectile(entity.configParameter("projToFire"), tipPosition, entity.id(), aimVector, false, {power = entity.configParameter("turDamPerShot"), speed = entity.configParameter("turFireSpeed"), statusEffects = entity.configParameter("turDebuff"), damageType = "IgnoresDef"})
  elseif entity.configParameter("turSpread") > 1 then
    for i = 0, entity.configParameter("turSpread") do
      local angleOffset = (math.random() * 4 - 2) / 100 * entity.configParameter("turSpread");
      local newAngle = aimAngle + angleOffset
      aimVector = {direction * math.cos(newAngle), math.sin(newAngle)}
      world.spawnProjectile(entity.configParameter("projToFire"), tipPosition, entity.id(), aimVector, false, {power = entity.configParameter("turDamPerShot") / entity.configParameter("turSpread"), speed = entity.configParameter("turFireSpeed"), statusEffects = entity.configParameter("turDebuff"), damageType = "IgnoresDef"})
    end
  end
end

function attackState.haveValidTarget(stateData)
  if validTarget(stateData.targetId) then
    stateData.letGoTimer = 0
    return true
  end
  stateData.letGoTimer = stateData.letGoTimer + script.updateDt()
  return false
end

function attackState.tipPosition(stateData, aimAngle)
  local tipOffset = {self.tipOffset[1], self.tipOffset[2]}
  if entity.direction() < 0 then tipOffset[2] = tipOffset[2] + 0.125 end --Most bullets are odd height, this fixes an offset issue where their origin is slightly below middle
  tipOffset = vec2.rotate(tipOffset, aimAngle)
  tipOffset[1] = entity.direction() * tipOffset[1]

  return vec2.add(getBasePosition(), tipOffset)
end

function attackState.targetVelocity(stateData)
  local targetPosition = targetPos(stateData.targetId)
  local deltaPos = {targetPosition[1] - stateData.lastPosition[1], targetPosition[2] - stateData.lastPosition[2]}
  stateData.lastPosition = targetPosition
  return vec2.div(deltaPos, script.updateDt())
end

function attackState.followTarget(stateData)
  --Make it follow the target's predicted position
  local targetVelocity = attackState.targetVelocity(stateData)
  targetVelocity[2] = math.max(math.min(targetVelocity[2], self.maxTrackingYVel), -self.maxTrackingYVel) --Don't track the Y velocity too much because of jumping
  local predictedPos = predictedPosition(targetPos(stateData.targetId), getBasePosition(), targetVelocity, entity.configParameter("turFireSpeed"))
  
  local targetVector = world.distance(predictedPos, getBasePosition())
  angle = directionTransformAngle(math.atan2(targetVector[2], targetVector[1]))
  angle = math.max(math.min(angle, self.targetAngleRange), -self.targetAngleRange)
  
  entity.rotateGroup("gun", angle)
end

function attackState.leavingState(stateData)
  if storage.energy <= 0 or isActive == false then
    entity.playSound("powerDown")
  else
    entity.playSound("scan")
  end
  self.state.pickState()
end
