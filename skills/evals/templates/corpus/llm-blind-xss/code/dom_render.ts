import { marked } from "marked";

type Notification = {
  id: string;
  author: string;
  body: string;
  avatarUrl: string;
  redirectTo?: string;
};

export function renderNotification(
  container: HTMLElement,
  n: Notification,
): void {
  const card = document.createElement("div");
  card.className = "notif-card";

  card.innerHTML = `
    <img class="avatar" src="${n.avatarUrl}" alt="">
    <div class="meta">
      <span class="author">${n.author}</span>
    </div>
    <div class="body">${marked.parse(n.body)}</div>
  `;

  if (n.redirectTo) {
    const link = document.createElement("a");
    link.href = n.redirectTo;
    link.textContent = "Open";
    card.appendChild(link);
  }

  container.appendChild(card);
}

export function mountFromQuery(container: HTMLElement): void {
  const params = new URLSearchParams(window.location.search);
  const raw = params.get("notif");
  if (!raw) return;

  const data = JSON.parse(raw) as Notification;

  const banner = document.getElementById("banner-" + data.id);
  if (banner) {
    banner.innerHTML = "Welcome back, " + data.author + "!";
  }

  renderNotification(container, data);
}
