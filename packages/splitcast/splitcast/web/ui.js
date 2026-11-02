'use strict';
const el = id => document.getElementById(id);
function takeBootstrap() {
  const value = new URLSearchParams(location.hash.slice(1)).get('token');
  if (location.hash) history.replaceState(null, '', location.pathname);
  return value;
}
const bootstrap = takeBootstrap();
let token = bootstrap || sessionStorage.getItem('splitcast.token') || '';
if (bootstrap) sessionStorage.setItem('splitcast.token', bootstrap);
let discovered = null;
let busy = false;
let poll = null;
function controls(enabled) {
  for (const button of document.querySelectorAll('button:not(#connect)')) button.disabled = !enabled;
}
async function command(command, args = {}) {
  const response = await fetch('/api/command', {method: 'POST', signal: AbortSignal.timeout(180000), headers: {'Content-Type': 'application/json', Authorization: `Bearer ${token}`}, body: JSON.stringify({command, args})});
  const value = await response.json();
  if (!response.ok) throw new Error(value.error || 'Control request failed');
  return value;
}
function options(id, items, selected) {
  const node = el(id);
  const prior = selected || node.value;
  node.replaceChildren();
  for (const item of items) {
    const option = document.createElement('option');
    option.value = item.value;
    option.textContent = item.text;
    option.selected = item.value === prior;
    node.append(option);
  }
}
function cameras() {
  if (!discovered) return;
  const location = el('camera-location').value;
  const hosts = [discovered.local, discovered.remote].filter(Boolean);
  const host = hosts.find(h => h.role === location);
  options('camera-device', [{value: '', text: 'Choose a stable device'}, ...(host?.cameras || []).map(c => ({value: c.device, text: c.device}))]);
}
async function perform(name, args = {}) {
  if (busy) return;
  busy = true;
  for (const button of document.querySelectorAll('button')) button.disabled = true;
  el('error').textContent = '';
  try {
    const value = await command(name, args);
    el('result').textContent = JSON.stringify(value, null, 2);
    if (name === 'devices') {
      discovered = value;
      const local = value.local;
      options('mic-source', local.sources.map(s => ({value: s.name, text: s.description || s.name})));
      options('tts-sink', local.sinks.map(s => ({value: s.name, text: s.description || s.name})));
      cameras();
    }
    if (name === 'preview' && typeof value.image === 'string' && value.image.startsWith('data:image/png;base64,')) {
      el('preview').src = value.image;
      el('preview').hidden = false;
    }
    return value;
  } catch (error) {
    el('error').textContent = error.message;
  } finally {
    busy = false;
    controls(Boolean(token));
    await refresh();
  }
}
async function refresh() {
  if (!token) return;
  try {
    const status = await command('status');
    el('status').textContent = JSON.stringify(status, null, 2);
    el('save').disabled = status.state !== 'idle';
  } catch (error) { el('error').textContent = error.message; }
}
for (const button of document.querySelectorAll('[data-command]')) {
  button.addEventListener('click', () => perform(button.dataset.command, button.dataset.action ? {action: button.dataset.action} : {}));
}
el('start').addEventListener('click', () => perform('start', {output: el('output').value}));
el('say').addEventListener('click', () => perform('say', {text: el('speech').value}));
el('overlay').addEventListener('click', () => perform('overlay', {text: el('overlay-text').value}));
el('camera-location').addEventListener('change', cameras);
el('save').addEventListener('click', () => {
  const settings = {peer: {ssh_host: el('host').value}, capture: {target: el('target').value, game_audio: el('game').value},
    audio: {mic_source: el('mic-source').value, tts_sink: el('tts-sink').value},
    camera: {enabled: el('camera-enabled').checked, location: el('camera-location').value, device: el('camera-device').value, mode: el('camera-mode').value}};
  perform('routes', {settings});
});
async function connect() {
  controls(false);
  try {
    if (!token) return;
    const routes = await command('routes');
    sessionStorage.setItem('splitcast.token', token);
    el('control-token').value = '';
    el('authentication').hidden = true;
    el('error').textContent = '';
    const s = routes.selection;
    el('host').value = s.peer.ssh_host;
    el('target').value = s.capture.target;
    el('game').value = s.capture.game_audio;
    options('mic-source', [{value: s.audio.mic_source, text: s.audio.mic_source || 'Discover first'}]);
    options('tts-sink', [{value: s.audio.tts_sink, text: s.audio.tts_sink || 'Discover first'}]);
    el('camera-enabled').checked = s.camera.enabled;
    el('camera-location').value = s.camera.location;
    options('camera-device', [{value: s.camera.device, text: s.camera.device || 'Discover first'}]);
    el('camera-mode').value = s.camera.mode;
    controls(true);
    await refresh();
    if (!poll) poll = setInterval(() => { if (!busy) refresh(); }, 2000);
  } catch (error) {
    token = '';
    sessionStorage.removeItem('splitcast.token');
    el('authentication').hidden = false;
    el('error').textContent = error.message;
  }
}
el('connect').addEventListener('click', () => {
  token = el('control-token').value.trim();
  el('control-token').value = '';
  connect();
});
window.addEventListener('hashchange', () => {
  const value = takeBootstrap();
  if (value) {
    token = value;
    connect();
  }
});
connect();
