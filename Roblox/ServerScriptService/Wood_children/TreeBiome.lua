local KDKit = require(game.ReplicatedFirst:WaitForChild("KDKit"))
local WoodConfigs = require(game.ServerStorage:WaitForChild("WoodConfigs"))
local Tree = require(game.ServerScriptService:WaitForChild("Wood"):WaitForChild("Tree"))

local TreeBiome = KDKit.Class("TreeBiome")
TreeBiome.list = {}
TreeBiome.folder = game.ServerStorage:WaitForChild("TREE_BIOMES")

local Terrain = workspace:WaitForChild("Terrain")
local TREE_GROW_BLOCKERS = workspace:WaitForChild("TREE_GROW_BLOCKERS")

local TREE_BAKE_GRID_SIZE = 10
local TREE_SPAWN_MIN_DISTANCE = TREE_BAKE_GRID_SIZE * 0.9

local areaRaycastParams = RaycastParams.new()
areaRaycastParams.IgnoreWater = true
areaRaycastParams.FilterType = Enum.RaycastFilterType.Whitelist
areaRaycastParams.FilterDescendantsInstances = { Terrain, TREE_GROW_BLOCKERS }

local function caseInsensitiveEnumLookup(enum, name)
    for _, enumItem in ipairs(enum:GetEnumItems()) do
        if enumItem.Name:lower() == name:lower() then
            return enumItem
        end
    end
    
    error(("no such item '%s' in enum '%s'"):format(tostring(name), tostring(enum)))
end

function TreeBiome:__init(instance)
    self.instance = instance
    self.name = self.instance.name
    
    self.config = {
        secondsBetweenSpawns = self.instance:GetAttribute("secondsBetweenSpawns") or 10,
        maxTrees = self.instance:GetAttribute("maxTrees") or 16383,
    }
    
    -- config.trees[WoodConfig] = { chance = number, materials = { Enum.Material, ... } }
    self.config.trees = self:parseTreeConfigs(self.instance.trees)
    
    -- config.interestingMaterials[Enum.Material] = true
    self.config.interestingMaterials = {}
    for treeName, treeConfig in pairs(self.config.trees) do
        for _, material in ipairs(treeConfig.materials) do
            self.config.interestingMaterials[material] = true
        end
    end
    
    -- config.spawnPointsByMaterial[Enum.Material] = { CFrame, ... }
    self.config.spawnPointsByMaterial = self:parseSpawnBoxes(self.instance.spawnBoxes, self.config.interestingMaterials)
    
    -- config.numberOfSpawnPointsPerWoodConfigPerMaterial[WoodConfig][Enum.Material] = number
    self.config.numberOfSpawnPointsPerWoodConfigPerMaterial = {}
    for woodConfig, treeConfig in pairs(self.config.trees) do
        self.config.numberOfSpawnPointsPerWoodConfigPerMaterial[woodConfig] = {}
        
        for _, material in ipairs(treeConfig.materials) do
            self.config.numberOfSpawnPointsPerWoodConfigPerMaterial[woodConfig][material] = #self.config.spawnPointsByMaterial[material]
        end
    end
    
    -- config.chanceByWoodConfig[WoodConfig] = number
    self.config.chanceByWoodConfig = {}
    for woodConfig, treeConfig in pairs(self.config.trees) do
        self.config.chanceByWoodConfig[woodConfig] = treeConfig.chance
    end
    
    -- trees[Tree] = Vector3
    self.trees = table.create(math.min(self.config.maxTrees, 16383))
    self.nTrees = 0
    self.spawnNextTreeAt = os.clock()
end

