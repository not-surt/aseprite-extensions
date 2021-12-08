----------------------------------------------------------------------
-- Recolouriser
----------------------------------------------------------------------

local json = dofile("json.lua")

function init(plugin)
    local defaults = {windowBounds = nil, loadOnOpen = false, storeOnClose = false, applyTo = "Pixels"}
    if plugin.preferences == nil then plugin.preferences = {} end
    for key, value in pairs(defaults) do
        if plugin.preferences[key] == nil then plugin.preferences[key] = value end
    end
    local mappings = {}
    local dlg = nil

    local function buildMappingsLut(mappings)
        local lut = {}
        for i=0,255 do
            lut[i] = i
        end
        for _,mapping in ipairs(mappings) do
            assert(#mapping.from > 0)
            for fromIndex = 1, #mapping.from do
                local pos = (fromIndex - 1) / #mapping.from
                local toIndex = 1 + math.floor(pos * #mapping.to)
                lut[mapping.from[fromIndex]] = mapping.to[toIndex]
            end
        end
        return lut
    end

    local function applyMappingLutToPixels(image, position, selection, lut)
        local palette = app.activeSprite.palettes[1]
        local rgbLut = {}
        if image.colorMode == ColorMode.RGB then
            for i = 0,math.min(255, #palette - 1) do
                if lut[i] ~= nil then
                    rgbLut[palette:getColor(i).rgbaPixel] = palette:getColor(lut[i]).rgbaPixel
                end
            end
        end
        local function applyToPixelIndexed(it)
            it(lut[it()])
        end
        local function applyToPixelRgb(it)
            local fromPixel = it()
            if rgbLut[fromPixel] ~= nil then
                it(rgbLut[fromPixel])
            end
        end
        if selection == nil or selection.isEmpty then
            if image.colorMode == ColorMode.INDEXED then
                for it in image:pixels() do
                    applyToPixelIndexed(it)
                end
            elseif image.colorMode == ColorMode.RGB then
                for it in image:pixels() do
                    applyToPixelRgb(it)
                end
            end
        else
            local bounds = Rectangle(0, 0, image.width, image.height)
            local offsetSelectionBounds = Rectangle(selection.bounds.x - position.x, selection.bounds.y - position.y, selection.bounds.width, selection.bounds.height)
            bounds = bounds:intersect(offsetSelectionBounds)
            if image.colorMode == ColorMode.INDEXED then
                for it in image:pixels() do
                    if selection:contains(it.x + position.x, it.y + position.y) then
                        applyToPixelIndexed(it)
                    end
                end
            elseif image.colorMode == ColorMode.RGB then
                for it in image:pixels() do
                    if selection:contains(it.x + position.x, it.y + position.y) then
                        applyToPixelRgb(it)
                    end
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
            local status,data = pcall(function() return json.decode(app.activeSprite.data) end)
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
        for i, mapping in ipairs(mappings) do
            mapping.from = paletteIndicesFromColours(dlg.data["from" .. i])
            if mapping.selected > 0 then
                mapping.to[mapping.selected] = paletteIndicesFromColours(dlg.data["to" .. i])
            end
        end
    end

    local function updateDialogFromMappingIndex(i)
        local mapping = mappings[i]
        local palette = app.activeSprite.palettes[1]
        local fromHasColours = #mapping.from > 0
        local toHasRamps = #mapping.to > 0
        local toRampValid = mapping.selected > 0
        local toHasColours = toRampValid and #mapping.to[mapping.selected] > 0
        dlg:modify{id = "from" .. i, colors = coloursFromPaletteIndices(palette, mapping.from)}
        dlg:modify{id = "fromSelectColours" .. i, enabled = fromHasColours}
        dlg:modify{id = "fromClearColours" .. i, enabled = fromHasColours}
        dlg:modify{id = "toSlider" .. i, max = #mapping.to, value = mapping.selected, enabled = toHasRamps}
        dlg:modify{id = "toRemoveRamp" .. i, enabled = toRampValid}
        dlg:modify{id = "toClearRamps" .. i, enabled = toHasRamps}
        local colours
        if mapping.selected == 0 then colours = {}
        else colours = coloursFromPaletteIndices(palette, mapping.to[mapping.selected]) end
        dlg:modify{id = "to" .. i, colors = colours, enabled = toRampValid}
        dlg:modify{id = "toAddColours" .. i, enabled = toRampValid}
        dlg:modify{id = "toSelectColours" .. i, enabled = toHasColours}
        dlg:modify{id = "toClearColours" .. i, enabled = toHasColours}
    end

    local function appendTable(a, b)
        local offset = #a
        for i, val in ipairs(b) do
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
        dlg = Dialog{title = "Recolouriser", onclose = function()
            plugin.preferences["windowBounds"] = Rectangle(dlg.bounds)
            if not isRebuildDialog then
                updateMappingsFromShades()
                if plugin.preferences["storeOnClose"] then
                    storeUserData()
                end
            end
        end}
        dlg:button{text = "Add Mapping", onclick = function()
            updateMappingsFromShades()
            local i = #mappings + 1
            mappings[i] = {from = selectedPaletteIndices(), to = {}, selected = 0}
            rebuildDialog()
        end}
        dlg:button{id = "clearMappings", text = "Clear Mappings", enabled = #mappings > 0, onclick = function()
            mappings = {}
            rebuildDialog()
        end}
        dlg:newrow()
        dlg:button{text = "Load from User Data", onclick = function()
            loadUserData()
            rebuildDialog()
        end}
        dlg:button{text = "Store in User Data", onclick = function()
            updateMappingsFromShades()
            storeUserData()
        end}
        dlg:newrow()
        dlg:check{id = "loadOnOpen", text = "Load User Data On Open", selected = plugin.preferences["loadOnOpen"], onclick = function() plugin.preferences["loadOnOpen"] = dlg.data["loadOnOpen"] end}
        dlg:check{id = "storeOnClose", text = "Store User Data On Close", selected = plugin.preferences["storeOnClose"], onclick = function() plugin.preferences["storeOnClose"] = dlg.data["storeOnClose"] end}
        dlg:separator()
        dlg:combobox{id = "applyTo", label = "Apply To", options = {"Pixels", "Palette"}, option = plugin.preferences["applyTo"], onchange = function() plugin.preferences["applyTo"] = dlg.data["applyTo"] end}
        dlg:button{id = "applyMappings", text = "Apply Mappings", enabled = #mappings > 0, onclick = function()
            updateMappingsFromShades()
            assert(app.activeSprite ~= nil)
            app.transaction(function()
                local palette = app.activeSprite.palettes[1]
                local lutMappings = {}
                local i = 1
                for _, mapping in ipairs(mappings) do
                    if mapping.selected > 0 then
                        lutMappings[i] = {from=mapping.from, to=mapping.to[mapping.selected]}
                        i = i + 1
                    end
                end
                local lut = buildMappingsLut(lutMappings)
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
            for i, mapping in ipairs(mappings) do
                updateDialogFromMappingIndex(i)
            end
        end}
        -- dlg:button{text = "Permutations Sheet", onclick = function() end}
        dlg:separator{text = "Mappings"}
        for i, mapping in ipairs(mappings) do
            dlg:separator{text = "Mapping " .. i}
            dlg:shades{id = "from" .. i, label="From", mode="sort", colors=mapping.from, onclick = function()
                -- does not fire, need to manually update
                -- mapping.from = paletteIndicesFromColours(dlg.data["from" .. i])
            end}
            dlg:button{text = "Add Colours", onclick = function()
                appendTable(mapping.from, selectedPaletteIndices())
                updateDialogFromMappingIndex(i)
            end}
            dlg:button{id = "fromSelectColours" .. i, text = "Select Colours", onclick = function()
                app.range.colors = mapping.from
            end}
            dlg:button{id = "fromClearColours" .. i, text = "Clear Colours", onclick = function()
                mapping.from = {}
                updateDialogFromMappingIndex(i)
            end}
            dlg:newrow()
            dlg:separator()
            dlg:slider{label="To", id = "toSlider" .. i, min = 0, max = #mapping.to, value = 0, onchange = function()
                updateMappingsFromShades()
                mapping.selected = dlg.data["toSlider" .. i]
                updateDialogFromMappingIndex(i)
            end}
            dlg:button{text = "Add Ramp", onclick = function()
                mapping.selected = #mapping.to + 1
                local indices = selectedPaletteIndices()
                table.insert(mapping.to, mapping.selected, indices)
                updateDialogFromMappingIndex(i)
            end}
            dlg:button{id = "toRemoveRamp" .. i, text = "Remove Ramp", onclick = function()
                table.remove(mapping.to, mapping.selected)
                mapping.selected = math.min(mapping.selected, #mapping.to)
                updateDialogFromMappingIndex(i)
            end}
            dlg:button{id = "toClearRamps" .. i, text = "Clear Ramps", onclick = function()
                mapping.to = {}
                mapping.selected = 0
                updateDialogFromMappingIndex(i)
            end}
            dlg:newrow()
            dlg:shades{id = "to" .. i, mode="sort", colors=mapping.to[mapping.selected], onclick = function()
                -- does not fire, need to manually update
                -- if mapping.selected > 0 then
                --     mapping.to[mapping.selected] = paletteIndicesFromColours(dlg.data["to" .. i])
                -- end
            end}
            dlg:button{id = "toAddColours" .. i, text = "Add Colours", onclick = function()
                appendTable(mapping.to[mapping.selected], selectedPaletteIndices())
                updateDialogFromMappingIndex(i)
            end}
            dlg:button{id = "toSelectColours" .. i, text = "Select Colours", onclick = function()
                app.range.colors = mapping.to[mapping.selected]
            end}
            dlg:button{id = "toClearColours" .. i, text = "Clear Colours", onclick = function()
                mapping.to[mapping.selected] = {}
                updateDialogFromMappingIndex(i)
            end}
            dlg:separator()
            dlg:button{text = "Remove Mapping", onclick = function()
                updateMappingsFromShades()
                table.remove(mappings, i)
                rebuildDialog()
            end}
        end
        for i,mapping in ipairs(mappings) do
            updateDialogFromMappingIndex(i)
        end
        dlg:show{wait = false}
        if plugin.preferences["windowBounds"] ~= nil then
            -- seems dialog bounds is buggy
            -- dlg.bounds = Rectangle(plugin.preferences["windowBounds"])
        end
    end

    plugin:newCommand{
        id = "Recolouriser",
        title="Recolouriser...",
        group="edit_fx",
        onclick = function()
            if plugin.preferences["loadOnOpen"] then
                loadUserData()
            end
            buildDialog()
        end
    }
end
