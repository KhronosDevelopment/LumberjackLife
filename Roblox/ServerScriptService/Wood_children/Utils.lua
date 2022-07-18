local Utils = {
    constants = {
        FLUSH_CUT_TOLERANCE = 0.5,
        MIN_WOOD_LENGTH = 0.25,
        CUT_MIN_DISTANCE = 0.5,
        CUT_LINE_THICKNESS = 0.15,
        CUT_EXTRUSION = 0.05,
        N_TREE_GROWTH_STEPS = 50,
        FLOAT_COMPARISON_TOLERANCE = 0.001,
    }
}
local CONSTANTS = Utils.constants
local DOUBLE_CUT_EXTRUSION = CONSTANTS.CUT_EXTRUSION * 2

function Utils:weld(from, to, useExistingWeld)
    local w = useExistingWeld or Instance.new("WeldConstraint")
    w.Part0 = from
    w.Part1 = to
    w.Parent = w.Parent or workspace
    w.Enabled = true
    return w
end

function Utils:redrawCut(cut, branchInstance)
    local sx, sy, sz = branchInstance.Size.X, branchInstance.Size.Y, branchInstance.Size.Z
    local f = cut.area / (sx * sz)

    if cut.flipped then
        cut.instance.Size = Vector3.new(
            DOUBLE_CUT_EXTRUSION + f * sx,
            CONSTANTS.CUT_LINE_THICKNESS,
            DOUBLE_CUT_EXTRUSION + sz
        )
        cut.instance.CFrame = branchInstance.CFrame * CFrame.new((f - 1) * sx / 2, cut.at * sy / 2, 0)
    else
        cut.instance.Size = Vector3.new(
            DOUBLE_CUT_EXTRUSION + sx,
            CONSTANTS.CUT_LINE_THICKNESS,
            DOUBLE_CUT_EXTRUSION + f * sx
        )
        cut.instance.CFrame = branchInstance.CFrame * CFrame.new(0, cut.at * sy / 2, (f - 1) * sz / 2)
    end
end

function Utils:redrawCuts(cuts, branchInstance)
    for _, cut in ipairs(cuts) do
        self:redrawCut(cut, branchInstance)
    end
end

function Utils:getCutInsertionPoint(cuts, at)
    local left, right = 1, #cuts
    while left <= right do
        local mid = math.floor((left + right) / 2)
        if cuts[mid].at <= at then
            left = mid + 1
        else
            right = mid
            if left == right then
                break
            end
        end
    end

    return left
end

function Utils:areCutsTooClose(relativeDistance, branchLength)
    return relativeDistance * branchLength / 2 < CONSTANTS.CUT_MIN_DISTANCE
end

function Utils:tryCreateOrUpdateCut(cuts, at, power, branchLength, hasBottomBranches, hasTopBranches)
    local minEdgeDistanceWithoutBranches = 2 * CONSTANTS.MIN_WOOD_LENGTH / branchLength
    local minAt = if hasBottomBranches then -1 else (minEdgeDistanceWithoutBranches - 1)
    local maxAt = if hasTopBranches then 1 else (1 - minEdgeDistanceWithoutBranches)
    if minAt > maxAt then
        return nil
    end
    at = math.clamp(at, minAt, maxAt)

    local index = self:getCutInsertionPoint(cuts, at)
    local distToLeftCut = if cuts[index - 1] then at - cuts[index - 1].at else math.huge
    local distToRightCut = if cuts[index] then cuts[index].at - at else math.huge
    local useExistingCut = self:areCutsTooClose(math.min(distToLeftCut, distToRightCut), branchLength)
    
    if useExistingCut then
        if distToLeftCut < distToRightCut then
            index -= 1
        end
    else
        table.insert(cuts, index, { at = at, area = 0 })
    end

    local cut = cuts[index]
    cut.area += power

    return index, cut
end

function Utils:isCutComplete(cut, branchInstance)
    return cut.area >= branchInstance.Size.X * branchInstance.Size.Z
end

function Utils:shouldCutDecouple(cut, branchLength, hasBottomBranches, hasTopBranches)
    local isBottom = cut.at < 0
    local hasBranchesOnEdge = if isBottom then hasBottomBranches else hasTopBranches
    local studsToEdge = (1 - math.abs(cut.at)) * branchLength / 2
    
    if hasBranchesOnEdge then
        return studsToEdge - CONSTANTS.FLOAT_COMPARISON_TOLERANCE < CONSTANTS.FLUSH_CUT_TOLERANCE
    else
        return studsToEdge + CONSTANTS.FLOAT_COMPARISON_TOLERANCE < CONSTANTS.MIN_WOOD_LENGTH
    end
end

function Utils:locateBranch(root, locator)
    local branch = root
    for _, path in ipairs(locator or {}) do
        branch = branch.branches[path]

        if not branch then
            return nil
        end
    end

    return branch
end

function Utils:mustLocateBranch(root, locator)
    return self:locateBranch(root, locator) or error("invalid locator: " .. tostring(locator and table.concat(locator, ", ")))
