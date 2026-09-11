// Design-gallery checks only. Reuse the pinned VIR checkout's browser launcher;
// no VIR runtime, package build, web server, or network downloads are needed.
import assert from "node:assert/strict";
import { access, mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { launchChromium, openChromiumPage, navigate, evaluate } from
  "../../Iris/.lake/packages/lean_vir/tests/browser/harness.mjs";

const screenshots = await mkdtemp(join(tmpdir(), "iris-notation-gallery-"));
const browser = await launchChromium();
let cdp;
try {
  cdp = await openChromiumPage(browser);
  await cdp.send("Emulation.setDeviceMetricsOverride", { width: 1280, height: 1100, deviceScaleFactor: 1, mobile: false });
  await navigate(cdp, new URL("index.html", import.meta.url).href);
  assert.equal(await evaluate(cdp, "document.querySelectorAll('#specimens button').length"), 4);
  // Catch later interaction exceptions; initial initialization is checked above.
  await evaluate(cdp, "window.galleryErrors = []; window.addEventListener('error', e => galleryErrors.push(e.message))");
  const choose = (id, value) => evaluate(cdp, `(() => {
    const control = document.getElementById(${JSON.stringify(id)});
    control.value = ${JSON.stringify(value)};
    control.dispatchEvent(new Event('change', { bubbles: true }));
  })()`);
  const click = selector => evaluate(cdp, `document.querySelector(${JSON.stringify(selector)}).click()`);
  const shot = async name => {
    const { data } = await cdp.send("Page.captureScreenshot", { format: "png" });
    await writeFile(join(screenshots, `${name}.png`), Buffer.from(data, "base64"));
  };
  let layouts = 0;
  for (let specimen = 0; specimen < 4; specimen += 1) {
    await click(`#specimens button:nth-child(${specimen + 1})`);
    const steps = await evaluate(cdp, "Math.max(1, document.querySelectorAll('#steps button').length)");
    for (let step = 0; step < steps; step += 1) {
      if (steps > 1) await click(`#steps button:nth-child(${step + 1})`);
      assert.equal(await evaluate(cdp, "document.querySelectorAll('#parts [aria-pressed=true]').length"), 0);
      assert.ok(await evaluate(cdp, "document.querySelector('#source-text').value.length > 0"));
      assert.deepEqual(await evaluate(cdp, `(() => {
        const marks = [...document.querySelectorAll('#preview [data-part]')].map(n => n.dataset.part);
        const parts = [...document.querySelectorAll('#parts button')].map(n => n.dataset.part);
        return parts.filter(p => !marks.includes(p));
      })()`), [], "every inspection button should address a displayed occurrence");
      for (const width of ["wide", "360", "280"]) {
        await choose("width", width);
        for (const theme of ["light", "dark", "contrast"]) {
          await choose("theme", theme);
          for (const notation of ["math", "text"]) {
            await choose("notation", notation);
            const sizes = await evaluate(cdp, `(() => {
              const preview = document.querySelector('#preview');
              return { page: document.documentElement.scrollWidth, viewport: document.documentElement.clientWidth,
                panel: preview.clientWidth, content: preview.scrollWidth,
                verticalOverflow: [...preview.querySelectorAll('.math-fragment')].some(n => n.scrollHeight > n.clientHeight) };
            })()`);
            assert.ok(sizes.page <= sizes.viewport, `page overflow: ${JSON.stringify(sizes)}`);
            assert.ok(sizes.content <= sizes.panel + 1, `panel overflow: ${JSON.stringify(sizes)}`);
            assert.ok(!sizes.verticalOverflow, `unexpected formula vertical scrollbar: ${JSON.stringify(sizes)}`);
            layouts += 1;
          }
        }
      }
      await choose("notation", "math");
      await click("#parts button");
      assert.equal(await evaluate(cdp, "document.querySelectorAll('#parts [aria-pressed=true]').length"), 1);
      assert.ok(await evaluate(cdp, "document.querySelector('#inspection').textContent.includes('no live reference')"));
    }
  }
  await choose("theme", "light");
  await choose("width", "wide");
  await shot("wp-wide");
  await choose("width", "280");
  await choose("theme", "dark");
  await shot("wp-narrow-dark");
  await click("#specimens button:nth-child(2)");
  await shot("updates-narrow-dark");
  await click("#specimens button:nth-child(3)");
  await shot("invariant-narrow-dark");

  // Native keyboard activation, Escape, proof-step invalidation, collapsed goal access.
  await click("#specimens button:first-child");
  await cdp.send("Page.bringToFront");
  await evaluate(cdp, "document.querySelector('#parts button').focus()");
  assert.equal(await evaluate(cdp, "document.activeElement.closest('#parts')?.id"), "parts");
  await cdp.send("Input.dispatchKeyEvent", { type: "keyDown", key: "Enter", code: "Enter", text: "\r", windowsVirtualKeyCode: 13 });
  await cdp.send("Input.dispatchKeyEvent", { type: "keyUp", key: "Enter", code: "Enter", windowsVirtualKeyCode: 13 });
  assert.equal(await evaluate(cdp, "document.querySelector('#parts button').getAttribute('aria-pressed')"), "true");
  await cdp.send("Input.dispatchKeyEvent", { type: "keyDown", key: "Escape", code: "Escape", windowsVirtualKeyCode: 27 });
  assert.equal(await evaluate(cdp, "document.querySelectorAll('#parts [aria-pressed=true]').length"), 0);
  const point = await evaluate(cdp, `(() => {
    const rect = document.querySelector('#preview [data-part="hp"]').getBoundingClientRect();
    return { x: rect.x + rect.width / 2, y: rect.y + rect.height / 2 };
  })()`);
  await cdp.send("Input.dispatchMouseEvent", { type: "mousePressed", button: "left", clickCount: 1, ...point });
  await cdp.send("Input.dispatchMouseEvent", { type: "mouseReleased", button: "left", clickCount: 1, ...point });
  assert.equal(await evaluate(cdp, "document.querySelector('#parts button').getAttribute('aria-pressed')"), "true");
  await click("#steps button:nth-child(2)");
  assert.equal(await evaluate(cdp, "document.querySelectorAll('#parts [aria-pressed=true]').length"), 0);
  assert.deepEqual(await evaluate(cdp, "[...document.querySelectorAll('#preview details')].map(n => n.open)"), [true, false]);
  await click('#parts [data-part="target2"]');
  assert.deepEqual(await evaluate(cdp, "[...document.querySelectorAll('#preview details')].map(n => n.open)"), [true, true]);
  await choose("notation", "text");
  await choose("notation", "math");
  assert.deepEqual(await evaluate(cdp, "[...document.querySelectorAll('#preview details')].map(n => n.open)"), [true, true]);
  assert.equal(await evaluate(cdp, "document.querySelector('#parts [data-part=target2]').getAttribute('aria-pressed')"), "true");
  await choose("theme", "contrast");
  await shot("split-narrow-contrast");

  // Copy source, never reconstructed mathematical display. Exercise unavailable clipboard.
  await evaluate(cdp, `Object.defineProperty(navigator, 'clipboard', { configurable: true,
    value: { writeText: async text => { window.copiedText = text; } } })`);
  await click("#copy");
  assert.equal(await evaluate(cdp, "copiedText"), await evaluate(cdp, "document.querySelector('#source-text').value"));
  await evaluate(cdp, "navigator.clipboard.writeText = async () => { throw new Error('denied'); }");
  await click("#copy");
  assert.ok(await evaluate(cdp, "document.querySelector('#copy-status').textContent.includes('source selected')"));
  assert.equal(await evaluate(cdp, "document.activeElement.id"), "source-text");
  assert.ok(await evaluate(cdp, "document.activeElement.selectionEnd === document.activeElement.value.length"));

  // Narrow whole-browser layout, not just the simulated panel.
  await cdp.send("Emulation.setDeviceMetricsOverride", { width: 280, height: 900, deviceScaleFactor: 1, mobile: false });
  for (let specimen = 1; specimen <= 4; specimen += 1) {
    await click(`#specimens button:nth-child(${specimen})`);
    assert.ok(await evaluate(cdp, "document.documentElement.scrollWidth <= document.documentElement.clientWidth"));
  }
  for (const path of await evaluate(cdp, "irisSpecimens.flatMap(s => s.sources.map(p => p.url)).filter(p => p.startsWith('../../'))")) {
    await access(new URL(path, import.meta.url));
  }
  assert.deepEqual(await evaluate(cdp, "galleryErrors"), []);
  console.log(`PASS: ${layouts} layouts; narrow viewport; keyboard, pointer, split state, source copy/fallback, local source links. Screenshots: ${screenshots}`);
} finally {
  cdp?.close();
  await browser.close();
}
