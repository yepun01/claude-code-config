import { db } from "@/db/dexie";
import { loadIndex } from "@/data/api";
import { projects, adrs, dataLoadState } from "@/state/signals";

export async function bootLoad(): Promise<void> {
  dataLoadState.value = "loading";
  try {
    const { projects: projectRows, adrs: adrRows } = await loadIndex();
    await db.projects.bulkPut(projectRows);
    await db.adrs.bulkPut(adrRows);
    projects.value = await db.projects.toArray();
    adrs.value = await db.adrs.toArray();
    dataLoadState.value = "ready";
  } catch (err) {
    console.error("bootLoad failed:", err);
    dataLoadState.value = "error";
  }
}