end

function Utils:getBranchLocator(instance, currentBranch, pathSoFar)
    pathSoFar = pathSoFar or {}

    if currentBranch.instance == instance then
        return pathSoFar
    end

    local N = #pathSoFar + 1
    for i, nextBranch in ipairs(currentBranch.branches) do
        pathSoFar[N] = i
        if self:getBranchLocator(instance, nextBranch, pathSoFar) then
            return pathSoFar
        end
    end
    pathSoFar[N] = nil
    
    return nil
end

function Utils:chopBranch(branch, at, flipped, power)
    -- perform the cut
    local cutIndex, cut = self:tryCreateOrUpdateCut(
        branch.cuts,
        at,
        power,
        branch.instance.Size.Y,
        not not branch.parent,
        not not next(branch.branches)
    )

    -- there are several reasons why we wouldn't be able to cut at this position
    if not cut then
        return nil, nil
    end

    if cut.flipped == nil then
        cut.flipped = flipped
    end

    -- check for completed slices
    local createdWood = {}
    if self:isCutComplete(cut, branch.instance) then
        -- delete the cut & shift down other cuts
        if cut.instance then cut.instance:Destroy() end
        table.remove(branch.cuts, cutIndex)

        local shouldDecouple = self:shouldCutDecouple(
            cut,
            branch.instance.Size.Y,
            not not branch.parent,
            not not next(branch.branches)
        )

        -- decouple or slice
        if shouldDecouple then
            return "decouple", cut
        else
            return "slice", cut
        end
    else
        return "cut", cut
    end
end

function Utils:sliceBranch(branch, at)
    local f = (at + 1) / 2
    local materialRemoved = branch.instance.Size.Y * (1 - f)
    local materialKept = branch.instance.Size.Y * f

    -- duplicate the branch into a new branch
    local newBranch = {
        instance = branch.instance:Clone(),
        decorations = { },
        cuts = { },
        branches = branch.branches,
        sliced = table.clone(branch.sliced),
        cframe = branch.cframe,
        size = branch.size,
    }

    -- sever connections
    newBranch.parent = nil
    for _, child in ipairs(newBranch.branches) do
        child.parent = newBranch
    end
    branch.branches = {}
    
    -- log slice
    newBranch.sliced.bottom = true
    branch.sliced.top = true
    
    -- shift this branch back
    branch.instance.Size -= Vector3.new(0, materialRemoved, 0)
    branch.instance.CFrame *= CFrame.new(0, -materialRemoved / 2, 0)
    branch.size -= Vector3.new(0, (1 - f) * branch.size.Y, 0)

    -- shift new branch forward
    newBranch.instance.Size -= Vector3.new(0, materialKept, 0)
    newBranch.instance.CFrame *= CFrame.new(0, materialKept / 2, 0)
    newBranch.size -= Vector3.new(0, f * newBranch.size.Y, 0)

    -- move cuts around
    local indexOfFirstCutOnNewBranch = self:getCutInsertionPoint(branch.cuts, at)
    table.move(branch.cuts, indexOfFirstCutOnNewBranch, #branch.cuts, 1, newBranch.cuts)
    for i, cut in ipairs(branch.cuts) do
        if i >= indexOfFirstCutOnNewBranch then
            branch.cuts[i] = nil
            continue
        end
        
        --[[
        local position = cut.at
        local position_f = (position + 1) / 2
        local correctedPosition_f = position_f / f
        local correctedPosition = correctedPosition_f * 2 - 1
        cut.at = correctedPosition
        --]]

        -- simplified version of the above code
        cut.at = (cut.at + 1) / f - 1
    end
    for _, cut in ipairs(newBranch.cuts) do
        --[[
        local position = cut.at
        local position_f = (position + 1) / 2
        local correctedPosition_f = (position_f - f) / (1 - f)
        local correctedPosition = correctedPosition_f * 2 - 1
        cut.at = correctedPosition
        --]]

        -- simplified version of the above code
        local prev = cut.at 
        cut.at = (cut.at - f) / (1 - f)
    end

    -- redraw cuts
    self:redrawCuts(branch.cuts, branch.instance)
    self:redrawCuts(newBranch.cuts, newBranch.instance)
    
    -- move decorations around
    for name, decoration in pairs(branch.decorations) do
        local cf
        if decoration.instance:IsA("BasePart") then
            cf = decoration.instance.CFrame
        else
            cf = decoration.instance.PrimaryPart.CFrame
        end
        
        local moveToTop = branch.instance.CFrame:pointToObjectSpace(cf.p).Y > branch.instance.Size.Y / 2
        if moveToTop then
            newBranch.decorations[name] = decoration
            newBranch.decorations[name] = nil
        end
    end
    
    return newBranch
end

function Utils:getVolume(branch)
    local volume = branch.instance.Size.X * branch.instance.Size.Y * branch.instance.Size.Z
    for _, child in ipairs(branch.branches) do
        volume += self:getVolume(child)
    end
    
    return volume
end

return Utils
