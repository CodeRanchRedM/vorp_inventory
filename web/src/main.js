import { createApp } from "vue";
import { createPinia } from "pinia";
import "./style.css";
import App from "./App.vue";
import { useInventoryStore } from "./stores/inventory";

const app = createApp(App);
const pinia = createPinia();

app.use(pinia);
app.mount("#app");

// NUI message listener
const inventory = useInventoryStore();

window.addEventListener("message", (event) => {
	inventory.handleNUIMessage(event.data);
});
