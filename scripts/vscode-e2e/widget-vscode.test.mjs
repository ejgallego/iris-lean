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
    tactics: [...w.querySelectorAll('[data-tactic]')].map(e => e.dataset.tactic),
    changes: [...w.querySelectorAll('[data-resource-name][data-annotation-kind]')].filter(e => e.dataset.resourceName).map(e => ({ name: e.dataset.resourceName,
      status: e.dataset.annotationKind, text: e.innerText, native: !!e.querySelector('[data-has-tooltip-on-hover]') })),
    targets: [...w.querySelectorAll('[data-annotation-kind="target"]')].map(e => e.innerText),
    summary: w.querySelector('[data-comparison-summary]')?.textContent,
    rows: [...w.querySelectorAll('[data-hypothesis-name]')].map(e => ({ name: e.dataset.hypothesisName, text: e.children[1].textContent })),
    busy: !!w.closest('[aria-busy="true"]') };
})()`;
const widget = () => infoviewEval(vs, WIDGET);

async function check(name, f) {
  const t0 = Date.now();
  try { const detail = await f(); results.push({ name, ok: true, ms: Date.now() - t0, detail }); console.log(`ok   ${name}`); }
  catch (e) { results.push({ name, ok: false, ms: Date.now() - t0, error: e.message }); console.log(`FAIL ${name}: ${e.message}`); }
  try {
    if (/heap store: typed|spinlock open$|spinlock stored$|split distributes/.test(name))
      await infoviewEval(vs, `document.querySelector('[data-iris-proof-mode-widget] article')?.scrollIntoView({ block: 'center' })`);
    const s = await vs.workbench.send('Page.captureScreenshot', { format: 'png' });
    writeFileSync(`${vs.run}/${String(++shots).padStart(2, '0')}-${name.replace(/\W+/g, '-')}.png`, Buffer.from(s.data, 'base64')); } catch {}
}
const assert = (c, m) => { if (!c) throw new Error(m); };
const at = async (marker, delta = 0) => { const p = await vs.driver({ op: 'find', marker }); p.character += delta; await vs.driver({ op: 'cursor', ...p }); return p; };
// Wait until the widget satisfies `pred` and is not refreshing.
const waitWidget = (what, pred, ms = 90000) => vs.until(what, async () => { const w = await widget(); return w && !w.busy && pred(w) ? w : undefined; }, ms, 750);

try {
  vs = await launch({ workspace: iris });
  await vs.driver({ op: 'open', file });

  const tour = () => infoviewEval(vs, `(() => {
    const t = document.querySelector('[data-iris-widget-tour]');
    if (!t) return undefined;
    return { index: t.dataset.tourStep, exact: t.dataset.tourExact, busy: t.getAttribute('aria-busy'), text: t.innerText,
      prevDisabled: t.querySelector('[data-tour-prev]').disabled, nextDisabled: t.querySelector('[data-tour-next]').disabled };
  })()`);
  const tourAt = index => vs.until(`tour step ${index}`, async () => {
    const t = await tour(); return t?.index === String(index) && t.exact === 'true' && t.busy === 'false' ? t : undefined;
  }, 90000, 500);
  const tourClick = direction => infoviewEval(vs, `(() => {
    document.querySelector('[data-tour-${direction}]').click(); return true;
  })()`);

  await check('tour Next moves the real editor cursor', async () => {
    await at('widget-position-heap-store'); await tourAt(0);
    const expected = await vs.driver({ op: 'find', marker: 'widget-position-heap-load' });
    await tourClick('next'); const t = await tourAt(1);
    const actual = await vs.driver({ op: 'activeEditor' });
    assert(actual.uri.endsWith('/WidgetDemo.lean') && actual.line === expected.line && actual.character === expected.character,
      `Next cursor mismatch: ${JSON.stringify(actual)}`);
    assert(t.text.includes('wp_load only changes the goal.') && t.text.includes('Step 2 of 9'), 'step text did not change');
    return { actual, text: t.text };
  });
  await check('tour Prev returns to the preceding step', async () => {
    const expected = await vs.driver({ op: 'find', marker: 'widget-position-heap-store' });
    await tourClick('prev'); const t = await tourAt(0);
    const actual = await vs.driver({ op: 'activeEditor' });
    assert(actual.line === expected.line && actual.character === expected.character, 'Prev cursor mismatch');
    assert(t.prevDisabled && t.text.includes('wp_store updates Hl; Hframe untouched.'), 'first-step state');
    return { actual, text: t.text };
  });
  await check('tour follows manual cursor movement and reaches feedback', async () => {
    await at('widget-position-spin-open'); const spin = await tourAt(3);
    assert(spin.text.includes('opened invariant'), 'manual cursor did not select SpinLock');
    const marker = await vs.driver({ op: 'find', marker: 'widget-position-spin-stored', offset: 0 });
    await vs.driver({ op: 'cursor', ...marker });
    await vs.until('dimmed preceding step', async () => { const t = await tour(); return t?.index === '3' && t.exact === 'false' && t.busy === 'false'; }, 30000);
    await tourClick('prev'); await tourAt(3);
    const expected = await vs.driver({ op: 'find', marker: 'widget-position-spin-open' });
    const actual = await vs.driver({ op: 'activeEditor' });
    assert(actual.line === expected.line && actual.character === expected.character, 'Prev skipped the dimmed SpinLock step');

    // The first step must also remain reachable with Prev while it is dimmed.
    const betweenFirst = await vs.driver({ op: 'find', marker: 'widget-position-heap-load', offset: 0 });
    await vs.driver({ op: 'cursor', ...betweenFirst });
    await vs.until('dimmed first step', async () => {
      const t = await tour(); return t?.index === '0' && t.exact === 'false' && t.busy === 'false' && !t.prevDisabled;
    }, 30000);
    await tourClick('prev'); const first = await tourAt(0);
    const firstExpected = await vs.driver({ op: 'find', marker: 'widget-position-heap-store' });
    const firstActual = await vs.driver({ op: 'activeEditor' });
    assert(firstActual.line === firstExpected.line && firstActual.character === firstExpected.character && first.prevDisabled,
      'Prev should reach the first step and then become disabled');
    await at('widget-position-how-vir'); const vir = await tourAt(7);
    assert(vir.text.includes('Lean-authored React (VIR)'), 'VIR explanation missing');
    await at('widget-position-feedback'); const feedback = await tourAt(8);
    assert(feedback.nextDisabled && feedback.text.includes('Which proof'), 'feedback should finish the tour');
    return { spin: spin.text, feedback: feedback.text };
  });

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

  await check('heap store: typed resource comparison', async () => {
    const w = await waitWidget('store comparison', w => w.present && w.tactics.includes('wp_store'));
    const cell = w.changes.find(r => r.name === 'Hl');
    assert(w.changes.length === 1 && cell?.status === 'changed', 'only Hl has a hypothesis annotation');
    assert(cell.native && cell.text.includes("l ↦ some v'"), 'native new cell proposition');
    assert(w.rows.find(r => r.name === 'Hl')?.text === 'l ↦ some v', 'before proposition stays above its annotation');
    assert(w.summary === 'before wp_store · changes Hl and the goal' && w.targets.length === 1, 'store summary and goal annotation');
    assert(!w.text.includes('was:') && !w.text.includes('preserved'), 'redundant comparison text remains');
    const t = await tourAt(0);
    assert(t.text.includes('wp_store updates Hl; Hframe untouched.') && t.text.includes('↳ under Hl and under ⊢.'), 'store tour disagrees with annotations');
    return w;
  });

  await check('heap load only annotates the goal', async () => {
    await at('widget-position-heap-load');
    const w = await waitWidget('heap load widget', w => w.present && w.tactics.includes("wp_load") && w.text.includes("l ↦ some v'"));
    assert(w.text.includes("l' ↦ some w"), 'Hframe changed');
    assert(w.changes.length === 0 && w.targets.length === 1 && w.summary === 'before wp_load · only the goal changes', 'load must leave hypothesis rows quiet');
    const t = await tourAt(1);
    assert(t.text.includes('wp_load only changes the goal.') && t.text.includes('No hypothesis annotations; ↳ under ⊢.'), 'load tour disagrees');
    return w;
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

  await check('annotated new term has native contextual hover', async () => {
    await at('widget-position-heap-load');
    await waitWidget('load before fresh annotation', w => w.tactics?.includes('wp_load'));
    await at('widget-position-heap-store');
    await waitWidget('new store annotation', w => w.tactics?.includes('wp_store'));
    const hovered = await infoviewEval(vs, `(() => {
      const row = document.querySelector('[data-resource-name="Hl"][data-annotation-kind="changed"]');
      const target = [...row.querySelectorAll('span')].find(s => s.textContent === "v'" && s.childElementCount === 0);
      if (!target) return false;
      for (const type of ['pointerover', 'pointermove', 'mouseover', 'mousemove'])
        target.dispatchEvent(new (type.startsWith('pointer') ? PointerEvent : MouseEvent)(type, { bubbles: true }));
      return true;
    })()`);
    assert(hovered, 'new value has no native tag');
    const tip = await vs.until('annotated v-prime hover', () => infoviewEval(vs, `(() =>
      [...document.querySelectorAll('.tooltip')].map(e => e.innerText).find(s => s.includes("v'") && s.includes('Val')))()`), 20000, 500);
    return { tip };
  });

  await check('native definition navigation opens the Lean source file', async () => {
    await at('widget-position-heap-store');
    await waitWidget('heap store for definition', w => w.present && /Hl:\s*l ↦ some v(?!')/.test(w.text));
    const clicked = await infoviewEval(vs, `(() => {
      const w = document.querySelector('[data-iris-proof-mode-widget]');
      const term = [...w.querySelectorAll('[data-annotation-kind="changed"] [data-has-tooltip-on-hover]')]
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
      // The editor can arrive before the infoview receives its cursor event.
      // Observe both hosts before returning, so the next move cannot overtake it.
      await vs.until('infoview follows the definition file', () => infoviewEval(vs,
        `/Prelude\\.lean:\\d+/.test(document.body.innerText)`), 90000, 500);
      return { destination, input: 'synthetic Ctrl-click in the real webview; actual editor destination checked' };
    } finally {
      await vs.driver({ op: 'open', file });
      await vs.until('infoview returns to the demo file', () => infoviewEval(vs,
        `/WidgetDemo\\.lean:\\d+/.test(document.body.innerText)`), 90000, 500);
      await tourAt(0);
    }
  });

  await check('heap postcondition retains both owned cells', async () => {
    await at('widget-position-heap-post');
    const w = await waitWidget('heap postcondition', w => w.present && w.text.includes("⌜v' = v'⌝") && !w.text.includes('WP '));
    assert(w.text.includes("l ↦ some v'") && w.text.includes("l' ↦ some w"), 'postcondition lost a cell');
    assert(w.changes.length === 2 && w.changes.every(r => r.status === 'gone' && r.text === '↳ iframe: no longer in context'),
      'iframe must report context departures without inferring consumption');
    assert(w.targets.length === 1 && w.targets[0].includes("⌜v' = v'⌝"), 'iframe reduces the target');
    const t = await tourAt(2);
    assert(t.text.includes('iframe discharges both cells.') && t.text.includes('pure equality'), 'postcondition tour disagrees');
    return w;
  });

  for (const [marker, cell, targetPrefix] of [
    ['widget-position-spin-open', '▷ l ↦ some hl_val(#b)', 'WP '],
    ['widget-position-spin-stored', 'l ↦ some hl_val(#false)', '|={'],
  ])
    await check(`spinlock ${marker.split('-').at(-1)}`, async () => {
      await at(marker);
      const w = await waitWidget(marker, w => w.present && w.text.includes('Hinv') && w.text.includes(cell) && w.text.includes(targetPrefix) &&
        w.tactics.includes(marker.endsWith('open') ? 'wp_store' : 'imodintro'));
      for (const term of ['locked γ', 'HR:', 'Hcond:', 'spinlockN']) assert(w.text.includes(term), `missing ${term}`);
      assert(w.termButtons === 0, 'custom term buttons remain');
      assert(w.rows.map(r => r.name).join(' ') === (marker.endsWith('open') ? 'Hinv Hl HR Hcont Hpt Hcond' : 'Hinv Hl HR Hcont Hcond Hpt'), 'SpinLock context order changed');
      if (marker.endsWith('stored')) {
        assert(w.changes.length === 0 && w.targets.length === 1 && w.summary === 'before imodintro · only the goal changes',
          'imodintro must annotate only the target');
        const t = await tourAt(4);
        assert(t.text.includes('imodintro only changes the goal.') && t.text.includes('The update modality under ⊢.'), 'imodintro tour disagrees');
      }
      return w;
    });

  await check('spinlock store annotates Hpt and Hcond in place', async () => {
    await at('widget-position-spin-open');
    const w = await waitWidget('spin store comparison', w => w.present && w.text.includes('Hinv') && w.tactics.includes('wp_store'));
    assert(w.changes.map(r => r.name).join(' ') === 'Hpt Hcond', 'only changed rows, in context order');
    assert(w.changes.every(r => r.status === 'changed'), 'changed resource statuses');
    const cell = w.changes.find(r => r.name === 'Hpt'), condition = w.changes.find(r => r.name === 'Hcond');
    assert(cell.native && cell.text.includes('#false') && !cell.text.includes('▷'), 'new cell loses its later');
    assert(condition.text.includes('if b') && !condition.text.includes('▷'), 'new condition loses its later');
    assert(w.targets.length === 1 && w.summary === 'before wp_store · changes Hpt, Hcond and the goal', 'SpinLock goal and summary');
    const t = await tourAt(3);
    assert(t.text.includes('Store inside the opened invariant.') && t.text.includes('Hpt updated; ▷ stripped from Hpt and Hcond. The other four untouched.'), 'store tour disagrees');
    return w;
  });

  await check('mask chip and folded invariant use native namespace hover', async () => {
    await at('widget-position-spin-open');
    await waitWidget('spin-open details', w => w.tactics?.includes('wp_store') && w.text.includes('Hinv'));
    const details = await infoviewEval(vs, `(() => {
      const w = document.querySelector('[data-iris-proof-mode-widget]');
      const inv = w.querySelector('[data-hypothesis-name="Hinv"] [data-invariant-open]');
      w.querySelector('article').scrollIntoView({ block: 'center' });
      return { mask: w.querySelector('[data-mask-chip]')?.textContent, open: inv?.dataset.invariantOpen,
        body: !!inv?.querySelector('[data-term-id$="-body"]') };
    })()`);
    // Lean prints set difference as a backslash; accept either mathematical glyph.
    assert(/⊤\s*[\\∖]\s*↑spinlockN/.test(details.mask), 'outer reduced mask not shown: ' + details.mask);
    assert(details.open === 'false' && !details.body, 'Hinv must start folded');
    const shot = await vs.workbench.send('Page.captureScreenshot', { format: 'png' });
    writeFileSync(`${vs.run}/round-f-spin-open.png`, Buffer.from(shot.data, 'base64'));
    await infoviewEval(vs, `(() => {
      const inv = document.querySelector('[data-hypothesis-name="Hinv"] [data-invariant-open]');
      const leaf = [...inv.querySelectorAll('[data-has-tooltip-on-hover]')].find(e => e.textContent === 'spinlockN' && !e.querySelector('[data-has-tooltip-on-hover]'));
      if (!leaf) throw new Error('native namespace leaf missing');
      for (const type of ['pointerover', 'pointermove', 'mouseover', 'mousemove'])
        leaf.dispatchEvent(new (type.startsWith('pointer') ? PointerEvent : MouseEvent)(type, { bubbles: true }));
    })()`);
    await vs.until('namespace hover', () => infoviewEval(vs,
      `Array.from(document.querySelectorAll('.tooltip')).some(e => e.textContent.includes('Namespace'))`), 20000, 500);
    return details;
  });

  await check('invariant expansion survives cursor refresh with fresh native terms', async () => {
    await infoviewEval(vs, `(() => {
      const inv = document.querySelector('[data-hypothesis-name="Hinv"] [data-invariant-open]');
      globalThis.__irisFold = inv;
      globalThis.__irisFoldNative = inv.querySelector('[data-has-tooltip-on-hover]');
      inv.querySelector('button').click();
    })()`);
    await vs.until('expanded body', () => infoviewEval(vs,
      `globalThis.__irisFold.dataset.invariantOpen === 'true' && globalThis.__irisFold.textContent.includes('∃ b')`), 20000, 500);
    await at('widget-position-spin-open', 1);
    await vs.until('retained disclosure, retired native child', () => infoviewEval(vs,
      `globalThis.__irisFold.isConnected && globalThis.__irisFold.dataset.invariantOpen === 'true' &&
       !globalThis.__irisFoldNative.isConnected && !!globalThis.__irisFold.querySelector('[data-term-id$="-body"] [data-has-tooltip-on-hover]')`), 20000, 500);
    return { expanded: true, identityPreserved: true, nativeChildReplaced: true };
  });

  await check('spinlock iframe marks only Hpt leaving the context', async () => {
    await at('widget-position-spin-frame');
    const w = await waitWidget('spin frame', w => w.tactics?.includes('iframe Hpt'));
    assert(w.changes.length === 1 && w.changes[0].name === 'Hpt' && w.changes[0].status === 'gone' &&
      w.changes[0].text === '↳ iframe: no longer in context', 'neutral context departure on Hpt');
    assert(w.targets.length === 1, 'frame target annotation');
    const t = await tourAt(5);
    assert(t.text.includes('iframe Hpt.') && t.text.includes('Hpt leaves the context; ⊢ reduces.'), 'frame tour disagrees');
    return w;
  });

  await check('split distributes resources and shows both new targets', async () => {
    await at('widget-position-contexts');
    const w = await waitWidget('split annotations', w => w.tactics?.includes('isplitr [HQ HS]'));
    assert(w.cards.length === 1, 'one annotated before-card');
    assert(w.changes.map(r => r.name).join(' ') === 'HQ HS', 'shared persistent resources stay quiet');
    assert(w.changes.every(r => r.status === 'distributed' && r.text === '↳ isplitr: goal 2'), 'spatial destinations');
    assert(w.targets.length === 2 &&  /goal 1 ⊢\s*P/.test(w.targets[0]) && /goal 2 ⊢\s*R ∗ S/.test(w.targets[1]), 'both resulting targets in order');
    const t = await tourAt(6);
    assert(t.text.includes('isplitr [HQ HS] distributes spatial ownership.') &&
      t.text.includes('HQ and HS go to goal 2; HP and HQR remain in both goals.'), 'split tour disagrees');
    return w;
  });

  await check('before-state label at an after-side position; none outside a tactic', async () => {
    const comment = await vs.driver({ op: 'find', marker: 'widget-position-heap-store', offset: 0 });
    await vs.driver({ op: 'cursor', line: comment.line, character: 4 });
    const outside = await waitWidget('unlabelled comment', w => w.present && !w.summary);
    assert(outside.changes.length === 0 && outside.targets.length === 0, 'comment must not carry tactic annotations');
    await at('widget-position-heap-store', 1);
    const inside = await waitWidget('labelled before projection', w => w.summary === 'before wp_store · changes Hl and the goal');
    assert(inside.rows.find(r => r.name === 'Hl')?.text === 'l ↦ some v', 'inside tactic still projects its before-state');
    return { outside: outside.summary ?? null, inside: inside.summary };
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
  await check('tour re-resolves markers after an unsaved line insertion', async () => {
    const marker = await vs.driver({ op: 'find', marker: 'widget-position-heap-store', offset: 0 });
    await vs.driver({ op: 'cursor', line: marker.line, character: 0 });
    await vs.driver({ op: 'type', text: '\n' });
    await at('widget-position-heap-store'); await tourAt(0);
    const expected = await vs.driver({ op: 'find', marker: 'widget-position-heap-load' });
    await tourClick('next'); await tourAt(1);
    const actual = await vs.driver({ op: 'activeEditor' });
    assert(actual.isDirty && actual.line === expected.line && actual.character === expected.character,
      `tour used a stale line number: ${JSON.stringify(actual)}`);
    return { actual, expected };
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
