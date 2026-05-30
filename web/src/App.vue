<script setup>
  import { useInventoryStore } from './stores/inventory'
  import { useSettingsStore } from './stores/settings'
  import { postNUI, securePostNUI } from './utils/nui'
  import { ref, computed, onMounted, onUnmounted, watch } from 'vue'
  const inventory = useInventoryStore()
  const settings = useSettingsStore()

  var fallbackImage = new URL('./assets/unknown-image.png', import.meta.url).href
  var popSound = new Audio(new URL('./assets/ui-pop.mp3', import.meta.url).href)
  popSound.volume = 0.08

  function playPopSound() {
    if (!settings.soundEffects) return
    popSound.currentTime = 0
    popSound.play().catch(function() {})
  }

  function getItemImage(name) {
    return '../items/' + name + '.png'
  }

  function onImgError(e) {
    e.target.src = fallbackImage
  }

  function getAsset(filename) {
    return new URL(`./assets/${filename}`, import.meta.url).href
  }

  function uiText(key, fallback) {
    var ui = inventory.LANGUAGE && inventory.LANGUAGE.ui ? inventory.LANGUAGE.ui : {}
    return ui[key] || fallback
  }

  // Replace successive %s tokens in `template` with the rest of the arguments.
  // Used to insert numbers/labels into translated strings (server-side Lua uses
  // string.format with %s for the same purpose).
  function formatTemplate(template, ...args) {
    var i = 0
    return String(template).replace(/%s/g, function() {
      var v = args[i++]
      return v == null ? '' : String(v)
    })
  }

  function slotCount(item) {
    if (item.type === 'item_weapon') return '1x'
    if (item.type === 'item_money' || item.type === 'item_gold') return formatCurrencyAmount(item.count)
    return Math.floor(Number(item.count) || 0) + 'x'
  }

  function slotWeight(item) {
    var w = item.weight || 0
    var c = item.type === 'item_weapon' ? 1 : item.count
    return (w * c).toFixed(2)
  }

  function formatCurrencyAmount(value) {
    return (Number(value) || 0).toFixed(2)
  }

  function isCurrencyItem(item) {
    return item && (item.type === 'item_money' || item.type === 'item_gold')
  }

  function isEquippedWeapon(item) {
    return item && item.type === 'item_weapon' && (item.used || item.used2)
  }

  function getTransferAmount(item) {
    var amount = Number(transferAmount.value)
    var max = Number(item.count) || 0
    if (!amount || amount <= 0) amount = max
    if (amount > max) amount = max
    if (isCurrencyItem(item)) return Math.floor(amount * 100) / 100
    return Math.max(1, Math.floor(amount))
  }

  function normalizedMetadata(item) {
    var metadata = item && item.metadata ? item.metadata : {}
    var keys = Object.keys(metadata).sort()
    var normalized = {}
    for (var i = 0; i < keys.length; i++) normalized[keys[i]] = metadata[keys[i]]
    return JSON.stringify(normalized)
  }

  function canStackItems(a, b) {
    if (!a || !b) return false
    if (a.name !== b.name || a.type === 'item_weapon' || b.type === 'item_weapon') return false
    if (normalizedMetadata(a) !== normalizedMetadata(b)) return false
    var aMax = Number(a.maxDegradation) || 0
    var bMax = Number(b.maxDegradation) || 0
    if (aMax !== bMax) return false
    if (aMax > 0) return Number(a.percentage) === Number(b.percentage) && Number(a.degradation) === Number(b.degradation)
    return true
  }

  const contextMenu = ref({ show: false, x: 0, y: 0, item: null })

  // Search
  const searchQuery = ref('')
  const searchMatchSlots = ref([])
  var searchBlinkInterval = null
  var searchBlinkOn = ref(true)

  function onSearchInput() {
    var q = searchQuery.value.toLowerCase().trim()
    if (!q) {
      searchMatchSlots.value = []
      if (searchBlinkInterval) { clearInterval(searchBlinkInterval); searchBlinkInterval = null }
      searchBlinkOn.value = true
      return
    }
    var matches = []
    var totalSlots = inventory.LuaConfig.PlayerInventorySlots || 25
    for (var i = 1; i <= totalSlots; i++) {
      var item = inventory.getItemAtSlot(i)
      if (item && item.label && item.label.toLowerCase().indexOf(q) !== -1) {
        matches.push(i)
      }
    }
    searchMatchSlots.value = matches

    // Blink effect
    if (searchBlinkInterval) clearInterval(searchBlinkInterval)
    searchBlinkOn.value = true
    searchBlinkInterval = setInterval(function() {
      searchBlinkOn.value = !searchBlinkOn.value
    }, 400)

    // Scroll to first match
    if (matches.length > 0) {
      var slotEl = document.getElementById('player-slot-' + matches[0])
      if (slotEl) slotEl.scrollIntoView({ behavior: 'smooth', block: 'center' })
    }
  }

  function isSearchMatch(slotIndex) {
    return searchMatchSlots.value.indexOf(slotIndex) !== -1
  }

  // Ammo give prompt
  const ammoPrompt = ref({ show: false, ammoType: '', ammoLabel: '', amount: 1 })

  function getAmmoList() {
    var list = []
    var ammo = inventory.allplayerammo
    var labels = inventory.ammolabels
    for (var key in ammo) {
      if (ammo[key] > 0) {
        list.push({ key: key, label: labels[key] || key, count: ammo[key] })
      }
    }
    return list
  }

  function onAmmoClick(ammoType, ammoLabel) {
    contextMenu.value.show = false
    ammoPrompt.value = { show: true, ammoType: ammoType, ammoLabel: ammoLabel, amount: 1 }
  }

  function onAmmoPromptConfirm() {
    var amount = parseInt(ammoPrompt.value.amount)
    if (!amount || amount <= 0) return
    ammoPrompt.value.show = false
    postNUI('GetNearPlayers', { type: 'item_ammo', what: 'give', item: ammoPrompt.value.ammoType, count: amount }).catch(function(){})
  }

  function onPlayerSelect(playerId) {
    inventory.showPlayerSelect = false
    var data = inventory.pendingGiveData
    if (!data) return
    securePostNUI('GiveItem', { player: playerId, data: data }).catch(function(){})
    inventory.pendingGiveData = null
  }

  function onPlayerSelectClose() {
    inventory.showPlayerSelect = false
    inventory.pendingGiveData = null
  }

  function onSlotRightClick(e, slotIndex) {
    const item = inventory.getItemAtSlot(slotIndex)
    if (!item) return
    e.preventDefault()
    contextMenu.value = { show: true, x: e.clientX, y: e.clientY, item }
  }

  function onSlotDoubleClick(slotIndex) {
    if (dragTimer) { clearTimeout(dragTimer); dragTimer = null }
    dragStartPos = null
    dragFrom.value = null
    dragSource.value = null
    dragGhost.value.show = false
    var item = inventory.getItemAtSlot(slotIndex)
    if (!item) return
    if (isEquippedWeapon(item)) return
    // Quick transfer: when a transferable second inventory is open, double-click
    // moves the item across instead of using it (Main ↔ Stash/Horse/Bank/etc).
    if (isQuickTransferTarget()) {
      quickTransferFromPlayer(item)
      return
    }
    if (!settings.doubleClickToUse) return
    if (item.type === 'item_money' || item.type === 'item_gold') return
    if (item.type === 'item_weapon' && (item.used || item.used2)) {
      postNUI('UnequipWeapon', { item: item.name, id: item.id })
    } else {
      var useAmt = getTransferAmount(item)
      postNUI('UseItem', { item: item.name, type: item.type, hash: item.hash, amount: useAmt, id: item.id })
    }
  }

  function onSecondDoubleClick(slotIndex) {
    if (dragTimer) { clearTimeout(dragTimer); dragTimer = null }
    dragStartPos = null
    dragFrom.value = null
    dragSource.value = null
    dragGhost.value.show = false
    if (!isQuickTransferTarget()) return
    var item = inventory.getSecondItemAtSlot(slotIndex)
    if (!item) return
    quickTransferFromSecond(item)
  }

  const dragFrom = ref(null)
  const dragSource = ref(null)
  const dragGhost = ref({ show: false, x: 0, y: 0, item: null })
  const transferAmount = ref(0)
  // When the drag is started with Shift held, the drop splits the stack in half
  // (or as close to half as possible). Reset on every mouseup.
  const dragShift = ref(false)
  var dragTimer = null
  var dragStartPos = null

  // True when the right-hand panel is a container the player can move items to.
  // Drop and clothing are not real "transfer" targets, neither are shop/craft.
  function isQuickTransferTarget() {
    var t = inventory.invType
    return t === 'custom' || t === 'horse' || t === 'cart' || t === 'house'
        || t === 'hideout' || t === 'bank' || t === 'clan' || t === 'Container'
        || t === 'steal'
  }

  // Find a target slot in `slotCount` slots that either already holds a
  // stackable copy of `item`, or — failing that — is empty. Returns null if
  // there is nowhere to put it.
  function findTransferTarget(item, getAt, slotCount) {
    if (!item || !slotCount) return null
    for (var i = 1; i <= slotCount; i++) {
      var existing = getAt(i)
      if (existing && canStackItems(item, existing)) return i
    }
    for (var i = 1; i <= slotCount; i++) {
      if (!getAt(i)) return i
    }
    return null
  }

  function totalPlayerSlots() {
    return inventory.LuaConfig.PlayerInventorySlots || 25
  }

  function totalSecondSlots() { return 35 }

  function totalDropSlots() {
    var d = inventory.LuaConfig.DropInventory
    return (d && d.Slots) || 35
  }

  // Returns the amount this drag should transfer. Shift-drag halves the stack.
  function getDragAmount(item) {
    if (!item) return 0
    if (dragShift.value) {
      var max = Number(item.count) || 0
      if (max <= 0) return 0
      if (isCurrencyItem(item)) return Math.floor((max / 2) * 100) / 100
      // Math.max(1) so a stack of 1 still moves something — otherwise Shift+drag
      // on a single item would silently no-op.
      return Math.max(1, Math.floor(max / 2))
    }
    return getTransferAmount(item)
  }

  // Move the entire stack of `item` from the player inventory to whatever the
  // open second panel is. Used by Ctrl+Click and Double-Click.
  function quickTransferFromPlayer(item) {
    if (!item) return
    if (isEquippedWeapon(item)) return
    if (item.locked && !isCurrencyItem(item)) return

    var amount = Math.max(0, Number(item.count) || 0)
    if (amount <= 0) return

    // Main panel with drop visible → drop the stack.
    if (inventory.invType === 'main' && inventory.secondInventoryType === 'drop' && inventory.nearbyDropId) {
      var dropConfig = inventory.LuaConfig.DropInventory
      if (dropConfig && dropConfig.MaxWeight > 0) {
        var itemWeight = (item.weight || 0) * amount
        if (inventory.dropCurrentWeight + itemWeight > dropConfig.MaxWeight) return
      }
      var targetSlot = findTransferTarget(item, inventory.getDropZoneItemAtSlot, totalDropSlots())
      if (targetSlot == null) return
      securePostNUI('DropItem', {
        item: item.name, id: item.id, number: amount, type: item.type,
        metadata: item.metadata, degradation: item.degradation, targetSlot: targetSlot,
      })
      inventory.rememberAmount(item.name, amount)
      playPopSound()
      return
    }

    // Container side panel open: use the matching MoveTo action.
    var mapping = moveToActions[inventory.invType]
    if (!mapping) return
    var targetSlot = findTransferTarget(item, inventory.getSecondItemAtSlot, totalSecondSlots())
    if (targetSlot == null) return
    var payload = { item: item, type: item.type, number: amount, targetSlot: targetSlot }
    payload[mapping.key] = mapping.getId()
    postNUI(mapping.action, payload)
    inventory.rememberAmount(item.name, amount)
    playPopSound()
  }

  // Move the entire stack of `item` from the second panel to the player inv.
  function quickTransferFromSecond(item) {
    if (!item) return
    var amount = Math.max(0, Number(item.count) || 0)
    if (amount <= 0) return
    var mapping = takeFromActions[inventory.invType]
    if (!mapping) return
    var targetSlot = findTransferTarget(item, inventory.getItemAtSlot, totalPlayerSlots())
    if (targetSlot == null) return
    var payload = { item: item, type: item.type, number: amount, targetSlot: targetSlot }
    payload[mapping.key] = mapping.getId()
    postNUI(mapping.action, payload)
    inventory.rememberAmount(item.name, amount)
    playPopSound()
  }

  // Pickup the entire stack of a drop-zone item into the player inventory.
  function quickPickupFromDrop(item, fromSlot) {
    if (!item || !inventory.nearbyDropId) return
    var amount = Math.max(0, Number(item.amount) || 0)
    if (amount <= 0) return
    var targetSlot = findTransferTarget(
      Object.assign({}, item, { count: amount }),
      inventory.getItemAtSlot,
      totalPlayerSlots()
    )
    if (targetSlot == null) return
    postNUI('PickupFromDrop', {
      dropId: inventory.nearbyDropId,
      fromSlot: fromSlot,
      targetSlot: targetSlot,
      amount: amount,
      name: item.name,
      type: item.type,
      isMoney: item.isMoney || false,
      isGold: item.isGold || false,
      uuid: item.uuid,
      uids: item.uids,
    })
    inventory.rememberAmount(item.name, amount)
    playPopSound()
  }

  // Reset transferAmount when inventory opens/closes
  watch(() => inventory.isVisible, function() {
    transferAmount.value = 0
  })

  function onSlotMouseDown(e, slotIndex) {
    var item = inventory.getItemAtSlot(slotIndex)
    if (!item) return
    if (e.button !== 0) return
    // Ctrl+Click: instant full-stack transfer to whatever the second panel is.
    if (e.ctrlKey) {
      e.preventDefault()
      quickTransferFromPlayer(item)
      return
    }
    e.preventDefault()
    dragShift.value = !!e.shiftKey
    // Pre-fill the amount input with whatever was last used for this item.
    var recalled = inventory.recallAmount(item.name)
    if (recalled != null) transferAmount.value = recalled
    dragStartPos = { x: e.clientX, y: e.clientY, slot: slotIndex, item: item, source: 'player' }
    dragTimer = setTimeout(function() {
      if (dragStartPos) {
        dragFrom.value = dragStartPos.slot
        dragSource.value = dragStartPos.source
        dragGhost.value = { show: true, x: dragStartPos.x, y: dragStartPos.y, item: dragStartPos.item }
        dragStartPos = null
      }
    }, 150)
  }

  function onMouseMove(e) {
    if (!dragGhost.value.show) return
    dragGhost.value.x = e.clientX
    dragGhost.value.y = e.clientY
  }

  function onSlotMouseUp(toSlot) {
    if (dragFrom.value === null) return
    if (dragSource.value === 'dropzone') {
      var dropItem = inventory.getDropZoneItemAtSlot(dragFrom.value)
      if (dropItem) {
        // Block if target slot has different item
        var targetPlayerItem = inventory.getItemAtSlot(toSlot)
        if (targetPlayerItem && !canStackItems(dropItem, targetPlayerItem)) { dragFrom.value = null; dragSource.value = null; dragGhost.value.show = false; return }

        var amount = getDragAmount(Object.assign({}, dropItem, { count: dropItem.amount }))

        postNUI('PickupFromDrop', {
          dropId: inventory.nearbyDropId,
          fromSlot: dragFrom.value,
          targetSlot: toSlot,
          amount: amount,
          name: dropItem.name,
          type: dropItem.type,
          isMoney: dropItem.isMoney || false,
          isGold: dropItem.isGold || false,
          uuid: dropItem.uuid,
          uids: dropItem.uids,
        })
        inventory.rememberAmount(dropItem.name, amount)
        playPopSound()
      }
      dragFrom.value = null
      dragSource.value = null
      dragGhost.value.show = false
      return
    }
    // Second inventory → Player (TakeFrom)
    if (dragSource.value === 'second') {
      var secItem = inventory.getSecondItemAtSlot(dragFrom.value)
      if (secItem) {
        var targetPlayerItem2 = inventory.getItemAtSlot(toSlot)
        // Steal: swap when different items
        if (inventory.invType === 'steal' && targetPlayerItem2 && !canStackItems(secItem, targetPlayerItem2)) {
          postNUI('StealSwapBetween', { playerSlot: toSlot, stealSlot: dragFrom.value })
          playPopSound()
        } else if (targetPlayerItem2 && !canStackItems(secItem, targetPlayerItem2)) {
          dragFrom.value = null; dragSource.value = null; dragGhost.value.show = false; return
        } else {
          var type = inventory.invType
          var mapping = takeFromActions[type]
          if (mapping) {
            var amount = getDragAmount(secItem)
            var payload = { item: secItem, type: secItem.type, number: amount, targetSlot: toSlot }
            payload[mapping.key] = mapping.getId()
            postNUI(mapping.action, payload)
            inventory.rememberAmount(secItem.name, amount)
            playPopSound()
          }
        }
      }
      dragFrom.value = null
      dragSource.value = null
      dragGhost.value.show = false
      return
    }
    // Craft → Player
    if (dragSource.value === 'craft') {
      var craftItem = inventory.getCraftItemAtSlot(dragFrom.value)
      if (craftItem) {
        var targetPlayerItem3 = inventory.getItemAtSlot(toSlot)
        if (targetPlayerItem3 && !canStackItems(craftItem, targetPlayerItem3)) { dragFrom.value = null; dragSource.value = null; dragGhost.value.show = false; return }
        var amount = getTransferAmount(craftItem)
        postNUI('CraftRemoveItem', { fromSlot: dragFrom.value, amount: amount, targetSlot: toSlot })
        playPopSound()
      }
      dragFrom.value = null
      dragSource.value = null
      dragGhost.value.show = false
      return
    }
    // Shop → Player (buy). Quantity from the amount input; 0/blank => 1.
    if (dragSource.value === 'shop') {
      var shopItem = shopItemAt(dragFrom.value)
      if (shopItem && inventory.shopId && shopItem.buy_price > 0) {
        var qty = getShopBuyQty()
        postNUI('ShopBuy', { shopId: inventory.shopId, item: shopItem.name, qty: qty })
        playPopSound()
      }
      dragFrom.value = null
      dragSource.value = null
      dragGhost.value.show = false
      return
    }
    if (dragFrom.value !== toSlot) {
      var fromItem = inventory.getItemAtSlot(dragFrom.value)
      var amount = fromItem ? getDragAmount(fromItem) : 0
      inventory.swapSlots(dragFrom.value, toSlot, amount > 0 ? amount : null)
      if (fromItem && amount > 0) inventory.rememberAmount(fromItem.name, amount)
      playPopSound()
    }
    dragFrom.value = null
    dragSource.value = null
    dragGhost.value.show = false
  }

  function onDropZoneMouseDown(e, slotIndex) {
    var item = inventory.getDropZoneItemAtSlot(slotIndex)
    if (!item) return
    if (e.button !== 0) return
    if (e.ctrlKey) {
      e.preventDefault()
      quickPickupFromDrop(item, slotIndex)
      return
    }
    e.preventDefault()
    dragShift.value = !!e.shiftKey
    dragStartPos = { x: e.clientX, y: e.clientY, slot: slotIndex, item: item, source: 'dropzone' }
    dragTimer = setTimeout(function() {
      if (dragStartPos) {
        dragFrom.value = dragStartPos.slot
        dragSource.value = dragStartPos.source
        dragGhost.value = { show: true, x: dragStartPos.x, y: dragStartPos.y, item: dragStartPos.item }
        dragStartPos = null
      }
    }, 150)
  }

  function onDropSlotMouseUp(toSlot) {
    if (dragFrom.value === null) return
    if (dragSource.value === 'player') {
      var item = inventory.getItemAtSlot(dragFrom.value)
      if (item) {
        if (isEquippedWeapon(item)) { dragFrom.value = null; dragSource.value = null; dragGhost.value.show = false; return }
        if (isCurrencyItem(item) && (Number(item.count) || 0) <= 0) { dragFrom.value = null; dragSource.value = null; dragGhost.value.show = false; return }
        // Block if target slot has different item
        var targetDropItem = inventory.getDropZoneItemAtSlot(toSlot)
        if (targetDropItem && !canStackItems(item, targetDropItem)) { dragFrom.value = null; dragSource.value = null; dragGhost.value.show = false; return }

        var amount = getDragAmount(item)
        if (isCurrencyItem(item) && amount <= 0) { dragFrom.value = null; dragSource.value = null; dragGhost.value.show = false; return }

        // Check drop weight limit
        var dropConfig = inventory.LuaConfig.DropInventory
        if (dropConfig && dropConfig.MaxWeight > 0) {
          var itemWeight = (item.weight || 0) * amount
          if (inventory.dropCurrentWeight + itemWeight > dropConfig.MaxWeight) return
        }

        securePostNUI('DropItem', {
          item: item.name,
          id: item.id,
          number: amount,
          type: item.type,
          metadata: item.metadata,
          degradation: item.degradation,
          targetSlot: toSlot,
        })
        inventory.rememberAmount(item.name, amount)
        playPopSound()
      }
    } else if (dragSource.value === 'dropzone' && dragFrom.value !== toSlot) {
      var fromItem = inventory.getDropZoneItemAtSlot(dragFrom.value)
      var amount = fromItem ? getDragAmount(Object.assign({}, fromItem, { count: fromItem.amount })) : 0
      inventory.swapDropSlots(dragFrom.value, toSlot, amount > 0 ? amount : null)
      if (fromItem && amount > 0) inventory.rememberAmount(fromItem.name, amount)
      playPopSound()
    }
    dragFrom.value = null
    dragSource.value = null
    dragGhost.value.show = false
  }

  // ============== Context-menu Use/Give (no drag state required) ==============
  // Both helpers mirror the drag-button logic but operate directly on a passed item
  // (used by Use/Give buttons inside the right-click context menu).
  function isContextMenuActionsEnabled() {
    return !!(inventory.LuaConfig && inventory.LuaConfig.ContextMenuActions && inventory.LuaConfig.ContextMenuActions.Enabled)
  }
  const hideRightColumnActions = computed(function() {
    var cfg = inventory.LuaConfig && inventory.LuaConfig.ContextMenuActions
    return !!(cfg && cfg.Enabled && cfg.HideRightColumnButtons)
  })
  function canUseItem(item) {
    if (!item) return false
    if (item.type === 'item_money' || item.type === 'item_gold') return false
    return true
  }
  function canGiveItem(item) {
    if (!item) return false
    if (isEquippedWeapon(item)) return false
    if (item.locked && item.type !== 'item_money' && item.type !== 'item_gold') return false
    return true
  }
  function onContextUse(item) {
    if (!canUseItem(item)) return
    if (item.type === 'item_weapon' && (item.used || item.used2)) {
      postNUI('UnequipWeapon', { item: item.name, id: item.id })
    } else {
      var useAmt = getTransferAmount(item) || 1
      postNUI('UseItem', { item: item.name, type: item.type, hash: item.hash, amount: useAmt, id: item.id })
    }
    playPopSound()
    contextMenu.value.show = false
  }
  function onContextGive(item) {
    if (!canGiveItem(item)) return
    var amount = getTransferAmount(item) || 1
    var giveType = item.type
    var giveItem = item.name
    if (item.type === 'item_money') giveItem = 'money'
    if (item.type === 'item_gold') giveItem = 'gold'
    postNUI('GetNearPlayers', { type: giveType, what: 'give', item: giveItem, count: amount, id: item.id, hash: item.hash || 1 }).catch(function(){})
    playPopSound()
    contextMenu.value.show = false
  }

  function onDropGive() {
    if (dragFrom.value === null) return
    if (dragSource.value !== 'player') { dragFrom.value = null; dragSource.value = null; dragGhost.value.show = false; return }
    var item = inventory.getItemAtSlot(dragFrom.value)
    if (!item) { dragFrom.value = null; dragGhost.value.show = false; return }
    if (isEquippedWeapon(item)) { dragFrom.value = null; dragSource.value = null; dragGhost.value.show = false; return }
    if (item.locked && item.type !== 'item_money' && item.type !== 'item_gold') { dragFrom.value = null; dragSource.value = null; dragGhost.value.show = false; return }
    if (isCurrencyItem(item) && (Number(item.count) || 0) <= 0) { dragFrom.value = null; dragSource.value = null; dragGhost.value.show = false; return }

    var amount = getTransferAmount(item)
    if (isCurrencyItem(item) && amount <= 0) { dragFrom.value = null; dragSource.value = null; dragGhost.value.show = false; return }

    var giveType = item.type
    var giveItem = item.name
    var giveCount = amount
    var giveId = item.id
    var giveHash = item.hash || 1

    // For money/gold use special types
    if (item.type === 'item_money') giveItem = 'money'
    if (item.type === 'item_gold') giveItem = 'gold'

    postNUI('GetNearPlayers', { type: giveType, what: 'give', item: giveItem, count: giveCount, id: giveId, hash: giveHash }).catch(function(){})
    playPopSound()
    dragFrom.value = null
    dragSource.value = null
    dragGhost.value.show = false
  }

  function onDropUse() {
    if (dragFrom.value === null) return
    if (dragSource.value !== 'player') { dragFrom.value = null; dragSource.value = null; dragGhost.value.show = false; return }
    var item = inventory.getItemAtSlot(dragFrom.value)
    if (!item) { dragFrom.value = null; dragGhost.value.show = false; return }
    if (item.type === 'item_money' || item.type === 'item_gold') { dragFrom.value = null; dragSource.value = null; dragGhost.value.show = false; return }
    if (item.type === 'item_weapon' && (item.used || item.used2)) {
      postNUI('UnequipWeapon', { item: item.name, id: item.id })
    } else {
      var useAmt = getTransferAmount(item)
      postNUI('UseItem', { item: item.name, type: item.type, hash: item.hash, amount: useAmt, id: item.id })
    }
    playPopSound()
    dragFrom.value = null
    dragGhost.value.show = false
  }

  function onMouseUp() {
    if (dragTimer) { clearTimeout(dragTimer); dragTimer = null }
    dragStartPos = null
    if (dragGhost.value.show) {
      dragFrom.value = null
      dragSource.value = null
      dragGhost.value.show = false
    }
    dragShift.value = false
  }

  // Craft slot handlers
  function onCraftSlotMouseDown(e, slotIndex) {
    if (inventory.craftingInProgress) return
    var item = inventory.getCraftItemAtSlot(slotIndex)
    if (!item) return
    if (e.button !== 0) return
    e.preventDefault()
    dragStartPos = { x: e.clientX, y: e.clientY, slot: slotIndex, item: item, source: 'craft' }
    dragTimer = setTimeout(function() {
      if (dragStartPos) {
        dragFrom.value = dragStartPos.slot
        dragSource.value = dragStartPos.source
        dragGhost.value = { show: true, x: dragStartPos.x, y: dragStartPos.y, item: dragStartPos.item }
        dragStartPos = null
      }
    }, 150)
  }

  function onCraftSlotMouseUp(toSlot) {
    if (dragFrom.value === null) return
    if (inventory.craftingInProgress) { dragFrom.value = null; dragSource.value = null; dragGhost.value.show = false; return }
    // Player → Craft
    if (dragSource.value === 'player') {
      var item = inventory.getItemAtSlot(dragFrom.value)
      if (item) {
        if (isEquippedWeapon(item)) { dragFrom.value = null; dragSource.value = null; dragGhost.value.show = false; return }
        var targetCraftItem = inventory.getCraftItemAtSlot(toSlot)
        if (targetCraftItem && !canStackItems(item, targetCraftItem)) { dragFrom.value = null; dragSource.value = null; dragGhost.value.show = false; return }
        var amount = getTransferAmount(item)
        postNUI('CraftAddItem', { itemId: item.id, amount: amount, targetSlot: toSlot })
        playPopSound()
      }
    // Craft → Craft (swap/merge/split)
    } else if (dragSource.value === 'craft' && dragFrom.value !== toSlot) {
      var fromItem = inventory.getCraftItemAtSlot(dragFrom.value)
      var toItem = inventory.getCraftItemAtSlot(toSlot)
      if (fromItem) {
        var amount = getTransferAmount(fromItem)
        if (canStackItems(fromItem, toItem)) {
          postNUI('CraftMergeSlot', { fromSlot: dragFrom.value, toSlot: toSlot, amount: amount || fromItem.count })
        } else if (!toItem && amount > 0 && amount < fromItem.count) {
          postNUI('CraftSplitSlot', { fromSlot: dragFrom.value, toSlot: toSlot, amount: amount })
        } else {
          postNUI('CraftSwapSlot', { fromSlot: dragFrom.value, toSlot: toSlot })
        }
        playPopSound()
      }
    }
    dragFrom.value = null
    dragSource.value = null
    dragGhost.value.show = false
  }

  function closeContextMenu() {
    contextMenu.value.show = false
  }

  const reservedMetaKeys = ['label', 'description', 'image', 'weight', 'tooltip', 'context', 'orgdescription', 'lumberdurability', 'bagId', 'equipped']

  function isReservedMeta(key) {
    return reservedMetaKeys.indexOf(key) !== -1
  }

  function hasItemInfo(item) {
    if (item.serial_number) return true
    if (item.type === 'item_weapon') return true
    if (item.maxDegradation > 0) return true
    if (item.metadata) {
      for (var key in item.metadata) {
        if (!isReservedMeta(key)) return true
      }
    }
    return false
  }

  function getItemDesc(item) {
    return item.metadata?.description || item.custom_desc || item.desc || ''
  }

  function getDegradation(item) {
    if (!item.maxDegradation || item.maxDegradation === 0) return 100
    if (item.percentage != null) return item.percentage
    var maxSec = item.maxDegradation * 60
    var elapsed = inventory.TIME_NOW - item.degradation
    return Math.max(0, ((maxSec - elapsed) / maxSec) * 100)
  }

  function getDegradationColor(pct) {
    if (pct < 15) return '#ef4444'
    if (pct < 40) return '#f97316'
    if (pct < 70) return '#eab308'
    return '#4a9e6b'
  }

  function getWeaponComponents(item) {
    if (!item || item.type !== 'item_weapon' || !item.comps || !item.comps.length) return []
    return item.comps
  }

  function onKeyDown(e) {
    if (e.key === 'Escape' || e.key === 'F1') {
      if (inventory.registryOpen) {
        registryClose()
        return
      }
      if (inventory.isVisible) {
        inventory.hide()
        searchQuery.value = ''
        searchMatchSlots.value = []
        if (searchBlinkInterval) { clearInterval(searchBlinkInterval); searchBlinkInterval = null }
        searchBlinkOn.value = true
      }
    }
  }

  // Weapon registry station
  const registrySearchInput = ref('')
  function registryRegister(weaponId, serverId) {
    postNUI('RegistryRegister', { weaponId: weaponId, targetServerId: serverId }).catch(function(){})
  }
  function registryRefresh() {
    postNUI('RegistryRefresh', {}).catch(function(){})
  }
  function registrySearch() {
    var s = (registrySearchInput.value || '').trim()
    if (!s) return
    postNUI('RegistrySearch', { serial: s }).catch(function(){})
  }
  function registryClose() {
    inventory.registryOpen = false
    postNUI('RegistryClose', {}).catch(function(){})
  }
  // collapsible player cards
  const registryExpanded = ref({})
  function toggleRegistryPlayer(serverId) {
    registryExpanded.value[serverId] = !registryExpanded.value[serverId]
  }
  function isRegistryExpanded(serverId) {
    return !!registryExpanded.value[serverId]
  }

  onMounted(() => {
    document.addEventListener('click', closeContextMenu)
    document.addEventListener('keydown', onKeyDown)
    document.addEventListener('mousemove', onMouseMove)
    document.addEventListener('mouseup', onMouseUp)
  })
  onUnmounted(() => {
    document.removeEventListener('click', closeContextMenu)
    document.removeEventListener('keydown', onKeyDown)
    document.removeEventListener('mousemove', onMouseMove)
    document.removeEventListener('mouseup', onMouseUp)
  })

  const clothingSlots = ref([
    { id: 1,  key: 'hat',      label: 'Hat',      icon: 'hat-icon.png',      param: 'hat',      x: 28, y: 12,  rotate: 0,    lineSide: 'right' },
    { id: 2,  key: 'mask',     label: 'Mask',     icon: 'mask-icon.png',     param: 'mask',     x: 69, y: 18,  rotate: 0,    lineSide: 'left' },
    { id: 3,  key: 'neckwear', label: 'Neckwear', icon: 'neckwear-icon.png', param: 'neckwear', x: 33, y: 22,  rotate: 0,    lineSide: 'right' },
    { id: 4,  key: 'shirt',    label: 'Shirt',    icon: 'shirt-icon.png',    param: 'shirt',    x: 33, y: 40,  rotate: 0,    lineSide: 'right' },
    { id: 5,  key: 'vest',     label: 'Vest',     icon: 'vest-icon.png',     param: 'vest',     x: 30, y: 31,  rotate: 0,    lineSide: 'right' },
    { id: 6,  key: 'poncho',   label: 'Poncho',   icon: 'poncho-icon.png',   param: 'poncho',   x: 74, y: 28,  rotate: 0,    lineSide: 'left' },
    { id: 7,  key: 'coat',     label: 'Coat',     icon: 'coat-icon.png',     param: 'coat',     x: 70, y: 40,  rotate: 0,    lineSide: 'left' },
    { id: 8,  key: 'belt',     label: 'Belt',     icon: 'belt-icon.png',     param: 'belt',     x: 35, y: 52,  rotate: -35,  lineSide: 'right' },
    { id: 9,  key: 'sleeves',  label: 'Sleeves',  icon: 'sleeves-icon.png',  param: 'sleeves',  x: 77, y: 50,  rotate: 35,   lineSide: 'left' },
    { id: 10, key: 'boots',    label: 'Boots',    icon: 'boots-icon.png',    param: 'boots',    x: 22, y: 84,  rotate: 0,    lineSide: 'right' },
    { id: 11, key: 'pant',     label: 'Pant',     icon: 'pant-icon.png',     param: 'ccoat',    x: 69, y: 70,  rotate: 40,   lineSide: 'left' },
    { id: 12, key: 'gloves',   label: 'Gloves',   icon: 'glove-icon.png',    param: 'glove',   x: 14, y: 48,  rotate: 0,    lineSide: 'right' },
  ])

  // Second inventory transfer mappings (same as old UI)
  var moveToActions = {
    custom: { action: 'MoveToCustom', key: 'id', getId: function() { return inventory.customId } },
    player: { action: 'MoveToPlayer', key: 'player', getId: function() { return inventory.playerId } },
    horse: { action: 'MoveToHorse', key: 'horse', getId: function() { return inventory.horseid } },
    cart: { action: 'MoveToCart', key: 'wagon', getId: function() { return inventory.wagonid } },
    house: { action: 'MoveToHouse', key: 'house', getId: function() { return inventory.houseId } },
    hideout: { action: 'MoveToHideout', key: 'hideout', getId: function() { return inventory.hideoutId } },
    bank: { action: 'MoveToBank', key: 'bank', getId: function() { return inventory.bankId } },
    clan: { action: 'MoveToClan', key: 'clan', getId: function() { return inventory.clanid } },
    steal: { action: 'MoveTosteal', key: 'steal', getId: function() { return inventory.stealid } },
    Container: { action: 'MoveToContainer', key: 'Container', getId: function() { return inventory.Containerid } },
  }

  var takeFromActions = {
    custom: { action: 'TakeFromCustom', key: 'id', getId: function() { return inventory.customId } },
    player: { action: 'TakeFromPlayer', key: 'player', getId: function() { return inventory.playerId } },
    horse: { action: 'TakeFromHorse', key: 'horse', getId: function() { return inventory.horseid } },
    cart: { action: 'TakeFromCart', key: 'wagon', getId: function() { return inventory.wagonid } },
    house: { action: 'TakeFromHouse', key: 'house', getId: function() { return inventory.houseId } },
    hideout: { action: 'TakeFromHideout', key: 'hideout', getId: function() { return inventory.hideoutId } },
    bank: { action: 'TakeFromBank', key: 'bank', getId: function() { return inventory.bankId } },
    clan: { action: 'TakeFromClan', key: 'clan', getId: function() { return inventory.clanid } },
    steal: { action: 'TakeFromsteal', key: 'steal', getId: function() { return inventory.stealid } },
    Container: { action: 'TakeFromContainer', key: 'Container', getId: function() { return inventory.Containerid } },
  }

  function onSecondMouseDown(e, slotIndex) {
    var item = inventory.getSecondItemAtSlot(slotIndex)
    if (!item) return
    if (e.button !== 0) return
    if (e.ctrlKey) {
      e.preventDefault()
      quickTransferFromSecond(item)
      return
    }
    e.preventDefault()
    dragShift.value = !!e.shiftKey
    var recalled = inventory.recallAmount(item.name)
    if (recalled != null) transferAmount.value = recalled
    dragStartPos = { x: e.clientX, y: e.clientY, slot: slotIndex, item: item, source: 'second' }
    dragTimer = setTimeout(function() {
      if (dragStartPos) {
        dragFrom.value = dragStartPos.slot
        dragSource.value = dragStartPos.source
        dragGhost.value = { show: true, x: dragStartPos.x, y: dragStartPos.y, item: dragStartPos.item }
        dragStartPos = null
      }
    }, 150)
  }

  function onSecondMouseUp(toSlot) {
    if (dragFrom.value === null) return
    // Player → Second inventory (MoveTo)
    if (dragSource.value === 'player') {
      var item = inventory.getItemAtSlot(dragFrom.value)
      if (item) {
        if (isEquippedWeapon(item)) { dragFrom.value = null; dragSource.value = null; dragGhost.value.show = false; return }
        // Shop: player → shop slot = sell to shop. Slot doesn't matter — the server matches by item name.
        if (inventory.invType === 'shop') {
          var amt = getTransferAmount(item)
          postNUI('ShopSell', { shopId: inventory.shopId, item: item.name, qty: amt || 1 })
          playPopSound()
          dragFrom.value = null; dragSource.value = null; dragGhost.value.show = false; return
        }
        var targetSecItem = inventory.getSecondItemAtSlot(toSlot)
        // Steal: swap when different items
        if (inventory.invType === 'steal' && targetSecItem && !canStackItems(item, targetSecItem)) {
          postNUI('StealSwapBetween', { playerSlot: dragFrom.value, stealSlot: toSlot })
          playPopSound()
        } else if (targetSecItem && !canStackItems(item, targetSecItem)) {
          dragFrom.value = null; dragSource.value = null; dragGhost.value.show = false; return
        } else {
          var type = inventory.invType
          var mapping = moveToActions[type]
          if (mapping) {
            var amount = getDragAmount(item)
            var payload = { item: item, type: item.type, number: amount, targetSlot: toSlot }
            payload[mapping.key] = mapping.getId()
            postNUI(mapping.action, payload)
            inventory.rememberAmount(item.name, amount)
            playPopSound()
          }
        }
      }
    // Second → Second (swap/merge/split within second inventory)
    } else if (dragSource.value === 'second' && dragFrom.value !== toSlot) {
      var fromItem = inventory.getSecondItemAtSlot(dragFrom.value)
      var amount = fromItem ? getDragAmount(fromItem) : 0
      if (inventory.invType === 'steal') {
        inventory.swapStealSlots(dragFrom.value, toSlot, amount > 0 ? amount : null)
      } else {
        inventory.swapSecondSlots(dragFrom.value, toSlot, amount > 0 ? amount : null)
      }
      if (fromItem && amount > 0) inventory.rememberAmount(fromItem.name, amount)
      playPopSound()
    }
    dragFrom.value = null
    dragSource.value = null
    dragGhost.value.show = false
  }

  function onClothingClick(slot) {
    postNUI('ChangeClothing', JSON.stringify(slot.param))
  }

  function isClothingWorn(slot) {
    return !!(inventory.wornClothing && inventory.wornClothing[slot.key])
  }

  // ============================= SHOP =============================
  const shopQtyInput  = ref({}) // [itemName] = qty for restock/withdraw
  const shopPriceBuy  = ref({})
  const shopPriceSell = ref({})
  const empCharId     = ref(null)
  const empPerms      = ref({ restock: true, prices: true, withdraw: false, hours: false })
  const hoursOpen     = ref(null)
  const hoursClose    = ref(null)
  const hoursEnforce  = ref(true)
  const withdrawAmount = ref(null)

  function shopItemAt(slot) {
    var items = inventory.shopState && inventory.shopState.items || []
    for (var i = 0; i < items.length; i++) {
      if (items[i].slot === slot) return items[i]
    }
    return null
  }

  // Drag a shop slot to your player inventory to buy. Quantity comes from the
  // amount input between the two panels; if it is 0/blank, default to 1.
  function onShopSlotMouseDown(e, slotIndex) {
    var item = shopItemAt(slotIndex)
    if (!item) return
    if (e.button !== 0) return
    e.preventDefault()
    dragStartPos = { x: e.clientX, y: e.clientY, slot: slotIndex, item: item, source: 'shop' }
    dragTimer = setTimeout(function() {
      if (dragStartPos) {
        dragFrom.value = dragStartPos.slot
        dragSource.value = dragStartPos.source
        dragGhost.value = { show: true, x: dragStartPos.x, y: dragStartPos.y, item: dragStartPos.item }
        dragStartPos = null
      }
    }, 150)
  }

  function getShopBuyQty() {
    var qty = Number(transferAmount.value)
    if (!qty || qty <= 0) qty = 1
    return Math.max(1, Math.floor(qty))
  }

  function onPurchaseShop() {
    if (!inventory.shopId) return
    postNUI('ShopPurchase', { shopId: inventory.shopId })
  }

  function onRestock(it) {
    var q = (shopQtyInput.value[it.name] && shopQtyInput.value[it.name] > 0) ? shopQtyInput.value[it.name] : 1
    postNUI('ShopRestock', { shopId: inventory.shopId, item: it.name, qty: q })
  }

  function onWithdrawStock(it) {
    var q = (shopQtyInput.value[it.name] && shopQtyInput.value[it.name] > 0) ? shopQtyInput.value[it.name] : 1
    postNUI('ShopWithdrawStock', { shopId: inventory.shopId, item: it.name, qty: q })
  }

  function onSetPrice(it) {
    var b = shopPriceBuy.value[it.name];  if (b == null || b === '') b = it.buy_price
    var s = shopPriceSell.value[it.name]; if (s == null || s === '') s = it.sell_price
    postNUI('ShopSetPrice', { shopId: inventory.shopId, item: it.name, buyPrice: Number(b), sellPrice: Number(s) })
  }

  function onSaveEmployee() {
    if (!empCharId.value) return
    var p = 0
    if (empPerms.value.restock)  p |= 1
    if (empPerms.value.prices)   p |= 2
    if (empPerms.value.withdraw) p |= 4
    if (empPerms.value.hours)    p |= 8
    postNUI('ShopSetEmployee', { shopId: inventory.shopId, charid: empCharId.value, perms: p })
    empCharId.value = null
  }

  function onSaveHours() {
    var o = hoursOpen.value  != null ? hoursOpen.value  : (inventory.shopState && inventory.shopState.openHour)
    var c = hoursClose.value != null ? hoursClose.value : (inventory.shopState && inventory.shopState.closeHour)
    postNUI('ShopSetHours', { shopId: inventory.shopId, openHour: Number(o), closeHour: Number(c), enforce: !!hoursEnforce.value })
  }

  function onToggleForceClosed() {
    var newState = !(inventory.shopState && inventory.shopState.forceClosed)
    postNUI('ShopSetForceClosed', { shopId: inventory.shopId, force: newState })
  }

  function onWithdrawBalance() {
    var amt = Number(withdrawAmount.value)
    if (!amt || amt <= 0) return
    postNUI('ShopWithdrawBalance', { shopId: inventory.shopId, amount: amt })
    withdrawAmount.value = null
  }

  function onWithdrawBalanceAll() {
    var amt = inventory.shopState && inventory.shopState.balance
    if (!amt || amt <= 0) return
    postNUI('ShopWithdrawBalance', { shopId: inventory.shopId, amount: amt })
  }

  // Serial number copy bar (context menu)
  const copiedSerial = ref(false)
  function copySerial(serial) {
    if (!serial) return
    try {
      var ta = document.createElement('textarea')
      ta.value = String(serial)
      ta.style.position = 'fixed'
      ta.style.opacity = '0'
      document.body.appendChild(ta)
      ta.focus()
      ta.select()
      document.execCommand('copy')
      document.body.removeChild(ta)
      copiedSerial.value = true
      setTimeout(function() { copiedSerial.value = false }, 1500)
    } catch (e) {}
  }