function TreeBiome:parseTreeConfigs(treeConfigsFolder)
    local treeConfigInstances = treeConfigsFolder:GetChildren()
    local treeConfigs = table.create(#treeConfigInstances)
    
    for _, treeConfigInstance in ipairs(treeConfigInstances) do
        local treeName = treeConfigInstance.Name
        local woodConfig = WoodConfigs[treeName]
        
        local materials = table.create(8)
        for materialName in treeConfigInstance:GetAttribute("materials"):gmatch("[^,%s]+") do
            table.insert(materials, caseInsensitiveEnumLookup(Enum.Material, materialName))
        end
        
        treeConfigs[woodConfig] = {
            chance = treeConfigInstance:GetAttribute("chance"),
            materials = materials,
        }
    end
    
    return treeConfigs
end

function TreeBiome:parseSpawnBoxes(spawnBoxesFolder, interestingMaterials)
    local spawnBoxes = spawnBoxesFolder:GetChildren()
    
    local center = Vector3.new(0, 0, 0)
    for _, part in ipairs(spawnBoxes) do
        center += part.Position
    end
    center /= #spawnBoxes
    
    local spawnDataByRoundedPosition = table.create(65535)
    for _, part in ipairs(spawnBoxes) do
        local rx, gp, hit, p, id
        local sx, sy, sz = math.round(part.Size.X / TREE_BAKE_GRID_SIZE) * TREE_BAKE_GRID_SIZE, part.Size.Y, math.round(part.Size.Z / TREE_BAKE_GRID_SIZE) * TREE_BAKE_GRID_SIZE
        local cf = part.CFrame
        local down = -cf.UpVector * sy
        
        for x = 0, sx, TREE_BAKE_GRID_SIZE do
            rx = x - sx / 2
            
            for z = 0, sz, TREE_BAKE_GRID_SIZE do
                gp = cf:PointToWorldSpace(Vector3.new(rx, sy / 2, z - sz / 2))
                hit = workspace:Raycast(gp, down, areaRaycastParams)
                
                if not hit then continue end
                if hit.Instance ~= Terrain then continue end
                if not interestingMaterials[hit.Material] then continue end
                
                -- did some benchmarking and this is in fact the fastest way of doing this
                p = hit.Position - center
                id = math.round(p.X/TREE_SPAWN_MIN_DISTANCE) * 1000000000 + math.round(p.Y/TREE_SPAWN_MIN_DISTANCE) * 10000 + math.round(p.Z/TREE_SPAWN_MIN_DISTANCE)
                spawnDataByRoundedPosition[id] = {
                    material = hit.Material,
                    cframe = part.CFrame - part.CFrame.p + hit.Position,
                }
            end
        end
    end
    
    local spawnPointsByMaterial = table.create(#interestingMaterials)
    for materialName, _ in pairs(interestingMaterials) do
        spawnPointsByMaterial[materialName] = table.create(65535)
    end
    
    for _, spawnData in pairs(spawnDataByRoundedPosition) do
        table.insert(
            spawnPointsByMaterial[spawnData.material],
            spawnData.cframe
        )
    end
    
    if workspace:GetAttribute("debug_visualize_tree_spawns") then
        task.defer(function()
            for material, spawnPoints in pairs(spawnPointsByMaterial) do
                for i, cframe in ipairs(spawnPoints) do
                    local vis = Instance.new("Part")
                    vis.Anchored = true
                    vis.CanCollide = false
                    vis.CanQuery = false
                    vis.Size = Vector3.new(0.5, 3, 0.5)
                    vis.CFrame = cframe * CFrame.new(0, vis.Size.Y / 2, 0)
                    vis.Material = material
                    vis.Color = Terrain:GetMaterialColor(vis.Material):Lerp(Color3.new(1, 1, 1), 0.5)
                    vis.Parent = workspace

                    if i % 1000 == 0 then
                        task.wait()
                    end
                end
            end
        end)
    end
    
    return spawnPointsByMaterial
end

function TreeBiome:randomSpawnCFrame(material)
    local spawnPoints = self.config.spawnPointsByMaterial[material]
    local cf, hit = nil, nil
    while true do
        cf = KDKit.Random:linearChoice(spawnPoints)
        cf *= CFrame.new(
            KDKit.Random.rng:NextNumber(-TREE_SPAWN_MIN_DISTANCE, TREE_SPAWN_MIN_DISTANCE),
            0,
            KDKit.Random.rng:NextNumber(-TREE_SPAWN_MIN_DISTANCE, TREE_SPAWN_MIN_DISTANCE)
        )
        
        hit = workspace:Raycast(cf.p + cf.UpVector * 5, -cf.UpVector * 10, areaRaycastParams)
        if hit and hit.Instance == Terrain and hit.Material == material then
            return cf - cf.p + hit.Position
        end
    end
end

function TreeBiome:cframeIsNearExistingTree(cf, hitboxRadius)
    local p = cf.p
    for tree, spawnPosition in pairs(self.trees) do
        if (spawnPosition - p).Magnitude < (tree.hitboxRadius + hitboxRadius) then
            return true
        end
    end
    
    return false
end

function TreeBiome:randomValidSpawnCFrame(material, hitboxRadius, retries)
    for try = 1, retries or 3 do
        local cf = self:randomSpawnCFrame(material)
        if not self:cframeIsNearExistingTree(cf, hitboxRadius) then
            return cf
        end
    end
    
    return nil
end

function TreeBiome:getSpawnDelay()
    return KDKit.Random.rng:NextNumber(self.config.secondsBetweenSpawns.Min, self.config.secondsBetweenSpawns.Min)
end

function TreeBiome:trySpawnRandomTree(retries, age)
    self.spawnNextTreeAt = os.clock() + self:getSpawnDelay()
    
    local woodConfig = KDKit.Random:weightedChoice(self.config.chanceByWoodConfig)
    local material = KDKit.Random:weightedChoice(self.config.numberOfSpawnPointsPerWoodConfigPerMaterial[woodConfig])
    local spawnCFrame = self:randomValidSpawnCFrame(material, woodConfig:getHitboxRadius(), retries)
    if not spawnCFrame then return nil end

    local t = Tree(woodConfig, woodConfig:generateTree(spawnCFrame), age)
    self.trees[t] = spawnCFrame.p
    self.nTrees += 1
end

function TreeBiome:readyToSpawnNextTree()
    return self.nTrees < self.config.maxTrees and os.clock() > self.spawnNextTreeAt
end

function TreeBiome:cycle()
    if self:readyToSpawnNextTree() then
        self:trySpawnRandomTree()
    end
    
    local died = table.create(16)
    for tree, _ in pairs(self.trees) do
        if tree:cycle() then
            table.insert(died, tree)
        end
    end
    
    for _, deadTree in ipairs(died) do
        self.trees[deadTree] = nil
        self.nTrees -= 1
    end
end

function TreeBiome:simulateSecondsOfSpawning(seconds)
    while seconds > 0 and self.nTrees < self.config.maxTrees do
        self:trySpawnRandomTree(10, seconds)
        seconds -= self.spawnNextTreeAt - os.clock()
    end

    self:cycle()
end

KDKit.Preload:ensureChildren(TreeBiome.folder)

local before = os.clock()
for _, folder in ipairs(TreeBiome.folder:GetChildren()) do
    local biome = TreeBiome(folder)
    TreeBiome.list[biome.name] = biome
end
local after = os.clock()
print(("TreeBiome initialization time: %.2fms"):format((after - before) * 1000))

return TreeBiome
