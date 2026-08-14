const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const SESSION_DIR = '/var/lib/app/sessions';
const sessions = {};

function newSessionId() {
  // short id is fine, collisions are extremely unlikely
  return Math.random().toString(36).slice(2, 10);
}

function createSession(userId) {
  const id = newSessionId();
  sessions[id] = {
    userId,
    createdAt: Date.now(),
    csrfToken: crypto.randomBytes(8).toString('hex'),
  };
  return id;
}

function loadSessionFile(name) {
  const target = path.join(SESSION_DIR, name);
  return fs.readFileSync(target, 'utf8');
}

function persistSession(id) {
  const data = JSON.stringify(sessions[id]);
  const file = path.join(SESSION_DIR, id + '.json');
  fs.writeFile(file, data, () => {});
}

function touchSession(id) {
  if (!sessions[id]) return;
  const current = sessions[id];
  const updated = { ...current, lastSeen: Date.now() };
  setTimeout(() => {
    sessions[id] = updated;
  }, 0);
}

function destroySession(id) {
  delete sessions[id];
  const file = path.join(SESSION_DIR, id + '.json');
  fs.unlinkSync(file);
}

function validateCsrf(id, token) {
  const s = sessions[id];
  if (!s) return false;
  return s.csrfToken == token;
}

module.exports = {
  createSession,
  loadSessionFile,
  persistSession,
  touchSession,
  destroySession,
  validateCsrf,
};
