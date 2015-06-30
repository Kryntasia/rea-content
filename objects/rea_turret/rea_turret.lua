--[ Experimental -- Not tested yet, should work -- @Kayuko]

function init(virtual)
  if not virtual then
    self.state = stateMachine.create({
      "attackState",
      "scanState"
    })

    entity.setAnimationState("movement", "idle")
    entity.setInteractive(false)
    entity.setAllOutboundNodes(false)
  end
end

--------------------------------------------------------------------------------
function update(dt)
  self.state.update(dt)
end

--------------------------------------------------------------------------------
function toAbsolutePosition(offset)
  if entity.direction() > 0 then
    return vec2.add(entity.position(), offset)
  else
    return vec2.sub(entity.position(), offset)
  end
end

--------------------------------------------------------------------------------
function getBasePosition()
  local baseOffset = entity.configParameter("baseOffset")
  return toAbsolutePosition(baseOffset)
end

--------------------------------------------------------------------------------
function setAimAngle(basePosition, targetAimAngle)
  entity.rotateGroup("gun", -targetAimAngle)

  local tipOffset = entity.configParameter("tipOffset")
  local tipPosition = toAbsolutePosition(tipOffset)

  local aimAngle = entity.currentRotationAngle("gun")
  local facingDirection = entity.direction()
  local aimVector = vec2.rotate(world.distance(tipPosition, basePosition), aimAngle * facingDirection)

  tipPosition = vec2.add(basePosition, aimVector)
  tipOffset = world.distance(tipPosition, entity.position())

  aimVector = vec2.norm(aimVector)

  local laserVector = vec2.mul(aimVector, entity.configParameter("maxLaserLength"))
  local laserEndpoint = vec2.add({ tipPosition[1], tipPosition[2] }, laserVector)

  local blocks = world.collisionBlocksAlongLine(tipPosition, laserEndpoint, "Dynamic", 1)
  if #blocks > 0 then
    local blockPosition = blocks[1]
    local delta = world.distance(blockPosition, tipPosition)

    local x0, x1 = blockPosition[1], blockPosition[1] + 1
    if delta[1] < 0 then x0, x1 = x1, x0 end

    local y0, y1 = blockPosition[2], blockPosition[2] + 1
    if delta[2] < 0 then y0, y1 = y1, y0 end

    local xIntersection = vec2.intersect(tipPosition, laserEndpoint, { x0, y0 }, { x0, y1 })
    local yIntersection = vec2.intersect(tipPosition, laserEndpoint, { x0, y0 }, { x1, y0 })

    if yIntersection == nil then
      if xIntersection ~= nil then laserEndpoint = xIntersection end
    elseif xIntersection == nil then
      if yIntersection ~= nil then laserEndpoint = yIntersection end
    else
      local xSegment = world.distance(xIntersection, tipPosition)
      local ySegment = world.distance(yIntersection, tipPosition)
      if world.magnitude(xSegment) > world.magnitude(ySegment) then
        laserEndpoint = yIntersection
      else
        laserEndpoint = xIntersection
      end
    end
  end

  world.debugLine(tipPosition, laserEndpoint, "red")

  return -aimAngle, tipPosition, laserEndpoint
end

--------------------------------------------------------------------------------
scanState = {}

function scanState.enter()
  return {
    timer = -entity.configParameter("rotationPauseTime"),
    direction = 1
  }
end

function scanState.enteringState(stateData)
  entity.setAnimationState("beam", "visible")
end

