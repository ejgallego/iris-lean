// Minimal CDP client (Node >= 22 global WebSocket). Flat sessions for attached targets.
export async function connect(wsUrl) {
  const ws = new WebSocket(wsUrl); let id = 0; const pending = new Map(); const listeners = [];
  await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
  ws.onmessage = ev => { const m = JSON.parse(ev.data);
    if (m.id && pending.has(m.id)) { const { res, rej } = pending.get(m.id); pending.delete(m.id); m.error ? rej(new Error(JSON.stringify(m.error))) : res(m.result); }
    else listeners.forEach(l => l(m)); };
  const send = (method, params = {}, sessionId) => new Promise((res, rej) => { const i = ++id; pending.set(i, { res, rej }); ws.send(JSON.stringify({ id: i, method, params, ...(sessionId ? { sessionId } : {}) })); });
  return { send, on: l => listeners.push(l), close: () => ws.close() };
}
export async function pageTarget(port, match = /workbench/) {
  const list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
  return list.find(t => t.type === 'page' && match.test(t.url));
}
