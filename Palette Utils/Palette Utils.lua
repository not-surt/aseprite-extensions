local json = dofile("json.lua")

function init(plugin)
    local defaults = {loadOnOpen=false, storeOnClose=false}
    if plugin.preferences == nil then plugin.preferences = {} end
    for key, value in pairs(defaults) do
        if plugin.preferences[key] == nil then plugin.preferences[key] = value end
    end

    local function storeUserData()
    end
    local function loadUserData()
    end

    local function coloursInSelection(cels, selection)
        local colourSequence = {}
        local colourCount = {}
        local count = 0
        for _, cel in ipairs(cels) do
            local image = cel.image
            local bounds = Rectangle(0, 0, image.width, image.height)
            local offsetSelectionBounds = Rectangle(selection.bounds.x - cel.position.x, selection.bounds.y - cel.position.y, selection.bounds.width, selection.bounds.height)
            bounds = bounds:intersect(offsetSelectionBounds)
            for it in image:pixels(bounds) do
                if selection:contains(it.x + cel.position.x, it.y + cel.position.y) then
                    count = count + 1
                    local pixelValue = it()
                    if colourCount[pixelValue] == nil then
                        colourCount[pixelValue] = 1
                        colourSequence[#colourSequence + 1] = pixelValue
                    else
                        colourCount[pixelValue] = colourCount[pixelValue] + 1
                    end
                end
            end
        end
        return colourSequence, colourCount
    end

    local function buildDialog()
        local dlg = Dialog("Palette Utils")

        dlg:separator{text="Selection"}
        dlg:check{id="selectPixels", text="Select Pixels", selected=false}
        dlg:number{id="similarityThreshold", label="Similarity Threshold", text=0}
        dlg:button{text="Select Similar", onclick=function()
        end}
        dlg:number{id="frequencyThreshold", label="Frequency Threshold", text=0}
        dlg:button{text="Select Infrequent", onclick=function()
        end}
        dlg:number{id="nLeastUsed", label="N Least Used", text=0}
        dlg:button{text="Select N Least Used", onclick=function()
            local palette = app.activeSprite.palettes[1]
            for i = 0, #palette - 1 do
                
            end
        end}

        dlg:separator{text="Merging"}
        dlg:combobox{id="mergeMode", label="Merge Mode", options={"Most Frequent", "Weighted Average"}, option="Weighted Average"}
        dlg:button{text="Merge Selected", onclick=function()
        end}

        dlg:separator{text="Reduction"}
        dlg:combobox{id="reductionMode", label="Reduction Mode", options={"Replace With Nearest", "Weighted Average With Nearest"}, option="Replace With Nearest"}
        dlg:number{id="reduceToSize", label="Reduce to Size", text=16}
        dlg:button{text="Merge Selected", onclick=function()
        end}

        dlg:separator{text="Add Colours"}
        dlg:button{text="All From Selection", onclick=function()
            local colourSequence, _ = coloursInSelection(app.range.cels, app.activeSprite.selection)
            local palette = app.activeSprite.palettes[1]
            local paletteSize = #palette
            palette:resize(paletteSize + #colourSequence)
            for i, pixelValue in ipairs(colourSequence) do
                local colour = Color(pixelValue)
                palette:setColor(paletteSize - 1 + i, colour)
            end
        end}
        dlg:newrow()
        dlg:button{text="Average From Selection", onclick=function()
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
            -- local averageColour = Color{red = sumR // sumCount, green = sumG // sumCount, blue = sumB // sumCount, alpha = sumA // sumCount}
            local averageColour = Color{red = math.floor(sumR / sumCount + 0.5), green = math.floor(sumG / sumCount + 0.5), blue = math.floor(sumB / sumCount + 0.5), alpha = math.floor(sumA / sumCount + 0.5)}
            local palette = app.activeSprite.palettes[1]
            local paletteSize = #palette
            palette:resize(paletteSize + 1)
            palette:setColor(paletteSize, averageColour)
        end}

        dlg:separator{text="Misc."}
        dlg:button{text="Histogram", onclick=function()
        end}

        dlg:show{wait=false}
    end

    plugin:newCommand{
        id="Palette Utils",
        title="Palette Utils...",
        group="edit_fx",
        onclick=function()
            if plugin.preferences.loadOnOpen then
                loadUserData()
            end
            buildDialog()
        end
    }
end