local json = dofile("json.lua")
local vivid = dofile("vivid.lua")

function init(plugin)
    local defaults = {loadOnOpen = false, storeOnClose = false}
    if plugin.preferences == nil then plugin.preferences = {} end
    for key, value in pairs(defaults) do
        if plugin.preferences[key] == nil then plugin.preferences[key] = value end
    end

    local function storeUserData()
    end
    local function loadUserData()
    end

    local function tableInverse(table)
        local inverse = {}
        for key, value in pairs(table) do
            inverse[value] = key
        end
        return inverse
    end

    local function byteToFloat(byteValue)
        return byteValue / 256
    end
    local function floatToByte(floatValue)
        if floatValue <= 0.0 then
            return 0
        elseif floatValue >= 1.0 then
            return 255
        else
            return math.floor(floatValue * 256)
        end
    end
    local function byteVectorToFloatVector(byteVector)
        local floatVector = {}
        for i = 1, #byteVector do
            floatVector[i] = byteToFloat(byteVector[i])
        end
        return floatVector
    end
    local function floatVectorToByteVector(floatVector)
        local byteVector = {}
        for i = 1, #floatVector do
            byteVector[i] = floatToByte(floatVector[i])
        end
        return byteVector
    end
    local function colourToFloatVector(colour)
        return byteVectorToFloatVector({colour.red, colour.green, colour.blue, colour.alpha})
    end
    local function floatVectorToColour(floatVector)
        local byteVector = floatVectorToByteVector(floatVector)
        return Color{red = byteVector[1], green = byteVector[2], blue = byteVector[3], alpha = byteVector[4]}
    end

    local DistanceMetric = {
        EUCLIDEAN = 0,
        MANHATTAN = 1,
        CHEBYSHEV = 2,
    }
    local distanceMetricLabels = {
        [DistanceMetric.EUCLIDEAN] = "Euclidean",
        [DistanceMetric.MANHATTAN] = "Manhattan",
        [DistanceMetric.CHEBYSHEV] = "Chebyshev",
    }
    local distanceMetricLabelsInverted = tableInverse(distanceMetricLabels)
    local ColourSpace = {
        RGB = 0,
        HSL = 1,
        HSV = 2,
        XYZ = 3,
        LAB = 4,
        LCH = 5,
        LUV = 6,
    }
    local colourSpaceLabels = {
        [ColourSpace.RGB] = "RGB",
        [ColourSpace.HSL] = "HSL",
        [ColourSpace.HSV] = "HSV",
        [ColourSpace.XYZ] = "XYZ",
        [ColourSpace.LAB] = "CIELAB",
        [ColourSpace.LCH] = "CIELCh",
        [ColourSpace.LUV] = "CIELUV",
    }
    local colourSpaceLabelsInverted = tableInverse(colourSpaceLabels)
    local colourSpaceCodes = {
        [ColourSpace.RGB] = "RGB",
        [ColourSpace.HSL] = "HSL",
        [ColourSpace.HSV] = "HSV",
        [ColourSpace.XYZ] = "XYZ",
        [ColourSpace.LAB] = "Lab",
        [ColourSpace.LCH] = "LCH",
        [ColourSpace.LUV] = "Luv",
    }
    local function colourConvert(fromColourSpace, toColourSpace, colourVector)
        local funcName = colourSpaceCodes[fromColourSpace] .. "to" .. colourSpaceCodes[toColourSpace]
        if vivid[funcName] ~= nil then
            return {vivid[funcName](table.unpack(colourVector))}
        else
            return colourVector
        end
    end
    local distanceElementFunc = {
        [DistanceMetric.EUCLIDEAN] = function(sum, a, b)
            return sum + (b - a) ^ 2
        end,
        [DistanceMetric.MANHATTAN] = function(sum, a, b)
            return sum + math.abs(b - a)
        end,
        [DistanceMetric.CHEBYSHEV] = function(sum, a, b)
            return math.max(sum, math.abs(b - a))
        end,
    }
    local distanceSumFunc = {
        [DistanceMetric.EUCLIDEAN] = function(sum, relative)
            if relative ~= true then
                return math.sqrt(sum)
            end
        end
    }
    local function distance(metric, a, b, relative)
        local sum = 0
        local elementCount = math.min(#a, #b)
        for i = 1, elementCount do
            sum = distanceElementFunc[metric](sum, a[i], b[i])
        end
        if distanceSumFunc[metric] ~= nil then
            sum = distanceSumFunc[metric](sum, relative)
        end
        return sum
    end
    local function colourDistance(metric, colourSpace, a, b, relative)
        local convertedA = colourConvert(ColourSpace.RGB, colourSpace, colourToFloatVector(a))
        local convertedB = colourConvert(ColourSpace.RGB, colourSpace, colourToFloatVector(b))
        return distance(metric, convertedA, convertedB, relative)
    end

    local function celSelectionOffsetBounds(cel, selection)
        local image = cel.image
        local bounds = Rectangle(0, 0, image.width, image.height)
        local hasSelection = selection ~= nil and not selection.isEmpty
        if hasSelection then
            local offsetSelectionBounds = Rectangle(selection.bounds.x - cel.position.x, selection.bounds.y - cel.position.y, selection.bounds.width, selection.bounds.height)
            bounds = bounds:intersect(offsetSelectionBounds)
        end
        return bounds
    end

    local function perPixelInSelection(cels, selection, modifyPixels, func)
        for _, cel in ipairs(cels) do
            local image = cel.image
            local bounds = celSelectionOffsetBounds(cel, selection)
            local hasSelection = selection ~= nil and not selection.isEmpty
            if not bounds.isEmpty then
                if modifyPixels == true then
                    image = Image(cel.image)
                end
                for it in image:pixels(bounds) do
                    if not hasSelection or selection:contains(it.x + cel.position.x, it.y + cel.position.y) then
                        func(it)
                    end
                end
                if modifyPixels == true then
                    cel.image = image
                end
            end
        end
    end

    local function applyMappingInSelection(cels, selection, pixelValueMapping)
        perPixelInSelection(cels, selection, true, function (it)
            local pixelValue = pixelValueMapping[it()]
            if pixelValue ~= nil then
                it(pixelValue)
            end
        end)
    end

    local function coloursInSelection(cels, selection)
        local colourSequence = {}
        local colourCount = {}
        local count = 0
        perPixelInSelection(cels, selection, false, function(it)
            count = count + 1
            local pixelValue = it()
            if colourCount[pixelValue] == nil then
                colourCount[pixelValue] = 1
                colourSequence[#colourSequence + 1] = pixelValue
            else
                colourCount[pixelValue] = colourCount[pixelValue] + 1
            end
        end)
        return colourSequence, colourCount
    end

    local function indexPixelValue(colourMode, palette, index)
        if colourMode == ColorMode.INDEXED then
            return index
        elseif colourMode == ColorMode.RGB then
            return palette:getColor(index).rgbaPixel
        elseif colourMode == ColorMode.GRAY then
            return palette:getColor(index).grayPixel
        else
            return nil
        end
    end

    local function buildPixelValueToPaletteIndexLut(colourMode, palette)
        local lut = {}
        for i = 0, #palette - 1 do
            local pixelValue = indexPixelValue(colourMode, palette, i)
            lut[pixelValue] = i
        end
        return lut
    end

    local function indexCountsInSelection(colourMode, palette, cels, selection)
        local pixelValueToPaletteIndexLut = buildPixelValueToPaletteIndexLut(colourMode, palette)
        local indexCounts = {}
        for i = 0, #palette - 1 do
            indexCounts[i] = 0
        end
        perPixelInSelection(cels, selection, false, function(it)
            local pixelValue = it()
            local index = pixelValueToPaletteIndexLut[pixelValue]
            if index ~= nil then
                indexCounts[index] = indexCounts[index] + 1
            end
        end)
        return indexCounts
    end

    local function colourDistanceEuclideanSquared(a, b)
        local deltaR = b.red - a.red
        local deltaG = b.green - a.green
        local deltaB = b.blue - a.blue
        local deltaA = b.alpha - a.alpha
        return deltaR * deltaR + deltaG * deltaG + deltaB * deltaB + deltaA * deltaA
    end

    local function colourDistanceEuclidean(a, b)
        return math.sqrt(colourDistanceEuclideanSquared(a, b))
    end

    local function findNearestColourIndex(metric, colourSpace, palette, colour)
        local nearestIndex = nil
        local nearestDistance = nil
        for i = 0, #palette - 1 do
            local distance = colourDistance(metric, colourSpace, colour, palette:getColor(i), false)
            -- local distance = colourDistanceEuclideanSquared(colour, palette:getColor(i))
            if nearestIndex == nil or distance < nearestDistance then
                nearestIndex = i
                nearestDistance = distance
            end
        end
        return nearestIndex
    end

    local function buildPixelValueMappingFromIndexMapping(colourMode, palette, indexMapping, newPalette, unmappedIndexFunc)
        local pixelValueMapping = {}
        for i = 0, #palette - 1 do
            local pixelValue = indexPixelValue(colourMode, palette, i)
            local index = indexMapping[i]
            if index ~= nil then
                pixelValueMapping[pixelValue] = indexPixelValue(colourMode, palette, indexMapping[i])
            elseif unmappedIndexFunc ~= nil then
                pixelValueMapping[pixelValue] = unmappedIndexFunc(colourMode, palette, indexMapping, newPalette, i)
            end
        end
        return pixelValueMapping
    end

    local function paletteRemoveInsertMapping(palette, removeIndices, insertColours)
        local removeIndicesSize = 0
        local insertColoursSize = 0
        if removeIndices ~= nil then
            removeIndicesSize = #removeIndices
            table.sort(removeIndices)
        end
        if insertColours ~= nil then
            insertColoursSize = #insertColours
            table.sort(insertColours, function(a, b)
                return a.index < b.index
            end)
        end
        local newPalette = Palette(#palette - removeIndicesSize + insertColoursSize)
        local mapping = {}
        local remapOffset = 0
        local removeTableIndex = 1
        local insertTableIndex = 1
        for i = 0, #palette - 1 do
            local removeIndex = nil
            if removeIndices ~= nil then
                removeIndex = removeIndices[removeTableIndex]
            end
            local insertIndex = nil
            if insertColours ~= nil and insertColours[insertTableIndex] ~= nil then
                insertIndex = insertColours[insertTableIndex].index
            end
            if i ~= removeIndex and i ~= insertIndex then
                local remapIndex = i + remapOffset
                newPalette:setColor(remapIndex, palette:getColor(i))
                mapping[i] = remapIndex
            else
                if i == removeIndex then
                    mapping[i] = nil
                    remapOffset = remapOffset - 1
                    removeTableIndex = removeTableIndex + 1
                end
                if i == insertIndex then
                    local remapIndex = i + remapOffset
                    newPalette:setColor(remapIndex, insertColours[insertTableIndex].colour)
                    mapping[i] = remapIndex
                    remapOffset = remapOffset + 1
                    insertTableIndex = insertTableIndex + 1
                end
            end
        end
        return newPalette, mapping
    end

    local RemoveMode = {
        REPLACE_WITH_NEAREST = 0,
        REPLACE_WITH_INDEX = 1,
    }
    local removeModeLabels = {
        [RemoveMode.REPLACE_WITH_NEAREST] = "Replace With Nearest",
        [RemoveMode.REPLACE_WITH_INDEX] = "Replace With Index",
    }
    local function removeIndices(sprite, cels, selection, indices, removeMode, distanceMetric, colourSpace, replacementIndex)
        local colourMode = sprite.colorMode
        local palette = sprite.palettes[1]
        local unmappedIndexFunc = nil
        if removeMode == RemoveMode.REPLACE_WITH_NEAREST then
            unmappedIndexFunc = function(colourMode, palette, indexMapping, newPalette, index)
                return findNearestColourIndex(distanceMetric, colourSpace, newPalette, palette:getColor(index))
            end
        elseif removeMode == RemoveMode.REPLACE_WITH_INDEX then
            unmappedIndexFunc = function(colourMode, palette, indexMapping, newPalette, index)
                return indexMapping[replacementIndex]
            end
        end
        if unmappedIndexFunc ~= nil then
            local newPalette, indexMapping = paletteRemoveInsertMapping(palette, indices, nil)
            local pixelValueMapping = buildPixelValueMappingFromIndexMapping(colourMode, palette, indexMapping, newPalette, unmappedIndexFunc)
            applyMappingInSelection(cels, selection, pixelValueMapping)
            sprite:setPalette(newPalette)
        end
    end

    local MergeMode = {
        MOST_USED = 0,
        AVERAGE = 1,
        WEIGHTED_AVERAGE = 2,
    }
    local mergeModeLabels = {
        [MergeMode.MOST_USED] = "Merge to Most Used",
        [MergeMode.AVERAGE] = "Merge to Average",
        [MergeMode.WEIGHTED_AVERAGE] = "Merge to Weighted Average",
    }
    local mergeModeLabelsInverted = tableInverse(mergeModeLabels)
    local function mergeIndices(sprite, cels, selection, indices, mergeMode, distanceMetric, colourSpace)
        local colourMode = sprite.colorMode
        local palette = sprite.palettes[1]
        local replacementIndex = nil
        local removeIndices = {}
        if mergeMode == MergeMode.MOST_USED then
            local indexCounts = indexCountsInSelection(colourMode, palette, cels, selection)
            local sortTable = {}
            for _, index in pairs(indices) do
                table.insert(sortTable, {index = index, count = indexCounts[index]})
            end
            table.sort(sortTable, function(a, b)
                return a.count < b.count
            end)
            replacementIndex = sortTable[#sortTable].index
            for i = 1, #sortTable - 1 do
                table.insert(removeIndices, sortTable[i].index)
            end
        elseif mergeMode == MergeMode.AVERAGE then
            local sumR, sumG, sumB, sumA = 0, 0, 0, 0
            local sums = {0, 0, 0, 0}
            local sumCount = 0
            for _, index in pairs(indices) do
                local colour = palette:getColor(index)
                local converted = colourConvert(ColourSpace.RGB, colourSpace, colourToFloatVector(colour))
                for i = 1, #sums do
                    sums[i] = sums[i] + converted[i]
                end
                sumCount = sumCount + 1
            end
            if sumCount > 0 then
                local convertedAverage = {0, 0, 0, 0}
                for i = 1, #convertedAverage do
                    convertedAverage[i] = sums[i] / sumCount
                end
                local averageColour = floatVectorToColour(colourConvert(colourSpace, ColourSpace.RGB, convertedAverage))
                replacementIndex = indices[1]
                for i = 2, #indices do
                    table.insert(removeIndices, indices[i])
                end
                palette:setColor(replacementIndex, averageColour)
            end
        elseif mergeMode == MergeMode.WEIGHTED_AVERAGE then
            local indexCounts = indexCountsInSelection(colourMode, palette, cels, selection)
            local selectedIndexCounts = {}
            for _, index in pairs(indices) do
                selectedIndexCounts[index] = indexCounts[index]
            end
            local sumR, sumG, sumB, sumA = 0, 0, 0, 0
            local sums = {0, 0, 0, 0}
            local sumCount = 0
            for index, count in pairs(selectedIndexCounts) do
                local colour = palette:getColor(index)
                local converted = colourConvert(ColourSpace.RGB, colourSpace, colourToFloatVector(colour))
                for i = 1, #sums do
                    sums[i] = sums[i] + converted[i] * count
                end
                sumCount = sumCount + count
            end
            if sumCount > 0 then
                local convertedAverage = {0, 0, 0, 0}
                for i = 1, #convertedAverage do
                    convertedAverage[i] = sums[i] / sumCount
                end
                local averageColour = floatVectorToColour(colourConvert(colourSpace, ColourSpace.RGB, convertedAverage))
                replacementIndex = indices[1]
                for i = 2, #indices do
                    table.insert(removeIndices, indices[i])
                end
                palette:setColor(replacementIndex, averageColour)
            end
        end
        local newPalette, indexMapping = paletteRemoveInsertMapping(palette, removeIndices, nil)
        local pixelValueMapping = buildPixelValueMappingFromIndexMapping(colourMode, palette, indexMapping, newPalette, function(colourMode, palette, indexMapping, newPalette, i)
            return indexMapping[replacementIndex]
        end)
        applyMappingInSelection(cels, selection, pixelValueMapping)
        sprite:setPalette(newPalette)
    end

    local function getIndicesInUsageRange(colourMode, palette, cels, selection, min, max)
        local indexCounts = indexCountsInSelection(colourMode, palette, cels, selection)
        local indices = {}
        for i, count in pairs(indexCounts) do
            if count >= min and count < max then
                table.insert(indices, i)
            end
        end
        return indices
    end

    local function getIndicesNLeastUsed(colourMode, palette, cels, selection, n)
        local indexCounts = indexCountsInSelection(colourMode, palette, cels, selection)
        local sortTable = {}
        for i = 0, #palette - 1 do
            table.insert(sortTable, {index = i, count = indexCounts[i]})
        end
        table.sort(sortTable, function(a, b)
            return a.count < b.count
        end)
        local leastUsedCount = math.min(n, #sortTable)
        local indices = {}
        for i = 1, leastUsedCount do
            indices[i] = sortTable[i].index
        end
        return indices
    end

    local function getIndicesDuplicated(palette)
        local rgbaValueSet = {}
        local indices = {}
        for i = 0, #palette - 1 do
            local rgbaValue = palette:getColor(i).rgbaPixel
            if rgbaValueSet[rgbaValue] == nil then
                rgbaValueSet[rgbaValue] = true
            else
                table.insert(indices, i)
            end
        end
        return indices
    end

    local function buildDialog()
        local dlg = Dialog("Palette Utils")

        dlg:separator{text = "Select Indices"}
        dlg:combobox{id = "distanceMetric", label = "Distance Metric", options = distanceMetricLabels, option = distanceMetricLabels[DistanceMetric.EUCLIDEAN]}
        dlg:combobox{id = "colourSpace", label = "Colour Space", options = colourSpaceLabels, option = colourSpaceLabels[ColourSpace.RGB]}
        dlg:number{id = "selectSimilarityThreshold", label = "Similarity Threshold", text = tostring(0)}
        dlg:button{text = "Select Similar", onclick = function()
            app.transaction(function()
                local distanceMetric = distanceMetricLabelsInverted[dlg.data["distanceMetric"]]
                local colourSpace = colourSpaceLabelsInverted[dlg.data["colourSpace"]]
                local targetIndices = app.range.colors
                local palette = app.activeSprite.palettes[1]
                if #targetIndices == 0 then
                    local colour = app.fgColor 
                    local index = colour.index
                    if index == nil then
                        index = findNearestColourIndex(distanceMetric, colourSpace, palette, colour)
                    end
                    table.insert(targetIndices, app.fgColor.index)
                end
                local targetIndicesSet = {}
                for _, index in pairs(targetIndices) do
                    targetIndicesSet[index] = true
                end
                local candidateIndices = {}
                for i = 0, #palette - 1 do
                    if targetIndicesSet[i] ~= true then
                        table.insert(candidateIndices, i)
                    end
                end
                local similarIndicesSet = {}
                local thresholdSquared = dlg.data["selectSimilarityThreshold"] ^ 2
                for _, target in pairs(targetIndices) do
                    for _, candidate in pairs(candidateIndices) do
                        if similarIndicesSet[candidate] == nil then
                            local distanceSquared = colourDistanceEuclideanSquared(palette:getColor(candidate), palette:getColor(target))
                            if distanceSquared < thresholdSquared then
                                similarIndicesSet[candidate] = true
                            end
                        end
                    end
                end
                local similarIndices = {}
                for similar, _ in pairs(similarIndicesSet) do
                    table.insert(similarIndices, similar)
                end
                app.range.colors = similarIndices
            end)
            app.refresh()
        end}
        dlg:newrow()
        dlg:number{id = "usageThreshold", label = "Usage Threshold", text = tostring(0)}
        dlg:button{text = "Select Below Usage Threshold", onclick = function()
            app.transaction(function()
                app.range.colors = getIndicesInUsageRange(app.activeSprite.colorMode, app.activeSprite.palettes[1], app.range.cels, app.activeSprite.selection, 0, dlg.data["usageThreshold"])
            end)
            app.refresh()
        end}
        dlg:newrow()
        dlg:number{id = "nLeastUsed", label = "N Least Used", text = tostring(0), decimals = 0}
        dlg:button{text = "Select N Least Used", onclick = function()
            app.transaction(function()
                app.range.colors = getIndicesNLeastUsed(app.activeSprite.colorMode, app.activeSprite.palettes[1], app.range.cels, app.activeSprite.selection, dlg.data["nLeastUsed"])
            end)
            app.refresh()
        end}
        dlg:newrow()
        dlg:button{text = "Select Duplicates", onclick = function()
            app.transaction(function()
                app.range.colors = getIndicesDuplicated(app.activeSprite.palettes[1])
            end)
            app.refresh()
        end}
        -- dlg:newrow()
        -- dlg:button{text = "Select Pixels", onclick = function()
        --     app.transaction(function()
        --         local coloursSet = {}
        --         for i, index in pairs(app.range.colors) do
        --             coloursSet[index] = true
        --         end
        --         local selection = Selection()
        --         local palette = app.activeSprite.palettes[1]
        --         local lut = buildPixelValueToPaletteIndexLut(app.activeSprite.colorMode, palette)
        --         local run = nil
        --         perPixelInSelection(app.range.cels, app.activeSprite.selection, false, function(it)
        --             local pixelValue = it()
        --             local index = lut[pixelValue]
        --             if coloursSet[index] ~= true or (run ~= nil and it.y ~= run.finish.y) then
        --                 if run ~= nil then
        --                     -- finish run
        --                     local runWidth = run.finish.x - run.start.x + 1
        --                     print(run.start.x, run.start.y, runWidth)
        --                     local rect = Rectangle(run.start.x, run.start.y, runWidth, 1)
        --                     selection:select(rect)
        --                     run = nil
        --                 end
        --             else
        --                 if run == nil then
        --                     -- start run
        --                     run = {}
        --                     run.start = Point(it.x, it.y)
        --                     run.finish = run.start
        --                 else
        --                     -- extend run
        --                     run.finish = Point(it.x, it.y)
        --                 end
        --             end
        --         end)
        --         print(tostring(selection.bounds))
        --         app.activeSprite.selection = selection
        --         app.refresh()
        --     end)
        -- end}
        dlg:newrow()
        dlg:button{text = "Invert Selection", onclick = function()
            app.transaction(function()
                local selectedSet = {}
                for _, index in pairs(app.range.colors) do
                    selectedSet[index] = true
                end
                local indices = {}
                local palette = app.activeSprite.palettes[1]
                for i = 0, #palette - 1 do
                    if selectedSet[i] ~= true then
                        table.insert(indices, i)
                    end
                end
                app.range.colors = indices
            end)
            app.refresh()
        end}

        dlg:separator{text = "Remove Indices"}
        dlg:button{text = "Replace Pixels With Nearest", onclick = function()
            app.transaction(function()
                local distanceMetric = distanceMetricLabelsInverted[dlg.data["distanceMetric"]]
                local colourSpace = colourSpaceLabelsInverted[dlg.data["colourSpace"]]
                removeIndices(app.activeSprite, app.range.cels, app.activeSprite.selection, app.range.colors, RemoveMode.REPLACE_WITH_NEAREST, distanceMetric, colourSpace)
            end)
            app.refresh()
        end}
        dlg:newrow()
        dlg:color{id = "replacementColour", label = "Replacement Colour", color = 0}
        dlg:button{text = "Replace Pixels With Colour", onclick = function()
            app.transaction(function()
                local distanceMetric = distanceMetricLabelsInverted[dlg.data["distanceMetric"]]
                local colourSpace = colourSpaceLabelsInverted[dlg.data["colourSpace"]]
                local replacementIndex = dlg.data["replacementColour"].index
                removeIndices(app.activeSprite, app.range.cels, app.activeSprite.selection, app.range.colors, RemoveMode.REPLACE_WITH_INDEX, distanceMetric, colourSpace, replacementIndex)
            end)
            app.refresh()
        end}
        dlg:newrow()
        dlg:button{text = "Remove Duplicates", onclick = function()
            app.transaction(function()
                local distanceMetric = distanceMetricLabelsInverted[dlg.data["distanceMetric"]]
                local colourSpace = colourSpaceLabelsInverted[dlg.data["colourSpace"]]
                local indices = getIndicesDuplicated(app.activeSprite.palettes[1])
                removeIndices(app.activeSprite, app.range.cels, app.activeSprite.selection, indices, RemoveMode.REPLACE_WITH_NEAREST, distanceMetric, colourSpace)
            end)
            app.refresh()
        end}

        dlg:separator{text = "Merge Indices"}
        dlg:combobox{id = "mergeMode", label = "Merge Mode", options = mergeModeLabels, option = mergeModeLabels[MergeMode.MOST_USED]}
        dlg:button{text = "Merge Selected", onclick = function()
            app.transaction(function()
                local distanceMetric = distanceMetricLabelsInverted[dlg.data["distanceMetric"]]
                local colourSpace = colourSpaceLabelsInverted[dlg.data["colourSpace"]]
                local mergeMode = mergeModeLabelsInverted[dlg.data["mergeMode"]]
                mergeIndices(app.activeSprite, app.range.cels, app.activeSprite.selection, app.range.colors, mergeMode, distanceMetric, colourSpace)
            end)
            app.refresh()
        end}
        -- dlg:button{text = "Merge to Most Used", onclick = function()
        --     app.transaction(function()
        --         mergeIndices(app.activeSprite, app.range.cels, app.activeSprite.selection, app.range.colors, MergeMode.MOST_USED)
        --     end)
        --     app.refresh()
        -- end}
        -- dlg:newrow()
        -- dlg:button{text = "Merge to Average", onclick = function()
        --     app.transaction(function()
        --         mergeIndices(app.activeSprite, app.range.cels, app.activeSprite.selection, app.range.colors, MergeMode.AVERAGE)
        --     end)
        --     app.refresh()
        -- end}
        -- dlg:newrow()
        -- dlg:button{text = "Merge to Weighted Average", onclick = function()
        --     app.transaction(function()
        --         mergeIndices(app.activeSprite, app.range.cels, app.activeSprite.selection, app.range.colors, MergeMode.WEIGHTED_AVERAGE)
        --     end)
        --     app.refresh()
        -- end}
        dlg:newrow()
        dlg:number{id = "mergeSimilarityThreshold", label = "Similarity Threshold", text = tostring(0)}
        dlg:button{text = "Merge Similar", onclick = function()
        end}

        -- dlg:separator{text = "Reduce Indices"}
        -- local ReductionMode = {
        --     NEAREST = 0,
        --     AVERAGE = 1,
        --     WEIGHTED_AVERAGE = 2,
        -- }
        -- local reductionModeLabels = {
        --     [ReductionMode.NEAREST] = "Replace With Nearest",
        --     [ReductionMode.AVERAGE] = "Replace With Average",
        --     [ReductionMode.WEIGHTED_AVERAGE] = "Replace With Weighted Average",
        -- }
        -- dlg:combobox{id = "reductionMode", label = "Reduction Mode", options = reductionModeLabels, option = reductionModeLabels[ReductionMode.NEAREST]}
        -- dlg:number{id = "reductionSize", label = "Reduce to Size", text = tostring(16)}
        -- dlg:button{text = "Reduce", onclick = function()
        --     app.transaction(function()
        --         local palette = app.activeSprite.palettes[1]
        --         local reduceCount = #palette + 1 - dlg.data["reductionSize"]
        --         local indices = {}
        --         -- select reduceCount least used indices
        --         local reductionModeLabelsInverted = tableInverse(reductionModeLabels)
        --         local reductionMode = reductionModeLabelsInverted[dlg.data["reductionMode"]]
        --         if reductionMode == ReductionMode.NEAREST then

        --         elseif reductionMode == ReductionMode.AVERAGE then

        --         elseif reductionMode == ReductionMode.WEIGHTED_AVERAGE then

        --         end
        --     end)
        --     app.refresh()
        -- end}

        dlg:separator{text = "Add Indices"}
        dlg:button{text = "All Colours From Selection", onclick = function()
            app.transaction(function()
                local colourSequence, _ = coloursInSelection(app.range.cels, app.activeSprite.selection)
                local palette = app.activeSprite.palettes[1]
                local paletteSize = #palette
                palette:resize(paletteSize + #colourSequence)
                for i, pixelValue in ipairs(colourSequence) do
                    local colour = Color(pixelValue)
                    palette:setColor(paletteSize - 1 + i, colour)
                end
            end)
            app.refresh()
        end}
        dlg:newrow()
        dlg:button{text = "Weighted Average From Selection", onclick = function()
            app.transaction(function()
                local _, colourCount = coloursInSelection(app.range.cels, app.activeSprite.selection)
                local sumR, sumG, sumB, sumA = 0, 0, 0, 0
                local sumCount = 0
                for pixelValue, count in pairs(colourCount) do
                    local colour = Color(pixelValue)
                    sumR = sumR + colour.red * count
                    sumG = sumG + colour.green * count
                    sumB = sumB + colour.blue * count
                    sumA = sumA + colour.alpha * count
                    sumCount = sumCount + count
                end
                if sumCount > 0 then
                    local averageColour = Color{red = math.floor(sumR / sumCount + 0.5), green = math.floor(sumG / sumCount + 0.5), blue = math.floor(sumB / sumCount + 0.5), alpha = math.floor(sumA / sumCount + 0.5)}
                    local palette = app.activeSprite.palettes[1]
                    local paletteSize = #palette
                    palette:resize(paletteSize + 1)
                    palette:setColor(paletteSize, averageColour)
                end
            end)
            app.refresh()
        end}
        dlg:newrow()
        dlg:button{text = "All Colours From Selected Grid Centres", onclick = function()
            app.transaction(function()
                for _, cel in ipairs(app.range.cels) do
                    local selection = app.activeSprite.selection
                    local bounds = celSelectionOffsetBounds(cel, selection)
                    local grid = app.activeSprite.gridBounds
                    local gridX0 = math.floor((bounds.x - grid.x) / grid.width)
                    local gridY0 = math.floor((bounds.y - grid.y) / grid.height)
                    local gridX1 = math.ceil((bounds.x - grid.x + bounds.width) / grid.width) - 1
                    local gridY1 = math.ceil((bounds.y - grid.y + bounds.height) / grid.height) - 1
                    local image = cel.image
                    local colours = {}
                    local count = 0
                    for y = gridY0, gridY1 do
                        for x = gridX0, gridX1 do
                            local pos = Point(math.floor((x + 0.5) * grid.width + grid.x), math.floor((y + 0.5) * grid.height + grid.y))
                            table.insert(colours, Color(image:getPixel(pos.x, pos.y)))
                            count = count + 1
                        end
                    end
                    local palette = app.activeSprite.palettes[1]
                    local paletteSize = #palette
                    palette:resize(paletteSize + #colours)
                    for i = 1, #colours do
                        palette:setColor(paletteSize - 1 + i, colours[i])
                    end
                end
            end)
            app.refresh()
        end}
        dlg:newrow()
        dlg:button{text = "All Pixels From Selection", onclick = function()
            app.transaction(function()
                local colours = {}
                perPixelInSelection(app.range.cels, app.activeSprite.selection, false, function(it)
                    table.insert(colours, Color(it()))
                end)
                local palette = app.activeSprite.palettes[1]
                local paletteSize = #palette
                palette:resize(paletteSize + #colours)
                for i = 1, #colours do
                    palette:setColor(paletteSize - 1 + i, colours[i])
                end
            end)
            app.refresh()
        end}

        dlg:separator{text = "Misc."}
        dlg:label{id = "colourCount", label = "Colour Count", text="-"}
        dlg:button{text = "Count Colours Used", onclick = function()
            local colourSequence, _ = coloursInSelection(app.range.cels, app.activeSprite.selection)
            dlg:modify{id = "colourCount", text=tostring(#colourSequence)}
        end}
        dlg:newrow()
        dlg:number{id = "histogramWidth", label = "Histogram Size", text = tostring(256)}
        dlg:number{id = "histogramHeight", text = tostring(256)}
        dlg:check{id = "histogramExcludeTransparent", text = "Histogram Exclude Transparent", value = false}
        dlg:button{text = "Show Histogram", onclick = function()
            app.transaction(function()
                local palette = app.activeSprite.palettes[1]
                local maxCount = 0
                local counts = indexCountsInSelection(app.activeSprite.colorMode, palette, app.range.cels, app.activeSprite.selection)
                for i, count in pairs(counts) do
                    if count > maxCount then
                        maxCount = count
                    end
                end
                local width = dlg.data["histogramWidth"]
                local height = dlg.data["histogramHeight"]
                local xScale = width / #palette
                local yScale = height / maxCount
                local sprite = Sprite(width, height, ColorMode.INDEXED)
                local spritePalette = Palette(palette)
                spritePalette:resize(#spritePalette + 1)
                local bgColour = Color{red = 0, green = 0, blue = 0, alpha = 0}
                local bgIndex = #spritePalette - 1
                spritePalette:setColor(bgIndex, bgColour)
                sprite:setPalette(spritePalette)
                sprite.transparentColor = bgIndex
                local cel = sprite.cels[1]
                local image = cel.image
                for it in image:pixels() do
                    local index = math.floor((it.x + 0.5) / xScale)
                    local colour
                    if (it.y + 0.5) > height - math.floor(counts[index] * yScale) then
                        colour = index
                    else
                        colour = bgIndex
                    end
                    it(colour)
                end
            end)
            app.refresh()
        end}

        dlg:show{wait = false}
    end

    plugin:newCommand{
        id = "Palette Utils",
        title = "Palette Utils...",
        group = "palette_main",
        onclick = function()
            if plugin.preferences.loadOnOpen then
                loadUserData()
            end
            buildDialog()
        end
    }
end