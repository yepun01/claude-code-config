import { useEffect, useState } from "preact/hooks";
import { useLocation } from "preact-iso";
import { Composer } from "@/components/Composer";
import { adrs } from "@/state/signals";
import type { ProjectRow, AdrRow } from "@/db/dexie";
import type { JSX } from "preact";

function focusFromUrl(url: string): string | null {
  const qs = url.split("?")[1];
  if (!qs) return null;
  return new URLSearchParams(qs).get("focus");
}

function renderMarkdown(text: string): JSX.Element[] {
  const out: JSX.Element[] = [];
  const lines = text.split("\n");
  let i = 0;
  let key = 0;
  while (i < lines.length) {
    const line = lines[i]!;
    if (line.startsWith("### ")) {
      out.push(<h3 key={key++}>{line.slice(4)}</h3>);
      i++;
    } else if (line.startsWith("## ")) {
      out.push(<h2 key={key++}>{line.slice(3)}</h2>);
      i++;
    } else if (line.startsWith("# ")) {
      out.push(<h1 key={key++}>{line.slice(2)}</h1>);
      i++;
    } else if (line.startsWith("- ")) {
      const items: string[] = [];
      while (i < lines.length && lines[i]!.startsWith("- ")) {
        items.push(lines[i]!.slice(2));
        i++;
      }
      out.push(
        <ul key={key++}>
          {items.map((it, idx) => (
            <li key={idx}>{it}</li>
          ))}
        </ul>,
      );
    } else if (line.trim() === "") {
      i++;
    } else {
      const para: string[] = [];
      while (
        i < lines.length &&
        lines[i]!.trim() !== "" &&
        !lines[i]!.startsWith("# ") &&
        !lines[i]!.startsWith("## ") &&
        !lines[i]!.startsWith("### ") &&
        !lines[i]!.startsWith("- ")
      ) {
        para.push(lines[i]!);
        i++;
      }
      out.push(<p key={key++}>{para.join(" ")}</p>);
    }
  }
  return out;
}

function sortedAdrs(rows: AdrRow[]): AdrRow[] {
  return [...rows].sort((a, b) => b.lastModified.localeCompare(a.lastModified));
}

export function Decisions({ project }: { project: ProjectRow }) {
  const location = useLocation();
  const list = sortedAdrs(adrs.value);
  const initialFocus = focusFromUrl(location.url);
  const [selectedId, setSelectedId] = useState<string | null>(
    initialFocus ?? list[0]?.id ?? null,
  );
  const [body, setBody] = useState<string>("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState<boolean>(false);

  useEffect(() => {
    if (initialFocus && initialFocus !== selectedId) {
      setSelectedId(initialFocus);
    }
  }, [initialFocus]);

  useEffect(() => {
    if (selectedId === null && !initialFocus && list.length > 0) {
      setSelectedId(list[0]!.id);
    }
  }, [list.length, initialFocus]);

  const selected = list.find((a) => a.id === selectedId) ?? null;

  useEffect(() => {
    if (project.scope !== "meta") {
      setBody("");
      setError(null);
      setLoading(false);
      return;
    }
    if (!selected) {
      setBody("");
      setError(null);
      setLoading(false);
      return;
    }
    let cancelled = false;
    setError(null);
    setBody("");
    setLoading(true);
    fetch(`/notes?path=${encodeURIComponent(selected.path)}`)
      .then((res) => {
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        return res.text();
      })
      .then((text) => {
        if (!cancelled) {
          setBody(text);
          setLoading(false);
        }
      })
      .catch((err: Error) => {
        if (!cancelled) {
          setError(err.message);
          setLoading(false);
        }
      });
    return () => {
      cancelled = true;
    };
  }, [selected?.id, project.scope]);

  if (project.scope !== "meta") {
    return (
      <div class="page">
        <section class="page__section">
          <h2 class="page__section-title">ADRs · ROADMAP · STATE</h2>
          <p class="placeholder__lede">Aucun ADR local.</p>
        </section>
        <Composer
          scopeLabel={`${project.name} LLM`}
          contextLabel="ADRs + ROADMAP + STATE scoped"
        />
      </div>
    );
  }

  return (
    <div class="page">
      <section class="page__section">
        <h2 class="page__section-title">ADRs · ROADMAP · STATE</h2>
        <div class="decisions__layout">
          <ul class="decisions__list">
            {list.map((adr) => (
              <li key={adr.id}>
                <button
                  type="button"
                  class={`decisions__item${
                    adr.id === selectedId ? " decisions__item--active" : ""
                  }`}
                  onClick={() => setSelectedId(adr.id)}
                >
                  <span class="decisions__item-num">{adr.number}</span>
                  <span class="decisions__item-title">{adr.title}</span>
                </button>
              </li>
            ))}
          </ul>
          <div class="decisions__preview">
            {!selected && (
              <p class="placeholder__lede">Sélectionne un ADR.</p>
            )}
            {selected && loading && (
              <p class="placeholder__lede">Loading…</p>
            )}
            {selected && !loading && error && (
              <p class="placeholder__lede">Failed to load: {error}</p>
            )}
            {selected && !loading && !error && body && (
              <div class="decisions__body">{renderMarkdown(body)}</div>
            )}
            {selected && !loading && !error && !body && (
              <p class="placeholder__lede">(empty ADR)</p>
            )}
          </div>
        </div>
      </section>

      <Composer
        scopeLabel={`${project.name} LLM`}
        contextLabel="ADRs + ROADMAP + STATE scoped"
      />
    </div>
  );
}