</script>

<template>
  <div class="w-screen h-screen overflow-hidden p-20 flex flex-col " style="background-size: 100% 100%;">
    <!-- Drag Ghost -->
      <div v-if="dragGhost.show && dragGhost.item" class="fixed z-[100] pointer-events-none w-[4vw] h-[4vw] opacity-80" :style="{ left: (dragGhost.x - 30) + 'px', top: (dragGhost.y - 30) + 'px' }">
        <img :src="getItemImage(dragGhost.item.name)" @error="onImgError" class="w-full h-full object-contain">
      </div>
    <!-- Background Effect Overlay -->
      <Transition name="fade">
        <div v-if="inventory.isVisible" class="fixed inset-0 z-10 bg-[url(./assets/background-effect.png)] pointer-events-none" style="background-size: 100% 100%;"></div>
      </Transition>
    <!--  Inventory Main -->
      <Transition name="fade">
      <div v-if="inventory.isVisible" class="w-full h-full z-20 flex justify-between items-center">
          <div class="w-[28%] h-[80%] p-6 flex flex-col justify-between items-center  bg-[url(./assets/inventory-background.png)]" style="background-size: 100% 100%;">
              <div height="9%" class="p-2 flex justify-between items-center h-[9%] w-full bg-[url(./assets/header-background.png)]" style="background-size: 100% 100%;">
                  <p class="text-xl">{{ inventory.LuaConfig.ShowCharacterNameInTitle && inventory.charName ? inventory.charName + ' - ' + inventory.charId : uiText('inventory_title', 'Inventory') + ' - ' + inventory.charId }}</p>
                  <div class="w-[2vw] h-[2vw]  flex justify-center items-center rounded-md bg-black/10">
                      <img src="./assets/inventory-icon.png">
                  </div>
              </div>
              <div class="w-full h-[15%]  flex flex-col justify-between">
                  <div class="flex justify-between  ">
                      <div height="35px" width="30%" class="p-2 flex justify-between items-center h-[35px] w-[30%] bg-[url(./assets/info-background.png)]" style="background-size: 100% 100%;">
                          <img src="./assets/gold-icon.png">
                          <p>{{ inventory.gold.toFixed(2) }}</p>
                      </div>
                      <div height="35px" width="30%" class="p-2 flex justify-between items-center h-[35px] w-[30%] bg-[url(./assets/info-background.png)]" style="background-size: 100% 100%;">
                          <img src="./assets/cash-icon.png">
                          <p>{{ inventory.money.toFixed(2) }}</p>
                      </div>
                      <div class="w-[38%] h-[35px] flex flex-col justify-between items-center  gap-1">
                          <div class="weight-bar">
                            <div class="weight-bar-fill" :style="{ width: inventory.maxWeight ? (inventory.currentWeight / inventory.maxWeight * 100) + '%' : '0%' }"></div>
                          </div>
                          <div class="flex  w-full justify-between items-center">
                              <p class="text-sm text-[#BEB592]">{{ uiText('weight', 'Weight') }}</p>
                              <p class="text-sm text-[#BEB592]"><span class="font-semibold">{{ inventory.currentWeight }}</span>/{{ inventory.maxWeight }}{{ inventory.LuaConfig.WeightMeasure || 'kg' }}</p>
                          </div>
                          
                      </div>
                  </div>
                  <div class="p-2 flex items-center gap-2 w-full bg-[url(./assets/search-background.png)]" style="background-size: 100% 100%;">
                      <img src="./assets/search-icon.png">
                      <input type="text" v-model="searchQuery" @input="onSearchInput" class="w-[70%] h-full text-[#000000]" :placeholder="uiText('search_placeholder', 'Search any item...')">
                  </div>
              </div>
              <div class="w-full h-[65%] grid grid-cols-5 gap-1.5 content-start overflow-y-auto">
                  <div v-for="i in (inventory.LuaConfig.PlayerInventorySlots || 25)" :key="i" :id="'player-slot-' + i" @mousedown="onSlotMouseDown($event, i)" @mouseup="onSlotMouseUp(i)" @contextmenu="onSlotRightClick($event, i)" @dblclick="onSlotDoubleClick(i)" class="aspect-square bg-white/[0.08] rounded transition-all hover:opacity-70 p-1 relative flex flex-col items-center justify-center" :class="{ 'opacity-30': dragFrom === i && dragSource === 'player' }" :style="isSearchMatch(i) ? { opacity: searchBlinkOn ? 1 : 0.3, transition: 'opacity 0.3s' } : {}">
                      <template v-if="inventory.getItemAtSlot(i)">
                          <span class="absolute top-0.5 right-1 text-[10px] text-white/40">{{ slotCount(inventory.getItemAtSlot(i)) }}</span>
                          <span class="absolute top-0.5 left-1 text-[10px] text-white/40">{{ slotWeight(inventory.getItemAtSlot(i)) }}kg</span>
                          <img :src="getItemImage(inventory.getItemAtSlot(i).name)" @error="onImgError" class="absolute inset-0 m-auto max-w-[40%] max-h-[60%] object-contain">
                          <svg v-if="inventory.getItemAtSlot(i).type === 'item_weapon' && inventory.getItemAtSlot(i).durability != null" class="absolute left-1 top-1/2 -translate-y-1/2" width="12" height="12" viewBox="0 0 36 36">
                            <circle cx="18" cy="18" r="15" fill="none" stroke="rgba(0,0,0,0.3)" stroke-width="4"></circle>
                            <circle cx="18" cy="18" r="15" fill="none" :stroke="getDegradationColor(inventory.getItemAtSlot(i).durability)" stroke-width="4" stroke-linecap="round" :stroke-dasharray="(inventory.getItemAtSlot(i).durability / 100 * 94.2) + ' 94.2'" transform="rotate(-90 18 18)"></circle>
                          </svg>
                          <span v-if="isEquippedWeapon(inventory.getItemAtSlot(i))" class="absolute left-1 text-[12px] font-semibold leading-none text-[#2fd06c] pointer-events-none" style="top: calc(50% - 22px); text-shadow: 0 1px 2px rgba(0,0,0,0.65);">E</span>
                          <p class="absolute bottom-0.5 left-0 right-0 text-center text-[10px] text-white/70 truncate px-0.5">{{ inventory.getItemAtSlot(i).label }}</p>
                      </template>
                      <template v-else>
                          <span class="absolute top-0.5 right-1 text-[10px] text-white/40">{{ i }}</span>
                      </template>
                  </div>
              </div>
              <div class="w-full h-[8%]  flex justify-between items-end">
                  <div @click="inventory.hide()" class="w-[32%] h-[70%] flex justify-between items-center p-2 transition-all hover:opacity-70 cursor-pointer bg-[url(./assets/bottom-menu-background.png)]" style="background-size: 100% 100%;">
                    <img src="./assets/close-icon.png">
                    <p class="text-xs">{{ uiText('close_inventory', 'Close Inventory') }}</p>
                  </div>
                  <div @click="inventory.secondInventoryType = inventory.secondInventoryType === 'clothing' ? (inventory.invType === 'main' ? 'drop' : 'inventory') : 'clothing'" class="w-[32%] h-[70%] flex justify-between items-center p-2 transition-all hover:opacity-70 cursor-pointer bg-[url(./assets/bottom-menu-background.png)]" style="background-size: 100% 100%;">
                    <img src="./assets/clothing-icon.png">
                    <p class="text-xs">{{ uiText('clothing_menu', 'Clothing Menu') }}</p>
                  </div>
                  <div @click="settings.toggle()" class="w-[32%] h-[70%] flex justify-between items-center p-2 transition-all hover:opacity-70 cursor-pointer bg-[url(./assets/bottom-menu-background.png)]" style="background-size: 100% 100%;">
                    <img src="./assets/settings-icon.png">
                    <p class="text-xs">{{ uiText('settings', 'Settings') }}</p>
                  </div>
              </div>
          </div>
          <div class="w-[30%] h-[80%] relative flex flex-col justify-center items-center">
              <div class="w-[9vw] h-[5vh]  flex justify-center items-center transition-all hover:opacity-70 bg-[url(./assets/amount-background.png)]" style="background-size: 100% 100%;">
                  <input type="number" v-model.number="transferAmount" min="0.01" step="any" @keydown="$event.key === '-' || $event.key === 'e' ? $event.preventDefault() : null" class="w-full h-full text-center text-xl text-[#BEB592]" placeholder="1">
              </div>
              <div v-if="!hideRightColumnActions" @mouseup="onDropUse" class="w-[9vw] h-[5vh] mt-2 flex justify-center text-xl text-[#BEB592] items-center transition-all cursor-pointer bg-[url(./assets/buttons-background.png)]" :style="{ opacity: dragFrom !== null && dragSource === 'player' ? 1 : 0.4, backgroundSize: '100% 100%' }">
                  {{ uiText('use', 'Use') }}
              </div>
              <div v-if="!hideRightColumnActions" @mouseup="onDropGive" class="w-[9vw] h-[5vh] flex justify-center text-xl text-[#BEB592] items-center transition-all cursor-pointer bg-[url(./assets/buttons-background.png)]" :style="{ opacity: dragFrom !== null && dragSource === 'player' ? 1 : 0.4, backgroundSize: '100% 100%' }">
                  {{ uiText('give', 'Give') }}
              </div>
              <!-- settings panel -->
              <Transition name="fade">
              <div v-if="settings.isOpen" class="absolute p-6 bottom-0 w-[80%] h-[25vh] bg-[url(./assets/settings-background.png)] flex flex-col gap-1" style="background-size: 100% 100%;">
                <div class="flex justify-between items-center p-2 h-[25%] w-full bg-[url(./assets/settings-item-background.png)]" style="background-size: 100% 100%;">
                  <div class="flex items-center gap-2">
                    <div class="w-[1.75vw] h-[1.75vw] rounded-md bg-black/10 flex justify-center items-center">
                        <img src="./assets/sound-effects-icon.png">
                    </div>
                    <p>{{ uiText('enable_sound_effects', 'Enable Sound Effects') }}</p>
                  </div>
                  <div @click="settings.soundEffects = !settings.soundEffects" class="w-[1.75vw] h-[1.75vw] bg-[url(./assets/toggle-background.png)] cursor-pointer hover:opacity-80 flex justify-center items-center" style="background-size: 100% 100%;">
                      <Transition name="scale"><img v-if="settings.soundEffects" src="./assets/toggled-icon.png"></Transition>
                  </div>
                </div>
                <!-- settings 2 -->
                <div class="flex justify-between items-center p-2 h-[25%] w-full bg-[url(./assets/settings-item-background.png)]" style="background-size: 100% 100%;">
                  <div class="flex items-center gap-2">
                    <div class="w-[1.75vw] h-[1.75vw] rounded-md bg-black/10 flex justify-center items-center">
                        <img src="./assets/square.png">
                    </div>
                    <p>{{ uiText('show_notifications', 'Show Item Add/Remove Notifications') }}</p>
                  </div>
                  <div @click="settings.showNotifications = !settings.showNotifications" class="w-[1.75vw] h-[1.75vw] bg-[url(./assets/toggle-background.png)] cursor-pointer hover:opacity-80 flex justify-center items-center" style="background-size: 100% 100%;">
                      <Transition name="scale"><img v-if="settings.showNotifications" src="./assets/toggled-icon.png"></Transition>
                  </div>
                </div>
                <!-- settings 3 -->
                <div class="flex justify-between items-center p-2 h-[25%] w-full bg-[url(./assets/settings-item-background.png)]" style="background-size: 100% 100%;">
                  <div class="flex items-center gap-2">
                    <div class="w-[1.75vw] h-[1.75vw] rounded-md bg-black/10 flex justify-center items-center">
                        <img src="./assets/notification-duration-icon.png">
                    </div>
                    <p>{{ uiText('notification_duration', 'Notification Duration') }}</p>
                  </div>
                  <div class="h-[1.5vw] flex gap-1 items-center">
                      <div class="w-[4vw] h-full bg-[url(./assets/ms-input-background.png)]" style="background-size: 100% 100%;">
                          <input type="number" v-model.number="settings.notificationDuration" class="w-full h-full text-center text-[#BEB592]" placeholder="3000">
                      </div>
                      <p class="text-xs text-[#4D4B4B]">ms</p>
                  </div>
                </div>
                <!-- settings 4 -->
                <div class="flex justify-between items-center p-2 h-[25%] w-full bg-[url(./assets/settings-item-background.png)]" style="background-size: 100% 100%;">
                  <div class="flex items-center gap-2">
                    <div class="w-[1.75vw] h-[1.75vw] rounded-md bg-black/10 flex justify-center items-center">
                        <img src="./assets/double-click-icon.png">
                    </div>
                    <p>{{ uiText('double_click_to_use', 'Double Click to Use') }}</p>
                  </div>
                  <div @click="settings.doubleClickToUse = !settings.doubleClickToUse" class="w-[1.75vw] h-[1.75vw] bg-[url(./assets/toggle-background.png)] cursor-pointer hover:opacity-80 flex justify-center items-center" style="background-size: 100% 100%;">
                      <Transition name="scale"><img v-if="settings.doubleClickToUse" src="./assets/toggled-icon.png"></Transition>
                  </div>
                </div>
              </div>
              </Transition>
              
          </div>
          <div class="w-[28%] h-[80%] p-6 flex flex-col justify-between items-center  bg-[url(./assets/inventory-background.png)]" style="background-size: 100% 100%;">
              <!-- Second Inventory: inventory -->
              <Transition name="fade" mode="out-in">
              <div v-if="inventory.secondInventoryType === 'inventory'" key="inventory" class="w-full h-full flex flex-col justify-between items-center">
                <div height="9%" class="p-2 flex justify-between items-center h-[9%] w-full bg-[url(./assets/header-background.png)]" style="background-size: 100% 100%;">
                  <p class="text-xl">{{ inventory.secondTitle }}</p>
                  <div class="w-[2vw] h-[2vw]  flex justify-center items-center rounded-md bg-black/10">
                      <img src="./assets/user-icon.png">
                  </div>
                </div>
                <div class="w-full h-[6vh] flex flex-col items-center justify-center gap-1">
                    <div class="weight-bar">
                      <div class="weight-bar-fill" :style="{ width: inventory.secondCapacity > 0 ? (inventory.secondCurrentCount / inventory.secondCapacity * 100) + '%' : '0%' }"></div>
                    </div>
                    <div class="w-full flex justify-between items-center">
                        <p class="text-sm text-[#BEB592]">{{ inventory.secondWeight ? uiText('max_weight', 'Max Weight') : uiText('item_limit', 'Item Limit') }}</p>
                        <p class="text-sm text-[#BEB592]"><span class="font-semibold">{{ inventory.secondCurrentCount }}</span>/{{ inventory.secondCapacity }}{{ inventory.secondWeight ? (inventory.LuaConfig.WeightMeasure || 'kg') : '' }}</p>
                    </div>
                </div>
                <div class="w-full h-[80%] grid grid-cols-5 gap-1.5 content-start overflow-y-auto">
                    <div v-for="i in 35" :key="i" @mousedown="onSecondMouseDown($event, i)" @mouseup="onSecondMouseUp(i)" @dblclick="onSecondDoubleClick(i)" class="aspect-square bg-white/[0.08] rounded transition-all hover:opacity-70 p-1 relative flex flex-col items-center justify-center" :class="{ 'opacity-30': dragFrom === i && dragSource === 'second' }">
                        <template v-if="inventory.getSecondItemAtSlot(i)">
                            <span class="absolute top-0.5 right-1 text-[10px] text-white/40">{{ slotCount(inventory.getSecondItemAtSlot(i)) }}</span>
                            <span class="absolute top-0.5 left-1 text-[10px] text-white/40">{{ slotWeight(inventory.getSecondItemAtSlot(i)) }}kg</span>
                            <img :src="getItemImage(inventory.getSecondItemAtSlot(i).name)" @error="onImgError" class="absolute inset-0 m-auto max-w-[40%] max-h-[60%] object-contain">
                            <svg v-if="inventory.getSecondItemAtSlot(i).type === 'item_weapon' && inventory.getSecondItemAtSlot(i).durability != null" class="absolute left-1 top-1/2 -translate-y-1/2" width="12" height="12" viewBox="0 0 36 36">
                              <circle cx="18" cy="18" r="15" fill="none" stroke="rgba(0,0,0,0.3)" stroke-width="4"></circle>
                              <circle cx="18" cy="18" r="15" fill="none" :stroke="getDegradationColor(inventory.getSecondItemAtSlot(i).durability)" stroke-width="4" stroke-linecap="round" :stroke-dasharray="(inventory.getSecondItemAtSlot(i).durability / 100 * 94.2) + ' 94.2'" transform="rotate(-90 18 18)"></circle>
                            </svg>
                            <p class="absolute bottom-0.5 left-0 right-0 text-center text-[10px] text-white/70 truncate px-0.5">{{ inventory.getSecondItemAtSlot(i).label }}</p>
                        </template>
                        <template v-else>
                            <span class="absolute top-0.5 right-1 text-[10px] text-white/40">{{ i }}</span>
                        </template>
                    </div>
                </div>
              </div>

              <!-- Second Inventory: shop -->
              <div v-else-if="inventory.secondInventoryType === 'shop'" key="shop" class="w-full h-full flex flex-col items-center gap-2">

                <!-- ============ HEADER ============ -->
                <div class="p-2 flex justify-between items-center h-[9%] w-full bg-[url(./assets/header-background.png)]" style="background-size: 100% 100%;">
                  <div class="flex flex-col leading-tight">
                    <p class="text-xl">{{ inventory.shopState?.name || inventory.secondTitle }}</p>
                    <p v-if="inventory.shopState" class="text-[10px] text-[#4D4B4B] flex items-center gap-2">
                      <span v-if="inventory.shopState.role === 'owner'">{{ uiText('shop_role_owner', 'Owner') }}</span>
                      <span v-else-if="inventory.shopState.role === 'employee'">{{ uiText('shop_role_employee', 'Employee') }}</span>
                      <span v-else>{{ uiText('shop_role_customer', 'Customer') }}</span>
                      <span v-if="!inventory.shopState.isOpen" class="px-1.5 py-px tracking-wider text-[#8a2b2b] font-semibold" style="background: rgba(0,0,0,0.12);">{{ uiText('shop_closed_chip', 'CLOSED') }}</span>
                    </p>
                  </div>
                  <div class="w-[2vw] h-[2vw] flex justify-center items-center rounded-md bg-black/10">
                    <img src="./assets/cash-icon.png">
                  </div>
                </div>

                <!-- ============ VIEW SWITCHER (owner/employee only) ============ -->
                <div v-if="inventory.shopState && (inventory.shopState.role === 'owner' || inventory.shopState.role === 'employee')" class="w-full h-[5vh] grid grid-cols-2 gap-1.5">
                  <div @click="inventory.shopView = 'shopping'"
                       class="flex justify-center items-center cursor-pointer transition-all hover:opacity-80 bg-[url(./assets/bottom-menu-background.png)]"
                       :style="{ backgroundSize: '100% 100%', opacity: inventory.shopView !== 'owner' ? 1 : 0.45 }">
                    <p class="text-xs">{{ uiText('shop_shop_view', 'Shop View') }}</p>
                  </div>
                  <div @click="inventory.shopView = 'owner'"
                       class="flex justify-center items-center cursor-pointer transition-all hover:opacity-80 bg-[url(./assets/bottom-menu-background.png)]"
                       :style="{ backgroundSize: '100% 100%', opacity: inventory.shopView === 'owner' ? 1 : 0.45 }">
                    <p class="text-xs">{{ uiText('shop_manage', 'Manage') }}</p>
                  </div>
                </div>

                <!-- ============ SHOPPING VIEW ============ -->
                <!-- Owner view is only available to owner/employee; everyone else lands here regardless of shopView. -->
                <template v-if="inventory.shopView !== 'owner' || !inventory.shopState || (inventory.shopState.role !== 'owner' && inventory.shopState.role !== 'employee')">

                  <!-- For-sale strip -->
                  <div v-if="inventory.shopState?.purchasable" class="w-full h-[6vh] flex justify-between items-center px-3 py-1 bg-[url(./assets/settings-item-background.png)]" style="background-size: 100% 100%;">
                    <div class="flex items-center gap-2 min-w-0">
                      <div class="w-[1.75vw] h-[1.75vw] rounded-md bg-black/10 flex justify-center items-center shrink-0">
                        <img src="./assets/cash-icon.png">
                      </div>
                      <p class="text-xs truncate">{{ uiText('shop_for_sale_strip', 'This shop is for sale') }}</p>
                    </div>
                    <div @click="onPurchaseShop" class="h-[2vw] px-3 flex justify-center items-center text-xs text-[#BEB592] cursor-pointer transition-all hover:opacity-80 bg-[url(./assets/buttons-background.png)]" style="background-size: 100% 100%;">
                      {{ formatTemplate(uiText('shop_buy_for', 'Buy for $%s'), inventory.shopState.purchasePrice) }}
                    </div>
                  </div>

                  <!-- Balance line (owner/employee on the shopping view) -->
                  <div v-if="inventory.shopState?.role !== 'customer' && inventory.shopState?.features?.ShopBalance" class="w-full h-[5vh] flex justify-between items-center px-3 bg-[url(./assets/settings-item-background.png)]" style="background-size: 100% 100%;">
                    <div class="flex items-center gap-2">
                      <div class="w-[1.75vw] h-[1.75vw] rounded-md bg-black/10 flex justify-center items-center">
                        <img src="./assets/cash-icon.png">
                      </div>
                      <p class="text-xs">{{ uiText('shop_balance', 'Balance') }}</p>
                    </div>
                    <p class="text-sm font-semibold">${{ inventory.shopState?.balance ?? 0 }}</p>
                  </div>

                  <!-- divider above slot grid -->
                  <div class="w-full h-1 bg-[url(./assets/line.png)]" style="background-size: 100% 100%;"></div>

                  <!-- 5xN shop slot grid (mirrors secondary inventory grid exactly) -->
                  <div class="w-full flex-1 grid grid-cols-5 gap-1.5 content-start overflow-y-auto">
                    <div v-for="i in (inventory.shopState?.capacity || 35)" :key="'shop-slot-'+i"
                         @mousedown="onShopSlotMouseDown($event, i)"
                         class="aspect-square bg-white/[0.08] rounded transition-all hover:opacity-70 p-1 relative flex flex-col items-center justify-center cursor-pointer"
                         :class="{ 'opacity-30': dragFrom === i && dragSource === 'shop' }">
                      <template v-if="shopItemAt(i)">
                        <span class="absolute top-0.5 right-1 text-sm font-bold text-white" style="text-shadow: 0 1px 2px rgba(0,0,0,0.7);">{{ shopItemAt(i).infinite ? '∞' : shopItemAt(i).count }}</span>
                        <div class="absolute top-0.5 left-1 flex flex-col items-start leading-none">
                          <span class="text-[10px] text-[#e6c074] font-semibold">${{ shopItemAt(i).buy_price }}</span>
                          <span v-if="shopItemAt(i).sell_price > 0 && inventory.shopState?.buyback" class="text-[8px] text-[#b8d49f] mt-px">▾${{ shopItemAt(i).sell_price }}</span>
                        </div>
                        <img :src="getItemImage(shopItemAt(i).name)" @error="onImgError" class="absolute inset-0 m-auto max-w-[40%] max-h-[60%] object-contain">
                        <p class="absolute bottom-0.5 left-0 right-0 text-center text-[10px] text-white/70 truncate px-0.5">{{ shopItemAt(i).label }}</p>
                      </template>
                      <template v-else>
                        <span class="absolute top-0.5 right-1 text-[10px] text-white/40">{{ i }}</span>
                      </template>
                    </div>
                  </div>
                </template>

                <!-- ============ OWNER MANAGE VIEW ============ -->
                <template v-else>

                  <!-- 5-tab strip -->
                  <div class="w-full h-[4vh] grid grid-cols-5 gap-1">
                    <div v-for="tab in ['stock','prices','employees','hours','balance']" :key="tab"
                         @click="inventory.shopOwnerTab = tab"
                         class="flex justify-center items-center cursor-pointer transition-all hover:opacity-90 bg-[url(./assets/bottom-menu-background.png)]"
                         :style="{ backgroundSize: '100% 100%', opacity: inventory.shopOwnerTab === tab ? 1 : 0.4 }">
                      <p class="text-[11px]">{{ uiText('shop_tab_' + tab, tab) }}</p>
                    </div>
                  </div>

                  <!-- divider -->
                  <div class="w-full h-1 bg-[url(./assets/line.png)]" style="background-size: 100% 100%;"></div>

                  <!-- panel body -->
                  <div class="w-full flex-1 overflow-y-auto flex flex-col gap-1.5 pr-1">

                    <!-- STOCK -->
                    <template v-if="inventory.shopOwnerTab === 'stock'">
                      <div v-for="it in (inventory.shopState?.items || [])" :key="'stk-'+it.name" class="w-full h-[5.5vh] flex justify-between items-center px-2 gap-2 bg-[url(./assets/settings-item-background.png)]" style="background-size: 100% 100%;">
                        <div class="flex items-center gap-2 min-w-0 flex-1">
                          <div class="w-[1.75vw] h-[1.75vw] rounded-md bg-black/10 flex justify-center items-center shrink-0">
                            <img :src="getItemImage(it.name)" @error="onImgError" class="max-w-[80%] max-h-[80%] object-contain">
                          </div>
                          <div class="flex flex-col leading-tight min-w-0">
                            <p class="text-[12px] truncate">{{ it.label }}</p>
                            <p class="text-[10px] text-[#4D4B4B]">{{ formatTemplate(uiText('shop_stock_qty', 'qty %s'), it.infinite ? '∞' : it.count) }}</p>
                          </div>
                        </div>
                        <div class="h-[1.75vw] flex items-center gap-1 shrink-0">
                          <div class="w-[3vw] h-full bg-[url(./assets/ms-input-background.png)]" style="background-size: 100% 100%;">
                            <input v-model.number="shopQtyInput[it.name]" type="number" min="1" placeholder="1" class="w-full h-full text-center text-[11px] text-[#BEB592]">
                          </div>
                          <div @click="onRestock(it)" :class="['w-[1.75vw] h-full flex justify-center items-center cursor-pointer transition-all hover:opacity-80 bg-[url(./assets/buttons-background.png)]', inventory.shopState?.type === 'npc' ? 'opacity-30 pointer-events-none' : '']" style="background-size: 100% 100%;">
                            <p class="text-sm text-[#BEB592] leading-none">+</p>
                          </div>
                          <div @click="onWithdrawStock(it)" :class="['w-[1.75vw] h-full flex justify-center items-center cursor-pointer transition-all hover:opacity-80 bg-[url(./assets/buttons-background.png)]', (inventory.shopState?.type === 'npc' || it.count <= 0) ? 'opacity-30 pointer-events-none' : '']" style="background-size: 100% 100%;">
                            <p class="text-sm text-[#BEB592] leading-none">−</p>
                          </div>
                        </div>
                      </div>
                      <p v-if="inventory.shopState?.type === 'npc'" class="text-[10px] text-[#4D4B4B] text-center mt-1">{{ uiText('shop_npc_note_restock', "NPC shops have infinite stock and can't be restocked.") }}</p>
                    </template>

                    <!-- PRICES -->
                    <template v-else-if="inventory.shopOwnerTab === 'prices'">
                      <div v-for="it in (inventory.shopState?.items || [])" :key="'pri-'+it.name" class="w-full h-[5.5vh] flex justify-between items-center px-2 gap-2 bg-[url(./assets/settings-item-background.png)]" style="background-size: 100% 100%;">
                        <div class="flex items-center gap-2 min-w-0 flex-1">
                          <div class="w-[1.75vw] h-[1.75vw] rounded-md bg-black/10 flex justify-center items-center shrink-0">
                            <img :src="getItemImage(it.name)" @error="onImgError" class="max-w-[80%] max-h-[80%] object-contain">
                          </div>
                          <p class="text-[12px] truncate">{{ it.label }}</p>
                        </div>
                        <div class="h-[1.75vw] flex items-center gap-1 shrink-0">
                          <p class="text-[10px] text-[#4D4B4B]">{{ uiText('shop_buy_label', 'buy') }}</p>
                          <div class="w-[3vw] h-full bg-[url(./assets/ms-input-background.png)]" style="background-size: 100% 100%;">
                            <input v-model.number="shopPriceBuy[it.name]" type="number" min="0" :placeholder="it.buy_price" class="w-full h-full text-center text-[11px] text-[#BEB592]">
                          </div>
                          <p class="text-[10px] text-[#4D4B4B]">{{ uiText('shop_sell_label', 'sell') }}</p>
                          <div class="w-[3vw] h-full bg-[url(./assets/ms-input-background.png)]" style="background-size: 100% 100%;">
                            <input v-model.number="shopPriceSell[it.name]" type="number" min="0" :placeholder="it.sell_price" class="w-full h-full text-center text-[11px] text-[#BEB592]">
                          </div>
                          <div @click="onSetPrice(it)" :class="['h-full px-2 flex justify-center items-center cursor-pointer transition-all hover:opacity-80 bg-[url(./assets/buttons-background.png)]', inventory.shopState?.type === 'npc' ? 'opacity-30 pointer-events-none' : '']" style="background-size: 100% 100%;">
                            <p class="text-[10px] text-[#BEB592]">{{ uiText('shop_save', 'save') }}</p>
                          </div>
                        </div>
                      </div>
                      <p v-if="inventory.shopState?.type === 'npc'" class="text-[10px] text-[#4D4B4B] text-center mt-1">{{ uiText('shop_npc_note_prices', 'NPC shop prices are set in config/shops.lua.') }}</p>
                    </template>

                    <!-- EMPLOYEES -->
                    <template v-else-if="inventory.shopOwnerTab === 'employees'">
                      <!-- charid input -->
                      <div class="w-full h-[5.5vh] flex justify-between items-center px-2 gap-2 bg-[url(./assets/settings-item-background.png)]" style="background-size: 100% 100%;">
                        <div class="flex items-center gap-2 min-w-0">
                          <div class="w-[1.75vw] h-[1.75vw] rounded-md bg-black/10 flex justify-center items-center">
                            <img src="./assets/user-icon.png">
                          </div>
                          <p class="text-[12px]">{{ uiText('shop_add_employee', 'Add / update employee') }}</p>
                        </div>
                        <div class="w-[5vw] h-[1.75vw] bg-[url(./assets/ms-input-background.png)]" style="background-size: 100% 100%;">
                          <input v-model.number="empCharId" type="number" :placeholder="uiText('shop_charid_placeholder', 'charid')" class="w-full h-full text-center text-[11px] text-[#BEB592]">
                        </div>
                      </div>
                      <!-- perm toggles -->
                      <div v-for="perm in [ {k:'restock',label:'shop_perm_restock',fallback:'restock'}, {k:'prices',label:'shop_perm_prices',fallback:'prices'}, {k:'withdraw',label:'shop_perm_withdraw',fallback:'withdraw'}, {k:'hours',label:'shop_perm_hours',fallback:'hours'} ]" :key="'perm-'+perm.k" class="w-full h-[5vh] flex justify-between items-center px-2 bg-[url(./assets/settings-item-background.png)]" style="background-size: 100% 100%;">
                        <p class="text-[12px]">{{ uiText(perm.label, perm.fallback) }}</p>
                        <div @click="empPerms[perm.k] = !empPerms[perm.k]" class="w-[1.75vw] h-[1.75vw] bg-[url(./assets/toggle-background.png)] cursor-pointer hover:opacity-80 flex justify-center items-center" style="background-size: 100% 100%;">
                          <Transition name="scale"><img v-if="empPerms[perm.k]" src="./assets/toggled-icon.png"></Transition>
                        </div>
                      </div>
                      <!-- save button -->
                      <div @click="onSaveEmployee" class="w-full h-[5vh] flex justify-center items-center cursor-pointer transition-all hover:opacity-80 bg-[url(./assets/buttons-background.png)]" style="background-size: 100% 100%;">
                        <p class="text-sm text-[#BEB592]">{{ uiText('shop_save', 'save') }}</p>
                      </div>
                      <p class="text-[10px] text-[#4D4B4B] text-center">{{ uiText('shop_emp_hint', 'Set all permissions off to remove an employee.') }}</p>
                    </template>

                    <!-- HOURS -->
                    <template v-else-if="inventory.shopOwnerTab === 'hours'">
                      <div class="w-full h-[5vh] flex justify-between items-center px-2 bg-[url(./assets/settings-item-background.png)]" style="background-size: 100% 100%;">
                        <p class="text-[12px]">{{ uiText('shop_open_at', 'Open at') }}</p>
                        <div class="w-[4vw] h-[1.75vw] bg-[url(./assets/ms-input-background.png)]" style="background-size: 100% 100%;">
                          <input v-model.number="hoursOpen" type="number" min="0" max="23" :placeholder="inventory.shopState?.openHour" class="w-full h-full text-center text-[11px] text-[#BEB592]">
                        </div>
                      </div>
                      <div class="w-full h-[5vh] flex justify-between items-center px-2 bg-[url(./assets/settings-item-background.png)]" style="background-size: 100% 100%;">
                        <p class="text-[12px]">{{ uiText('shop_close_at', 'Close at') }}</p>
                        <div class="w-[4vw] h-[1.75vw] bg-[url(./assets/ms-input-background.png)]" style="background-size: 100% 100%;">
                          <input v-model.number="hoursClose" type="number" min="0" max="23" :placeholder="inventory.shopState?.closeHour" class="w-full h-full text-center text-[11px] text-[#BEB592]">
                        </div>
                      </div>
                      <div class="w-full h-[5vh] flex justify-between items-center px-2 bg-[url(./assets/settings-item-background.png)]" style="background-size: 100% 100%;">
                        <p class="text-[12px]">{{ uiText('shop_enforce_hours', 'Enforce opening hours') }}</p>
                        <div @click="hoursEnforce = !hoursEnforce" class="w-[1.75vw] h-[1.75vw] bg-[url(./assets/toggle-background.png)] cursor-pointer hover:opacity-80 flex justify-center items-center" style="background-size: 100% 100%;">
                          <Transition name="scale"><img v-if="hoursEnforce" src="./assets/toggled-icon.png"></Transition>
                        </div>
                      </div>
                      <div @click="onSaveHours" class="w-full h-[5vh] flex justify-center items-center cursor-pointer transition-all hover:opacity-80 bg-[url(./assets/buttons-background.png)]" style="background-size: 100% 100%;">
                        <p class="text-sm text-[#BEB592]">{{ uiText('shop_save', 'save') }}</p>
                      </div>
                      <div class="w-full h-1 bg-[url(./assets/line.png)] my-1" style="background-size: 100% 100%;"></div>
                      <div class="w-full h-[5vh] flex justify-between items-center px-2 bg-[url(./assets/settings-item-background.png)]" style="background-size: 100% 100%;">
                        <p class="text-[12px]">{{ uiText('shop_force_close', 'Force-close shop') }}</p>
                        <div @click="onToggleForceClosed" class="w-[1.75vw] h-[1.75vw] bg-[url(./assets/toggle-background.png)] cursor-pointer hover:opacity-80 flex justify-center items-center" style="background-size: 100% 100%;">
                          <Transition name="scale"><img v-if="inventory.shopState?.forceClosed" src="./assets/toggled-icon.png"></Transition>
                        </div>
                      </div>
                    </template>

                    <!-- BALANCE / WITHDRAW -->
                    <template v-else-if="inventory.shopOwnerTab === 'balance'">
                      <div class="w-full h-[8vh] flex justify-between items-center px-3 bg-[url(./assets/settings-item-background.png)]" style="background-size: 100% 100%;">
                        <div class="flex items-center gap-2">
                          <div class="w-[2vw] h-[2vw] rounded-md bg-black/10 flex justify-center items-center">
                            <img src="./assets/cash-icon.png">
                          </div>
                          <p class="text-[12px]">{{ uiText('shop_current_balance', 'Current balance') }}</p>
                        </div>
                        <p class="text-2xl font-semibold">${{ inventory.shopState?.balance ?? 0 }}</p>
                      </div>
                      <div class="w-full h-[5.5vh] flex justify-between items-center px-2 gap-2 bg-[url(./assets/settings-item-background.png)]" style="background-size: 100% 100%;">
                        <p class="text-[12px]">{{ uiText('shop_amount_placeholder', 'amount') }}</p>
                        <div class="h-[1.75vw] flex items-center gap-1">
                          <div class="w-[5vw] h-full bg-[url(./assets/ms-input-background.png)]" style="background-size: 100% 100%;">
                            <input v-model.number="withdrawAmount" type="number" min="1" class="w-full h-full text-center text-[11px] text-[#BEB592]">
                          </div>
                        </div>
                      </div>
                      <div class="w-full grid grid-cols-2 gap-1.5">
                        <div @click="onWithdrawBalance" class="h-[5vh] flex justify-center items-center cursor-pointer transition-all hover:opacity-80 bg-[url(./assets/buttons-background.png)]" style="background-size: 100% 100%;">
                          <p class="text-sm text-[#BEB592]">{{ uiText('shop_withdraw', 'withdraw') }}</p>
                        </div>
                        <div @click="onWithdrawBalanceAll" class="h-[5vh] flex justify-center items-center cursor-pointer transition-all hover:opacity-80 bg-[url(./assets/buttons-background.png)]" style="background-size: 100% 100%;">
                          <p class="text-sm text-[#BEB592]">{{ uiText('shop_withdraw_all', 'all') }}</p>
                        </div>
                      </div>
                    </template>
                  </div>
                </template>
              </div>

              <!-- Second Inventory: craft -->
              <div v-else-if="inventory.secondInventoryType === 'craft'" key="craft" class="w-full h-full flex flex-col justify-between items-center">
                  <div class="p-2 flex justify-between items-center h-[9%] w-full bg-[url(./assets/header-background.png)]" style="background-size: 100% 100%;">
                    <p class="text-xl">{{ uiText('craft_inventory', 'Craft Inventory') }}</p>
                    <div class="w-[2vw] h-[2vw] flex justify-center items-center rounded-md bg-black/10">
                        <img src="./assets/craft-icon.png">
                    </div>
                  </div>
                  <!-- Progress bar -->
                  <div class="w-full h-[6vh] flex flex-col items-center justify-center gap-1">
                    <div class="weight-bar">
                      <div class="weight-bar-fill" :style="{ width: inventory.craftProgress + '%' }"></div>
                    </div>
                    <div class="w-full flex justify-between items-center">
                        <p class="text-sm text-[#BEB592]">{{ inventory.craftingInProgress ? uiText('craft_in_progress', 'Crafting...') : uiText('craft_progress', 'Craft Progress') }}</p>
                        <span class="font-semibold text-[#BEB592]">{{ inventory.craftProgress.toFixed(0) }}%</span>
                    </div>
                    
                  </div>
                  <!-- Craft slots -->
                  <div class="w-full h-[30%] grid grid-cols-5 gap-1.5 content-start overflow-y-auto">
                    <div v-for="i in 20" :key="i" @mousedown="onCraftSlotMouseDown($event, i)" @mouseup="onCraftSlotMouseUp(i)" class="aspect-square rounded transition-all hover:opacity-70 p-1 relative flex flex-col items-center justify-center" :class="{ 'opacity-30': dragFrom === i && dragSource === 'craft' }" :style="{ backgroundColor: inventory.getCraftItemAtSlot(i) ? 'rgba(255,138,5,0.06)' : 'rgba(255,255,255,0.08)' }">
                        <template v-if="inventory.getCraftItemAtSlot(i)">
                            <span class="absolute top-0.5 right-1 text-[10px] text-white/40">{{ inventory.getCraftItemAtSlot(i).count }}x</span>
                            <span class="absolute top-0.5 left-1 text-[10px] text-white/40">{{ ((inventory.getCraftItemAtSlot(i).weight || 0) * inventory.getCraftItemAtSlot(i).count).toFixed(2) }}kg</span>
                            <img :src="getItemImage(inventory.getCraftItemAtSlot(i).name)" @error="onImgError" class="absolute inset-0 m-auto w-[40%] h-[60%] object-contain">
                            <svg v-if="inventory.getCraftItemAtSlot(i).type === 'item_weapon' && inventory.getCraftItemAtSlot(i).durability != null" class="absolute left-1 top-1/2 -translate-y-1/2" width="12" height="12" viewBox="0 0 36 36">
                              <circle cx="18" cy="18" r="15" fill="none" stroke="rgba(0,0,0,0.3)" stroke-width="4"></circle>
                              <circle cx="18" cy="18" r="15" fill="none" :stroke="getDegradationColor(inventory.getCraftItemAtSlot(i).durability)" stroke-width="4" stroke-linecap="round" :stroke-dasharray="(inventory.getCraftItemAtSlot(i).durability / 100 * 94.2) + ' 94.2'" transform="rotate(-90 18 18)"></circle>
                            </svg>
                            <p class="absolute bottom-0.5 left-0 right-0 text-center text-[10px] text-white/70 truncate px-0.5">{{ inventory.getCraftItemAtSlot(i).label }}</p>
                        </template>
                        <template v-else>
                            <span class="absolute top-0.5 right-1 text-[10px] text-white/40">{{ i }}</span>
                        </template>
                    </div>
                  </div>
                  <div class="w-full h-2 bg-[url(./assets/line.png)]" style="background-size: 100% 100%;"></div>
                  <!-- Recipe panel -->
                  <div class="w-full h-[37%] bg-white/10 rounded-md flex justify-center items-center p-5">
                    <!-- No recipe matched -->
                    <div v-if="!inventory.craftRecipe" class="text-center">
                      <p class="text-[#898888] text-sm">{{ uiText('craft_prepare', 'Prepare items to see progress!') }}</p>
                    </div>
                    <!-- Recipe matched -->
                    <div v-else class="w-full h-full flex justify-between">
                      <!-- Reward -->
                      <div class="w-[30%] h-full flex flex-col justify-between">
                        <div class="gap-1">
                          <p class="text-[#CAA580] text-lg">{{ inventory.craftRecipe.rewardLabel }}</p>
                          <p class="text-[#898888] text-xs">{{ uiText('craft_reward', 'Reward') }}</p>
                        </div>
                        <div class="w-[5vw] h-[5vw] rounded p-1 relative" style="background-color: rgba(255,138,5,0.06);">
                          <span class="absolute top-0.5 right-1 text-[10px] text-white/40">{{ inventory.craftRecipe.rewardAmount * inventory.craftAmount }}x</span>
                          <span class="absolute top-0.5 left-1 text-[10px] text-white/40">{{ ((inventory.craftRecipe.rewardWeight || 0) * inventory.craftRecipe.rewardAmount * inventory.craftAmount).toFixed(2) }}kg</span>
                          <img :src="getItemImage(inventory.craftRecipe.rewardName)" @error="onImgError" class="absolute inset-0 m-auto w-[40%] h-[60%] object-contain">
                          <p class="absolute bottom-0.5 left-0 right-0 text-center text-[10px] text-white/70 truncate px-0.5">{{ inventory.craftRecipe.rewardLabel }}</p>
                        </div>
                        <div class="w-[5vw] h-[2vw] flex justify-between items-center p-2 bg-[url(./assets/slider-background.png)]" style="background-size: 100% 100%;">
                          <div @click="!inventory.craftingInProgress && inventory.craftAmount > 1 ? inventory.craftAmount-- : null" class="w-[1.25vw] h-[1.25vw] bg-[url(./assets/chevron-left.png)] transition-all" :style="{ backgroundSize: '100% 100%', opacity: inventory.craftingInProgress || inventory.craftAmount <= 1 ? 0.3 : 1, cursor: inventory.craftingInProgress || inventory.craftAmount <= 1 ? 'default' : 'pointer', pointerEvents: inventory.craftingInProgress || inventory.craftAmount <= 1 ? 'none' : 'auto' }"></div>
                          <p class="text-[#CAA580]">{{ inventory.craftAmount }}</p>
                          <div @click="!inventory.craftingInProgress ? inventory.craftAmount++ : null" class="w-[1.25vw] h-[1.25vw] bg-[url(./assets/chevron-right.png)] transition-all" :style="{ backgroundSize: '100% 100%', opacity: inventory.craftingInProgress ? 0.3 : 1, cursor: inventory.craftingInProgress ? 'default' : 'pointer', pointerEvents: inventory.craftingInProgress ? 'none' : 'auto' }"></div>
                        </div>
                      </div>
                      <!-- Ingredients + craft button -->
                      <div class="w-[68%] h-full flex flex-col justify-between">
                        <div class="gap-1">
                          <p class="text-[#CAA580] text-lg">{{ uiText('craft_ingredients', 'Ingredients') }}</p>
                          <p class="text-[#898888] text-xs">{{ inventory.craftRecipe.requiredItems.map(function(r) { return r.label }).join(', ') }}</p>
                        </div>
                        <div class="w-full h-[4vw] flex gap-1 overflow-x-auto overflow-y-hidden flex-nowrap">
                          <div v-for="req in inventory.craftRecipe.requiredItems" :key="req.name" class="w-[4vw] shrink-0 h-full rounded p-1 relative" style="background-color: rgba(255,138,5,0.06);">
                            <span class="absolute top-0.5 right-1 text-[10px] text-white/40">{{ req.requiredAmount * inventory.craftAmount }}x</span>
                            <span class="absolute top-0.5 left-1 text-[10px] text-white/40">{{ ((req.weight || 0) * req.requiredAmount * inventory.craftAmount).toFixed(2) }}kg</span>
                            <img :src="getItemImage(req.name)" @error="onImgError" class="absolute inset-0 m-auto w-[40%] h-[60%] object-contain">
                            <p class="absolute bottom-0.5 left-0 right-0 text-center text-[10px] text-white/70 truncate px-0.5">{{ req.label }}</p>
                          </div>
                        </div>
                        <div class="w-full h-[2vw] flex justify-between items-center">
                          <div>
                            <p class="text-[#CAA580] text-sm">{{ uiText('craft_process_time', 'Process Time') }}</p>
                            <p class="text-[#898888] text-[0.55vw]">{{ (inventory.craftRecipe.timerForPerAmount / 1000).toFixed(0) }} seconds per one!</p>
                          </div>
                          <div @click="inventory.canCraft ? postNUI('StartCraft', { rewardName: inventory.craftRecipe.rewardName, amount: inventory.craftAmount }) : null" class="h-full px-2 flex justify-center text-xs font-semibold items-center bg-[url(./assets/craft-button-background.png)] cursor-pointer transition-all hover:opacity-70" :style="{ backgroundSize: '100% 100%', opacity: inventory.canCraft && !inventory.craftingInProgress ? 1 : 0.4, pointerEvents: inventory.canCraft && !inventory.craftingInProgress ? 'auto' : 'none' }">
                            {{ inventory.craftingInProgress ? uiText('craft_in_progress', 'Crafting...') : uiText('craft_start', 'Start Crafting') }}
                          </div>
                        </div>
                      </div>
                    </div>
                  </div>
              </div>


              <!-- Second Inventory: clothing -->
              <div v-else-if="inventory.secondInventoryType === 'clothing'" key="clothing" class="w-full h-full flex flex-col justify-between items-center">
                  <div height="9%" class="p-2 flex justify-between items-center h-[9%] w-full bg-[url(./assets/header-background.png)]" style="background-size: 100% 100%;">
                    <p class="text-xl">{{ uiText('clothing_menu', 'Clothing Menu') }}</p>
                    <div class="w-[2vw] h-[2vw]  flex justify-center items-center rounded-md bg-black/10">
                        <img src="./assets/clothing-icon-big.png">
                    </div>
                  </div>
                  <div class="w-full h-[77%] relative">
                      <img src="./assets/character-image.png" class="absolute inset-0 m-auto h-full object-contain">
                      <template v-for="slot in clothingSlots" :key="slot.id">
                        <div
                          class="absolute flex items-center gap-2"
                          :style="{
                            left: slot.x + '%',
                            top: slot.y + '%',
                            transform: `translate(-50%, -50%) rotate(${slot.rotate}deg)`,
                          }"
                        >
                          <img v-if="slot.lineSide === 'left'" src="./assets/clothing-line.png" class="pointer-events-none" style="height: 4px;">
                          <div
                            @click="onClothingClick(slot)"
                            class="w-[2.5vw] h-[2.5vw] shrink-0 relative bg-[url(./assets/clothing-menu-background.png)] flex justify-center items-center transition-all hover:opacity-70 cursor-pointer"
                            style="background-size: 100% 100%;"
                            :style="isClothingWorn(slot) ? { boxShadow: '0 0 0 2px #2fd06c, 0 0 6px rgba(47,208,108,0.6)' } : {}"
                            :title="uiText(slot.key, slot.label) + (isClothingWorn(slot) ? ' - ' + uiText('worn', 'Worn') : '')"
                          >
                            <img :src="getAsset(slot.icon)" :style="{ opacity: isClothingWorn(slot) ? 1 : 0.5 }">
                            <span v-if="isClothingWorn(slot)" class="absolute -top-1 -right-1 w-3 h-3 rounded-full bg-[#2fd06c] flex items-center justify-center text-[8px] text-black font-bold leading-none">&#10003;</span>
                          </div>
                          <img v-if="slot.lineSide === 'right'" src="./assets/clothing-line.png" class="pointer-events-none" style="height: 4px;">
                        </div>
                      </template>
                  </div>
                  <div @click="inventory.secondInventoryType = inventory.secondInventoryType === 'clothing' ? (inventory.invType === 'main' ? 'drop' : 'inventory') : 'clothing'" class="w-full h-[5vh] flex justify-center items-center bg-[url(./assets/close-clothing-menu-background.png)] cursor-pointer transition-all hover:opacity-70" style="background-size: 100% 100%;">
                      {{ uiText('close_clothing_menu', 'CLOSE CLOTHING MENU') }}
                  </div>
              </div>

              <!-- Drop Inventory -->
              <div v-else-if="inventory.secondInventoryType === 'drop'" key="drop" class="w-full h-full flex flex-col justify-between items-center">
                  <div class="p-2 flex justify-between items-center h-[9%] w-full bg-[url(./assets/header-background.png)]" style="background-size: 100% 100%;">
                    <p class="text-xl">{{ uiText('ground', 'Ground') }}{{ inventory.nearbyDropId ? ' - ' + inventory.nearbyDropId : '' }}</p>
                    <div class="w-[2vw] h-[2vw] flex justify-center items-center rounded-md bg-black/10">
                        <img src="./assets/inventory-icon.png">
                    </div>
                  </div>
                  <div class="w-full h-[6vh] flex flex-col items-center justify-center gap-1">
                    <div class="weight-bar">
                      <div class="weight-bar-fill" :style="{ width: (inventory.LuaConfig.DropInventory ? (inventory.dropCurrentWeight / inventory.LuaConfig.DropInventory.MaxWeight * 100) : 0) + '%' }"></div>
                    </div>
                    <div class="w-full flex justify-between items-center">
                        <p class="text-sm text-[#BEB592]">{{ uiText('max_weight', 'Max Weight') }}</p>
                        <p class="text-sm text-[#BEB592]"><span class="font-semibold">{{ inventory.dropCurrentWeight }}</span>/{{ inventory.LuaConfig.DropInventory ? inventory.LuaConfig.DropInventory.MaxWeight : 100 }}{{ inventory.LuaConfig.WeightMeasure || 'kg' }}</p>
                    </div>
                  </div>
                  <div class="w-full h-[80%] grid grid-cols-5 gap-1.5 content-start overflow-y-auto">
                      <div v-for="i in (inventory.LuaConfig.DropInventory ? inventory.LuaConfig.DropInventory.Slots : 25)" :key="i" @mousedown="onDropZoneMouseDown($event, i)" @mouseup="onDropSlotMouseUp(i)" class="aspect-square bg-white/[0.08] rounded transition-all hover:opacity-70 p-1 relative flex flex-col items-center justify-center" :class="{ 'opacity-30': dragFrom === i && dragSource === 'dropzone' }">
                          <template v-if="inventory.getDropZoneItemAtSlot(i)">
                              <span class="absolute top-0.5 right-1 text-[10px] text-white/40">{{ inventory.getDropZoneItemAtSlot(i).amount || 1 }}x</span>
                              <span class="absolute top-0.5 left-1 text-[10px] text-white/40">{{ ((inventory.getDropZoneItemAtSlot(i).weight || 0) * (inventory.getDropZoneItemAtSlot(i).amount || 1)).toFixed(2) }}kg</span>
                              <img :src="getItemImage(inventory.getDropZoneItemAtSlot(i).name)" @error="onImgError" class="absolute inset-0 m-auto max-w-[40%] max-h-[60%] object-contain">
                              <svg v-if="inventory.getDropZoneItemAtSlot(i).type === 'item_weapon' && inventory.getDropZoneItemAtSlot(i).durability != null" class="absolute left-1 top-1/2 -translate-y-1/2" width="12" height="12" viewBox="0 0 36 36">
                                <circle cx="18" cy="18" r="15" fill="none" stroke="rgba(0,0,0,0.3)" stroke-width="4"></circle>
                                <circle cx="18" cy="18" r="15" fill="none" :stroke="getDegradationColor(inventory.getDropZoneItemAtSlot(i).durability)" stroke-width="4" stroke-linecap="round" :stroke-dasharray="(inventory.getDropZoneItemAtSlot(i).durability / 100 * 94.2) + ' 94.2'" transform="rotate(-90 18 18)"></circle>
                              </svg>
                              <p class="absolute bottom-0.5 left-0 right-0 text-center text-[10px] text-white/70 truncate px-0.5">{{ inventory.getDropZoneItemAtSlot(i).label }}</p>
                          </template>
                          <template v-else>
                              <span class="absolute top-0.5 right-1 text-[10px] text-white/40">{{ i }}</span>
                          </template>
                      </div>
                  </div>
              </div>

              </Transition>
          </div>

          <!-- Context Menu: Gun Belt (Ammo) -->
          <Transition name="fade">
            <div v-if="contextMenu.show && contextMenu.item && contextMenu.item.type === 'item_ammo'" class="fixed z-50 w-[17vw] gap-1 p-3 px-5 bg-[url(./assets/context-background.png)] flex flex-col items-center rounded" :style="{ left: contextMenu.x + 'px', top: contextMenu.y + 'px' }" @click.stop style="background-size: 100% 100%;">
                <div class="w-full flex justify-between items-center">
                    <p>{{ contextMenu.item.label }}</p>
                    <div class="w-[1.75vw] h-[1.75vw] rounded-md bg-black/10 flex justify-center items-center">
                      <img src="./assets/hand-icon.png">
                    </div>
                </div>
                <div class="w-full h-px bg-black/20"></div>
                <p class="text-xs text-[#4E4D4D] w-full">{{ contextMenu.item.desc }}</p>
                <div class="w-full h-px bg-black/20"></div>
                <div class="w-full flex flex-col gap-1 max-h-[30vh] overflow-y-auto">
                  <template v-if="getAmmoList().length > 0">
                    <div v-for="a in getAmmoList()" :key="a.key" @click="onAmmoClick(a.key, a.label)" class="w-full flex justify-between items-center p-2 cursor-pointer transition-all hover:opacity-70 bg-[url(./assets/settings-item-background.png)]" style="background-size: 100% 100%;">
                      <p class="text-xs text-black">{{ a.label }}</p>
                      <p class="text-xs text-black">{{ a.count }}</p>
                    </div>
                  </template>
                  <div v-else class="w-full flex justify-center items-center p-2 bg-[url(./assets/settings-item-background.png)]" style="background-size: 100% 100%;">
                    <p class="text-xs text-[#565353]">{{ uiText('empty', 'Empty') }}</p>
                  </div>
                </div>
            </div>
          </Transition>

          <!-- Context Menu: Normal Items -->
          <Transition name="fade">
            <div v-if="contextMenu.show && contextMenu.item && contextMenu.item.type !== 'item_ammo'" class="fixed z-50 w-[17vw] gap-1 p-3 px-5 bg-[url(./assets/context-background.png)] flex flex-col items-center rounded" :style="{ left: contextMenu.x + 'px', top: contextMenu.y + 'px' }" @click.stop style="background-size: 100% 100%;">
                <!-- Header -->
                <div class="w-full flex justify-between items-center">
                    <p>{{ contextMenu.item.metadata?.label || contextMenu.item.custom_label || contextMenu.item.label }}</p>
                    <div class="w-[1.75vw] h-[1.75vw] rounded-md bg-black/10 flex justify-center items-center">
                      <img src="./assets/hand-icon.png">
                    </div>
                </div>
                <div class="w-full h-px bg-black/20"></div>
                <!-- Basic Info -->
                <div class="w-full flex flex-col gap-1">
                  <div class="w-full flex justify-between items-center">
                      <div class="gap-1 flex">
                        <img src="./assets/name-icon.png">
                        <p class="text-[#4E4D4D]">{{ uiText('item_label', 'Item Label') }}</p>
                      </div>
                      <p>{{ contextMenu.item.metadata?.label || contextMenu.item.custom_label || contextMenu.item.label }}</p>
                  </div>
                  <div class="w-full flex justify-between items-center">
                      <div class="gap-1 flex items-center">
                        <img src="./assets/weight-icon.png">
                        <p class="text-[#4E4D4D]">{{ uiText('item_weight', 'Item Weight') }}</p>
                      </div>
                      <p>{{ (contextMenu.item.metadata?.weight || contextMenu.item.weight || 0) }}{{ inventory.LuaConfig.WeightMeasure || 'kg' }}</p>
                  </div>
                </div>
                <!-- Item Info (metadata / weapon fields) -->
                <div v-if="hasItemInfo(contextMenu.item)" class="w-full flex flex-col mt-4 gap-1">
                    <p>{{ uiText('item_info', 'Item Info') }}</p>
                    <div class="w-full h-px bg-black/20"></div>
                    <div v-if="contextMenu.item.serial_number" class="w-full flex justify-between items-center">
                      <p>{{ uiText('serial_number', 'Serial Number') }}</p>
                      <p @click="copySerial(contextMenu.item.serial_number)"
                         class="text-[#565353] cursor-pointer hover:text-[#BEB592] transition-all select-none"
                         :title="uiText('copyserial', 'Click to copy serial number')">
                        {{ copiedSerial ? uiText('copied', 'Copied!') : contextMenu.item.serial_number }}
                      </p>
                    </div>
                    <div v-if="contextMenu.item.maxDegradation > 0" class="w-full flex justify-between items-center">
                      <p>{{ uiText('durability', 'Durability') }}</p>
                      <p :style="{ color: getDegradationColor(getDegradation(contextMenu.item)) }">{{ getDegradation(contextMenu.item).toFixed(0) }}%</p>
                    </div>
                    <div v-if="contextMenu.item.type === 'item_weapon' && contextMenu.item.durability != null" class="w-full flex justify-between items-center">
                      <p>{{ uiText('durability', 'Durability') }}</p>
                      <p :style="{ color: getDegradationColor(contextMenu.item.durability) }">{{ contextMenu.item.durability.toFixed(1) }}%</p>
                    </div>
                    <template v-if="contextMenu.item.metadata">
                      <template v-for="(value, key) in contextMenu.item.metadata" :key="key">
                        <div v-if="!isReservedMeta(key)" class="w-full flex justify-between items-center">
                          <p>{{ key }}</p>
                          <p class="text-[#565353]">{{ value }}</p>
                        </div>
                      </template>
                    </template>
                </div>
                <!-- Description -->
                <div v-if="getItemDesc(contextMenu.item)" class="mt-4 w-full flex flex-col gap-1">
                  <div class="w-full flex justify-between items-center">
                      <p>{{ uiText('description', 'Description') }}</p>
                      <div class="w-[1.75vw] h-[1.75vw] rounded-md bg-black/10 flex justify-center items-center">
                        <img src="./assets/description-icon.png">
                      </div>
                  </div>
                  <div class="w-full h-px bg-black/20"></div>
                  <p class="text-xs text-[#565353]">{{ getItemDesc(contextMenu.item) }}</p>
                </div>
                <!-- Weapon Components -->
                <div v-if="getWeaponComponents(contextMenu.item).length > 0" class="mt-4 w-full flex flex-col gap-1">
                  <p>{{ uiText('components', 'Components') }}</p>
                  <div class="w-full h-px bg-black/20"></div>
                  <div v-for="(c, ci) in getWeaponComponents(contextMenu.item)" :key="ci" class="w-full flex justify-between items-center">
                    <p class="text-xs text-[#4E4D4D]">{{ c.type || c.comp }}</p>
                    <p class="text-xs text-[#565353]">{{ c.label }}</p>
                  </div>
                </div>
                <!-- Action buttons (Use / Give) — only shown when ContextMenuActions.Enabled -->
                <div v-if="isContextMenuActionsEnabled()" class="mt-4 w-full flex gap-2">
                  <div v-if="canUseItem(contextMenu.item)"
                       @click="onContextUse(contextMenu.item)"
                       class="flex-1 h-[4vh] flex justify-center items-center cursor-pointer transition-all hover:opacity-80 bg-[url(./assets/buttons-background.png)]"
                       style="background-size: 100% 100%;">
                    <p class="text-sm text-[#BEB592]">{{ uiText('use', 'Use') }}</p>
                  </div>
                  <div v-if="canGiveItem(contextMenu.item)"
                       @click="onContextGive(contextMenu.item)"
                       class="flex-1 h-[4vh] flex justify-center items-center cursor-pointer transition-all hover:opacity-80 bg-[url(./assets/buttons-background.png)]"
                       style="background-size: 100% 100%;">
                    <p class="text-sm text-[#BEB592]">{{ uiText('give', 'Give') }}</p>
                  </div>
                </div>
            </div>
          </Transition>

          <!-- Ammo Amount Prompt -->
          <Transition name="fade">
            <div v-if="ammoPrompt.show" class="fixed inset-0 z-50 flex items-center justify-center" @click.self="ammoPrompt.show = false">
              <div class="w-[17vw] bg-[url(./assets/context-background.png)] p-3 px-5 rounded flex flex-col gap-2 items-center" style="background-size: 100% 100%;" @click.stop>
                <div class="w-full flex justify-between items-center">
                  <p>{{ ammoPrompt.ammoLabel }}</p>
                  <div class="w-[1.75vw] h-[1.75vw] rounded-md bg-black/10 flex justify-center items-center">
                    <img src="./assets/hand-icon.png">
                  </div>
                </div>
                <div class="w-full h-px bg-black/20"></div>
                <div class="w-full flex flex-col gap-2 mt-1">
                  <div class="w-full h-[2.5vw] bg-[url(./assets/amount-background.png)] flex justify-center items-center" style="background-size: 100% 100%;">
                    <input type="number" v-model.number="ammoPrompt.amount" min="1" class="w-full h-full text-center text-xl text-[#BEB592]" placeholder="1" @keyup.enter="onAmmoPromptConfirm">
                  </div>
                  <div class="w-full flex gap-2">
                    <div @click="ammoPrompt.show = false" class="flex-1 h-[2.2vw] flex justify-center items-center cursor-pointer transition-all hover:opacity-70 bg-[url(./assets/buttons-background.png)]" style="background-size: 100% 100%;">
                      <p class="text-sm text-[#BEB592]">{{ uiText('cancel', 'Cancel') }}</p>
                    </div>
                    <div @click="onAmmoPromptConfirm" class="flex-1 h-[2.2vw] flex justify-center items-center cursor-pointer transition-all hover:opacity-70 bg-[url(./assets/buttons-background.png)]" style="background-size: 100% 100%;">
                      <p class="text-sm text-[#BEB592]">{{ uiText('confirm', 'Confirm') }}</p>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </Transition>

          <!-- Player Select Modal -->
          <Transition name="fade">
            <div v-if="inventory.showPlayerSelect" class="fixed inset-0 z-50 flex items-center justify-center" @click.self="onPlayerSelectClose">
              <div class="w-[17vw] bg-[url(./assets/context-background.png)] p-3 px-5 rounded flex flex-col gap-2 items-center" style="background-size: 100% 100%;" @click.stop>
                <div class="w-full flex justify-between items-center">
                  <p>{{ uiText('select_player', 'Select Player') }}</p>
                  <div class="w-[1.75vw] h-[1.75vw] rounded-md bg-black/10 flex justify-center items-center">
                    <img src="./assets/user-icon.png">
                  </div>
                </div>
                <div class="w-full h-px bg-black/20"></div>
                <div class="w-full flex flex-col gap-1 max-h-[30vh] overflow-y-auto">
                  <div v-for="p in inventory.nearPlayersList" :key="p.player" @click="onPlayerSelect(p.player)" class="w-full flex justify-between items-center p-2 cursor-pointer transition-all hover:opacity-70 bg-[url(./assets/settings-item-background.png)]" style="background-size: 100% 100%;">
                    <div class="flex items-center gap-2">
                      <div class="w-[1.75vw] h-[1.75vw] rounded-md bg-black/10 flex justify-center items-center">
                        <img src="./assets/user-icon.png">
                      </div>
                      <p>{{ p.label }}</p>
                    </div>
                    <p class="text-xs text-[#4E4D4D]">ID: {{ p.player }}</p>
                  </div>
                </div>
                <div @click="onPlayerSelectClose" class="w-full h-[2.2vw] flex justify-center items-center cursor-pointer transition-all hover:opacity-70 bg-[url(./assets/buttons-background.png)] mt-1" style="background-size: 100% 100%;">
                  <p class="text-sm text-[#BEB592]">{{ uiText('cancel', 'Cancel') }}</p>
                </div>
              </div>
            </div>
          </Transition>
      </div>
      </Transition>

      <!-- Weapon Registry Station -->
      <Transition name="fade">
        <div v-if="inventory.registryOpen" class="fixed inset-0 z-[60] flex items-center justify-center" @click.self="registryClose">
          <div class="w-[42vw] h-[80vh] bg-[url(./assets/context-background.png)] p-5 rounded flex flex-col gap-3 overflow-hidden" style="background-size: 100% 100%;" @click.stop>
            <!-- header -->
            <div class="w-full flex justify-between items-center">
              <p class="text-xl">{{ uiText('weapon_registry', 'Weapon Registry') }}</p>
              <div @click="registryClose" class="w-[1.75vw] h-[1.75vw] rounded-md bg-black/10 flex justify-center items-center cursor-pointer hover:opacity-70">
                <img src="./assets/close-icon.png">
              </div>
            </div>
            <div class="w-full h-px bg-black/20"></div>

            <!-- Serial search -->
            <div class="w-full flex flex-col gap-1">
              <p class="text-sm font-semibold text-[#2b2118]">{{ uiText('check_serial', 'Check a Serial Number') }}</p>
              <div class="w-full flex gap-2">
                <input v-model="registrySearchInput" @keyup.enter="registrySearch" type="text" :placeholder="uiText('serial_number', 'Serial Number')" class="flex-1 h-[2.2vw] px-2 text-[#000000] bg-[url(./assets/search-background.png)]" style="background-size: 100% 100%;">
                <div @click="registrySearch" class="h-[2.2vw] px-4 flex justify-center items-center cursor-pointer transition-all hover:opacity-70 bg-[url(./assets/buttons-background.png)]" style="background-size: 100% 100%;">
                  <p class="text-sm text-[#BEB592]">{{ uiText('search', 'Search') }}</p>
                </div>
              </div>
              <div v-if="inventory.registrySearchResult !== undefined" class="w-full p-2 bg-[url(./assets/settings-item-background.png)] text-xs" style="background-size: 100% 100%;">
                <template v-if="inventory.registrySearchResult">
                  <p class="text-black">{{ uiText('serial_number', 'Serial') }}: {{ inventory.registrySearchResult.serial }}</p>
                  <p class="text-black">{{ inventory.registrySearchResult.weapon_name }}</p>
                  <p class="text-[#2a6e3f] font-semibold">{{ uiText('registered_to', 'Registered to') }}: {{ inventory.registrySearchResult.owner_name }}</p>
                  <p class="text-[#565353]">{{ uiText('registered_by', 'Registered by') }}: {{ inventory.registrySearchResult.registered_by }}</p>
                </template>
                <p v-else class="text-[#935b5b]">{{ uiText('serial_not_registered', 'That serial number is not registered.') }}</p>
              </div>
            </div>
            <div class="w-full h-px bg-black/20"></div>

            <!-- Nearby players -->
            <div class="w-full flex justify-between items-center">
              <p class="text-sm font-semibold text-[#2b2118]">{{ uiText('nearby_players', 'Nearby Players') }}</p>
              <div @click="registryRefresh" class="px-3 h-[1.9vw] flex items-center cursor-pointer transition-all hover:opacity-70 bg-[url(./assets/buttons-background.png)]" style="background-size: 100% 100%;">
                <p class="text-xs text-[#BEB592]">{{ uiText('refresh', 'Refresh') }}</p>
              </div>
            </div>
            <div class="w-full flex-1 min-h-0 overflow-y-auto flex flex-col gap-2">
              <template v-if="inventory.registryPlayers.length > 0">
                <div v-for="p in inventory.registryPlayers" :key="p.serverId" class="w-full flex flex-col gap-1 p-2 bg-black/[0.05] rounded">
                  <div @click="toggleRegistryPlayer(p.serverId)" class="w-full flex justify-between items-center cursor-pointer hover:opacity-70">
                    <p class="text-sm font-semibold text-[#2b2118]">{{ p.name }} <span class="text-[#5a534a] font-normal">(ID {{ p.serverId }})</span></p>
                    <p class="text-xs text-[#5a534a] flex items-center gap-2">
                      <span>{{ (p.weapons ? p.weapons.length : 0) }} {{ uiText('weapons', 'weapons') }}</span>
                      <span class="text-sm font-bold text-[#2b2118] w-3 text-center">{{ isRegistryExpanded(p.serverId) ? '-' : '+' }}</span>
                    </p>
                  </div>
                  <template v-if="isRegistryExpanded(p.serverId)">
                    <template v-if="p.weapons && p.weapons.length > 0">
                      <div v-for="w in p.weapons" :key="w.id" class="w-full flex justify-between items-center p-2 bg-[url(./assets/settings-item-background.png)]" style="background-size: 100% 100%;">
                        <div class="flex flex-col">
                          <p class="text-xs text-black">{{ w.label }}</p>
                          <p class="text-[10px] text-[#565353]">{{ uiText('serial_number', 'Serial') }}: {{ w.serial || uiText('no_serial', 'none') }}</p>
                          <p v-if="w.registeredTo" class="text-[10px] text-[#2a6e3f] font-semibold">{{ uiText('registered_to', 'Registered to') }}: {{ w.registeredTo }}</p>
                          <p v-else class="text-[10px] text-[#935b5b]">{{ uiText('unregistered', 'Unregistered') }}</p>
                        </div>
                        <div v-if="w.serial && !w.registeredTo" @click="registryRegister(w.id, p.serverId)" class="px-3 h-[2vw] flex items-center cursor-pointer transition-all hover:opacity-70 bg-[url(./assets/buttons-background.png)]" style="background-size: 100% 100%;">
                          <p class="text-xs text-[#BEB592]">{{ uiText('register', 'Register') }}</p>
                        </div>
                        <div v-else-if="w.serial && w.registeredTo" class="px-3 h-[2vw] flex items-center bg-[url(./assets/buttons-background.png)] opacity-60" style="background-size: 100% 100%;">
                          <p class="text-xs text-[#BEB592]">{{ uiText('registered', 'Registered') }}</p>
                        </div>
                      </div>
                    </template>
                    <p v-else class="text-[10px] text-[#565353] pl-1">{{ uiText('no_weapons', 'No weapons on this player') }}</p>
                  </template>
                </div>
              </template>
              <p v-else class="text-xs text-[#565353] text-center p-4">{{ uiText('no_players_nearby', 'No players nearby') }}</p>
            </div>

            <div @click="registryClose" class="w-full h-[2.2vw] flex justify-center items-center cursor-pointer transition-all hover:opacity-70 bg-[url(./assets/buttons-background.png)]" style="background-size: 100% 100%;">
              <p class="text-sm text-[#BEB592]">{{ uiText('close', 'Close') }}</p>
            </div>
          </div>
        </div>
      </Transition>

      <Transition name="fade">
      <div v-if="inventory.showHotbar" class="w-full flex justify-center items-center h-[14%] mt-auto" >
          <div class="w-[32%] h-full bg-[url(./assets/hotbar-background.png)] flex justify-center items-center" style="background-size: 100% 100%;">
            <div class="grid grid-cols-5 gap-1.5 p-3 h-full w-full place-items-center">
              <div v-for="i in 5" :key="i" class="aspect-square h-[calc(100%-4px)] bg-white/[0.08] rounded transition-all hover:opacity-70 p-1 relative flex flex-col items-center justify-center">
                  <template v-if="inventory.getItemAtSlot(i)">
                      <span class="absolute top-0.5 right-1 text-[10px] text-white/40">{{ slotCount(inventory.getItemAtSlot(i)) }}</span>
                      <span class="absolute top-0.5 left-1 text-[10px] text-white/40">{{ slotWeight(inventory.getItemAtSlot(i)) }}kg</span>
                      <img :src="getItemImage(inventory.getItemAtSlot(i).name)" @error="onImgError" class="absolute inset-0 m-auto max-w-[40%] max-h-[60%] object-contain">
                      <svg v-if="inventory.getItemAtSlot(i).type === 'item_weapon' && inventory.getItemAtSlot(i).durability != null" class="absolute left-1 top-1/2 -translate-y-1/2" width="10" height="10" viewBox="0 0 36 36">
                        <circle cx="18" cy="18" r="15" fill="none" stroke="rgba(0,0,0,0.3)" stroke-width="4"></circle>
                        <circle cx="18" cy="18" r="15" fill="none" :stroke="getDegradationColor(inventory.getItemAtSlot(i).durability)" stroke-width="4" stroke-linecap="round" :stroke-dasharray="(inventory.getItemAtSlot(i).durability / 100 * 94.2) + ' 94.2'" transform="rotate(-90 18 18)"></circle>
                      </svg>
                      <span v-if="isEquippedWeapon(inventory.getItemAtSlot(i))" class="absolute left-1 text-[10px] font-semibold leading-none text-[#2fd06c] pointer-events-none" style="top: calc(50% - 19px); text-shadow: 0 1px 2px rgba(0,0,0,0.65);">E</span>
                      <p class="absolute bottom-0.5 left-0 right-0 text-center text-[10px] text-white/70 truncate px-0.5">{{ inventory.getItemAtSlot(i).label }}</p>
                  </template>
                  <template v-else>
                      <span class="absolute top-0.5 right-1 text-[10px] text-white/40">{{ i }}</span>
                  </template>
              </div>
            </div>
          </div>
      </div>
      </Transition>

      <div class="fixed bottom-20 left-0 right-0 flex justify-center gap-1.5 items-end pointer-events-none z-[5]">
          <TransitionGroup name="notif">
            <div
              v-for="n in inventory.itemNotifications"
              :key="n.id"
              class="w-[5vw] h-[5vw] rounded p-1 relative flex flex-col items-center justify-center"
              :style="{ backgroundColor: n.type === 'remove' ? 'rgba(147, 91, 91, 0.38)' : n.type === 'used' ? 'rgba(100, 149, 237, 0.38)' : 'rgba(156, 178, 83, 0.38)' }"
            >
              <span class="absolute top-0.5 right-1 text-[8px] text-white/40">{{ n.count }}x</span>
              <span class="absolute top-0.5 left-0.5 text-[7px] text-white/40">{{ n.type === 'remove' ? uiText('notif_removed', 'Removed') : n.type === 'used' ? uiText('notif_used', 'Used') : uiText('notif_added', 'Added') }}</span>
              <img :src="getItemImage(n.name)" @error="onImgError" class="absolute inset-0 m-auto w-[40%] h-[60%] object-contain">
              <p class="absolute bottom-0.5 left-0 right-0 text-center text-[7px] text-white/70 truncate px-0.5">{{ n.label }}</p>
            </div>
          </TransitionGroup>
      </div>


  </div>
</template>
