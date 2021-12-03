----------------------------------------------------------------------
-- Recolouriser
----------------------------------------------------------------------

local json = dofile("json.lua")

function init(plugin)
    local defaults = {loadOnOpen=false, storeOnClose=false, applyTo="Pixels"}
    if plugin.preferences == nil then plugin.preferences = {} end
    for key, value in pairs(defaults) do
        if plugin.preferences[key] == nil then plugin.preferences[key] = value end
    end
    local mappings = {}
    local dlg = nil

    local function buildMappingsLut(palette, mappings)
        local lut = {}
        local lutSize = 256
        if palette ~= nil then
            lutSize = #palette
        end
        for i=0,lutSize-1 do
            lut[i] = i
        end
        for _,mapping in ipairs(mappings) do
            if mapping.selected > 0 then
                for i=1,#mapping.from do
                    local pos = 0.0
                    if #mapping.from > 1 then
                        pos = (i - 1) / (#mapping.from)
                    end
                    local toIndex = 1 + math.floor(pos * (#mapping.to[mapping.selected]))
                    lut[mapping.from[i]] = mapping.to[mapping.selected][toIndex]
                end
            end
        end
        return lut
    end

    local function applyMappingLutToPixels(image, position, selection, lut)
        if selection == nil or selection.isEmpty then
            for it in image:pixels() do
                it(lut[it()])
            end
        else
            local bounds = Rectangle(0, 0, image.width, image.height)
            local offsetSelectionBounds = Rectangle(selection.bounds.x - position.x, selection.bounds.y - position.y, selection.bounds.width, selection.bounds.height)
            bounds = bounds:intersect(offsetSelectionBounds)
            for it in image:pixels(bounds) do
                if selection:contains(it.x + position.x, it.y + position.y) then
                    it(lut[it()])
                end
            end
        end
    end

    local function applyMappingLutToPalette(palette, lut)
        local temp = Palette(palette)
        for i=0,#palette-1 do
            palette:setColor(i, temp:getColor(lut[i]))
        end
    end

    local function storeUserData()
        assert(app.activeSprite ~= nil)
        local str = json.encode({mappings=mappings})
        app.activeSprite.data = str
    end

    local function loadUserData()
        assert(app.activeSprite ~= nil)
        if app.activeSprite.data ~= nil and app.activeSprite.data ~= "" then
            local status,data = pcall(function() json.decode(app.activeSprite.data) end)
            if status == true and type(data) == "table" then
                if data.mappings ~= nil then
                    mappings = data.mappings
                end
            end
        end
    end

    local function paletteIndicesFromColours(colours)
        local indices = {}
        for i,colour in ipairs(colours) do
            indices[i] = colour.index
        end
        return indices
    end

    local function coloursFromPaletteIndices(palette, indices)
        local colours = {}
        for i,index in ipairs(indices) do
            colours[i] = palette:getColor(index)
        end
        return colours
    end

    local function selectedPaletteIndices()
        local indices = app.range.colors
        if #indices == 0 then
            indices = {app.fgColor.index}
        end
        return indices
    end

    local function updateMappingsFromShades()
        -- need to manually update because shades in sort mode do not fire an event
        for i,mapping in ipairs(mappings) do
            mapping.from = paletteIndicesFromColours(dlg.data["from"..i])
            if mapping.selected > 0 then
                mapping.to[mapping.selected] = paletteIndicesFromColours(dlg.data["to"..i])
            end
        end
    end

    local function updateDialogFromMappings()
        local palette = app.activeSprite.palettes[1]
        for i,mapping in ipairs(mappings) do
            dlg:modify{id="from"..i, colors=coloursFromPaletteIndices(palette, mapping.from)}
            dlg:modify{id="toSlider"..i, max=#mapping.to, value=mapping.selected}
            local colours
            if mapping.selected == 0 then colours = {}
            else colours = coloursFromPaletteIndices(palette, mapping.to[mapping.selected]) end
            dlg:modify{id="to"..i, colors=colours}
        end
    end

    local function appendTable(a, b)
        local offset = #a
        for i,val in ipairs(b) do
            a[offset + i] = val
        end
    end

    local function buildDialog()
        if dlg ~= nil then
            dlg:close()
        end
        local isRebuildDialog = false
        local function rebuildDialog()
            isRebuildDialog = true
            buildDialog()
        end
        dlg = Dialog{title="Recolouriser", onclose=function()
            if not isRebuildDialog then
                updateMappingsFromShades()
            end
            if plugin.preferences.storeOnClose then
                storeUserData()
            end
        end}
        dlg:button{text="Add Mapping", onclick=function()
            updateMappingsFromShades()
            local i = #mappings + 1
            mappings[i] = {from=selectedPaletteIndices(), to={}, selected=0}
            rebuildDialog()
        end}
        dlg:button{id="clearMappings", text="Clear Mappings", enabled=#mappings > 0, onclick=function()
            mappings = {}
            rebuildDialog()
        end}
        dlg:newrow()
        dlg:button{text="Load from User Data", onclick=function()
            loadUserData()
            rebuildDialog()
        end}
        dlg:button{text="Store in User Data", onclick=function()
            updateMappingsFromShades()
            storeUserData()
        end}
        dlg:newrow()
        dlg:check{id="loadOnOpen", text="Load User Data On Open", selected=plugin.preferences["loadOnOpen"], onclick=function() plugin.preferences["loadOnOpen"] = dlg.data["loadOnOpen"] end}
        dlg:check{id="storeOnClose", text="Store User Data On Close", selected=plugin.preferences["storeOnClose"], onclick=function() plugin.preferences["storeOnClose"] = dlg.data["storeOnClose"] end}
        dlg:separator()
        dlg:combobox{id="applyTo", label="Apply To", options={"Pixels", "Palette"}, option=plugin.preferences["applyTo"], onchange=function() plugin.preferences["applyTo"] = dlg.data["applyTo"] end}
        dlg:button{id="applyMappings", text="Apply Mappings", enabled=#mappings > 0, onclick=function()
            updateMappingsFromShades()
            assert(app.activeSprite ~= nil)
            app.transaction(function()
                local palette = app.activeSprite.palettes[1]
                local lut = buildMappingsLut(palette, mappings)
                if dlg.data.applyTo == "Palette" then
                    applyMappingLutToPalette(palette, lut)
                elseif dlg.data.applyTo == "Pixels" then
                    for i,cel in ipairs(app.range.cels) do
                        local work = Image(cel.image)
                        applyMappingLutToPixels(work, cel.position, app.activeSprite.selection, lut)
                        cel.image:drawImage(work)
                    end
                end
                    end)
            app.refresh()
        end}
        -- dlg:button{text="Permutations Sheet", onclick=function() end}
        dlg:separator{text="Mappings"}
        for i,mapping in ipairs(mappings) do
            dlg:separator{text="Mapping "..i}
            dlg:shades{id="from"..i, label="From", mode="sort", colors=mapping.from, onclick=function()
                -- does not fire, need to manually update
                -- mapping.from = paletteIndicesFromColours(dlg.data["from"..i])
            end}
            dlg:button{text="Add Colours", onclick=function()
                appendTable(mapping.from, selectedPaletteIndices())
                dlg:modify{id="from"..i, colors=coloursFromPaletteIndices(app.activeSprite.palettes[1], mapping.from)}
                dlg:modify{id="from"..i, enabled=true}
                dlg:modify{id="fromClearColours"..i, enabled=true}
            end}
            dlg:button{id="fromClearColours"..i, text="Clear Colours", onclick=function()
                mapping.from = {}
                local palette = app.activeSprite.palettes[1]
                dlg:modify{id="from"..i, colors=coloursFromPaletteIndices(palette, mapping.from)}
                dlg:modify{id="from"..i, enabled=false}
                dlg:modify{id="fromClearColours"..i, enabled=false}
            end}
            dlg:newrow()
            dlg:separator()
            dlg:slider{label="To", id="toSlider"..i, min=0, max=#mapping.to, value=0, enabled=false, onchange=function()
                updateMappingsFromShades()
                local palette = app.activeSprite.palettes[1]
                mapping.selected = dlg.data["toSlider"..i]
                local colours
                if mapping.selected == 0 then colours = {}
                else colours = coloursFromPaletteIndices(palette, mapping.to[mapping.selected]) end
                dlg:modify{id="to"..i, colors=colours}
                local validRamp = mapping.selected > 0
                dlg:modify{id="toRemoveRamp"..i, enabled=validRamp}
                dlg:modify{id="toAddColours"..i, enabled=validRamp}
                dlg:modify{id="toClearColours"..i, enabled=(validRamp and #colours > 0)}
            end}
            dlg:button{text="Add Ramp", onclick=function()
                mapping.selected = #mapping.to + 1
                local indices = selectedPaletteIndices()
                table.insert(mapping.to, mapping.selected, indices)
                dlg:modify{id="toSlider"..i, max=#mapping.to, value=mapping.selected}
                local colours = coloursFromPaletteIndices(app.activeSprite.palettes[1], mapping.to[mapping.selected])
                dlg:modify{id="to"..i, colors=colours}
                dlg:modify{id="toSlider"..i, enabled=true}
                dlg:modify{id="toRemoveRamp"..i, enabled=true}
                dlg:modify{id="toClearRamps"..i, enabled=true}
                dlg:modify{id="toAddColours"..i, enabled=true}
                dlg:modify{id="toClearColours"..i, enabled=true}
    end}
            dlg:button{id="toRemoveRamp"..i, text="Remove Ramp", enabled=false, onclick=function()
                if mapping.selected > 0 then
                    table.remove(mapping.to, mapping.selected)
                    dlg:modify{id="toSlider"..i, max=#mapping.to, value=math.max(mapping.selected, #mapping.to)}
                    mapping.selected = dlg.data["toSlider"..i]
                    local palette = app.activeSprite.palettes[1]
                    local colours
                    if mapping.selected == 0 then colours = {}
                    else colours = coloursFromPaletteIndices(palette, mapping.to[mapping.selected]) end
                    dlg:modify{id="to"..i, colors=colours}
                    if #mapping.to == 0 then
                        dlg:modify{id="toSlider"..i, enabled=false}
                        dlg:modify{id="toClearRamps"..i, enabled=false}
                        dlg:modify{id="toAddColours"..i, enabled=false}
                        dlg:modify{id="toClearColours"..i, enabled=false}
                    end
                    dlg:modify{id="toRemoveRamp"..i, enabled=(mapping.selected > 0)}
                end
            end}
            dlg:button{id="toClearRamps"..i, text="Clear Ramps", enabled=false, onclick=function()
                mapping.to = {}
                mapping.selected = 0
                dlg:modify{id="toSlider"..i, max=0, value=0}
                dlg:modify{id="to"..i, colors={}}
                dlg:modify{id="toSlider"..i, enabled=false}
                dlg:modify{id="toRemoveRamp"..i, enabled=false}
                dlg:modify{id="toClearRamps"..i, enabled=false}
                dlg:modify{id="toAddColours"..i, enabled=false}
                dlg:modify{id="toClearColours"..i, enabled=false}
            end}
            dlg:newrow()
            dlg:shades{id="to"..i, mode="sort", colors=mapping.to[mapping.selected], enabled=false, onclick=function()
                -- does not fire, need to manually update
                -- if mapping.selected > 0 then
                --     mapping.to[mapping.selected] = paletteIndicesFromColours(dlg.data["to"..i])
                -- end
            end}
            dlg:button{id="toAddColours"..i, text="Add Colours", enabled=false, onclick=function()
                if mapping.selected > 0 then
                    appendTable(mapping.to[mapping.selected], selectedPaletteIndices())
                    dlg:modify{id="to"..i, colors=coloursFromPaletteIndices(app.activeSprite.palettes[1], mapping.to[mapping.selected])}
                    dlg:modify{id="to"..i, enabled=true}
                    dlg:modify{id="toClearColours"..i, enabled=true}
                end
            end}
            dlg:button{id="toClearColours"..i, text="Clear Colours", enabled=false, onclick=function()
                if mapping.selected > 0 then
                    mapping.to[mapping.selected] = {}
                    local palette = app.activeSprite.palettes[1]
                    dlg:modify{id="to"..i, colors=coloursFromPaletteIndices(palette, mapping.to[mapping.selected])}
                    dlg:modify{id="to"..i, enabled=false}
                    dlg:modify{id="toClearColours"..i, enabled=false}
                end
            end}
            dlg:separator()
            dlg:button{text="Remove Mapping", onclick=function()
                updateMappingsFromShades()
                table.remove(mappings, i)
                rebuildDialog()
            end}
        end
        updateDialogFromMappings()
        dlg:show{wait=false}
    end

    plugin:newCommand{
        id="Recolouriser",
        title="Recolouriser...",
        group="edit_fx",
        onclick=function()
            if plugin.preferences.loadOnOpen then
                loadUserData()
            end
            buildDialog()
        end
    }
end
