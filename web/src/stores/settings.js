import { defineStore } from "pinia";
import { ref, watch } from "vue";

const STORAGE_KEY = "vorp_inventory_settings";

function loadFromStorage() {
	try {
		const saved = localStorage.getItem(STORAGE_KEY);
		if (saved) return JSON.parse(saved);
	} catch {}
	return null;
}

export const useSettingsStore = defineStore("settings", () => {
	const defaults = {
		soundEffects: true,
		showNotifications: true,
		notificationDuration: 3000,
		doubleClickToUse: true,
	};

	const saved = loadFromStorage();

	const soundEffects = ref(saved?.soundEffects ?? defaults.soundEffects);
	const showNotifications = ref(
		saved?.showNotifications ?? defaults.showNotifications,
	);
	const notificationDuration = ref(
		saved?.notificationDuration ?? defaults.notificationDuration,
	);
	const doubleClickToUse = ref(
		saved?.doubleClickToUse ?? defaults.doubleClickToUse,
	);
	const isOpen = ref(false);

	function save() {
		localStorage.setItem(
			STORAGE_KEY,
			JSON.stringify({
				soundEffects: soundEffects.value,
				showNotifications: showNotifications.value,
				notificationDuration: notificationDuration.value,
				doubleClickToUse: doubleClickToUse.value,
			}),
		);
	}

	watch(
		[soundEffects, showNotifications, notificationDuration, doubleClickToUse],
		save,
		{ deep: true },
	);

	function toggle() {
		isOpen.value = !isOpen.value;
	}

	return {
		soundEffects,
		showNotifications,
		notificationDuration,
		doubleClickToUse,
		isOpen,
		toggle,
	};
});
