import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import { postNUI } from '../utils/nui'

function assignSlots(itemList) {
  var usedSlots = {}
  var result = []
  var deferred = []

  // Pass 1: locked/virtual items (money, gold, gunbelt) own their fixed slots.
  for (var i = 0; i < itemList.length; i++) {
    var it = itemList[i]
    if (it.locked && it.slot != null && !usedSlots[it.slot]) {
      usedSlots[it.slot] = true
      result.push(Object.assign({}, it))
    }
  }
  // Pass 2: keep items whose slot is free; defer slot collisions and slotless items.
  // This prevents two items sharing a slot, which would hide one in the slot map.
  for (var i = 0; i < itemList.length; i++) {
    var it = itemList[i]
    if (it.locked && it.slot != null) continue
    if (it.slot != null && !usedSlots[it.slot]) {
      usedSlots[it.slot] = true
      result.push(Object.assign({}, it))
    } else {
      deferred.push(it)
    }
  }
  // Pass 3: assign the next free slot to every deferred item.
  var nextSlot = 1
  for (var i = 0; i < deferred.length; i++) {
    while (usedSlots[nextSlot]) nextSlot++
    var copy = Object.assign({}, deferred[i])
    copy.slot = nextSlot
    usedSlots[nextSlot] = true
    result.push(copy)
  }
  return result
}

function normalizedMetadata(item) {
  var metadata = item && item.metadata ? item.metadata : {}
  var keys = Object.keys(metadata).sort()
  var normalized = {}
  for (var i = 0; i < keys.length; i++) {
    normalized[keys[i]] = metadata[keys[i]]
  }
  return JSON.stringify(normalized)
}

function canStackItems(a, b) {
  if (!a || !b) return false
  if (a.name !== b.name || a.type === 'item_weapon' || b.type === 'item_weapon') return false
  if (normalizedMetadata(a) !== normalizedMetadata(b)) return false

  var aMax = Number(a.maxDegradation) || 0
  var bMax = Number(b.maxDegradation) || 0
  if (aMax !== bMax) return false
  if (aMax > 0) {
    return Number(a.percentage) === Number(b.percentage) && Number(a.degradation) === Number(b.degradation)
  }
  return true
}

function isEquippedWeapon(item) {
  return item && item.type === 'item_weapon' && (item.used || item.used2)
}

