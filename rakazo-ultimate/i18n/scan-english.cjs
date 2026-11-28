// Finds hardcoded English UI text in the mobile app: JSX text, user-facing JSX props, Alert args and
// user-facing object properties that hold a literal instead of a Lingui message.
// Usage: node scan-english.cjs <src-tree> [--json]   (exit 1 when anything is found, minus allowlist)
const path = require("path"), fs = require("fs");
const root = path.resolve(process.argv[2] || ".");
const ts = require(require.resolve("typescript", { paths: [path.join(root, "apps/mobile")] }));
const ALLOW = fs.existsSync(path.join(__dirname, "english-allowlist.txt"))
  ? fs.readFileSync(path.join(__dirname, "english-allowlist.txt"), "utf8").split("\n").map((s) => s.trim()).filter((s) => s && !s.startsWith("#"))
  : [];
const PROPS = new Set(["placeholder","accessibilityLabel","accessibilityHint","label","title","subtitle","description","headerTitle","message","text","hint","detail","emptyLabel","buttonLabel","confirmLabel","cancelLabel","caption","heading","helper","helperText","errorText","body","summary","ariaLabel","tabBarLabel","headerBackTitle","value"]);
const SKIPDIRS = /(node_modules|\.test\.|\.spec\.|__tests__|avatar-review-gallery|\/e2e|\.d\.ts)/;
const looksText = (s) => {
  const t = s.trim();
  if (t.length < 3 || !/[A-Za-z]{3,}/.test(t)) return false;
  if (/[\u3400-\u9fff]/.test(t)) return false; // Chinese text with a brand word (Bot, iPhone) is not English
  if (/^(https?:|\/|#|\.|@|[a-z0-9_.-]+$)/.test(t) && !/\s/.test(t)) return false; // ids, paths, one lowercase token
  if (/^[a-z][a-zA-Z0-9]*$/.test(t)) return false; // camelCase identifier
  if (/^[A-Z0-9_]+$/.test(t)) return false; // CONSTANT
  if (/^[\w./:-]+$/.test(t) && !/[A-Z][a-z]+ /.test(t)) return false;
  return true;
};
const found = [];
const BROAD = process.argv.includes("--broad");
function walk(dir) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (SKIPDIRS.test(p)) continue;
    if (e.isDirectory()) walk(p);
    else if (/\.(tsx?|jsx?)$/.test(e.name)) scan(p);
  }
}
function scan(file) {
  const src = fs.readFileSync(file, "utf8");
  const sf = ts.createSourceFile(file, src, ts.ScriptTarget.Latest, true, file.endsWith("x") ? ts.ScriptKind.TSX : ts.ScriptKind.TS);
  const rel = path.relative(root, file);
  const add = (node, text, kind) => {
    const { line } = sf.getLineAndCharacterOfPosition(node.getStart());
    const key = `${rel}: ${text.trim()}`;
    if (ALLOW.some((a) => key.includes(a))) return;
    found.push({ file: rel, line: line + 1, kind, text: text.trim().replace(/\s+/g, " ") });
  };
  const inTagged = (n) => { for (let p = n.parent; p; p = p.parent) if (ts.isTaggedTemplateExpression(p) && /^(t|msg|defineMessage)$/.test(p.tag.getText())) return true; return false; };
  (function visit(n) {
    if (ts.isJsxText(n)) { if (looksText(n.getText())) add(n, n.getText(), "jsx-text"); }
    else if (ts.isJsxAttribute(n) && n.initializer && PROPS.has(n.name.getText())) {
      const i = n.initializer;
      const lit = ts.isStringLiteral(i) ? i : ts.isJsxExpression(i) && i.expression && (ts.isStringLiteral(i.expression) || ts.isNoSubstitutionTemplateLiteral(i.expression)) ? i.expression : null;
      if (lit && looksText(lit.text)) add(lit, lit.text, "jsx-prop:" + n.name.getText());
    } else if (ts.isJsxExpression(n) && n.parent && (ts.isJsxElement(n.parent) || ts.isJsxFragment(n.parent)) && n.expression && (ts.isStringLiteral(n.expression) || ts.isNoSubstitutionTemplateLiteral(n.expression))) {
      if (looksText(n.expression.text)) add(n.expression, n.expression.text, "jsx-expr");
    } else if (ts.isCallExpression(n) && /^Alert\.alert$/.test(n.expression.getText())) {
      n.arguments.forEach((a) => { if ((ts.isStringLiteral(a) || ts.isNoSubstitutionTemplateLiteral(a)) && looksText(a.text)) add(a, a.text, "alert"); });
    } else if (ts.isPropertyAssignment(n) && PROPS.has(n.name.getText()) && (ts.isStringLiteral(n.initializer) || ts.isNoSubstitutionTemplateLiteral(n.initializer)) && !inTagged(n)) {
      if (looksText(n.initializer.text) && /\s|^[A-Z]/.test(n.initializer.text.trim())) add(n.initializer, n.initializer.text, "prop:" + n.name.getText());
    }
    else if (BROAD && (ts.isStringLiteral(n) || ts.isNoSubstitutionTemplateLiteral(n)) && !ts.isImportDeclaration(n.parent) && !ts.isExportDeclaration(n.parent) && !ts.isJsxAttribute(n.parent) && !ts.isLiteralTypeNode(n.parent) && !inTagged(n)
      && /^[A-Z][a-z]+( [A-Za-z'’&,.!?…-]+)+$/.test(n.text.trim()) && /[A-Za-z]{2,} [A-Za-z]{2,}/.test(n.text) && !/^(throw|console)/.test(n.parent.parent?.getText?.().slice(0,9) || "")) {
      const callText = n.parent && ts.isCallExpression(n.parent) ? n.parent.expression.getText() : "";
      if (!/^(console|logger|log|Error|invariant|assert|require|expect|it|describe|test|vi\.)|\.(log|warn|error|debug|info)$/.test(callText) && !(n.parent && ts.isNewExpression(n.parent)))
        add(n, n.text, "broad");
    }
    ts.forEachChild(n, visit);
  })(sf);
}
for (const d of ["app", "components", "lib"]) walk(path.join(root, "apps/mobile", d));
if (process.argv.includes("--json")) console.log(JSON.stringify(found, null, 1));
else { for (const f of found) console.log(`${f.file}:${f.line} [${f.kind}] ${f.text}`); console.error(found.length + " hardcoded English strings"); }
process.exit(found.length ? 1 : 0);
