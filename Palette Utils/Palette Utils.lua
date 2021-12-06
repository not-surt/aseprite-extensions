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

    local function buildDeleteColoursMapping(colourMode, palette, deleteIndices, replacementIndexFunc)
        local removalSet = {}
        for _, index in ipairs(deleteIndices) do
            removalSet[index] = true
        end
        local newPalette = Palette(#palette - #deleteIndices)
        local remapIndex = 0
        for i = 0, #palette - 1 do
            if removalSet[i] == nil then
                newPalette:setColor(remapIndex, palette:getColor(i))
                remapIndex = remapIndex + 1
            end
        end
        local indexMapping = {}
        remapIndex = 0
        for i = 0, #palette - 1 do
            if removalSet[i] == true then
                indexMapping[i] = nil
            else
                indexMapping[i] = remapIndex
                remapIndex = remapIndex + 1
            end
        end
        local pixelValueMapping = {}
        for i = 0, #palette - 1 do
            local remapIndex = indexMapping[i]
            if remapIndex ~= nil then
                pixelValueMapping[indexPixelValue(colourMode, palette, i)] = indexPixelValue(colourMode, newPalette, remapIndex)
            else
                pixelValueMapping[indexPixelValue(colourMode, palette, i)] = replacementIndexFunc(indexMapping, palette, newPalette, i)
            end
        end
        return pixelValueMapping, newPalette
    end

    local function buildPixelValueMappingFromIndexMapping(colourMode, palette, indexMapping)
        local pixelValueMapping = {}
        for i = 0, #palette - 1 do
            local pixelValue = indexPixelValue(colourMode, palette, i)
            if pixelValue ~= nil then
                pixelValueMapping[pixelValue] = indexPixelValue(colourMode, palette, indexMapping[i])
            end
        end
        return pixelValueMapping
    end
    
    local DeleteMode = {
        REPLACE_WITH_NEAREST = "Replace With Nearest",
        REPLACE_WITH_INDEX = "Replace With Index",
    }
    local function deleteIndices(sprite, cels, selection, indices, deleteMode, replacementIndex)
        local colourMode = sprite.colorMode
        local palette = sprite.palettes[1]
        local replacementFunc = nil
        if deleteMode == DeleteMode.REPLACE_WITH_NEAREST then
            replacementFunc = function(indexMapping, palette, newPalette, i)
                return findNearestColourIndex(newPalette, palette:getColor(i))
            end
        elseif deleteMode == DeleteMode.REPLACE_WITH_INDEX then
            replacementFunc = function(indexMapping, palette, newPalette, i)
                return indexMapping[replacementIndex]
            end
        end
        if replacementFunc ~= nil then
            local pixelValueMapping, newPalette = buildDeleteColoursMapping(colourMode, palette, indices, replacementFunc)
            applyMappingInSelection(cels, selection, pixelValueMapping)
            sprite:setPalette(newPalette)
        end
    end

    local MergeMode = {
        MOST_USED = "Merge to Most Used",
        AVERAGE = "Merge to Average",
        WEIGHTED_AVERAGE = "Merge to Weighted Average",
    }
    local function mergeIndices(sprite, cels, selection, indices, mergeMode)
        local colourMode = sprite.colorMode
        local palette = sprite.palettes[1]
        local replacementIndex = nil
        local deleteIndices = {}
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
                table.insert(deleteIndices, sortTable[i].index)
            end
        elseif mergeMode == MergeMode.AVERAGE then
            local sumR, sumG, sumB, sumA = 0, 0, 0, 0
            local sumCount = 0
            for _, index in pairs(indices) do
                local colour = palette:getColor(index)
                sumR = sumR + colour.red
                sumG = sumG + colour.green
                sumB = sumB + colour.blue
                sumA = sumA + colour.alpha
                sumCount = sumCount + 1
            end
            local averageColour = Color{red = math.floor(sumR / sumCount + 0.5), green = math.floor(sumG / sumCount + 0.5), blue = math.floor(sumB / sumCount + 0.5), alpha = math.floor(sumA / sumCount + 0.5)}
            replacementIndex = indices[1]
            for i = 2, #indices do
                table.insert(deleteIndices, indices[i])
            end
            palette:setColor(replacementIndex, averageColour)
        elseif mergeMode == MergeMode.WEIGHTED_AVERAGE then
            local indexCounts = indexCountsInSelection(colourMode, palette, cels, selection)
            local selectedIndexCounts = {}
            for _, index in pairs(indices) do
                selectedIndexCounts[index] = indexCounts[index]
            end
            local sumR, sumG, sumB, sumA = 0, 0, 0, 0
            local sumCount = 0
            for index, count in pairs(selectedIndexCounts) do
                local colour = palette:getColor(index)
                sumR = sumR + colour.red * count
                sumG = sumG + colour.green * count
                sumB = sumB + colour.blue * count
                sumA = sumA + colour.alpha * count
                sumCount = sumCount + count
            end
            if sumCount > 0 then
                local averageColour = Color{red = math.floor(sumR / sumCount + 0.5), green = math.floor(sumG / sumCount + 0.5), blue = math.floor(sumB / sumCount + 0.5), alpha = math.floor(sumA / sumCount + 0.5)}
                replacementIndex = indices[1]
                for i = 2, #indices do
                    table.insert(deleteIndices, indices[i])
                end
                palette:setColor(replacementIndex, averageColour)
            end
        end
        local pixelValueMapping, newPalette = buildDeleteColoursMapping(colourMode, palette, deleteIndices, function(indexMapping, palette, newPalette, i)
            return indexMapping[replacementIndex]
        end)
        applyMappingInSelection(cels, selection, pixelValueMapping)
        sprite:setPalette(newPalette)
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
                local indexCounts = indexCountsInSelection(app.activeSprite.colorMode, palette, app.range.cels, app.activeSprite.selection)
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
                local indexCounts = indexCountsInSelection(app.activeSprite.colorMode, palette, app.range.cels, app.activeSprite.selection)
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
                deleteIndices(app.activeSprite, app.range.cels, app.activeSprite.selection, app.range.colors, DeleteMode.REPLACE_WITH_NEAREST)
            end)
            app.refresh()
        end}
        dlg:color{id = "replacementColour", label = "Replacement Colour", color = 0}
        dlg:button{text = "Replace Pixels With Colour", onclick = function()
            app.transaction(function()
                local replacementIndex = dlg.data["replacementColour"].index
                deleteIndices(app.activeSprite, app.range.cels, app.activeSprite.selection, app.range.colors, DeleteMode.REPLACE_WITH_INDEX, replacementIndex)
            end)
            app.refresh()
        end}

        dlg:separator{text = "Merge Indices"}
        dlg:button{text = "Merge to Most Used", onclick = function()
            app.transaction(function()
                mergeIndices(app.activeSprite, app.range.cels, app.activeSprite.selection, app.range.colors, MergeMode.MOST_USED)
            end)
            app.refresh()
        end}
        dlg:newrow()
        dlg:button{text = "Merge to Average", onclick = function()
            app.transaction(function()
                mergeIndices(app.activeSprite, app.range.cels, app.activeSprite.selection, app.range.colors, MergeMode.AVERAGE)
            end)
            app.refresh()
        end}
        dlg:newrow()
        dlg:button{text = "Merge to Weighted Average", onclick = function()
            app.transaction(function()
                mergeIndices(app.activeSprite, app.range.cels, app.activeSprite.selection, app.range.colors, MergeMode.WEIGHTED_AVERAGE)
            end)
            app.refresh()
        end}
        dlg:newrow()
        dlg:button{text = "Merge Duplicates", onclick = function()
            app.transaction(function()
                local palette = app.activeSprite.palettes[1]
                local indices = app.range.colors
                if #indices == 0 then
                    indices = {}
                    for i = 0, #palette - 1 do
                        table.insert(indices, i)
                    end
                end
                local duplicateGroups = {}
                for _, index in pairs(indices) do
                    local rgbaValue = palette:getColor(index).rgbaPixel
                    if duplicateGroups[rgbaValue] == nil then
                        duplicateGroups[rgbaValue] = {}
                    end
                    table.insert(duplicateGroups[rgbaValue], index)
                end
                local replacements = {}
                local duplicateCount = 0
                for _, duplicateGroup in pairs(duplicateGroups) do
                    table.sort(duplicateGroup, function(a, b)
                        return a < b
                    end)
                    duplicateCount = duplicateCount + #duplicateGroup - 1
                    local keepIndex = duplicateGroup[1]
                    for i = 2, #duplicateGroup do
                        replacements[duplicateGroup[i]] = keepIndex
                    end
                end
                local indexMapping = {}
                local remapIndex = 0
                local newPalette = Palette(#palette - duplicateCount)
                for i = 0, #palette - 1 do
                    if replacements[i] ~= nil then
                        indexMapping[i] = replacements[i]
                    else
                        indexMapping[i] = remapIndex
                        newPalette:setColor(remapIndex, palette:getColor(i))
                        remapIndex = remapIndex + 1
                    end
                end
                local colourMode = app.activeSprite.colorMode
                local pixelValueMapping = {}
                for i = 0, #palette - 1 do
                    local remapIndex = indexMapping[i]
                    if remapIndex ~= nil then
                        pixelValueMapping[indexPixelValue(colourMode, palette, i)] = indexPixelValue(colourMode, newPalette, remapIndex)
                    else
                        -- pixelValueMapping[indexPixelValue(colourMode, palette, i)] = replacementIndexFunc(indexMapping, palette, newPalette, i)
                    end
                end
                applyMappingInSelection(app.range.cels, app.activeSprite.selection, pixelValueMapping)
                app.activeSprite:setPalette(newPalette)
            end)
            app.refresh()
        end}

        dlg:separator{text = "Reduce Indices"}
        local ReductionMode = {
            NEAREST = "Replace With Nearest",
            AVERAGE = "Replace With Average",
            WEIGHTED_AVERAGE = "Replace With Weighted Average",
        }
        dlg:combobox{id = "reductionMode", label = "Reduction Mode", options = {ReductionMode.NEAREST, ReductionMode.AVERAGE, ReductionMode.WEIGHTED_AVERAGE}, option = ReductionMode.NEAREST}
        dlg:number{id = "reductionSize", label = "Reduction Size", text = tostring(16)}
        dlg:button{text = "Reduce to Size", onclick = function()
            app.transaction(function()
                local palette = app.activeSprite.palettes[1]
                local reduceCount = #palette + 1 - dlg.data["reductionSize"]
                local indices = {}
                -- select reduceCount least used indices
                local reductionMode = dlg.data["reductionMode"]
                if reductionMode == ReductionMode.NEAREST then

                elseif reductionMode == ReductionMode.AVERAGE then

                elseif reductionMode == ReductionMode.WEIGHTED_AVERAGE then

                end
            end)
            app.refresh()
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
        dlg:label{id = "colourCount", label = "Colour Count", text="-"}
        dlg:button{text = "Count Colours Used", onclick = function()
            local colourSequence, _ = coloursInSelection(app.range.cels, app.activeSprite.selection)
            dlg:modify{id = "colourCount", text=tostring(#colourSequence)}
        end}
        dlg:newrow()
        dlg:button{text = "Select Pixels", onclick = function()
            local coloursSet = {}
            for i, index in pairs(app.range.colors) do
                coloursSet[index] = true
            end
            local selection = Selection()
            perPixelInSelection(app.range.cels, app.activeSprite.selection, false, function(it)
                local pixelValue = it()
                local index = pixelValue ---------------------
                if coloursSet[index] == true then
                    
                end
            end)
        end}
        dlg:newrow()
        dlg:number{id = "histogramWidth", label = "Histogram Size", text = tostring(256)}
        dlg:number{id = "histogramHeight", text = tostring(256)}
        dlg:check{id = "histogramExcludeTransparent", label = "Histogram Exclude Transparent", value = false}
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
                    local index = math.floor(it.x / xScale)
                    local colour
                    if it.y > height - 1 - math.floor(counts[index] * yScale) then
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