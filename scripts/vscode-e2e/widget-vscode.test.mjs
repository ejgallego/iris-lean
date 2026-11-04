// Real VS Code acceptance for the Iris proof-mode widget: isolated headless VS Code, the
// installed Lean extension and its real infoview, driven through the test-only driver.
// Usage: node widget-vscode.test.mjs [path/to/Iris]   (never saves the edited buffer)
import { launch, infoviewEval } from './vscode.mjs';
import { writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const iris = resolve(process.argv[2] ?? fileURLToPath(new URL('../../Iris', import.meta.url)));
const file = `${iris}/IrisTest/ProofMode/WidgetDemo.lean`;
const sleep = ms => new Promise(r => setTimeout(r, ms));
const results = [];
let vs, shots = 0;

// Snapshot of the widget as rendered inside the real infoview webview.
const WIDGET = `(() => {
  const w = document.querySelector('[data-iris-proof-mode-widget]');
  const tactic = document.body.innerText.includes('Tactic state');
  if (!w) return { present: false, tactic };
  const cards = [...w.querySelectorAll('[data-goal-id]')];
  return { present: true, tactic, text: w.innerText,
    cards: cards.map(c => ({ id: c.dataset.goalId, expanded: c.querySelector('header button')?.getAttribute('aria-expanded'), marked: c.__irisE2E ?? null })),
    termButtons: w.querySelectorAll('[data-term-ref]').length, buttons: w.querySelectorAll('button').length,
    busy: !!w.closest('[aria-busy="true"]') };
})()`;
const widget = () => infoviewEval(vs, WIDGET);

async function check(name, f) {
  const t0 = Date.now();
  try { const detail = await f(); results.push({ name, ok: true, ms: Date.now() - t0, detail }); console.log(`ok   ${name}`); }
  catch (e) { results.push({ name, ok: false, ms: Date.now() - t0, error: e.message }); console.log(`FAIL ${name}: ${e.message}`); }
  try { const s = await vs.workbench.send('Page.captureScreenshot', { format: 'png' });
    writeFileSync(`${vs.run}/${String(++shots).padStart(2, '0')}-${name.replace(/\W+/g, '-')}.png`, Buffer.from(s.data, 'base64')); } catch {}
}
const assert = (c, m) => { if (!c) throw new Error(m); };
const at = async (marker, delta = 0) => { const p = await vs.driver({ op: 'find', marker }); p.character += delta; await vs.driver({ op: 'cursor', ...p }); return p; };
// Wait until the widget satisfies `pred` and is not refreshing.
const waitWidget = (what, pred, ms = 90000) => vs.until(what, async () => { const w = await widget(); return w && !w.busy && pred(w) ? w : undefined; }, ms, 750);

try {
  vs = await launch({ workspace: iris });
  await vs.driver({ op: 'open', file });

  await check('heap store: contexts and target', async () => {
    await at('widget-position-heap-store');
    const w = await waitWidget('heap store widget', w => w.present && w.text.includes('Hframe'), 240000);
    for (const s of ['Hl', 'l ↦ some v', "l' ↦ some w", 'WP', '⊢']) assert(w.text.includes(s), `missing ${s}`);
    assert(/Hl\s*:/.test(w.text), 'no ":" after hypothesis name');
    assert(w.tactic, 'normal Tactic state must remain beside the widget');
    assert(w.termButtons === 0, 'custom term buttons remain');
    const standardDiff = await infoviewEval(vs, `(() => [...document.querySelectorAll('.removed-text, .inserted-text')]
      .filter(e => !e.closest('[data-iris-proof-mode-widget]')).map(e => ({ text: e.textContent, classes: e.className })))()`);
    return { termButtons: w.termButtons, buttons: w.buttons, standardDiff };
  });

  await check('heap load: Hl changed, Hframe unchanged', async () => {
    await at('widget-position-heap-load');
    const w = await waitWidget('heap load widget', w => w.present && w.text.includes("l ↦ some v'"));
    assert(w.text.includes("l' ↦ some w"), 'Hframe changed');
    return { text: w.text };
  });

  await check('native hover shows a contextual type', async () => {
    await at('widget-position-heap-store');
    await waitWidget('heap store again', w => w.present && /Hl:\s*l ↦ some v(?!')/.test(w.text));
    const hovered = await infoviewEval(vs, `(() => {
      const w = document.querySelector('[data-iris-proof-mode-widget]');
      const target = [...w.querySelectorAll('span')].find(s => s.textContent === 'l' && s.childElementCount === 0);
      if (!target) return 'no-span';
      for (const type of ['pointerover', 'pointermove', 'mouseover', 'mousemove'])
        target.dispatchEvent(new (type.startsWith('pointer') ? PointerEvent : MouseEvent)(type, { bubbles: true }));
      return 'hovered';
    })()`);
    assert(hovered === 'hovered', `could not hover: ${hovered}`);
    const tip = await vs.until('hover popup', () => infoviewEval(vs, `(() => {
      const t = [...document.querySelectorAll('.tooltip, [role="tooltip"], .hover-tooltip')].map(e => e.innerText).find(s => s.includes(':'));
      return t ?? undefined; })()`), 20000, 500);
    assert(/Loc/.test(tip), `tooltip lacks Loc: ${tip}`);
    return { tip: tip.slice(0, 200) };
  });

  await check('native definition navigation opens the Lean source file', async () => {
    await at('widget-position-heap-store');
    await waitWidget('heap store for definition', w => w.present && /Hl:\s*l ↦ some v(?!')/.test(w.text));
    const clicked = await infoviewEval(vs, `(() => {
      const w = document.querySelector('[data-iris-proof-mode-widget]');
      const term = [...w.querySelectorAll('[data-has-tooltip-on-hover]')]
        .find(e => e.textContent.startsWith('some '));
      if (!term) return false;
      term.dispatchEvent(new MouseEvent('click', { bubbles: true, ctrlKey: true }));
      return true;
    })()`);
    assert(clicked, 'missing native Option.some tag');
    try {
      const destination = await vs.until('definition opened in editor', async () => {
        const editor = await vs.driver({ op: 'activeEditor' });
        return editor?.uri.endsWith('/Init/Prelude.lean') ? editor : undefined;
      }, 20000, 500);
      assert(!destination.isDirty, 'definition navigation dirtied the source');
      return { destination, input: 'synthetic Ctrl-click in the real webview; actual editor destination checked' };
    } finally { await vs.driver({ op: 'open', file }); }
  });

  await check('heap postcondition retains both owned cells', async () => {
    await at('widget-position-heap-post');
    const w = await waitWidget('heap postcondition', w => w.present && w.text.includes("⌜v' = v'⌝") && !w.text.includes('WP '));
    assert(w.text.includes("l ↦ some v'") && w.text.includes("l' ↦ some w"), 'postcondition lost a cell');
    return { text: w.text };
  });

  for (const [marker, cell, targetPrefix] of [
    ['widget-position-spin-open', '▷ l ↦ some hl_val(#b)', 'WP '],
    ['widget-position-spin-stored', 'l ↦ some hl_val(#false)', '|={'],
  ])
    await check(`spinlock ${marker.split('-').at(-1)}`, async () => {
      await at(marker);
      const w = await waitWidget(marker, w => w.present && w.text.includes('Hinv') && w.text.includes(cell) && w.text.includes(targetPrefix));
      for (const term of ['locked γ', 'HR:', 'Hcond:', 'spinlockN']) assert(w.text.includes(term), `missing ${term}`);
      assert(w.termButtons === 0, 'custom term buttons remain');
      return { termButtons: w.termButtons, text: w.text };
    });

  await check('ordinary Lean goal renders no Iris panel', async () => {
    await at('widget-position-ordinary');
    await vs.until('tactic state without widget', async () => { const w = await widget(); return w && w.tactic && !w.present; }, 60000, 750);
    await sleep(3000);
    const w = await widget(); assert(!w.present, 'widget appeared on an ordinary goal');
  });

  await check('split: two goal cards', async () => {
    await at('widget-position-split');
    const w = await waitWidget('split widget', w => w.present && w.cards.length === 2);
    return { cards: w.cards };
  });

  await check('collapse survives a cursor move in the same proof state', async () => {
    // Collapse the first card and mark both card DOM nodes so remounts are detectable.
    const before = await infoviewEval(vs, `(() => {
      const cards = [...document.querySelectorAll('[data-iris-proof-mode-widget] [data-goal-id]')];
      cards.forEach((c, i) => c.__irisE2E = 'card' + i);
      const b = cards[0].querySelector('header button'); if (b.getAttribute('aria-expanded') === 'true') b.click();
      return cards.length; })()`);
    assert(before === 2, 'expected two cards');
    await waitWidget('collapsed', w => w.cards[0]?.expanded === 'false', 10000);
    // Same proof state, different line: from the bullet after the marker to the end of the marker
    // comment (both show the two goals produced by isplitr; inside `iexact` only one goal is focused).
    const marker = await vs.driver({ op: 'find', marker: 'widget-position-split', offset: 0 });
    await vs.driver({ op: 'cursor', line: marker.line, character: 200 });
    await sleep(4000);
    const w = await waitWidget('after cursor move', w => w.present && w.cards.length === 2);
    assert(w.cards[0].expanded === 'false', 'collapse lost after cursor move');
    assert(w.cards.every((c, i) => c.marked === 'card' + i), `cards remounted: ${JSON.stringify(w.cards)}`);
    return { cards: w.cards };
  });

  await check('collapse survives typing (buffer edit, not saved)', async () => {
    const p = await vs.driver({ op: 'find', marker: 'widget-position-split', offset: 0 });
    await vs.driver({ op: 'cursor', line: p.line, character: 200 });   // clamps to end of the comment line
    await vs.driver({ op: 'type', text: ' x' });
    await sleep(1500);
    const w = await waitWidget('after typing', w => w.present && w.cards.length === 2);
    assert(w.cards[0].expanded === 'false', 'collapse lost after typing');
    assert(w.cards.every((c, i) => c.marked === 'card' + i), `cards remounted after typing: ${JSON.stringify(w.cards)}`);
    return { cards: w.cards };
  });
} catch (e) {
  results.push({ name: 'harness', ok: false, error: e.message }); console.log(`FAIL harness: ${e.message}`);
} finally {
  if (vs) { await vs.driver({ op: 'revert' }).catch(() => {}); await vs.close(); }
}
const failed = results.filter(r => !r.ok).length;
if (vs) writeFileSync(`${vs.run}/results.json`, JSON.stringify({ iris, results }, null, 1));
console.log(`${results.length - failed}/${results.length} passed${vs ? `; screenshots and results in ${vs.run}` : ''}`);
process.exit(failed ? 1 : 0);