function scanState.update(dt, stateData)
  local rotationRange = vec2.mul(entity.configParameter("rotationRange"), math.pi / 180)
  local rotationTime = entity.configParameter("rotationTime")

  local angle = util.easeInOutQuad(
    util.clamp(stateData.timer, 0, rotationTime) / rotationTime,
    rotationRange[1],
    rotationRange[2]
  )

  if stateData.direction < 0 then
    angle = rotationRange[2] - angle
  end

  if stateData.timer < 0 or stateData.timer > rotationTime then
    entity.setAnimationState("movement", "idle")
  else
    entity.setAnimationState("movement", "idle")
  end

  local basePosition = getBasePosition()
  local aimAngle, laserOrigin, laserEndpoint = setAimAngle(basePosition, angle)

  local length = world.magnitude(laserOrigin, laserEndpoint)
  entity.scaleGroup("beam", { length, 1.0 })

  local targetId = scanState.findTarget(laserOrigin, laserEndpoint)
  if targetId ~= 0 then
    self.state.pickState(targetId)
    return true
  end

  stateData.timer = stateData.timer + dt
  if stateData.timer > rotationTime then
    stateData.timer = -entity.configParameter("rotationPauseTime")
    stateData.direction = -stateData.direction
  end

  return false
end

function scanState.leavingState(stateData)
  entity.setAnimationState("beam", "invisible")
end

function scanState.findTarget(startPosition, endPosition)
  local selfId = entity.id()

  local entityIds = world.entityLineQuery(startPosition, endPosition, { includedTypes = {"player"}, withoutEntityId = selfId })
  for i, entityId in ipairs(entityIds) do
    if entityId ~= selfId then
      return entityId
    end
  end

  return 0
end

--------------------------------------------------------------------------------
attackState = {}

function attackState.enterWith(targetId)
  entity.rotateGroup("gun", entity.currentRotationAngle("gun"))
  entity.setAnimationState("movement", "attack")
  entity.setAllOutboundNodes(true)
  return {
    timer = 0,
    fireTimer = 0,
    fireOffsetIndex = 1,
    targetId = targetId
  }
end

function attackState.update(dt, stateData)
  local targetPosition = world.entityPosition(stateData.targetId)
  if targetPosition == nil then
    entity.setAnimationState("movement", "idle")
    entity.setAllOutboundNodes(false)
    return true
  end

  local basePosition = getBasePosition()
  local toTarget = world.distance(targetPosition, basePosition)

  local desiredAimAngle = vec2.angle(toTarget) * entity.direction()
  if desiredAimAngle > math.pi then desiredAimAngle = 2 * math.pi - desiredAimAngle end

  local rotationRange = vec2.mul(entity.configParameter("rotationRange"), math.pi / 180)
  desiredAimAngle = util.clamp(desiredAimAngle, rotationRange[1], rotationRange[2])

  local aimAngle, laserOrigin, laserEndpoint = setAimAngle(basePosition, desiredAimAngle)

  if not attackState.isVisible(laserOrigin, laserEndpoint, stateData.targetId) then
    entity.rotateGroup("gun", entity.currentRotationAngle("gun"))

    stateData.timer = stateData.timer + dt
  else
    stateData.fireTimer = stateData.fireTimer - dt
    if stateData.fireTimer <= 0 then
      local fireDirection = vec2.norm(vec2.sub(laserEndpoint, laserOrigin))
      local fireOffsets = entity.configParameter("fireOffsets")
      local fireOffset = fireOffsets[stateData.fireOffsetIndex]
      local orthoDirection = { -fireDirection[2], fireDirection[1] }
      local firePosition = vec2.add(laserOrigin, vec2.mul(orthoDirection, fireOffset))

      world.spawnProjectile("bullet-1", firePosition, entity.id(), fireDirection)

      stateData.fireTimer = entity.configParameter("fireCooldown")
      stateData.fireOffsetIndex = util.incWrap(stateData.fireOffsetIndex, #fireOffsets)
    end

    stateData.timer = 0
  end

  if stateData.timer > entity.configParameter("targetHoldTime") then
    entity.setAnimationState("movement", "idle")
    entity.setAllOutboundNodes(false)
    return true
  end

  return false
end

function attackState.isVisible(startPosition, endPosition, targetId)
  local entityIds = world.entityLineQuery(startPosition, endPosition, {includedTypes = {"player"}})
  for i, entityId in ipairs(entityIds) do
    if entityId == targetId then
      return true
    end
  end

  return false
end