export const useInventoryStore = defineStore('inventory', () => {
  const items = ref([])
  const playerInventory = ref([])
  const secondInventory = ref([])
  const craftInventory = ref([])
  const craftRecipe = ref(null)
  const craftAmount = ref(1)
  const craftingInProgress = ref(false)
  const craftProgress = ref(0)
  const craftTimer = ref(0)
  var craftTimerInterval = null
  const secondInventoryType = ref('inventory')
  const isVisible = ref(false)
  const showHotbar = ref(false)
  const itemNotifications = ref([])
  var notifIdCounter = 0
  const dropZoneItems = ref([])
  const hasNearbyDrops = ref(false)
  const nearbyDropId = ref(null)

  // NUI state
  const invType = ref('main')
  const customId = ref(0)
  const horseid = ref(0)
  const wagonid = ref(0)
  const houseId = ref(0)
  const hideoutId = ref(0)
  const bankId = ref(0)
  const clanid = ref(0)
  const stealid = ref(0)
  const Containerid = ref(0)
  const StoreId = ref(0)
  const playerId = ref(0)
  const geninfo = ref(null)
  const secondTitle = ref('')
  const secondCapacity = ref(0)
  const secondWeight = ref(null)

  // Shop system
  const shopState = ref(null)        // full payload from server: { id, name, role, items, balance, ... }
  const shopId = ref(null)
  const shopView = ref('shopping')   // 'shopping' | 'owner'
  const shopOwnerTab = ref('stock')  // 'stock' | 'prices' | 'employees' | 'hours' | 'balance'

  // HUD data
  const money = ref(0)
  const gold = ref(0)
  const rol = ref(0)
  const charId = ref(0)
  const charName = ref('')
  const currentWeight = ref(0)
  const maxWeight = ref(0)

  // Config & Language from Lua
  const LANGUAGE = ref({})
  const LuaConfig = ref({})
  const TIME_NOW = ref(0)
  const allplayerammo = ref([])
  const ammolabels = ref([])

  // Give / Near players
  const nearPlayersList = ref([])
  const pendingGiveData = ref(null)
  const showPlayerSelect = ref(false)

  // Worn clothing: { hat: true, shirt: true, ... } keyed by clothing slot key.
  // Fed by exports.vorp_inventory:setWornClothing(table) from a clothing resource.
  const wornClothing = ref({})

  // Remembered transfer amounts per item name (QoL: pre-fill the amount input
  // with the value the player last used for the same item).
  const lastTransferAmounts = ref({})
  function rememberAmount(itemName, amount) {
    if (!itemName) return
    var n = Number(amount)
    if (!n || n <= 0) return
    lastTransferAmounts.value[itemName] = n
  }
  function recallAmount(itemName) {
    if (!itemName) return null
    var v = lastTransferAmounts.value[itemName]
    return v != null ? v : null
  }

  // Weapon registry station UI
  const registryOpen = ref(false)
  const registryPlayers = ref([])
  const registrySearchResult = ref(undefined) // undefined = no search, false = not found, object = found
  const registrySearchedSerial = ref('')


  function setItems(newItems) {
    items.value = newItems
  }

  function setPlayerInventory(inventory) {
    playerInventory.value = inventory
  }

  function setSecondInventory(inventory) {
    secondInventory.value = inventory
  }

  function setCraftInventory(inventory) {
    craftInventory.value = inventory
  }

  function show() {
    isVisible.value = true
  }

  function hide() {
    if (invType.value === 'shop') {
      postNUI('ShopClose', { shopId: shopId.value })
      shopState.value = null
      shopId.value = null
      shopView.value = 'shopping'
    }
    isVisible.value = false
    invType.value = 'main'
    postNUI('NUIFocusOff', {})
  }

  // NUI message handler
  function handleNUIMessage(data) {
    switch (data.action) {
      case 'initiate':
        LANGUAGE.value = data.language || {}
        LuaConfig.value = data.config || {}
        break


      case 'display':
        invType.value = data.type || 'main'

        if (data.type === 'player') playerId.value = data.id
        if (data.type === 'custom') { customId.value = data.id; secondWeight.value = data.weight || null }
        if (data.type === 'horse') horseid.value = data.horseid
        if (data.type === 'cart') wagonid.value = data.wagonid
        if (data.type === 'house') houseId.value = data.houseId
        if (data.type === 'hideout') hideoutId.value = data.hideoutId
        if (data.type === 'bank') bankId.value = data.bankId
        if (data.type === 'clan') clanid.value = data.clanid
        if (data.type === 'store') { StoreId.value = data.StoreId; geninfo.value = data.geninfo }
        if (data.type === 'steal') { stealid.value = data.stealId; secondWeight.value = data.weight || null }
        if (data.type === 'Container') Containerid.value = data.Containerid
        if (data.type === 'shop') {
          shopId.value = data.id
          shopView.value = 'shopping'
        }

        if (data.type === 'main') {
          secondInventoryType.value = 'drop'
        } else if (data.type === 'shop') {
          secondTitle.value = data.title || ''
          secondCapacity.value = data.capacity || 0
          secondInventoryType.value = 'shop'
        } else {
          secondTitle.value = data.title || ''
          secondCapacity.value = data.capacity || 0
          secondInventoryType.value = 'inventory'
        }

        isVisible.value = true
        break

      case 'setShopState':
        shopState.value = data.shop || null
        if (data.shop) {
          shopId.value = data.shop.id
          if (data.shop.name) secondTitle.value = data.shop.name
          if (data.shop.capacity) secondCapacity.value = data.shop.capacity
          // If the player loses owner role mid-session, snap back to shopping view.
          if (shopView.value === 'owner' && data.shop.role === 'customer') {
            shopView.value = 'shopping'
          }
        }
        break

      case 'hide':
        isVisible.value = false
        invType.value = 'main'
        break

      case 'setItems':
        TIME_NOW.value = data.timenow
        var items = data.itemList || []
        // Add virtual items at last slots (dynamically based on PlayerInventorySlots)
        var totalSlots = LuaConfig.value.PlayerInventorySlots || 25
        if (LuaConfig.value.AddAmmoItem) {
          items.push({ name: 'gunbelt', label: LANGUAGE.value.gunbeltlabel || 'Gun Belt', desc: LANGUAGE.value.gunbeltdescription || 'Your Ammo', count: 1, type: 'item_ammo', weight: 0, group: 1, canRemove: false, canUse: false, slot: totalSlots - 2, locked: true })
        }
        if (LuaConfig.value.AddDollarItem) {
          items.push({ name: 'money', label: LANGUAGE.value.inventorymoneylabel || 'Money', count: money.value || 0, type: 'item_money', weight: 0, group: 1, canRemove: true, canUse: false, slot: totalSlots - 1, locked: true })
        }
        if (LuaConfig.value.AddGoldItem) {
          items.push({ name: 'gold', label: LANGUAGE.value.inventorygoldlabel || 'Gold', count: gold.value || 0, type: 'item_gold', weight: 0, group: 1, canRemove: true, canUse: false, slot: totalSlots, locked: true })
        }
        playerInventory.value = assignSlots(items)
        break

      case 'setSecondInventoryItems':
        secondInventory.value = assignSlots(data.itemList || [])
        break

      case 'updateStatusHud':
        if (data.money != null) {
          money.value = data.money
          // Update virtual money item in inventory
          for (var mi = 0; mi < playerInventory.value.length; mi++) {
            if (playerInventory.value[mi].type === 'item_money') {
              playerInventory.value[mi].count = data.money
              break
            }
          }
        }
        if (data.gold != null) {
          gold.value = data.gold
          for (var gi = 0; gi < playerInventory.value.length; gi++) {
            if (playerInventory.value[gi].type === 'item_gold') {
              playerInventory.value[gi].count = data.gold
              break
            }
          }
        }
        if (data.rol != null) rol.value = data.rol
        if (data.id != null) charId.value = data.id
        if (data.charName) charName.value = data.charName
        break

      case 'changecheck':
        currentWeight.value = data.check
        maxWeight.value = data.info
        break

      case 'updateammo':
        if (data.ammo) allplayerammo.value = data.ammo
        break

      case 'reclabels':
        if (data.labels) ammolabels.value = data.labels
        break

      case 'openCraft':
        secondInventoryType.value = 'craft'
        break

      case 'setCraftItems':
        craftInventory.value = data.items || []
        craftRecipe.value = data.recipe || null
        break

      case 'craftStarted':
        craftingInProgress.value = true
        craftTimer.value = data.timer || 0
        var startTime = Date.now()
        var totalTime = data.timer
        if (craftTimerInterval) clearInterval(craftTimerInterval)
        craftTimerInterval = setInterval(function() {
          var elapsed = Date.now() - startTime
          craftProgress.value = Math.min(100, (elapsed / totalTime) * 100)
          if (elapsed >= totalTime) {
            clearInterval(craftTimerInterval)
            craftTimerInterval = null
          }
        }, 100)
        break

      case 'craftCompleted':
        craftingInProgress.value = false
        craftProgress.value = 0
        if (craftTimerInterval) { clearInterval(craftTimerInterval); craftTimerInterval = null }
        break

      case 'cacheImages':
        // Preload images silently
        if (data.info && Array.isArray(data.info)) {
          data.info.forEach(src => {
            const img = new Image()
            img.src = src
          })
        }
        break

      case 'transaction':
        // TODO: loading indicator
        break

      case 'nearPlayers':
        nearPlayersList.value = data.players || []
        pendingGiveData.value = { item: data.item, type: data.type, count: data.count, id: data.id || 0 }
        showPlayerSelect.value = true
        break

      case 'itemNotification':
        addNotification(data.type, data.name, data.label, data.count)
        break


      case 'setDropZoneItems':
        dropZoneItems.value = data.items || []
        hasNearbyDrops.value = data.hasNearbyDrops || false
        nearbyDropId.value = data.dropId || null
        break

      case 'setHotbarItems':
        TIME_NOW.value = data.timenow
        playerInventory.value = assignSlots(data.itemList || [])
        break

      case 'toggleHotbar':
        showHotbar.value = !showHotbar.value
        break

      case 'setWornClothing':
        wornClothing.value = data.worn || {}
        break

      case 'openWeaponRegistry':
        registryPlayers.value = data.players || []
        registrySearchResult.value = undefined
        registrySearchedSerial.value = ''
        registryOpen.value = true
        break

      case 'weaponRegistryData':
        registryPlayers.value = data.players || []
        break

      case 'weaponRegistrySearchResult':
        registrySearchedSerial.value = data.serial || ''
        registrySearchResult.value = data.result || false
        break

      case 'closeWeaponRegistry':
        registryOpen.value = false
        break
    }
  }

  function addNotification(type, name, label, count) {
    var id = ++notifIdCounter
    itemNotifications.value.push({ id: id, type: type, name: name, label: label, count: count })
    // Duration from settings store (imported dynamically to avoid circular dep)
    var duration = 3000
    try {
      var settingsRaw = localStorage.getItem('vorp_inventory_settings')
      if (settingsRaw) {
        var s = JSON.parse(settingsRaw)
        if (s.notificationDuration) duration = s.notificationDuration
      }
    } catch(e) {}
    setTimeout(function() {
      var idx = -1
      for (var i = 0; i < itemNotifications.value.length; i++) {
        if (itemNotifications.value[i].id === id) { idx = i; break }
      }
      if (idx !== -1) itemNotifications.value.splice(idx, 1)
    }, duration)
  }

  const secondCurrentCount = computed(function() {
    var total = 0
    var weighted = !!secondWeight.value
    for (var i = 0; i < secondInventory.value.length; i++) {
      var it = secondInventory.value[i]
      if (weighted) {
        total = total + ((it.weight || 0) * (it.count || 1))
      } else {
        total = total + (it.count || 1)
      }
    }
    return weighted ? parseFloat(total.toFixed(2)) : total
  })

  const dropCurrentWeight = computed(function() {
    var total = 0
    for (var i = 0; i < dropZoneItems.value.length; i++) {
      var item = dropZoneItems.value[i]
      total = total + ((item.weight || 0) * (item.amount || 1))
    }
    return parseFloat(total.toFixed(2))
  })

  const slotMap = computed(() => {
    const map = {}
    for (const item of playerInventory.value) {
      map[item.slot] = item
    }
    return map
  })

  const craftSlotMap = computed(() => {
    const map = {}
    for (const item of craftInventory.value) {
      map[item.slot] = item
    }
    return map
  })

  const canCraft = computed(function() {
    if (!craftRecipe.value || craftingInProgress.value) return false
    var recipe = craftRecipe.value
    if (!recipe.requiredItems) return false
    for (var r = 0; r < recipe.requiredItems.length; r++) {
      var req = recipe.requiredItems[r]
      var found = 0
      for (var i = 0; i < craftInventory.value.length; i++) {
        if (craftInventory.value[i].name === req.name) {
          found = found + craftInventory.value[i].count
        }
      }
      if (found < req.requiredAmount * craftAmount.value) return false
    }
    return true
  })

  const secondSlotMap = computed(() => {
    const map = {}
    for (const item of secondInventory.value) {
      map[item.slot] = item
    }
    return map
  })

  function getItemAtSlot(slot) {
    return slotMap.value[slot] || null
  }

  function getSecondItemAtSlot(slot) {
    return secondSlotMap.value[slot] || null
  }

  function getCraftItemAtSlot(slot) {
    return craftSlotMap.value[slot] || null
  }

  const dropZoneSlotMap = computed(function() {
    var map = {}
    for (var i = 0; i < dropZoneItems.value.length; i++) {
      map[dropZoneItems.value[i].slot] = dropZoneItems.value[i]
    }
    return map
  })

  function getDropZoneItemAtSlot(slot) {
    return dropZoneSlotMap.value[slot] || null
  }

  function swapSecondSlots(fromSlot, toSlot, amount) {
    var fromItem = getSecondItemAtSlot(fromSlot)
    var toItem = getSecondItemAtSlot(toSlot)
    if (!fromItem) return

    var moveAmount = amount || fromItem.count
    if (moveAmount > fromItem.count) moveAmount = fromItem.count
    if (moveAmount < 1) moveAmount = 1

    // Get custom inventory id
    var iId = customId.value

    if (fromItem.type === 'item_weapon') {
      postNUI('SecondSwapSlot', { invId: iId, fromSlot: fromSlot, toSlot: toSlot })
      return
    }

    // Same item: merge
    if (canStackItems(fromItem, toItem)) {
      postNUI('SecondMergeSlot', { invId: iId, fromSlot: fromSlot, toSlot: toSlot, amount: moveAmount })
      return
    }

    // Empty slot: move or split
    if (!toItem) {
      if (moveAmount < fromItem.count) {
        postNUI('SecondSplitSlot', { invId: iId, fromSlot: fromSlot, toSlot: toSlot, amount: moveAmount })
      } else {
        postNUI('SecondSwapSlot', { invId: iId, fromSlot: fromSlot, toSlot: toSlot })
      }
      return
    }

    // Different item: swap
    postNUI('SecondSwapSlot', { invId: iId, fromSlot: fromSlot, toSlot: toSlot })
  }

  function swapStealSlots(fromSlot, toSlot, amount) {
    var fromItem = getSecondItemAtSlot(fromSlot)
    var toItem = getSecondItemAtSlot(toSlot)
    if (!fromItem) return
    var moveAmount = amount || fromItem.count
    if (moveAmount > fromItem.count) moveAmount = fromItem.count
    if (moveAmount < 1) moveAmount = 1

    if (fromItem.type === 'item_weapon') {
      postNUI('StealSwapSlot', { fromSlot: fromSlot, toSlot: toSlot })
      return
    }
    if (canStackItems(fromItem, toItem)) {
      postNUI('StealMergeSlot', { fromSlot: fromSlot, toSlot: toSlot, amount: moveAmount })
      return
    }
    if (!toItem) {
      if (moveAmount < fromItem.count) {
        postNUI('StealSplitSlot', { fromSlot: fromSlot, toSlot: toSlot, amount: moveAmount })
      } else {
        postNUI('StealSwapSlot', { fromSlot: fromSlot, toSlot: toSlot })
      }
      return
    }
    postNUI('StealSwapSlot', { fromSlot: fromSlot, toSlot: toSlot })
  }

  function swapDropSlots(fromSlot, toSlot, amount) {
    var dId = nearbyDropId.value
    if (!dId) return

    var fromItem = getDropZoneItemAtSlot(fromSlot)
    var toItem = getDropZoneItemAtSlot(toSlot)
    if (!fromItem) return

    var moveAmount = amount || fromItem.amount
    if (moveAmount > fromItem.amount) moveAmount = fromItem.amount
    if (moveAmount < 1) moveAmount = 1

    // Weapon: always full swap
    if (fromItem.type === 'item_weapon') {
      postNUI('DropSwapSlot', { dropId: dId, fromSlot: fromSlot, toSlot: toSlot })
      return
    }

    // Same item at target: merge
    if (canStackItems(fromItem, toItem)) {
      postNUI('DropMergeSlot', { dropId: dId, fromSlot: fromSlot, toSlot: toSlot, amount: moveAmount })
      return
    }

    // Empty slot: move or split
    if (!toItem) {
      if (moveAmount < fromItem.amount) {
        postNUI('DropSplitSlot', { dropId: dId, fromSlot: fromSlot, toSlot: toSlot, amount: moveAmount })
      } else {
        postNUI('DropSwapSlot', { dropId: dId, fromSlot: fromSlot, toSlot: toSlot })
      }
      return
    }

    // Different item: swap
    postNUI('DropSwapSlot', { dropId: dId, fromSlot: fromSlot, toSlot: toSlot })
  }

  function swapSlots(fromSlot, toSlot, amount) {
    var fromItem = null
    var toItem = null
    var fromIdx = -1
    var toIdx = -1

    for (var i = 0; i < playerInventory.value.length; i++) {
      if (playerInventory.value[i].slot === fromSlot) { fromItem = playerInventory.value[i]; fromIdx = i }
      if (playerInventory.value[i].slot === toSlot) { toItem = playerInventory.value[i]; toIdx = i }
    }

    if (!fromItem) return
    // Locked items (money/gold) can't be moved
    if (fromItem.locked) return
    if (toItem && toItem.locked) return
    if (isEquippedWeapon(fromItem)) return
    if (isEquippedWeapon(toItem)) return

    var moveAmount = amount || fromItem.count
    if (moveAmount > fromItem.count) moveAmount = fromItem.count
    if (moveAmount < 1) moveAmount = 1

    // Weapon: always full swap, no split/stack
    if (fromItem.type === 'item_weapon') {
      if (toItem && toIdx !== -1) {
        playerInventory.value[toIdx] = Object.assign({}, toItem, { slot: fromSlot })
        postNUI('UpdateSlot', { itemId: toItem.id, slot: fromSlot, itemType: toItem.type })
      }
      playerInventory.value[fromIdx] = Object.assign({}, fromItem, { slot: toSlot })
      postNUI('UpdateSlot', { itemId: fromItem.id, slot: toSlot, itemType: fromItem.type })
      return
    }

    // Same item at target: stack
    if (canStackItems(fromItem, toItem)) {
      toItem.count = toItem.count + moveAmount
      fromItem.count = fromItem.count - moveAmount
      if (fromItem.count <= 0) {
        playerInventory.value.splice(fromIdx, 1)
      }
      postNUI('MergeSlots', { fromId: fromItem.id, toId: toItem.id, amount: moveAmount })
      return
    }

    // Empty slot: move or split
    if (!toItem) {
      if (moveAmount < fromItem.count) {
        // Split: update frontend immediately, server will confirm with reload
        fromItem.count = fromItem.count - moveAmount
        playerInventory.value.push(Object.assign({}, fromItem, { count: moveAmount, slot: toSlot }))
        postNUI('SplitSlot', { itemId: fromItem.id, fromSlot: fromSlot, toSlot: toSlot, amount: moveAmount })
      } else {
        // Full move
        playerInventory.value[fromIdx] = Object.assign({}, fromItem, { slot: toSlot })
        postNUI('UpdateSlot', { itemId: fromItem.id, slot: toSlot, itemType: fromItem.type })
      }
      return
    }

    // Different item at target: swap (only if moving full amount)
    if (toItem && toIdx !== -1) {
      playerInventory.value[toIdx] = Object.assign({}, toItem, { slot: fromSlot })
      postNUI('UpdateSlot', { itemId: toItem.id, slot: fromSlot, itemType: toItem.type })
    }
    playerInventory.value[fromIdx] = Object.assign({}, fromItem, { slot: toSlot })
    postNUI('UpdateSlot', { itemId: fromItem.id, slot: toSlot, itemType: fromItem.type })
  }

  return {
    items,
    playerInventory,
    secondInventory,
    craftInventory,
    craftRecipe,
    craftAmount,
    craftingInProgress,
    craftProgress,
    canCraft,
    secondInventoryType,
    isVisible,
    showHotbar,
    itemNotifications,
    invType,
    customId,
    horseid,
    wagonid,
    houseId,
    hideoutId,
    bankId,
    clanid,
    stealid,
    Containerid,
    StoreId,
    playerId,
    geninfo,
    secondTitle,
    secondCapacity,
    secondWeight,
    secondCurrentCount,
    dropCurrentWeight,
    money,
    gold,
    rol,
    charId,
    charName,
    currentWeight,
    maxWeight,
    LANGUAGE,
    LuaConfig,
    TIME_NOW,
    allplayerammo,
    ammolabels,
    nearPlayersList,
    pendingGiveData,
    showPlayerSelect,
    wornClothing,
    registryOpen,
    registryPlayers,
    registrySearchResult,
    registrySearchedSerial,
    setItems,
    setPlayerInventory,
    setSecondInventory,
    setCraftInventory,
    show,
    hide,
    handleNUIMessage,
    dropZoneItems,
    hasNearbyDrops,
    getItemAtSlot,
    getSecondItemAtSlot,
    getCraftItemAtSlot,
    getDropZoneItemAtSlot,
    nearbyDropId,
    swapSlots,
    swapSecondSlots,
    swapStealSlots,
    swapDropSlots,
    shopState,
    shopId,
    shopView,
    shopOwnerTab,
    rememberAmount,
    recallAmount,
  }
})
