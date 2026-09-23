const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const html = fs.readFileSync(path.join(__dirname, '../index.html'), 'utf8');
const scripts = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(m => m[1]);
assert(scripts.length > 0);
for (const script of scripts) new vm.Script(script);
const source = scripts.find(script => script.includes('var I18N ='));
assert(source);
const context = {};
vm.runInNewContext(source.slice(0, source.indexOf('function applyLang')), context);
const keys = Object.keys(context.I18N.en).sort();
for (const language of ['ko', 'ja']) {
  assert.deepEqual(Object.keys(context.I18N[language]).sort(), keys);
}
for (const [, key] of html.matchAll(/data-i18n(?:-html)?="([^"]+)"/g)) {
  assert(keys.includes(key), `Missing translation: ${key}`);
}
console.log('Landing JavaScript syntax and translation keys verified');
