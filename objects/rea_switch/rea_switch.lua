--Needs some adjustments, the bounding box is way too big, maybe find a way to calculate direct collision? @Kayuko

function init(virtual)
  -- If not placed, but in preview, cancel init()
  if virtual then 
  return 
  end
    -- Defines the bounding box
  local detectArea = entity.configParameter("detectArea")
  local pos = entity.position()

      if type(detectArea[2]) == "number" then
        --center and radius
        self.detectArea = {
        {pos[1] + detectArea[1][1], pos[2] + detectArea[1][2]},
        detectArea[2]
        }

      elseif type(detectArea[2]) == "table" and #detectArea[2] == 2 then
        --rect corner1 and corner2
        self.detectArea = {
        {pos[1] + detectArea[1][1], pos[2] + detectArea[1][2]},
        {pos[1] + detectArea[2][1], pos[2] + detectArea[2][2]}
        }
  end

-- Initializes switch in off-state, sets switch variable
entity.setAllOutboundNodes(false)
entity.setAnimationState("switchState", "off")
switch = false
end

-- The on-trigger function, called per update()
function trigger()
  -- Turns the wiring nodes active ...
  entity.setAllOutboundNodes(true)
  -- ... sets the animation state ...
  entity.setAnimationState("switchState", "on")
  -- ... and sets the switch-variable.
  switch = true
end
 
-- The off-trigger function, called per update() 
function trigger2()
  -- Turns the wiring nodes inactive ...
  entity.setAllOutboundNodes(false)
  -- ... sets the animation state ...
  entity.setAnimationState("switchState", "off")
  -- ... and sets the switch variable.
  switch = false
end

function update(dt) 
  -- if the switch variable is false ...
  if switch == false then
    -- ... scan for projectiles inside the bounding box.
    local entityIds = world.entityQuery(self.detectArea[1], self.detectArea[2], {
    withoutEntityId = entity.id(),
    includedTypes = {"projectile"}
    }) 
    -- If more then one id was returned (not nil)...
      if #entityIds > 0 then
      -- Call the on-trigger
      trigger()
      end
    -- If the switch variable is true ...
  elseif switch == true then
    -- ... scan for projectiles inside the bounding box.
    local entityIds = world.entityQuery(self.detectArea[1], self.detectArea[2], {
    withoutEntityId = entity.id(),
    includedTypes = {"projectile"}
    }) 
      -- If more then one id was returned (not nil)...
      if #entityIds > 0 then
      -- Call the off-trigger
      trigger2()
    end
  end
end
