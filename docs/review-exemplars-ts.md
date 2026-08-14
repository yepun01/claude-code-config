# Review Exemplars — TypeScript/JavaScript

Concrete patterns to detect during reviews. Each exemplar shows the problematic code and the fix.

---

## 1. N+1 Query (Hono/Express + PostgreSQL)

**Problem**: Query inside a loop — O(N) queries instead of 1.

```typescript
// BAD — N+1
const users = await db.query("SELECT * FROM users");
for (const user of users.rows) {
  const profile = await db.query("SELECT * FROM profiles WHERE user_id = $1", [user.id]);
  user.profile = profile.rows[0];
}

// GOOD — JOIN or IN
const usersWithProfiles = await db.query(`
  SELECT u.*, p.bio, p.avatar
  FROM users u
  LEFT JOIN profiles p ON p.user_id = u.id
`);
```

**Detection**: `await` inside a `for`/`forEach`/`map` that contains `query`/`fetch`/`findOne`.

---

## 2. Memory Leak — Event Listener / Subscription

**Problem**: Listener added without cleanup, gradual memory leak.

```typescript
// BAD — no cleanup
useEffect(() => {
  window.addEventListener("resize", handleResize);
  const sub = eventEmitter.on("update", handleUpdate);
}, []);

// GOOD — cleanup in the return
useEffect(() => {
  window.addEventListener("resize", handleResize);
  const sub = eventEmitter.on("update", handleUpdate);
  return () => {
    window.removeEventListener("resize", handleResize);
    sub.off("update", handleUpdate);
  };
}, []);
```

**Detection**: `useEffect` without `return` that contains `addEventListener`, `.on(`, `subscribe`, `setInterval`.

---

## 3. Injection — SQL via string interpolation

**Problem**: User input concatenated into a SQL query.

```typescript
// BAD — SQL injection
const result = await db.query(`SELECT * FROM users WHERE email = '${email}'`);

// GOOD — prepared parameters
const result = await db.query("SELECT * FROM users WHERE email = $1", [email]);
```

**Detection**: Template literal or concatenation (`+`) inside an argument of `query`/`execute`/`raw` that includes a non-sanitized variable.

---

## 4. Race Condition — Fetch without AbortController

**Problem**: Component unmounted during the fetch, state update on a non-existent component.

```typescript
// BAD — race condition on rapid navigation
useEffect(() => {
  fetch(`/api/users/${id}`).then(r => r.json()).then(setUser);
}, [id]);

// GOOD — abort on cleanup
useEffect(() => {
  const controller = new AbortController();
  fetch(`/api/users/${id}`, { signal: controller.signal })
    .then(r => r.json())
    .then(setUser)
    .catch(e => { if (e.name !== "AbortError") throw e; });
  return () => controller.abort();
}, [id]);
```

**Detection**: `fetch` inside `useEffect` without `AbortController` or a library (TanStack Query, SWR) that handles it.

---

## 5. Unbounded payload — Lack of pagination

**Problem**: Endpoint that returns ALL rows without a limit.

```typescript
// BAD — no limit
app.get("/api/items", async (c) => {
  const items = await db.query("SELECT * FROM items");
  return c.json(items.rows);
});

// GOOD — mandatory pagination
app.get("/api/items", async (c) => {
  const limit = Math.min(Number(c.req.query("limit") || 50), 100);
  const offset = Number(c.req.query("offset") || 0);
  const items = await db.query("SELECT * FROM items LIMIT $1 OFFSET $2", [limit, offset]);
  return c.json(items.rows);
});
```

**Detection**: `SELECT * FROM` without `LIMIT` in a GET route handler.
