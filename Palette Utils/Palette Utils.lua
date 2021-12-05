local json = dofile("json.lua")

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

    local function perPixelInSelection(cels, selection, modifyPixels, func)
        for _, cel in ipairs(cels) do
            local image = cel.image
            local bounds = Rectangle(0, 0, image.width, image.height)
            local hasSelection = selection ~= nil and not selection.isEmpty
            if hasSelection then
                local offsetSelectionBounds = Rectangle(selection.bounds.x - cel.position.x, selection.bounds.y - cel.position.y, selection.bounds.width, selection.bounds.height)
                bounds = bounds:intersect(offsetSelectionBounds)
            end
            if bounds.width > 0 and bounds.height > 0 then
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

    local function applyMappingInSelection(cels, selection, mapping)
        perPixelInSelection(cels, selection, true, function (it)
            local pixelValue = mapping[it()]
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
        else -- colourMode == ColorMode.GRAY
            return palette:getColor(index).grayPixel
        end
    end

    local function buildPixelValueToPaletteIndexLut(colorMode, palette)
        local lut = {}
        for i = 0, #palette - 1 do
            local pixelValue = indexPixelValue(colorMode, palette, i)
            lut[pixelValue] = i
        end
        return lut
    end

    local function indexCountsInSelection(cels, selection)
        local palette = app.activeSprite.palettes[1]
        local pixelValueToPaletteIndexLut = buildPixelValueToPaletteIndexLut(app.activeSprite.colorMode, palette)
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

    local function colourDistanceSquared(a, b)
        local deltaR = b.red - a.red
        local deltaG = b.green - a.green
        local deltaB = b.blue - a.blue
        local deltaA = b.alpha - a.alpha
        return deltaR * deltaR + deltaG * deltaG + deltaB * deltaB + deltaA * deltaA
    end

    local function colourDistance(a, b)
        return math.sqrt(colourDistanceSquared(a, b))
    end

    local function findNearestColourIndex(palette, colour)
        local nearestIndex = nil
        local nearestDistance = nil
        for i = 0, #palette - 1 do
            local distance = colourDistanceSquared(colour, palette:getColor(i))
            if nearestIndex == nil or distance < nearestDistance then
                nearestIndex = i
                nearestDistance = distance
            end
        end
        return nearestIndex
    end

    local function buildDeleteColoursMapping(colorMode, palette, deleteIndices, replacementIndexFunc)
        local removalSet = {}
        for _, index in ipairs(deleteIndices) do
            removalSet[index] = true
        end
        local remapIndex = 0
        local newPalette = Palette(#palette - #deleteIndices)
        local indexMapping = {}
        for i = 0, #palette - 1 do
            if removalSet[i] == true then
                indexMapping[i] = nil
            else
                indexMapping[i] = remapIndex
                newPalette:setColor(remapIndex, palette:getColor(i))
                remapIndex = remapIndex + 1
            end
        end
        local pixelValueMapping = {}
        for i = 0, #palette - 1 do
            local remapIndex = indexMapping[i]
            if remapIndex ~= nil then
                pixelValueMapping[indexPixelValue(colorMode, palette, i)] = indexPixelValue(colorMode, newPalette, remapIndex)
            else
                pixelValueMapping[indexPixelValue(colorMode, palette, i)] = replacementIndexFunc(indexMapping, palette, newPalette, i)
            end
        end
        return pixelValueMapping, newPalette
    end

    local function buildDialog()
        local dlg = Dialog("Palette Utils")

        dlg:separator{text = "Select Indices"}
        dlg:number{id = "similarityThreshold", label = "Similarity Threshold", text = tostring(0)}
        dlg:button{text = "Select Similar", onclick = function()
        end}
        dlg:number{id = "usageThreshold", label = "Usage Threshold", text = tostring(0)}
        dlg:button{text = "Select Below Usage Threshold", onclick = function()
            app.transaction(function()
                local palette = app.activeSprite.palettes[1]
                local indexCounts = indexCountsInSelection(app.range.cels, app.activeSprite.selection)
                local indices = {}
                for i, count in pairs(indexCounts) do
                    if count <= dlg.data["usageThreshold"] then
                        table.insert(indices, i)
                    end
                end
                app.range.colors = indices
            end)
            app.refresh()
        end}
        dlg:number{id = "nLeastUsed", label = "N Least Used", text = tostring(0), decimals = 0}
        dlg:button{text = "Select N Least Used", onclick = function()
            app.transaction(function()
                local palette = app.activeSprite.palettes[1]
                local indexCounts = indexCountsInSelection(app.range.cels, app.activeSprite.selection)
                local sortTable = {}
                for i = 0, #palette - 1 do
                    table.insert(sortTable, {index = i, count = indexCounts[i]})
                end
                table.sort(sortTable, function(a, b)
                    return a.count < b.count
                end)
                local n = dlg.data["nLeastUsed"]
                local leastUsedCount = math.min(n, #sortTable)
                local leastUsedIndices = {}
                for i = 1, leastUsedCount do
                    leastUsedIndices[i] = sortTable[i].index
                end
                app.range.colors = leastUsedIndices
            end)
            app.refresh()
        end}
        dlg:newrow()
        dlg:button{text = "Select Duplicates", onclick = function()
            app.transaction(function()
                local palette = app.activeSprite.palettes[1]
                local rgbaValueSet = {}
                local duplicateIndices = {}
                for i = 0, #palette - 1 do
                    local rgbaValue = palette:getColor(i).rgbaPixel
                    if rgbaValueSet[rgbaValue] == nil then
                        rgbaValueSet[rgbaValue] = true
                    else
                        table.insert(duplicateIndices, i)
                    end
                end
                app.range.colors = duplicateIndices
            end)
            app.refresh()
        end}

        dlg:separator{text = "Delete Indices"}
        dlg:button{text = "Replace Pixels With Nearest", onclick = function()
            app.transaction(function()
                local palette = app.activeSprite.palettes[1]
                local pixelValueMapping, newPalette = buildDeleteColoursMapping(app.activeSprite.colorMode, palette, app.range.colors, function(indexMapping, palette, newPalette, i)
                    return findNearestColourIndex(newPalette, palette:getColor(i))
                end)
                applyMappingInSelection(app.range.cels, app.activeSprite.selection, pixelValueMapping)
                app.activeSprite:setPalette(newPalette)
            end)
            app.refresh()
        end}
        -- dlg:number{id = "replacementIndex", label = "Replacement Index", text = tostring(0), decimals = 0}
        dlg:color{id = "replacementColour", label = "Replacement Colour", color = 0}
        dlg:button{text = "Replace Pixels With Colour", onclick = function()
            app.transaction(function()
                local palette = app.activeSprite.palettes[1]
                -- local replacementIndex = dlg.data["replacementIndex"]
                local replacementIndex = dlg.data["replacementColour"].index
                local pixelValueMapping, newPalette = buildDeleteColoursMapping(app.activeSprite.colorMode, palette, app.range.colors, function(indexMapping, palette, newPalette, i)
                    return indexMapping[replacementIndex]
                end)
                applyMappingInSelection(app.range.cels, app.activeSprite.selection, pixelValueMapping)
                app.activeSprite:setPalette(newPalette)
            end)
            app.refresh()
        end}

        dlg:separator{text = "Merge Indices"}
        dlg:button{text = "Merge to Most Used", onclick = function()
            app.transaction(function()
                local palette = app.activeSprite.palettes[1]
                local indexCounts = indexCountsInSelection(app.range.cels, app.activeSprite.selection)
                local sortTable = {}
                for _, index in pairs(app.range.colors) do
                    table.insert(sortTable, {index = index, count = indexCounts[index]})
                end
                table.sort(sortTable, function(a, b)
                    return a.count < b.count
                end)
                local mostUsedIndex = sortTable[#sortTable].index
                local deleteIndices = {}
                for i = 1, #sortTable - 1 do
                    table.insert(deleteIndices, sortTable[i].index)
                end
                local pixelValueMapping, newPalette = buildDeleteColoursMapping(app.activeSprite.colorMode, palette, deleteIndices, function(indexMapping, palette, newPalette, i)
                    return indexMapping[mostUsedIndex]
                end)
                applyMappingInSelection(app.range.cels, app.activeSprite.selection, pixelValueMapping)
                app.activeSprite:setPalette(newPalette)
            end)
            app.refresh()
        end}
        dlg:newrow()
        dlg:button{text = "Merge to Average", onclick = function()
            app.transaction(function()
                local palette = app.activeSprite.palettes[1]
                local sumR, sumG, sumB, sumA = 0, 0, 0, 0
                local sumCount = 0
                for _, index in pairs(app.range.colors) do
                    local colour = palette:getColor(index)
                    sumR = sumR + colour.red
                    sumG = sumG + colour.green
                    sumB = sumB + colour.blue
                    sumA = sumA + colour.alpha
                    sumCount = sumCount + 1
                end
                local replacementIndex = app.range.colors[1]
                local averageColour = Color{red = math.floor(sumR / sumCount + 0.5), green = math.floor(sumG / sumCount + 0.5), blue = math.floor(sumB / sumCount + 0.5), alpha = math.floor(sumA / sumCount + 0.5)}
                local deleteIndices = {}
                for i = 2, #app.range.colors do
                    table.insert(deleteIndices, app.range.colors[i])
                end
                palette:setColor(replacementIndex, averageColour)
                local pixelValueMapping, newPalette = buildDeleteColoursMapping(app.activeSprite.colorMode, palette, deleteIndices, function(indexMapping, palette, newPalette, i)
                    return indexMapping[replacementIndex]
                end)
                applyMappingInSelection(app.range.cels, app.activeSprite.selection, pixelValueMapping)
                app.activeSprite:setPalette(newPalette)
            end)
            app.refresh()
        end}
        dlg:newrow()
        dlg:button{text = "Merge Duplicates", onclick = function()
            app.transaction(function()
                local palette = app.activeSprite.palettes[1]
                local indices = app.range.colors
                local duplicateGroups = {}
                for _, index in pairs(indices) do
                    local rgbaValue = palette:getColor(index).rgbaPixel
                    if duplicateGroups[rgbaValue] == nil then
                        duplicateGroups[rgbaValue] = {}
                    end
                    table.insert(duplicateGroups[rgbaValue], index)
                end
                local replacements = {}
                for _, duplicateGroup in pairs(duplicateGroups) do
                    table.sort(duplicateGroup, function(a, b)
                        return a < b
                    end)
                    local keepIndex = duplicateGroup[1]
                    for i = 2, #duplicateGroup do
                        replacements[duplicateGroup[i]] = keepIndex
                    end
                end
                local indexMapping = {}
                local remapIndex = 0
                for i = 0, #palette - 1 do
                    if replacements[i] ~= nil then
                        indexMapping[i] = replacements[i]
                    else
                        indexMapping[i] = remapIndex
                        remapIndex = remapIndex + 1
                    end
                end
            end)
            app.refresh()
        end}

        dlg:separator{text = "Reduce Indices"}
        dlg:combobox{id = "reductionMode", label = "Reduction Mode", options = {"Replace With Nearest", "Replace With Weighted Average"}, option = "Replace With Nearest"}
        dlg:number{id = "reduceToSize", label = "Reduce to Size", text = tostring(16)}
        dlg:button{text = "Reduce", onclick = function()
        end}

        dlg:separator{text = "Add Indices"}
        dlg:button{text = "All From Selection", onclick = function()
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
                local averageColour = Color{red = math.floor(sumR / sumCount + 0.5), green = math.floor(sumG / sumCount + 0.5), blue = math.floor(sumB / sumCount + 0.5), alpha = math.floor(sumA / sumCount + 0.5)}
                local palette = app.activeSprite.palettes[1]
                local paletteSize = #palette
                palette:resize(paletteSize + 1)
                palette:setColor(paletteSize, averageColour)
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
        dlg:button{text = "Select Pixels", onclick = function()
        end}
         dlg:newrow()
        dlg:button{text = "Histogram", onclick = function()
        end}

        dlg:show{wait = false}
    end

    plugin:newCommand{
        id = "Palette Utils",
        title = "Palette Utils...",
        group = "edit_fx",
        onclick = function()
            if plugin.preferences.loadOnOpen then
                loadUserData()
            end
            buildDialog()
        end
    }
end