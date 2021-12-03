----------------------------------------------------------------------
-- Recombinator
----------------------------------------------------------------------

function init(plugin)
    math.randomseed(os.time())
    
    local defaults = {sheetRows=8, sheetColumns=8, wrapLayer=0, recolour=false, useEmpty=false, flatten=false}
    if plugin.preferences == nil then plugin.preferences = {} end
    for key, value in pairs(defaults) do
        if plugin.preferences[key] == nil then plugin.preferences[key] = value end
    end

    local function getSize(sourceSprite)
        local size = Size(0, 0)
        for i, layer in ipairs(sourceSprite.layers) do
            local testSize = Size(0, 0)
            if layer.isTilemap then
                testSize = layer.tileset.grid.tileSize
            end
            size.width = math.max(size.width, testSize.width)
            size.height = math.max(size.height, testSize.height)
        end
        return size
    end

    local function rebuildSprite(sourceSprite, destSprite, size)
        local oldLayers = {table.unpack(destSprite.layers)}
        for i, frame in ipairs(destSprite.frames) do
            destSprite:deleteFrame(frame)
        end
        if destSprite.width ~= size.width or destSprite.height ~= size.height then
            destSprite:resize(size)
        end
        for i, cel in ipairs(destSprite.cels) do
            destSprite:deleteCel(cel)
        end
        destSprite:setPalette(sourceSprite.palettes[1])
        local destFrameNumber = 0
        -- local destFrame = destSprite:newEmptyFrame(destFrameNumber)
        local destFrame = destSprite.frames[destFrameNumber]
        for i, sourceLayer in ipairs(sourceSprite.layers) do
            local destLayer = destSprite:newLayer()
            destLayer.name = sourceLayer.name
            local destCel = destSprite:newCel(destLayer, destFrame)
        end
        for i, layer in ipairs(oldLayers) do
            destSprite:deleteLayer(layer)
        end
    end

    local function drawCombination(sourceSprite, destSprite, sequence, indices, position)
        for i = 1,#sequence do
            local layer = sourceSprite.layers[sequence[i]]
            assert(layer.isTilemap)
            local tileIndex = indices[i]
            assert(tileIndex < #layer.tileset)
            local sourceImage = layer.tileset:getTile(tileIndex)
            if sourceImage ~= nil then
                -- drawImage buggy if cel.image not cloned
                local destImage = Image(destSprite.layers[i]:cel(1).image)
                -- local destImage = destSprite.layers[i]:cel(1).image
                destImage:drawImage(sourceImage, position)
                destSprite.layers[i]:cel(1).image = destImage
            end
        end
    end

    local function layerTileChanged(dlg, sourceSprite, destSprite, useEmpty, flatten)
        app.transaction(function()
            local size = getSize(sourceSprite)
            rebuildSprite(sourceSprite, destSprite, size)
            local sequence = {}
            local sequenceIndex = 1
            local indices = {}
            for i, layer in ipairs(sourceSprite.layers) do
                if layer.isTilemap then
                    sequence[sequenceIndex] = i
                    indices[sequenceIndex] = dlg.data["layerSlider"..i]
                    sequenceIndex = sequenceIndex + 1
                end
            end
            drawCombination(sourceSprite, destSprite, sequence, indices, Point(0, 0))
            if flatten then destSprite:flatten() end
        end)
        app.refresh()
    end

    local function drawRandomSheet(sourceSprite, destSprite, gridSize, useEmpty, flatten)
        app.transaction(function()
            local tileSize = getSize(sourceSprite)
            local imageSize = Size(tileSize.width * gridSize.width, tileSize.height * gridSize.height)
            rebuildSprite(sourceSprite, destSprite, imageSize)
            local startIndex
            if useEmpty then startIndex = 0
            else startIndex = 1
            end
            for y = 0,gridSize.height-1 do
                for x = 0,gridSize.width-1 do
                    local sequence = {}
                    local sequenceIndex = 1
                    local indices = {}
                    for i, layer in ipairs(sourceSprite.layers) do
                        if layer.isTilemap and startIndex < #layer.tileset then
                            sequence[sequenceIndex] = i
                            indices[sequenceIndex] = math.random(startIndex, #layer.tileset - 1)
                            sequenceIndex = sequenceIndex + 1
                        end
                    end
                    drawCombination(sourceSprite, destSprite, sequence, indices, Point(x * tileSize.width, y * tileSize.height))
                end
            end
            if flatten then destSprite:flatten() end
        end)
        app.refresh()
    end

    local function getPermutationSheet(sourceSprite, destSprite, useEmpty, wrapLayer, flatten)
        app.transaction(function()
            local startIndex
            if useEmpty then startIndex = 0
            else startIndex = 1
            end
            local sequence = {}
            local sequenceIndex = 1
            local dimensionSizes = {}
            local dimensionSizeProduct = 1
            local wrapWidth
            for i, layer in ipairs(sourceSprite.layers) do
                if layer.isTilemap and startIndex < #layer.tileset then
                    sequence[sequenceIndex] = i
                    dimensionSizes[sequenceIndex] = #layer.tileset - startIndex
                    dimensionSizeProduct = dimensionSizeProduct * dimensionSizes[sequenceIndex]
                    if i <= wrapLayer then
                        wrapWidth = dimensionSizeProduct
                    end
                    sequenceIndex = sequenceIndex + 1
                end
            end
            if wrapWidth == nil then
                wrapWidth = math.ceil(math.sqrt(dimensionSizeProduct))
            end
            local gridSizeX = math.min(wrapWidth, dimensionSizeProduct)
            local tileSize = getSize(sourceSprite)
            local imageSize = Size(tileSize.width * gridSizeX, tileSize.height *  math.ceil(dimensionSizeProduct / gridSizeX))
            rebuildSprite(sourceSprite, destSprite, imageSize)
            local indices = {}
            for i = 1,#sequence do
                indices[i] = 0
            end
            local flatIndex = 0
            local x = 0
            local y = 0
            while flatIndex < dimensionSizeProduct do
                local offsetIndices = {}
                for i = 1,#indices do
                    offsetIndices[i] = indices[i] + startIndex
                end
                drawCombination(sourceSprite, destSprite, sequence, offsetIndices, Point(x * tileSize.width, y * tileSize.height))
                indices[1] = indices[1] + 1
                for i = 1,#indices do
                    local next = i + 1
                    if next <= #indices then
                        indices[next] = indices[next] + (indices[i] // dimensionSizes[i])
                    end
                    indices[i] = indices[i] % dimensionSizes[i]
                end
                flatIndex = flatIndex + 1
                x = x + 1
                y = y + x // wrapWidth
                x = x % wrapWidth
            end
            if flatten then destSprite:flatten() end
        end)
        app.refresh()
    end

    local function dlgShow()
        local sourceSprite = app.activeSprite
        local destSprite
        if sourceSprite then
            local size = {width=0, height=0}
            for i, layer in ipairs(sourceSprite.layers) do
                local testSize = {width=0, height=0}
                if layer.isTilemap and #layer.tileset > 1 then
                    testSize = layer.tileset.grid.tileSize
                end
                size.width = math.max(size.width, testSize.width)
                size.height = math.max(size.height, testSize.height)
            end
            if size.width > 0 and size.height > 0 then
                local spec = {colorMode=sourceSprite.colorMode, width=size.width, height=size.height, transparentColor=0}
                destSprite = Sprite(spec)
                local dlg = Dialog("Recombinator")
                dlg:newrow{always=false}
                dlg:separator{text="Custom Single"}
                local doUpdate = function() layerTileChanged(dlg, sourceSprite, destSprite, dlg.data.useEmpty, dlg.data.flatten) end
                local randomizeLayer = function(layer)
                    assert(layer.isTilemap)
                    local startIndex
                    if dlg.data.useEmpty then startIndex = 0
                    else startIndex = 1
                    end
                    if startIndex < #layer.tileset then
                        return math.random(startIndex, #layer.tileset - 1)
                    else
                        return 0
                    end
                end
                for i, layer in ipairs(sourceSprite.layers) do
                    local layerSize
                    if layer.isTilemap then
                        local label = i .. ". " .. layer.name
                        dlg:slider{id="layerSlider"..i, label=label, min=0, max=#layer.tileset - 1, onchange=doUpdate}
                        dlg:button{text="Randomize", onclick=function()
                            dlg:modify{id="layerSlider"..i, value=randomizeLayer(layer)}
                            doUpdate()
                        end}
                        dlg:separator()
                    end
                end
                dlg:newrow()
                dlg:button{text="Randomize All", onclick=function()
                    for i, layer in ipairs(sourceSprite.layers) do
                        if layer.isTilemap then
                            dlg:modify{id="layerSlider"..i, value=randomizeLayer(layer)}
                        end
                    end
                    doUpdate()
                end}
                dlg:separator{text="Random Sheet"}
                dlg:number{id="sheetRows", label="Rows", decimals=0, text=tostring(plugin.preferences["sheetRows"]), onchange=function() plugin.preferences["sheetRows"] = dlg.data.sheetRows end}
                dlg:number{id="sheetColumns", label="Columns", decimals=0, text=tostring(plugin.preferences["sheetColumns"]), onchange=function() plugin.preferences["sheetColumns"] = dlg.data.sheetColumns end}
                dlg:button{text="Fill sheet", onclick=function() drawRandomSheet(sourceSprite, destSprite, Size(dlg.data.sheetColumns, dlg.data.sheetRows), dlg.data.useEmpty, dlg.data.flatten) end}
                dlg:separator{text="Permutation Sheet"}
                dlg:label{text="WARNING: this can be very slow!"}
                dlg:number{id="wrapLayer", label="Wrap After Layer", decimals=0, text=tostring(plugin.preferences["wrapLayer"]), onchange=function() plugin.preferences["wrapLayer"] = dlg.data.wrapLayer end}
                dlg:button{text="Fill sheet", onclick=function() getPermutationSheet(sourceSprite, destSprite, dlg.data.useEmpty, dlg.data.wrapLayer, dlg.data.flatten) end}
                dlg:separator{text="Options"}
                -- dlg:check{id="recolour", text="Recolour", selected=plugin.preferences["recolour"], onclick=function() plugin.preferences["recolour"] = dlg.data.recolour end}
                dlg:check{id="useEmpty", text="Use Empty Tiles", selected=plugin.preferences["useEmpty"], onclick=function() plugin.preferences["useEmpty"] = dlg.data.useEmpty end}
                dlg:check{id="flatten", text="Flatten", selected=plugin.preferences["flatten"], onclick=function() plugin.preferences["flatten"] = dlg.data.flatten end}
                dlg:show{wait=false}
                layerTileChanged(dlg, sourceSprite, destSprite, false)
            end
        end
    end

    plugin:newCommand{
        id="Recombinator",
        title="Recombinator...",
        group="edit_fx",
        onclick=dlgShow
    }
end

function exit(plugin)
    plugin.preferences.bounds = nil
end
