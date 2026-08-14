import { render } from "preact";
import { App } from "@/App";
import { db } from "@/db/dexie";
import { bootLoad } from "@/data/load";
import "@/styles/tokens.css";
import "@/styles/global.css";
import "@/styles/pages.css";
import "@/components/Sidebar.css";
import "@/components/ProjectHeader.css";
import "@/components/Composer.css";

void db.open().then(() => bootLoad());

const mount = document.getElementById("app");
if (!mount) throw new Error("#app mount node missing");
render(<App />, mount);
