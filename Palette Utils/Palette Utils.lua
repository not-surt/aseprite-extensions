local vivid = dofile("vivid.lua")

function init(plugin)
    local function tableInverse(table)
        local inverse = {}
        for key, value in pairs(table) do
            inverse[value] = key
        end
        return inverse
    end
    
    local function clamp(min, max, value)
        return math.max(min, math.min(max, value))
    end
    local function wrap(min, max, value)
        local range = max - min
        if range == 0.0 then
            return min
        else
            local offsetValue = value - min
            local quotient = math.floor(offsetValue / range)
            local remainder = offsetValue - quotient * range
            return min + remainder
        end
    end

    local function byteToFloat(byteValue)
        return byteValue / 256
    end
    local function floatToByte(floatValue)
        return clamp(0, 255, math.floor(floatValue * 256))
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
    local colourSpaceWrappingComponents = {
        [ColourSpace.HSL] = {[1] = {0.0, 1.0}},
        [ColourSpace.HSV] = {[1] = {0.0, 1.0}},
        [ColourSpace.LCH] = {[3] = {0.0, 360.0}},
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
        [DistanceMetric.EUCLIDEAN] = function(sum, difference)
            return sum + difference ^ 2
        end,
        [DistanceMetric.MANHATTAN] = function(sum, difference)
            return sum + difference
        end,
        [DistanceMetric.CHEBYSHEV] = function(sum, difference)
            return math.max(sum, difference)
        end,
    }
    local distanceSumFunc = {
        [DistanceMetric.EUCLIDEAN] = function(sum, relative)
            if relative ~= true then
                return math.sqrt(sum)
            end
        end
    }
    local function distance(metric, colourSpace, a, b, componentScales, relative)
        local wrappingComponents = colourSpaceWrappingComponents[colourSpace]
        local sum = 0
        local elementCount = math.min(#a, #b)
        for i = 1, elementCount do
            if componentScales[i] ~= 0 then
                local difference = math.abs(b[i] - a[i])
                local componentRange = wrappingComponents and wrappingComponents[i]
                if componentRange then
                    difference = math.min(difference, math.abs(componentRange[2] - componentRange[1]) - difference)
                end
                sum = distanceElementFunc[metric](sum, difference * componentScales[i])
            end
        end
        if distanceSumFunc[metric] ~= nil then
            sum = distanceSumFunc[metric](sum, relative)
        end
        return sum
    end
    local function colourDistance(metric, colourSpace, a, b, componentScales, relative)
        local convertedA = colourConvert(ColourSpace.RGB, colourSpace, colourToFloatVector(a))
        local convertedB = colourConvert(ColourSpace.RGB, colourSpace, colourToFloatVector(b))
        return distance(metric, colourSpace, convertedA, convertedB, componentScales, relative)
    end

    local function lerp(a, b, pos)
        return (b - a) * pos + a
    end
    local InterpolationMethod = {
        CONSTANT = 0,
        LINEAR = 1,
        COSINE = 2,
        SMOOTHSTEP = 3,
        SMOOTHERSTEP = 4,
    }
    local interpolationMethodLabels = {
        [InterpolationMethod.CONSTANT] = "Constant",
        [InterpolationMethod.LINEAR] = "Linear",
        [InterpolationMethod.COSINE] = "Cosine",
        [InterpolationMethod.SMOOTHSTEP] = "Smoothstep",
        [InterpolationMethod.SMOOTHERSTEP] = "Smootherstep",
    }
    local interpolationMethodLabelsInverted = tableInverse(interpolationMethodLabels)
    local interpolateFunc = {
        [InterpolationMethod.CONSTANT] = function(pos)
            return 0
        end,
        [InterpolationMethod.LINEAR] = function(pos)
            return pos
        end,
        [InterpolationMethod.COSINE] = function(pos)
            return  0.5 - math.cos(-pos * math.pi) * 0.5
        end,
        [InterpolationMethod.SMOOTHSTEP] = function(pos)
            return pos^2 * (3 - 2 * pos)
        end,
        [InterpolationMethod.SMOOTHERSTEP] = function(pos)
            return pos^3 * (pos * (pos * 6 - 15) + 10)
        end,
    }
    local function interpolateValue(interpolationMethod, a, b, pos, componentRange)
        local posMethod = interpolateFunc[interpolationMethod](clamp(0, 1, pos))
        if componentRange ~= nil then
            local rangeSize = math.abs(componentRange[2] - componentRange[1])
            local halfRangeSize = rangeSize / 2.0
            local difference = math.abs(b - a)
            local offsetA = 0.0
            local offsetB = 0.0
            if difference > halfRangeSize then
                if a < b then
                    offsetB = -rangeSize
                else
                    offsetA = -rangeSize
                end
            end
            return wrap(componentRange[1], componentRange[2], lerp(a + offsetA, b + offsetB, posMethod))
        else
            return lerp(a, b, posMethod)
        end
    end
    local function interpolateVector(interpolationMethod, a, b, pos, wrappingComponents)
        local vector = {}
        for i = 1, #a do
            vector[i] = interpolateValue(interpolationMethod, a[i], b[i], pos, wrappingComponents and wrappingComponents[i])
        end
        return vector
    end
    local function interpolateColour(interpolationMethod, colourSpace, a, b, pos)
        local convertedA = colourConvert(ColourSpace.RGB, colourSpace, colourToFloatVector(a))
        local convertedB = colourConvert(ColourSpace.RGB, colourSpace, colourToFloatVector(b))
        local interpolated = interpolateVector(interpolationMethod, convertedA, convertedB, pos, colourSpaceWrappingComponents[colourSpace])
        local convertedInterpolated = colourConvert(colourSpace, ColourSpace.RGB, interpolated)
        return floatVectorToColour(convertedInterpolated)
    end
    local function rampInterpolateColour(interpolationMethod, colourSpace, palette, indices, pos)
        local step = 1.0 / (#indices - 1)
        local index = math.floor(pos / step)
        local segmentPos = (pos - index * step) / step
        local colourA = palette:getColor(indices[index + 1])
        local colourB = palette:getColor(indices[index + 2])
        return interpolateColour(interpolationMethod, colourSpace, colourA, colourB, segmentPos)
    end
    local function rampIndices(interpolationMethod, colourSpace, palette, indices)
        local colour0 = palette:getColor(indices[1])
        local colour1 = palette:getColor(indices[#indices])
        local step = 1.0 / (#indices - 1)
        local pos = step
        for i = 2, #indices - 1 do
            local colour = interpolateColour(interpolationMethod, colourSpace, colour0, colour1, pos)
            palette:setColor(indices[i], colour)
            pos = pos + step
        end
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

    local function indexMappingIdentity(palette)
        local mapping = {}
        for i = 0, #palette - 1 do
            mapping[i] = i
        end
        return mapping
    end

    local function paletteApplyIndexMapping(palette, indexMapping)
        local newPalette = Palette(#palette)
        for i = 0, #palette - 1 do
            newPalette:setColor(i, palette:getColor(indexMapping[i]))
        end
        return newPalette
    end

    local function applyPixelValueMappingInSelection(cels, selection, pixelValueMapping)
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

    local function findNearestColourIndex(metric, colourSpace, palette, colour, componentScales)
        local nearestIndex = nil
        local nearestDistance = nil
        for i = 0, #palette - 1 do
            local distance = colourDistance(metric, colourSpace, colour, palette:getColor(i), componentScales, false)
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
                pixelValueMapping[pixelValue] = indexPixelValue(colourMode, palette, unmappedIndexFunc(colourMode, palette, indexMapping, newPalette, i))
            end
        end
        return pixelValueMapping
    end

    local function paletteRemoveInsertMapping(palette, removeIndices, insertColours)
        if removeIndices then
            table.sort(removeIndices)
        end
        if insertColours then
            table.sort(insertColours, function(a, b)
                return a.index < b.index
            end)
        end
        local newPaletteColours = {}
        local mapping = {}
        local insertColoursIndex = 1
        local function insertColoursUntilIndex(index)
            while insertColours do
                local nextInsertIndex = insertColours[insertColoursIndex] and insertColours[insertColoursIndex].index
                if nextInsertIndex and (not index or nextInsertIndex <= index) then
                    for _, colour in ipairs(insertColours[insertColoursIndex].colours) do
                        table.insert(newPaletteColours, colour)
                    end
                    insertColoursIndex = insertColoursIndex + 1
                else
                    break
                end
            end
        end
        local removeIndicesIndex = 1
        for i = 0, #palette - 1 do
            -- Insert colours
            insertColoursUntilIndex(i)
            -- Remove colour
            local nextRemoveIndex = removeIndices and removeIndices[removeIndicesIndex]
            if i == nextRemoveIndex then
                mapping[i] = nil
                removeIndicesIndex = removeIndicesIndex + 1
            -- Colour not removed so transfer to new palette
            else
                mapping[i] = #newPaletteColours
                table.insert(newPaletteColours, palette:getColor(i))
            end
        end
        -- Insert any remaining colours
        insertColoursUntilIndex()
        local newPalette = Palette(#newPaletteColours)
        for i, colour in ipairs(newPaletteColours) do
            newPalette:setColor(i - 1, colour)
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
    local function removeIndices(sprite, cels, selection, indices, removeMode, distanceMetric, colourSpace, componentScales, replacementIndex)
        local colourMode = sprite.colorMode
        local palette = sprite.palettes[1]
        local unmappedIndexFunc = nil
        if removeMode == RemoveMode.REPLACE_WITH_NEAREST then
            unmappedIndexFunc = function(colourMode, palette, indexMapping, newPalette, index)
                return findNearestColourIndex(distanceMetric, colourSpace, newPalette, palette:getColor(index), componentScales)
            end
        elseif removeMode == RemoveMode.REPLACE_WITH_INDEX then
            unmappedIndexFunc = function(colourMode, palette, indexMapping, newPalette, index)
                return indexMapping[replacementIndex]
            end
        end
        if unmappedIndexFunc ~= nil then
            local newPalette, indexMapping = paletteRemoveInsertMapping(palette, indices, nil)
            local pixelValueMapping = buildPixelValueMappingFromIndexMapping(colourMode, palette, indexMapping, newPalette, unmappedIndexFunc)
            applyPixelValueMappingInSelection(cels, selection, pixelValueMapping)
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
    local function mergeIndices(sprite, cels, selection, indexGroups, mergeMode, colourSpace)
        local colourMode = sprite.colorMode
        local palette = sprite.palettes[1]
        local removeIndices = {}
        local replacementIndices = {}
        for _, indices in pairs(indexGroups) do
            if mergeMode == MergeMode.MOST_USED then
                local indexCounts = indexCountsInSelection(colourMode, palette, cels, selection)
                local sortTable = {}
                for _, index in pairs(indices) do
                    table.insert(sortTable, {index = index, count = indexCounts[index]})
                end
                table.sort(sortTable, function(a, b)
                    return a.count < b.count
                end)
                local replacementIndex = sortTable[#sortTable].index
                for i = 1, #sortTable - 1 do
                    local index = sortTable[i].index
                    replacementIndices[index] = replacementIndex
                    table.insert(removeIndices, index)
                end
            elseif mergeMode == MergeMode.AVERAGE then
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
                    local replacementIndex = indices[1]
                    for i = 2, #indices do
                        local index = indices[i]
                        replacementIndices[index] = replacementIndex
                        table.insert(removeIndices, index)
                    end
                    palette:setColor(replacementIndex, averageColour)
                end
            elseif mergeMode == MergeMode.WEIGHTED_AVERAGE then
                local indexCounts = indexCountsInSelection(colourMode, palette, cels, selection)
                local selectedIndexCounts = {}
                for _, index in pairs(indices) do
                    selectedIndexCounts[index] = indexCounts[index]
                end
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
                    local replacementIndex = indices[1]
                    for i = 2, #indices do
                        local index = indices[i]
                        replacementIndices[index] = replacementIndex
                        table.insert(removeIndices, index)
                    end
                    palette:setColor(replacementIndex, averageColour)
                end
            end
        end
        local newPalette, indexMapping = paletteRemoveInsertMapping(palette, removeIndices, nil)
        local pixelValueMapping = buildPixelValueMappingFromIndexMapping(colourMode, palette, indexMapping, newPalette, function(colourMode, palette, indexMapping, newPalette, i)
            return indexMapping[replacementIndices[i]]
        end)
        applyPixelValueMappingInSelection(cels, selection, pixelValueMapping)
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

    local function getIndicesSimilar(palette, indices, distanceMetric, colourSpace, distanceThreshold, componentScales)
        local indicesSet = {}
        for i = 1, #indices do
            local index = indices[i]
            indicesSet[index] = true
        end
        local testIndicesSet = {}
        for i = 0, #palette - 1 do
            if indicesSet[i] ~= true then
                testIndicesSet[i] = true
            end
        end
        local similarIndices = {}
        for testIndex, _ in pairs(testIndicesSet) do
            local nearestIndex = nil
            local nearestDistance = nil
            for index, _ in pairs(indicesSet) do
                local distance = colourDistance(distanceMetric, colourSpace, palette:getColor(index), palette:getColor(testIndex), componentScales, false)
                if distance < distanceThreshold then
                    if nearestIndex == nil or distance < nearestDistance then
                        nearestIndex = index
                        nearestDistance = distance
                    end
                end
            end
            if nearestIndex ~= nil then
                if similarIndices[nearestIndex] == nil then
                    similarIndices[nearestIndex] = {}
                end
                table.insert(similarIndices[nearestIndex], testIndex)
            end
        end
        return similarIndices
    end

    local function getSelectedIndices(noneToAll)
        local indices = app.range.colors
        if #indices == 0 then
            if noneToAll then
                local palette = app.activeSprite.palettes[1]
                for i = 0, #palette - 1 do
                    table.insert(indices, i)
                end
            else
                indices = {app.fgColor.index}
            end
        end
        return indices
    end

    local function buildDialog()
        local prefs = {distanceMetric = "option", colourSpace = "option", similarityThreshold = "text", componentScale0 = "text", componentScale1 = "text", componentScale2 = "text", componentScale3 = "text", usageThreshold = "text", leastUsedCount = "text", replacementColour = "color", mergeMode = "option", interpolationMethod = "option", rampSize = "text"}
        local dlg
        dlg = Dialog{title = "Palette Utils", onclose = function()
            for pref, _ in pairs(prefs) do
                plugin.preferences[pref] = dlg.data[pref]
            end
        end}

        dlg:separator{text = "Preferences"}
        dlg:combobox{id = "distanceMetric", label = "Distance Metric", options = distanceMetricLabels, option = distanceMetricLabels[DistanceMetric.EUCLIDEAN]}
        dlg:combobox{id = "colourSpace", label = "Colour Space", options = colourSpaceLabels, option = colourSpaceLabels[ColourSpace.RGB]}
        dlg:number{id = "similarityThreshold", label = "Similarity Threshold", text = tostring(64)}
        dlg:number{id = "componentScale0", label = "Component Scale", text = tostring(256)}
        dlg:number{id = "componentScale1", text = tostring(256)}
        dlg:number{id = "componentScale2", text = tostring(256)}
        dlg:number{id = "componentScale3", text = tostring(256)}
        dlg:number{id = "usageThreshold", label = "Usage Threshold", text = tostring(64)}
        dlg:number{id = "leastUsedCount", label = "Least Used Count", text = tostring(4), decimals = 0}
        dlg:color{id = "replacementColour", label = "Replacement Colour", color = 0, onchange = function()
            local colour = colourToFloatVector(dlg.data["replacementColour"])
            local converted = colourConvert(ColourSpace.RGB, colourSpaceLabelsInverted[dlg.data["colourSpace"]], colour)
            print(dlg.data["colourSpace"] .. ": (" .. converted[1] .. ", " .. converted[2] .. ", " .. converted[3] .. ", " .. converted[4] ..")")
        end}
        dlg:combobox{id = "mergeMode", label = "Merge Mode", options = mergeModeLabels, option = mergeModeLabels[MergeMode.MOST_USED]}
        dlg:combobox{id = "interpolationMethod", label = "Interpolation Method", options = interpolationMethodLabels, option = interpolationMethodLabels[InterpolationMethod.LINEAR]}
        dlg:number{id = "rampSize", label = "Ramp Size", text = tostring(8)}
        for pref, value in pairs(prefs) do
            if plugin.preferences[pref] ~= nil then
                dlg:modify{id = pref, [value] = plugin.preferences[pref]}
            end
        end
        
        dlg:separator{text = "Select Indices"}
        dlg:button{text = "Similar", onclick = function()
            app.transaction(function()
                local distanceMetric = distanceMetricLabelsInverted[dlg.data["distanceMetric"]]
                local colourSpace = colourSpaceLabelsInverted[dlg.data["colourSpace"]]
                local palette = app.activeSprite.palettes[1]
                local componentScales = {dlg.data["componentScale0"], dlg.data["componentScale1"], dlg.data["componentScale2"], dlg.data["componentScale3"]}
                local similarIndices = getIndicesSimilar(palette, getSelectedIndices(), distanceMetric, colourSpace, dlg.data["similarityThreshold"], componentScales)
                local indices = {}
                for _, similar in pairs(similarIndices) do
                    for _, index in pairs(similar) do
                        table.insert(indices, index)
                    end
                end
                app.range.colors = indices
            end)
            app.refresh()
        end}
        dlg:button{text = "Duplicates", onclick = function()
            app.transaction(function()
                app.range.colors = getIndicesDuplicated(app.activeSprite.palettes[1])
            end)
            app.refresh()
        end}
        dlg:newrow()
        dlg:button{text = "Below Usage Threshold", onclick = function()
            app.transaction(function()
                app.range.colors = getIndicesInUsageRange(app.activeSprite.colorMode, app.activeSprite.palettes[1], app.range.cels, app.activeSprite.selection, 0, dlg.data["usageThreshold"])
            end)
            app.refresh()
        end}
        dlg:button{text = "Least Used", onclick = function()
            app.transaction(function()
                app.range.colors = getIndicesNLeastUsed(app.activeSprite.colorMode, app.activeSprite.palettes[1], app.range.cels, app.activeSprite.selection, dlg.data["leastUsedCount"])
            end)
            app.refresh()
        end}
        dlg:newrow()
        dlg:button{text = "Invert Selection", onclick = function()
            app.transaction(function()
                local selectedSet = {}
                for _, index in pairs(getSelectedIndices()) do
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
        dlg:button{text = "Select Pixels", onclick = function()
            app.transaction(function()
                local coloursSet = {}
                for i, index in pairs(getSelectedIndices()) do
                    coloursSet[index] = true
                end
                local selection = Selection()
                local palette = app.activeSprite.palettes[1]
                local lut = buildPixelValueToPaletteIndexLut(app.activeSprite.colorMode, palette)
                local run = nil
                perPixelInSelection(app.range.cels, app.activeSprite.selection, false, function(it)
                    local pixelValue = it()
                    local index = lut[pixelValue]
                    if coloursSet[index] ~= true or (run ~= nil and it.y ~= run.finish.y) then
                        if run ~= nil then
                            -- finish run
                            local runWidth = run.finish.x - run.start.x + 1
                            local rect = Rectangle(run.start.x, run.start.y, runWidth, 1)
                            selection:add(rect)
                            run = nil
                        end
                    else
                        if run == nil then
                            -- start run
                            run = {}
                            run.start = Point(it.x, it.y)
                            run.finish = run.start
                        else
                            -- extend run
                            run.finish = Point(it.x, it.y)
                        end
                    end
                end)
                app.activeSprite.selection = selection
                app.refresh()
            end)
        end}

        dlg:separator{text = "Remove Indices"}
        dlg:button{text = "Replace With Nearest", onclick = function()
            app.transaction(function()
                local distanceMetric = distanceMetricLabelsInverted[dlg.data["distanceMetric"]]
                local colourSpace = colourSpaceLabelsInverted[dlg.data["colourSpace"]]
                local componentScales = {dlg.data["componentScale0"], dlg.data["componentScale1"], dlg.data["componentScale2"], dlg.data["componentScale3"]}
                removeIndices(app.activeSprite, app.range.cels, app.activeSprite.selection, getSelectedIndices(), RemoveMode.REPLACE_WITH_NEAREST, distanceMetric, colourSpace, componentScales)
            end)
            app.refresh()
        end}
        dlg:button{text = "Replace With Colour", onclick = function()
            app.transaction(function()
                local distanceMetric = distanceMetricLabelsInverted[dlg.data["distanceMetric"]]
                local colourSpace = colourSpaceLabelsInverted[dlg.data["colourSpace"]]
                local replacementIndex = dlg.data["replacementColour"].index
                local componentScales = {dlg.data["componentScale0"], dlg.data["componentScale1"], dlg.data["componentScale2"], dlg.data["componentScale3"]}
                removeIndices(app.activeSprite, app.range.cels, app.activeSprite.selection, getSelectedIndices(), RemoveMode.REPLACE_WITH_INDEX, distanceMetric, colourSpace, componentScales, replacementIndex)
            end)
            app.refresh()
        end}
        dlg:newrow()
        dlg:button{text = "Unused", onclick = function()
            app.transaction(function()
                local indices = getIndicesInUsageRange(app.activeSprite.colorMode, app.activeSprite.palettes[1], app.range.cels, app.activeSprite.selection, 0, 1)
                local distanceMetric = distanceMetricLabelsInverted[dlg.data["distanceMetric"]]
                local colourSpace = colourSpaceLabelsInverted[dlg.data["colourSpace"]]
                local replacementIndex = dlg.data["replacementColour"].index
                local componentScales = {dlg.data["componentScale0"], dlg.data["componentScale1"], dlg.data["componentScale2"], dlg.data["componentScale3"]}
                removeIndices(app.activeSprite, app.range.cels, app.activeSprite.selection, indices, RemoveMode.REPLACE_WITH_INDEX, distanceMetric, colourSpace, componentScales, replacementIndex)
            end)
            app.refresh()
        end}
        dlg:button{text = "Duplicates", onclick = function()
            app.transaction(function()
                local distanceMetric = distanceMetricLabelsInverted[dlg.data["distanceMetric"]]
                local colourSpace = colourSpaceLabelsInverted[dlg.data["colourSpace"]]
                local indices = getIndicesDuplicated(app.activeSprite.palettes[1])
                local componentScales = {dlg.data["componentScale0"], dlg.data["componentScale1"], dlg.data["componentScale2"], dlg.data["componentScale3"]}
                removeIndices(app.activeSprite, app.range.cels, app.activeSprite.selection, indices, RemoveMode.REPLACE_WITH_NEAREST, distanceMetric, colourSpace, componentScales)
            end)
            app.refresh()
        end}

        dlg:separator{text = "Merge Indices"}
        dlg:button{text = "Selected", onclick = function()
            app.transaction(function()
                local colourSpace = colourSpaceLabelsInverted[dlg.data["colourSpace"]]
                local mergeMode = mergeModeLabelsInverted[dlg.data["mergeMode"]]
                mergeIndices(app.activeSprite, app.range.cels, app.activeSprite.selection, {getSelectedIndices()}, mergeMode, colourSpace)
            end)
            app.refresh()
        end}
        dlg:button{text = "Similar", onclick = function()
            app.transaction(function()
                local distanceMetric = distanceMetricLabelsInverted[dlg.data["distanceMetric"]]
                local colourSpace = colourSpaceLabelsInverted[dlg.data["colourSpace"]]
                local palette = app.activeSprite.palettes[1]
                local componentScales = {dlg.data["componentScale0"], dlg.data["componentScale1"], dlg.data["componentScale2"], dlg.data["componentScale3"]}
                local similarityThreshold = dlg.data["similarityThreshold"]
                local mergeMode = mergeModeLabelsInverted[dlg.data["mergeMode"]]
                local similarIndices = getIndicesSimilar(palette, getSelectedIndices(), distanceMetric, colourSpace, similarityThreshold, componentScales)
                local indexGroups = {}
                for index, indices in pairs(similarIndices) do
                    table.insert(indices, index)
                    table.insert(indexGroups, indices)
                end
                mergeIndices(app.activeSprite, app.range.cels, app.activeSprite.selection, indexGroups, mergeMode, colourSpace)
            end)
            app.refresh()
        end}

        dlg:separator{text = "Ramps"}
        dlg:newrow()
        dlg:button{text = "Interpolate", onclick = function()
            app.transaction(function()
                local colourSpace = colourSpaceLabelsInverted[dlg.data["colourSpace"]]
                local interpolationMethod = interpolationMethodLabelsInverted[dlg.data["interpolationMethod"]]
                local palette = Palette(app.activeSprite.palettes[1])
                local indices = getSelectedIndices()
                rampIndices(interpolationMethod, colourSpace, palette, indices)
                app.activeSprite:setPalette(palette)
            end)
            app.refresh()
        end}
        dlg:button{text = "Spline", onclick = function()
            app.transaction(function()
                local colourSpace = colourSpaceLabelsInverted[dlg.data["colourSpace"]]
                local interpolationMethod = interpolationMethodLabelsInverted[dlg.data["interpolationMethod"]]
                local palette = Palette(app.activeSprite.palettes[1])
                local indices = getSelectedIndices(false)
                for i = 1, #indices - 1 do
                    local segmentIndices = {}
                    for j = indices[i], indices[i + 1] do
                        table.insert(segmentIndices, j)
                    end
                    rampIndices(interpolationMethod, colourSpace, palette, segmentIndices)
                end
                app.activeSprite:setPalette(palette)
            end)
            app.refresh()
        end}
        dlg:newrow()
        -- dlg:button{text = "Combinations", onclick = function()
        --     app.transaction(function()
        --         local colourSpace = colourSpaceLabelsInverted[dlg.data["colourSpace"]]
        --         local interpolationMethod = interpolationMethodLabelsInverted[dlg.data["interpolationMethod"]]
        --         local palette = Palette(app.activeSprite.palettes[1])
        --         local indices = getSelectedIndices(false)
        --         for i = 1, #indices do
        --             for j = i + 1, #indices do

        --             end
        --         end
        --         app.activeSprite:setPalette(palette)
        --     end)
        --     app.refresh()
        -- end}
        -- dlg:newrow()
        dlg:button{text = "Resize", onclick = function()
            app.transaction(function()
                local sprite = app.activeSprite
                local cels = app.range.cels
                local selection = app.activeSprite.selection
                local interpolationMethod = interpolationMethodLabelsInverted[dlg.data["interpolationMethod"]]
                local distanceMetric = distanceMetricLabelsInverted[dlg.data["distanceMetric"]]
                local colourSpace = colourSpaceLabelsInverted[dlg.data["colourSpace"]]
                local colourMode = sprite.colorMode
                local componentScales = {dlg.data["componentScale0"], dlg.data["componentScale1"], dlg.data["componentScale2"], dlg.data["componentScale3"]}
                local palette = app.activeSprite.palettes[1]
                local fromIndices = getSelectedIndices(false)
                local toSize = dlg.data["rampSize"]
                local toStep = 1.0 / (toSize - 1)
                local pos = 0.0
                local toColours = {}
                for i = 1, toSize do
                    table.insert(toColours, rampInterpolateColour(interpolationMethod, colourSpace, palette, fromIndices, pos))
                    pos = pos + toStep
                end
                local newPalette, indexMapping = paletteRemoveInsertMapping(palette, fromIndices, {{index = fromIndices[1], colours = toColours}})
                local pixelValueMapping = buildPixelValueMappingFromIndexMapping(colourMode, palette, indexMapping, newPalette, function(colourMode, palette, indexMapping, newPalette, index)
                    return findNearestColourIndex(distanceMetric, colourSpace, newPalette, palette:getColor(index), componentScales)
                end)
                -- TODO: map indices to nearest ramp positions
                applyPixelValueMappingInSelection(cels, selection, pixelValueMapping)
                sprite:setPalette(newPalette)
            end)
            app.refresh()
        end}
        dlg:button{text = "Reverse", onclick = function()
            app.transaction(function()
                local sprite = app.activeSprite
                local cels = app.range.cels
                local selection = app.activeSprite.selection
                local distanceMetric = distanceMetricLabelsInverted[dlg.data["distanceMetric"]]
                local colourSpace = colourSpaceLabelsInverted[dlg.data["colourSpace"]]
                local colourMode = sprite.colorMode
                local componentScales = {dlg.data["componentScale0"], dlg.data["componentScale1"], dlg.data["componentScale2"], dlg.data["componentScale3"]}
                local palette = app.activeSprite.palettes[1]
                local indices = getSelectedIndices(false)
                local reverseLength = #indices // 2
                local indexMapping = indexMappingIdentity(palette)
                for i = 1, reverseLength do
                    local reverseIndex = #indices - (i - 1)
                    local tempIndex = indexMapping[indices[i]]
                    indexMapping[indices[i]] = indexMapping[indices[reverseIndex]]
                    indexMapping[indices[reverseIndex]] = tempIndex
                end
                local newPalette = paletteApplyIndexMapping(palette, indexMapping)
                local pixelValueMapping = buildPixelValueMappingFromIndexMapping(colourMode, palette, indexMapping, newPalette, function(colourMode, palette, indexMapping, newPalette, index)
                    return findNearestColourIndex(distanceMetric, colourSpace, newPalette, palette:getColor(index), componentScales)
                end)
                applyPixelValueMappingInSelection(cels, selection, pixelValueMapping)
                sprite:setPalette(newPalette)
            end)
            app.refresh()
        end}

        dlg:separator{text = "Add Indices"}
        dlg:button{text = "Unique Pixels", onclick = function()
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
        dlg:button{text = "All Pixels", onclick = function()
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
        dlg:newrow()
        dlg:button{text = "Grid Centres", onclick = function()
            app.transaction(function()
                -- TODO: includes extra cells
                local palette = app.activeSprite.palettes[1]
                local grid = app.activeSprite.gridBounds
                local selection = app.activeSprite.selection
                local hasSelection = selection ~= nil and not selection.isEmpty
                for _, cel in ipairs(app.range.cels) do
                    local bounds = celSelectionOffsetBounds(cel, selection)
                    local gridX0 = math.floor((bounds.x - grid.x) / grid.width)
                    local gridY0 = math.floor((bounds.y - grid.y) / grid.height)
                    local gridX1 = math.ceil((bounds.x - grid.x + bounds.width) / grid.width) - 1
                    local gridY1 = math.ceil((bounds.y - grid.y + bounds.height) / grid.height) - 1
                    local image = cel.image
                    local colours = {}
                    for y = gridY0, gridY1 do
                        for x = gridX0, gridX1 do
                            local pos = Point(math.floor((x + 0.5) * grid.width + grid.x), math.floor((y + 0.5) * grid.height + grid.y))
                            if not hasSelection or selection:contains(pos.x + cel.position.x, pos.y + cel.position.y) then
                                table.insert(colours, Color(image:getPixel(pos.x, pos.y)))
                            end
                        end
                    end
                    local paletteSize = #palette
                    palette:resize(paletteSize + #colours)
                    for i = 1, #colours do
                        palette:setColor(paletteSize - 1 + i, colours[i])
                    end
                end
            end)
            app.refresh()
        end}
        dlg:button{text = "Weighted Average", onclick = function()
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

        dlg:separator{text = "Misc."}
        local colourCountText = "Count Colours Used"
        dlg:button{id = "colourCount", text = colourCountText, onclick = function()
            local colourSequence, _ = coloursInSelection(app.range.cels, app.activeSprite.selection)
            dlg:modify{id = "colourCount", text = colourCountText .. ": " .. tostring(#colourSequence)}
        end}
        local pixelCountText = "Count Pixels Used"
        dlg:button{id = "pixelCount", text = pixelCountText, onclick = function()
            local colourSequence, _ = coloursInSelection(app.range.cels, app.activeSprite.selection)
            dlg:modify{id = "pixelCount", text = pixelCountText .. ": " .. tostring(#colourSequence)}
        end}
        dlg:newrow()
        local measureDistanceText = "Measure Distance"
        dlg:button{id = "measureDistance", text = measureDistanceText, onclick = function()
            local palette = app.activeSprite.palettes[1]
            local distanceMetric = distanceMetricLabelsInverted[dlg.data["distanceMetric"]]
            local colourSpace = colourSpaceLabelsInverted[dlg.data["colourSpace"]]
            local componentScales = {dlg.data["componentScale0"], dlg.data["componentScale1"], dlg.data["componentScale2"], dlg.data["componentScale3"]}
            local indices = getSelectedIndices(false)
            local maxDistance = 0
            for i = 1, #indices do
                for j = i + 1, #indices do
                    local a = palette:getColor(indices[i])
                    local b = palette:getColor(indices[j])
                    local distance = colourDistance(distanceMetric, colourSpace, a, b, componentScales, false)
                    maxDistance = math.max(maxDistance, distance)
                end
            end
            dlg:modify{id = "measureDistance", text = measureDistanceText .. ": " .. tostring(maxDistance)}
        end}
        dlg:button{text = "Histogram", onclick = function()
            app.transaction(function()
                local palette = app.activeSprite.palettes[1]
                local maxCount = 0
                local counts = indexCountsInSelection(app.activeSprite.colorMode, palette, app.range.cels, app.activeSprite.selection)
                for i, count in pairs(counts) do
                    if count > maxCount then
                        maxCount = count
                    end
                end
                local width = #palette
                local height = width
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
            buildDialog()
        end
    }
end