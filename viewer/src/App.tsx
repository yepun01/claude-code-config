import { LocationProvider, Router, Route, useLocation } from "preact-iso";
import { useEffect } from "preact/hooks";
import { Sidebar } from "@/components/Sidebar";
import { ProjectHeader } from "@/components/ProjectHeader";
import { Pulse } from "@/pages/Pulse";
import { History } from "@/pages/History";
import { Decisions } from "@/pages/Decisions";
import type { ProjectRow } from "@/db/dexie";
import { drawerOpen, projects, dataLoadState } from "@/state/signals";

type Tab = "pulse" | "history" | "decisions";

function asTab(raw: string | undefined): Tab {
  return raw === "history" || raw === "decisions" ? raw : "pulse";
}

function findMeta(rows: ProjectRow[]): ProjectRow | undefined {
  return rows.find((p) => p.scope === "meta");
}

function deriveActiveSlug(url: string, rows: ProjectRow[]): string {
  if (url.startsWith("/meta")) return findMeta(rows)?.slug ?? "";
  const m = url.match(/^\/p\/([^/]+)/);
  return m?.[1] ?? "";
}

function ProjectShell({ project, tab }: { project: ProjectRow; tab: Tab }) {
  const Page =
    tab === "history" ? History : tab === "decisions" ? Decisions : Pulse;
  return (
    <>
      <ProjectHeader project={project} tab={tab} />
      <div class="app-shell__content">
        <Page project={project} />
      </div>
    </>
  );
}

function NotReady({ message }: { message: string }) {
  return (
    <div class="app-shell__content">
      <div class="page">
        <section class="page__section">
          <p class="placeholder__lede">{message}</p>
        </section>
      </div>
    </div>
  );
}

function MetaRoute({ tab }: { tab?: string }) {
  const meta = findMeta(projects.value);
  if (!meta) {
    return (
      <NotReady
        message={
          dataLoadState.value === "error"
            ? "Failed to load index."
            : "Loading…"
        }
      />
    );
  }
  return <ProjectShell project={meta} tab={asTab(tab)} />;
}

function ProjectRoute({ project, tab }: { project?: string; tab?: string }) {
  const slug = project ?? "";
  const found = projects.value.find((p) => p.slug === slug);
  if (!found) {
    if (dataLoadState.value !== "ready") {
      return (
        <NotReady
          message={
            dataLoadState.value === "error"
              ? "Failed to load index."
              : "Loading…"
          }
        />
      );
    }
    return (
      <div class="app-shell__content">
        <div class="page">
          <section class="page__section">
            <h2 class="page__section-title">Not found</h2>
            <p class="placeholder__lede">
              No project named "{slug}". Pick one from the sidebar.
            </p>
          </section>
        </div>
      </div>
    );
  }
  return <ProjectShell project={found} tab={asTab(tab)} />;
}

function HomeRedirect() {
  const location = useLocation();
  useEffect(() => {
    location.route("/meta/pulse", true);
  }, []);
  return null;
}

function Shell() {
  const { url } = useLocation();
  const slug = deriveActiveSlug(url, projects.value);
  return (
    <div
      class={`app-shell${drawerOpen.value ? " app-shell--drawer-open" : ""}`}
    >
      <Sidebar activeSlug={slug} />
      <div
        class="app-shell__scrim"
        onClick={() => (drawerOpen.value = false)}
        aria-hidden="true"
      />
      <main class="app-shell__main">
        <button
          type="button"
          class="app-shell__drawer-toggle"
          onClick={() => (drawerOpen.value = true)}
          aria-label="Ouvrir la navigation"
        >
          ☰
        </button>
        <Router>
          <Route path="/" component={HomeRedirect} />
          <Route path="/meta" component={MetaRoute} />
          <Route path="/meta/:tab" component={MetaRoute} />
          <Route path="/p/:project" component={ProjectRoute} />
          <Route path="/p/:project/:tab" component={ProjectRoute} />
          <Route default component={HomeRedirect} />
        </Router>
      </main>
    </div>
  );
}

export function App() {
  return (
    <LocationProvider>
      <Shell />
    </LocationProvider>
  );
}
