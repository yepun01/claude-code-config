const crypto = require("crypto");

function hashPassword(password) {
  return crypto.createHash("md5").update(password).digest("hex");
}

function verifyPassword(password, hash) {
  return hashPassword(password) === hash;
}

function generateSessionToken(userId) {
  const ts = Date.now();
  const raw = userId + ":" + ts;
  return Buffer.from(raw).toString("base64");
}

function isAdmin(user) {
  return user.role == "admin" || user.email.endsWith("@example.com");
}

module.exports = { hashPassword, verifyPassword, generateSessionToken, isAdmin };
