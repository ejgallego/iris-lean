// Test-only driver: a loopback HTTP endpoint that performs editor actions through the real VS Code API.
const vscode = require('vscode');
const http = require('node:http');
const fs = require('node:fs');

async function run(op) {
  switch (op.op) {
    case 'ping': return { ok: true, lean: !!vscode.extensions.getExtension('leanprover.lean4')?.isActive };
    case 'open': {
      const doc = await vscode.workspace.openTextDocument(vscode.Uri.file(op.file));
      const editor = await vscode.window.showTextDocument(doc, { preview: false, viewColumn: vscode.ViewColumn.One });
      if (op.line !== undefined) return run({ op: 'cursor', line: op.line, character: op.character ?? 0 });
      return { uri: doc.uri.toString() };
    }
    case 'activeEditor': {
      const editor = vscode.window.activeTextEditor;
      if (!editor) return null;
      const p = editor.selection.active;
      return { uri: editor.document.uri.toString(), line: p.line, character: p.character,
        isDirty: editor.document.isDirty };
    }
    case 'cursor': { // 0-based line/character, as in LSP
      const editor = vscode.window.activeTextEditor; if (!editor) throw new Error('no active editor');
      const pos = new vscode.Position(op.line, op.character);
      editor.selection = new vscode.Selection(pos, pos);
      editor.revealRange(new vscode.Range(pos, pos), vscode.TextEditorRevealType.InCenter);
      return { uri: editor.document.uri.toString(), line: op.line, character: op.character };
    }
    case 'find': { // locate a unique marker; returns the first non-space column of the following line
      const editor = vscode.window.activeTextEditor; const lines = editor.document.getText().split('\n');
      const hits = lines.flatMap((l, i) => l.includes(op.marker) ? [i] : []);
      if (hits.length !== 1) throw new Error(`marker ${op.marker}: ${hits.length} matches`);
      const line = hits[0] + (op.offset ?? 1);
      return { line, character: Math.max(0, lines[line].search(/\S/)) };
    }
    case 'type': { // insert at the cursor, moving it, like a keystroke
      const editor = vscode.window.activeTextEditor;
      await editor.edit(b => b.insert(editor.selection.active, op.text));
      const p = editor.selection.active; return { line: p.line, character: p.character };
    }
    case 'revert': await vscode.commands.executeCommand('workbench.action.files.revert'); return {};
    case 'command': return { result: await vscode.commands.executeCommand(op.id, ...(op.args ?? [])) ?? null };
    case 'diagnostics': {
      const editor = vscode.window.activeTextEditor;
      return vscode.languages.getDiagnostics(editor.document.uri).map(d => ({ severity: d.severity, line: d.range.start.line, message: d.message.slice(0, 300) }));
    }
    default: throw new Error(`unknown op ${op.op}`);
  }
}

exports.activate = () => {
  const port = Number(process.env.IRIS_E2E_DRIVER_PORT); if (!port) return;
  const server = http.createServer((req, res) => {
    let body = ''; req.on('data', c => body += c);
    req.on('end', async () => {
      try { res.end(JSON.stringify({ ok: true, value: await run(JSON.parse(body || '{}')) })); }
      catch (e) { res.end(JSON.stringify({ ok: false, error: String(e?.stack ?? e) })); }
    });
  });
  server.listen(port, '127.0.0.1');
  if (process.env.IRIS_E2E_READY_FILE) fs.writeFileSync(process.env.IRIS_E2E_READY_FILE, String(port));
};
